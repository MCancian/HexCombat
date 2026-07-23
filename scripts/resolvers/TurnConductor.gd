class_name TurnConductor
extends RefCounted

## Static turn orchestration for HexCombat's WeGo resolution (plan 0014 P3). Every public method
## takes `state: GameStateData` as its first argument, mutates it in place, and returns the same
## typed value the pre-refactor GameState method returned. Reading the GameData content autoload
## (map/OOB/scenario content) is allowed — it is the universal read-only content source, not
## runtime state — but this class NEVER takes the GameState autoload singleton as a parameter,
## which is what makes it unit-testable against a GameStateData built from scratch. GameState.gd's
## resolve_* methods are now one-line delegating wrappers to these.

const FEBA_RETREAT_THRESHOLD_KM := 10.0



static func resolve_turn(state: GameStateData, dice: Dice = null) -> void:
	if state.phase != GameStateData.Phase.PLANNING:
		push_error("Cannot resolve turn outside PLANNING phase")
		return

	if dice == null:
		dice = SeededDice.new(state.turn_number)

	state.phase = GameStateData.Phase.RESOLUTION
	EventBus.phase_changed.emit(state.phase)
	# Sea phase ordering (D3-D): IJFS (Red joint fires) suppresses/destroys Green anti-ship systems
	# first; then Green anti-ship + mines attrit the Red crossing (removing BNs from the reserve);
	# then offload lands only the survivors. Each draws from its own INDEPENDENT substream (never the
	# combat dice), so the ground-combat golden invariant stays byte-stable.
	resolve_ijfs_turn(state, dice)
	# D4-H (2d): IJFS maneuver kills reduce the ground OOB before combat. Deterministic (reads the
	# writeback the warmup just produced; no dice), so the combat golden stays reproducible.
	apply_ijfs_maneuver_casualties(state)
	# Sealift (plan 0004): tick the ship return/reload pipeline and embark this turn's wave (first
	# echelon adopted, follow-on echelons loaded onto ready amphibious lift) BEFORE the crossing, so
	# the anti-ship phase attrits exactly the hulls that sail. Dice-free -> combat golden unaffected.
	resolve_sealift_turn(state)
	resolve_antiship_turn(state, dice)
	state.last_offload_summary = resolve_offload_turn(state, dice)

	# disable_phases (plan 0012): a scenario/override can skip the ground WeGo phases wholesale so
	# calibration sweeps run standard games while isolating the sea/IJFS phases. Buffered orders
	# simply never execute; skipping consumes no dice, so an empty list is byte-identical.
	var skip_movement := GameData.disabled_phases.has("movement")
	var skip_ground_combat := GameData.disabled_phases.has("ground_combat")
	if not skip_movement:
		apply_move_orders(state, Brigade.Team.RED)
		apply_move_orders(state, Brigade.Team.GREEN)
	if skip_ground_combat:
		state.last_contested_hexes.clear()
	else:
		state.last_contested_hexes = find_contested_hexes()
	var combat_summaries: Array[CombatSummary] = []
	# Per-hex combat substream (plan 0010): each contested hex draws from its OWN dice stream derived
	# from the root turn seed, so a design tweak that changes the roll count in one hex's fight never
	# scrambles the dice of an unrelated hex. Turn-scoped salt matches the ijfs/antiship pattern so an
	# injected constant-seed dice still varies per turn.
	for hex_id in state.last_contested_hexes:
		var summary := resolve_combat_at(state, hex_id, dice.derive("combat:%d:%s" % [state.turn_number, hex_id]))
		if summary != null:
			combat_summaries.append(summary)
	if not skip_ground_combat:
		apply_feba_retreats(state)
	GameData.recompute_hex_ownership()
	for summary in combat_summaries:
		summary.owner_after = String(GameData.hex_states[summary.hex_id].owner)
	state.last_combat_summaries = combat_summaries.duplicate()
	resolve_supply_turn(state)
	resolve_cleanup_phase(state)

	# Debug-only invariant (refactor item 4): at the settled end of a turn the brigade↔hex indexes
	# must be consistent. Gated on OS.is_debug_build() so the validator is never called in release;
	# in debug/test/headless runs it fails loud on any silent index desync. End-of-turn only (a settled
	# boundary) — NOT the per-mutator hot path, which can hold benign transient desync mid-resolution.
	if OS.is_debug_build():
		var index_violations := GameData.validate_runtime_indexes()
		assert(index_violations.is_empty(), "runtime index desync at end of resolve_turn: %s" % "; ".join(index_violations))

	state.phase = GameStateData.Phase.END
	EventBus.phase_changed.emit(state.phase)
	EventBus.combat_resolved.emit(combat_summaries)
	EventBus.turn_resolved.emit(state.turn_number)


static func resolve_offload_turn(state: GameStateData, dice: Dice) -> Dictionary:
	assert(dice != null, "resolve_offload_turn requires a Dice instance")
	# Infrastructure lifecycle ticks every offload phase (plan 0006), even with an empty reserve:
	# ground combat can seize a port hex long after the last beach landing. Ownership here is last
	# turn's post-combat state — the producer->consumer edge is combat ownership -> next offload.
	var infra_nodes: Array = []
	if state.infrastructure_state != null:
		var owner_by_hex_map := owner_by_hex()
		InfrastructureResolver.tick(state.infrastructure_state, GameData.infrastructure, owner_by_hex_map)
		infra_nodes = InfrastructureResolver.red_offload_nodes(state.infrastructure_state, GameData.infrastructure, owner_by_hex_map)

	if state.ship_reserve.is_empty():
		var empty_manifest := OffloadResolver.empty_manifest()
		empty_manifest["lost_at_sea"] = state.pending_lost_at_sea
		# D3-F applies lost_at_sea to the reserve; D0-C only threads the value.
		state.pending_lost_at_sea = 0
		EventBus.offload_resolved.emit(empty_manifest)
		return empty_manifest

	var cost_config: Dictionary = GameData.offload_weights if GameData.use_offload_weight_matrix else {}
	var outcome := OffloadResolver.resolve(
		state.turn_number, state.ship_reserve, GameData.beaches, GameData.brigades,
		infra_nodes, cost_config, GameData.beach_to_to, owner_by_hex())
	for landing_value in outcome["landings"]:
		var landing: Dictionary = landing_value
		var brigade_id := String(landing["brigade_id"])
		GameData.set_brigade_hex(brigade_id, String(landing["beach_hex"]))
		GameData.get_brigade(brigade_id).entry_bearing = float(landing["offset_bearing"])
	state.ship_reserve = outcome["remaining_ship_reserve"]
	GameData.recompute_hex_ownership()

	var manifest: Dictionary = outcome["manifest"]
	# Drain the landed BNs from their offloading cohorts; a fully-offloaded cohort frees its hulls
	# into the return/reload pipeline (or straight back to ready when return time is 0) — plan 0004 D4.
	var landed_ids: Array = []
	for landed_value in manifest["manifest_landed"]:
		landed_ids.append(String((landed_value as Dictionary)["bn_id"]))
	# JLSF deliveries (plan 0006): the detachment is ashore at its node — start the repair clock
	# and free its hulls like any landed cargo.
	for arrival_value in outcome.get("jlsf_arrivals", []):
		var arrival: Dictionary = arrival_value
		var port_id := String(arrival["port_id"])
		if state.infrastructure_state != null and state.infrastructure_state.nodes.has(port_id):
			state.infrastructure_state.nodes[port_id]["jlsf"] = InfrastructureState.JLSF_ARRIVED
		for bn_id_value in arrival["bn_ids"]:
			landed_ids.append(String(bn_id_value))
	if state.sealift_state != null:
		SealiftResolver.drain_bn_ids(state.sealift_state, landed_ids, GameData.amphibious_return_time_turns)
		project_sealift_onto_fleet(state)
	reconcile_lost_jlsf(state)

	manifest["lost_at_sea"] = state.pending_lost_at_sea
	# D3-F applies lost_at_sea to the reserve; D0-C only threads the value.
	state.pending_lost_at_sea = 0
	EventBus.offload_resolved.emit(manifest)
	return manifest


static func owner_by_hex() -> Dictionary:
	var owners: Dictionary = {}
	for hex_id in GameData.hex_states.keys():
		owners[String(hex_id)] = String((GameData.hex_states[hex_id] as HexState).owner)
	return owners


## A JLSF deployment lost whole at sea (its pseudo-BNs all drowned in the crossing) leaves no
## pool or reserve trace; reset its node marker so a new deployment can be ordered/auto-queued.
static func reconcile_lost_jlsf(state: GameStateData) -> void:
	if state.infrastructure_state == null:
		return
	for id_value in state.infrastructure_state.nodes.keys():
		var node: Dictionary = state.infrastructure_state.nodes[id_value]
		var marker := String(node["jlsf"])
		if marker != InfrastructureState.JLSF_QUEUED and marker != InfrastructureState.JLSF_ENROUTE:
			continue
		var brigade_id := JlsfCargo.brigade_id_for(String(id_value))
		if not reserve_or_pool_has(state, brigade_id):
			node["jlsf"] = InfrastructureState.JLSF_NONE


static func reserve_or_pool_has(state: GameStateData, brigade_id: String) -> bool:
	for entry_value in state.ship_reserve:
		if String((entry_value as Dictionary).get("brigade_id", "")) == brigade_id:
			return true
	if state.sealift_state != null:
		for entry_value in state.sealift_state.mainland_pool:
			if String((entry_value as Dictionary).get("brigade_id", "")) == brigade_id:
				return true
	return false


static func resolve_supply_turn(state: GameStateData) -> Dictionary:
	assert(state.supply_state != null, "resolve_supply_turn requires supply_state")
	var units := active_red_battalion_units()
	var moved_ids: Array[String] = []
	var engaged_ids: Array[String] = []
	for brigade_value in GameData.brigades.values():
		var brigade: Brigade = brigade_value
		if brigade.team != Brigade.Team.RED or brigade.destroyed or brigade.hex_id.is_empty():
			continue
		if brigade.moved_this_turn:
			moved_ids.append(brigade.id)
		if brigade.fought_this_turn:
			engaged_ids.append(brigade.id)

	var summary := SupplyResolver.resolve(state.supply_state, units, moved_ids, engaged_ids, state.turn_number)
	EventBus.supply_updated.emit(summary)
	return summary


# --- IJFS (D4) — Red joint/air-missile fires daily phase ----------------------------------------

static func resolve_ijfs_turn(state: GameStateData, dice: Dice) -> Dictionary:
	assert(dice != null, "resolve_ijfs_turn requires a Dice instance")
	if state.ijfs_state == null:
		rebuild_ijfs_state(state)
	var outcome := IjfsResolver.resolve(state.ijfs_state, GameData.brigades, state.turn_number, state._ijfs_day, dice)
	state._ijfs_day = state.turn_number
	var ledgers: Dictionary = outcome["ledgers"]
	state.last_ijfs_summary = ledgers["summary"]
	state.last_ijfs_writeback = outcome["writeback"]
	EventBus.ijfs_resolved.emit(state.last_ijfs_summary)
	return ledgers


## Lazily build the persistent anti-ship Green firing systems (aggregated by (to_number, type_id)).
## Shared by resolve_ijfs_turn (IJFS targeting) and resolve_antiship_turn (firing).
static func ensure_antiship_systems(state: GameStateData) -> void:
	if state._antiship_built:
		return
	var built := GameStateBuilder.build_antiship_systems()
	state.antiship_systems = built["systems"]
	state.antiship_containers = built["containers"]
	state._antiship_built = true


static func rebuild_ijfs_state(state: GameStateData) -> void:
	# Anti-ship systems must exist first (their containers seed the per-(TO,type) IJFS targets).
	ensure_antiship_systems(state)
	state.ijfs_state = GameStateBuilder.build_ijfs_state(state.antiship_containers, GameData.brigades)
	state._ijfs_day = 0


static func update_maneuver_posture(state: GameStateData) -> void:
	IjfsResolver.update_maneuver_posture(state.ijfs_state, GameData.brigades)


static func sync_maneuver_targets_to_oob(state: GameStateData) -> void:
	IjfsResolver.sync_maneuver_targets_to_oob(state.ijfs_state, GameData.brigades)


static func apply_ijfs_maneuver_casualties(state: GameStateData) -> void:
	var casualties: Array = state.last_ijfs_writeback.maneuver_casualties if state.last_ijfs_writeback != null else []
	IjfsResolver.apply_maneuver_casualties(casualties, GameData.brigades)


## D3-D: Green coastal anti-ship fires + mine warfare against the Red amphibious crossing. Threads the
## firing plan (D3-B2) -> crossing (D3-B3) -> mines (D3-C); ship losses convert to BNs lost at sea
## (ShipLoadingModel) and feed register_ship_losses (the D0-C seam offload consumes). Runs after IJFS
## (Green systems suppressed/destroyed first) and before offload (only survivors land). Draws from an
## INDEPENDENT substream so the ground-combat golden invariant stays byte-stable.
static func resolve_antiship_turn(state: GameStateData, dice: Dice) -> Dictionary:
	ensure_antiship_systems(state)
	state.last_antiship_summary = null

	# Independent substream (same isolation pattern as resolve_ijfs_turn). SeededDice.derive is a
	# pure hash of (seed, label) — it consumes no parent-stream state, so deriving before the
	# resolver's no-wave check cannot shift the base combat stream.
	var as_dice: Dice
	if dice is SeededDice:
		as_dice = dice.derive("antiship:%d" % state.turn_number)
	else:
		as_dice = SeededDice.new(hash("antiship:%d" % state.turn_number))

	# Theaters reads the GameData autoload internally, so the TO maps are materialized here and
	# passed into the pure resolver as plain data.
	var to_adjacency: Dictionary = {}
	for to_num in GameData.active_tos:
		to_adjacency[to_num] = Theaters.adjacent_tos(to_num)

	# Only the BNs sailing this turn (the sealift "sent" cohorts) cross and take attrition; offloading
	# BNs are safe ashore. Slice that crossing wave out of the full reserve (plan 0004 D3).
	var crossing_reserve := crossing_reserve_from_sent_cohorts(state)
	# Captured pre-resolve: drain/flip below mutate the cohorts before the summary is stored.
	var wave_bns: int = SealiftResolver.sent_cohort_bn_ids(state.sealift_state).size()

	var outcome := AntishipResolver.resolve(
		state.turn_number, crossing_reserve, state.antiship_systems, state.last_ijfs_writeback,
		state.last_sealift_sent_by_type, GameData.ship_defs, GameData.beach_to_to, GameData.active_tos, to_adjacency,
		state.lost_at_sea_accumulator, state.sealift_state.escort_sam, as_dice)
	if outcome["summary"] == null:
		# Nothing crossed this turn: no fires, no state to apply (pending_lost_at_sea keeps its value).
		return {}

	state.lost_at_sea_accumulator = float(outcome["accumulator"])
	# Apply hull losses to the sealift cohorts (carriers) + the fleet, then drop drowned BNs from the
	# reserve AND their cohorts, and flip the surviving crossers to offloading (plan 0004 D3).
	apply_crossing_hull_losses(state, outcome["destroyed_by_type"])
	var lost_ids: Array = outcome["lost_ids"]
	state.ship_reserve = AntishipResolver.remaining_reserve_after_losses(state.ship_reserve, lost_ids)
	SealiftResolver.drain_bn_ids(state.sealift_state, lost_ids, GameData.amphibious_return_time_turns)
	SealiftResolver.flip_sent_to_offloading(state.sealift_state)
	# Deplete the escort SAM magazines by what fired, and divert any type that dropped to/below its
	# reload threshold (plan 0004 D5). No-op when the magazine is unmodelled (escort_sam empty).
	SealiftResolver.apply_escort_consumption(
		state.sealift_state, outcome["escort_sam_consumed"], GameData.escort_reload_time_turns)
	project_sealift_onto_fleet(state)
	register_ship_losses(state, int(outcome["bn_equiv_lost"]))
	state.last_antiship_summary = outcome["summary"]
	state.last_antiship_summary.wave_bns = wave_bns
	EventBus.antiship_resolved.emit(state.last_antiship_summary.to_dict())
	return state.last_antiship_summary.to_dict()


## The subset of ship_reserve whose BNs are bound to a "sent" cohort (crossing this turn), with each
## kept entry trimmed to just those BNs. Empty when nothing sails.
static func crossing_reserve_from_sent_cohorts(state: GameStateData) -> Array:
	var sailing := SealiftResolver.sent_cohort_bn_ids(state.sealift_state)
	if sailing.is_empty():
		return []
	var crossing: Array = []
	for entry_value in state.ship_reserve:
		var entry: Dictionary = entry_value
		var bns: Array = []
		for bn in entry.get("bns", []):
			if sailing.has(String((bn as Dictionary).get("id", ""))):
				bns.append(bn)
		if bns.is_empty():
			continue
		var trimmed: Dictionary = entry.duplicate(true)
		trimmed["bns"] = bns
		crossing.append(trimmed)
	return crossing


## Apply crossing/mine hull losses: carrier losses come out of the "sent" cohorts, escort/screen
## losses out of the ready pool — both booked as destroyed on the fleet. The ShipState bins are then
## reprojected from the sealift state by the caller (plan 0004 D3).
static func apply_crossing_hull_losses(state: GameStateData, destroyed_by_type: Dictionary) -> void:
	for ship_type_value in destroyed_by_type.keys():
		var ship_type := String(ship_type_value)
		var requested := int(destroyed_by_type[ship_type_value])
		if requested <= 0:
			continue
		var ship_state: ShipState = state.fleet.get(ship_type, null)
		if ship_state == null:
			continue
		# Carriers (capacity > 0) lose hulls out of their cohorts; escorts out of the ready screen.
		var ship_def: ShipDef = GameData.ship_defs_by_name.get(ship_type, null)
		var applied: int
		if ship_def != null and ship_def.is_carrier():
			applied = SealiftResolver.remove_carrier_hulls(state.sealift_state, ship_type, requested)
		else:
			applied = mini(requested, ship_state.fleet_surviving_total)
		ship_state.destroyed += applied
		ship_state.fleet_surviving_total -= applied


static func register_ship_losses(state: GameStateData, bn_equiv_lost: int) -> void:
	state.pending_lost_at_sea = maxi(0, bn_equiv_lost)


# --- D5-C Cleanup phase — end-of-turn per-system flag reset ------------------------------------

static func resolve_cleanup_phase(state: GameStateData) -> Dictionary:
	GameData.recompute_hex_ownership()
	# Pure work (flag reset, victory census + verdict, activity latch) lives in CleanupResolver;
	# consumes no dice, so the golden RNG stream is unaffected.
	var outcome := CleanupResolver.resolve(
		state.antiship_systems, GameData.brigades, state.ship_reserve, GameData.victory_config,
		state.turn_number, state._china_has_landed)
	state._china_has_landed = bool(outcome["china_has_landed"])
	state.last_cleanup_summary = outcome["summary"]
	state.game_over = state.last_cleanup_summary.game_over
	state.winner = state.last_cleanup_summary.winner
	EventBus.cleanup_resolved.emit(state.last_cleanup_summary.to_dict())
	return state.last_cleanup_summary.to_dict()


static func taiwan_battalion_census(state: GameStateData) -> Dictionary:
	return CleanupResolver.census(GameData.brigades, state.ship_reserve, GameData.victory_config)


# --- D5-A Frontline phase — redistribute Red brigades along a drawn polyline -------------------

static func frontline_hex_centers() -> Array:
	var centers: Array = []
	for hex_value in GameData.hexes:
		var hex: Hex = hex_value
		centers.append({"id": hex.id, "lat": hex.center.x, "lon": hex.center.y})
	return centers


static func resolve_frontline_phase(state: GameStateData, polyline_coords: Array) -> Dictionary:
	# Only the drawing side's brigades reshuffle along the line — RED here (the amphibious attacker),
	# mirroring TIV front_line_service's single-side filter. Intentional asymmetry, not a bug; if Green
	# ever draws front lines, pass its brigades instead.
	var candidate_brigades: Array = []
	for brigade_value in GameData.brigades.values():
		var brigade: Brigade = brigade_value
		if brigade.team == Brigade.Team.RED and not brigade.destroyed:
			candidate_brigades.append(brigade)

	state.last_frontline_summary = FrontlineResolver.resolve(polyline_coords, frontline_hex_centers(), candidate_brigades)
	for brigade_id in state.last_frontline_summary.moves.keys():
		GameData.set_brigade_hex(String(brigade_id), String(state.last_frontline_summary.moves[brigade_id]))
	EventBus.frontline_resolved.emit(state.last_frontline_summary.to_dict())
	return state.last_frontline_summary.to_dict()


static func active_red_battalion_units() -> Array:
	var units: Array = []
	for brigade_value in GameData.brigades.values():
		var brigade: Brigade = brigade_value
		if brigade.team != Brigade.Team.RED or brigade.destroyed or brigade.hex_id.is_empty():
			continue
		for battalion_value in brigade.composition:
			var battalion: Battalion = battalion_value
			for _qty_index in range(battalion.qty):
				units.append({
					"brigade_id": brigade.id,
					"type": battalion.type,
					"brigade_type": brigade.nato_type,
				})
	return units


## Sealift phase (plan 0004): advance the ship return pipeline and embark this turn's crossing wave.
## Dice-free and pure (SealiftResolver); this wrapper merges the newly-embarked BNs into the reserve,
## records the sailing fleet for the crossing, and reprojects the fleet ShipState bins from the
## advanced sealift state.
static func resolve_sealift_turn(state: GameStateData) -> void:
	if state.sealift_state == null:
		return
	var ready_by_type: Dictionary = {}
	for ship_type in state.fleet.keys():
		ready_by_type[String(ship_type)] = int((state.fleet[ship_type] as ShipState).ready)

	consume_jlsf_orders(state)
	var outcome := SealiftResolver.resolve(
		state.sealift_state, state.ship_reserve, ready_by_type, GameData.ship_defs)

	for entry_value in outcome["embarked_reserve_entries"]:
		var entry: Dictionary = entry_value
		# A JLSF deployment that got hulls this turn is now enroute (plan 0006).
		if JlsfCargo.is_jlsf_entry(entry) and state.infrastructure_state != null:
			var port_id := String(entry.get("port_id", ""))
			if state.infrastructure_state.nodes.has(port_id):
				state.infrastructure_state.nodes[port_id]["jlsf"] = InfrastructureState.JLSF_ENROUTE
		merge_reserve_entry(state, entry)
	state.last_sealift_sent_by_type = outcome["sent_by_type"]
	project_sealift_onto_fleet(state)


## Consume the deploy_jlsf order buffer through the JlsfCargo queueing policy (plan 0006). New
## pseudo-entries go to the FRONT of the mainland pool (logistics open the port gate before more
## troops help); JlsfCargo.queue_deployments owns ordering + marker flips.
static func consume_jlsf_orders(state: GameStateData) -> void:
	if state.infrastructure_state == null or state.sealift_state == null:
		state.jlsf_orders.clear()
		return
	var entries := JlsfCargo.queue_deployments(
		state.jlsf_orders, state.infrastructure_state, GameData.infrastructure, GameData.beaches,
		GameData.beach_to_to, GameData.auto_jlsf, GameData.jlsf_lift_bn_equiv)
	state.jlsf_orders.clear()
	for entry in entries:
		state.sealift_state.mainland_pool.push_front(entry)


## Merge a newly-embarked reserve entry into ship_reserve: append its BNs to the brigade's existing
## entry (a follow-on brigade already partway across) or add a new entry.
static func merge_reserve_entry(state: GameStateData, entry_value) -> void:
	var entry: Dictionary = entry_value
	var brigade_id := String(entry["brigade_id"])
	for existing_value in state.ship_reserve:
		var existing: Dictionary = existing_value
		if String(existing["brigade_id"]) == brigade_id:
			(existing["bns"] as Array).append_array(entry["bns"])
			return
	state.ship_reserve.append(entry)


## Reproject the fleet ShipState bins from the sealift state (the single source of truth for where
## hulls are): surviving_sent/offloading from cohorts, returning from the pipeline, ready as the
## remainder of the surviving fleet. Keeps ShipState.validate()'s invariants honest (plan 0004).
static func project_sealift_onto_fleet(state: GameStateData) -> void:
	var sent: Dictionary = {}
	var offloading: Dictionary = {}
	var returning: Dictionary = {}
	for cohort_value in state.sealift_state.cohorts:
		var cohort: Dictionary = cohort_value
		var bucket: Dictionary = sent if String(cohort["state"]) == SealiftState.STATE_SENT else offloading
		for ship_type in (cohort["hulls_by_type"] as Dictionary).keys():
			bucket[String(ship_type)] = int(bucket.get(String(ship_type), 0)) + int(cohort["hulls_by_type"][ship_type])
	for ship_type in state.sealift_state.return_pipeline.keys():
		for slot_value in (state.sealift_state.return_pipeline[ship_type] as Array):
			returning[String(ship_type)] = int(returning.get(String(ship_type), 0)) + int((slot_value as Dictionary)["count"])
	# Escort types reloading SAMs are away from the screen: all their surviving hulls are busy
	# (returning) until reload completes (plan 0004 D5).
	for ship_type in state.sealift_state.escort_reload.keys():
		var reloading_state: ShipState = state.fleet.get(String(ship_type), null)
		if reloading_state != null:
			returning[String(ship_type)] = int(returning.get(String(ship_type), 0)) + reloading_state.fleet_surviving_total

	for ship_type in state.fleet.keys():
		var ship_state: ShipState = state.fleet[ship_type]
		var ss := int(sent.get(String(ship_type), 0))
		var of := int(offloading.get(String(ship_type), 0))
		var rt := int(returning.get(String(ship_type), 0))
		ship_state.surviving_sent = ss
		ship_state.sent_original = ss
		ship_state.offloading = of
		ship_state.returning = rt
		ship_state.ready = ship_state.fleet_surviving_total - ss - of - rt
		assert(ship_state.ready >= 0, "sealift projection: negative ready for %s (surviving=%d busy=%d)" % [ship_type, ship_state.fleet_surviving_total, ss + of + rt])
		assert(ship_state.validate(), "sealift projection broke ShipState invariant for %s" % ship_type)


static func apply_move_orders(state: GameStateData, team: Brigade.Team) -> void:
	for order in state.orders[team]:
		var move_order: MoveOrder = order
		var brigade: Brigade = GameData.get_brigade(move_order.brigade_id)
		GameData.set_brigade_hex(move_order.brigade_id, move_order.target_hex)
		brigade.moved_this_turn = true
		if move_order.mode == Movement.MODE_ADMINISTRATIVE:
			brigade.adjust_organization(-Brigade.ADMIN_MOVE_ORG_COST)
			brigade.moved_admin_this_turn = true
		else:
			brigade.adjust_organization(-Brigade.TACTICAL_MOVE_ORG_COST)


static func find_contested_hexes() -> Array[String]:
	var contested: Array[String] = []
	for hex_id in GameData.hex_lookup.keys():
		var has_red := false
		var has_green := false
		for brigade_id in GameData.get_brigades_in_hex(String(hex_id)):
			var brigade: Brigade = GameData.get_brigade(String(brigade_id))
			if brigade == null or brigade.destroyed:
				continue
			match brigade.team:
				Brigade.Team.RED:
					has_red = true
				Brigade.Team.GREEN:
					has_green = true
			if has_red and has_green:
				contested.append(String(hex_id))
				break
	return contested


# Defender combat modifier for hex_id: terrain.defender_modifier (1.0 if the hex has no terrain
# classification) times a situational multiplier, currently always 1.0. The `* 1.0` is a
# deliberate seam — a future situational modifier (e.g. a first-landing beach-assault penalty on
# the defender, see BACKLOG) multiplies in here without touching CombatResolver or GameData.
static func defender_combat_modifier(hex_id: String) -> float:
	var terrain := GameData.get_terrain(hex_id)
	var terrain_modifier: float = terrain.defender_modifier if terrain != null else 1.0
	return terrain_modifier * 1.0


# Delegating wrapper (test-called surface) — pure logic lives in CombatResolver.
static func inject_supply_effectiveness(state: GameStateData, units: Array, team: int) -> void:
	var pool: float = state.supply_state.current_dos_tons if state.supply_state != null else 1.0
	CombatResolver.inject_supply_effectiveness(units, team, pool, GameData.red_out_of_supply_effectiveness)


# Thin wrapper: gathers contributors (board/commitment state), delegates the dice-consuming combat
# core to CombatResolver.resolve_at, then applies the result — casualties, FEBA accumulation,
# fought flags — and stamps owner_after. Application stays here because combat at one hex mutates
# state the next hex's contributor gathering reads (ported interleaving semantics).
static func resolve_combat_at(state: GameStateData, hex_id: String, dice: Dice) -> CombatSummary:
	var attacker_brigades := combat_contributors_for(state, Brigade.Team.RED, hex_id)
	var defender_brigades := combat_contributors_for(state, Brigade.Team.GREEN, hex_id)
	var pool: float = state.supply_state.current_dos_tons if state.supply_state != null else 1.0
	# Terrain resolves at hex_id (the defended/contested hex), not the attacker's origin — the
	# defender_modifier models fortification/cover of the ground being held, which belongs to the
	# hex under attack regardless of which side started there.
	var rules := CombatRules.new()
	rules.feba_base_km = GameData.feba_base_km
	rules.red_supply_pool = pool
	rules.red_out_of_supply_effectiveness = GameData.red_out_of_supply_effectiveness
	rules.unscreened_support_strength = GameData.unscreened_support_strength
	rules.maneuver_casualty_weight = GameData.maneuver_casualty_weight
	rules.support_casualty_weight = GameData.support_casualty_weight
	rules.defender_terrain_modifier = defender_combat_modifier(hex_id)
	rules.support_multipliers = GameData.support_multipliers
	rules.combat_base_loss_rate = GameData.combat_base_loss_rate
	rules.combat_attacker_ratio_slope = GameData.combat_attacker_ratio_slope
	rules.combat_defender_ratio_slope = GameData.combat_defender_ratio_slope
	rules.combat_loss_roll_midpoint = GameData.combat_loss_roll_midpoint
	rules.combat_loss_roll_scale = GameData.combat_loss_roll_scale
	rules.combat_min_loss_rate = GameData.combat_min_loss_rate
	rules.combat_max_attacker_loss_rate = GameData.combat_max_attacker_loss_rate
	rules.combat_max_defender_loss_rate = GameData.combat_max_defender_loss_rate
	rules.feba_balance_gain = GameData.feba_balance_gain
	rules.feba_balance_clamp = GameData.feba_balance_clamp
	rules.feba_roll_factor_min = GameData.feba_roll_factor_min
	rules.feba_roll_factor_span = GameData.feba_roll_factor_span
	rules.combat_min_effective_strength = GameData.combat_min_effective_strength
	rules.combat_attacker_advantage_ratio = GameData.combat_attacker_advantage_ratio
	rules.combat_defender_advantage_ratio = GameData.combat_defender_advantage_ratio
	rules.default_combat_strength = GameData.default_combat_strength

	var outcome := CombatResolver.resolve_at(
		hex_id,
		attacker_brigades,
		defender_brigades,
		dice,
		rules
	)
	if outcome["summary"] == null:
		return null

	var result: CombatResult = outcome["result"]
	for casualty in result.attacker_casualties:
		apply_casualty(casualty)
	for casualty in result.defender_casualties:
		apply_casualty(casualty)

	GameData.hex_states[hex_id].feba_km = GameData.hex_states[hex_id].feba_km + result.feba_movement_km
	for brigade_value in attacker_brigades + defender_brigades:
		var fought_brigade: Brigade = brigade_value
		fought_brigade.fought_this_turn = true

	var summary: CombatSummary = outcome["summary"]
	summary.owner_after = String(GameData.hex_states[hex_id].owner)
	return summary


static func combat_contributors_for(state: GameStateData, team: Brigade.Team, hex_id: String) -> Array:
	var contributors: Array = []
	var seen := {}
	for brigade_id_value in GameData.get_brigades_in_hex(hex_id):
		var brigade: Brigade = GameData.get_brigade(String(brigade_id_value))
		if brigade == null or brigade.destroyed or brigade.moved_admin_this_turn or brigade.team != team:
			continue
		contributors.append(brigade)
		seen[brigade.id] = true

	for commitment_value in state.commitments[team]:
		var commitment: CommitOrder = commitment_value
		if commitment.target_hex != hex_id:
			continue
		var brigade: Brigade = GameData.get_brigade(commitment.brigade_id)
		if brigade == null or brigade.destroyed or brigade.moved_admin_this_turn or brigade.team != team:
			continue
		if brigade.id in seen:
			continue
		contributors.append(brigade)
		seen[brigade.id] = true
	return contributors


static func apply_feba_retreats(state: GameStateData) -> void:
	for hex_id in state.last_contested_hexes:
		var feba: float = GameData.hex_states[hex_id].feba_km
		if absf(feba) < FEBA_RETREAT_THRESHOLD_KM:
			continue

		var retreating_team := Brigade.Team.RED
		if feba > 0.0:
			retreating_team = Brigade.Team.GREEN

		var retreaters: Array[Brigade] = []
		for brigade_id_value in GameData.get_brigades_in_hex(hex_id):
			var brigade: Brigade = GameData.get_brigade(String(brigade_id_value))
			if brigade != null and not brigade.destroyed and brigade.team == retreating_team:
				retreaters.append(brigade)
		if retreaters.is_empty():
			continue

		var target := find_retreat_hex(hex_id, retreating_team)
		if target == "":
			continue

		for brigade in retreaters:
			GameData.set_brigade_hex(brigade.id, target)
		GameData.hex_states[hex_id].feba_km = 0.0


static func find_retreat_hex(from_hex: String, team: Brigade.Team) -> String:
	var friendly_owner := HexOwner.RED
	var enemy_team := Brigade.Team.GREEN
	if team == Brigade.Team.GREEN:
		friendly_owner = HexOwner.GREEN
		enemy_team = Brigade.Team.RED

	for neighbor_id_value in GameData.get_neighbors(from_hex):
		var neighbor_id := String(neighbor_id_value)
		var neighbor_terrain := GameData.get_terrain(neighbor_id)
		if neighbor_terrain != null and neighbor_terrain.impassable:
			continue

		var has_enemy := false
		for brigade_id_value in GameData.get_brigades_in_hex(neighbor_id):
			var brigade: Brigade = GameData.get_brigade(String(brigade_id_value))
			if brigade != null and not brigade.destroyed and brigade.team == enemy_team:
				has_enemy = true
				break
		if has_enemy:
			continue

		var owner := String(GameData.hex_states[neighbor_id].owner)
		if owner == friendly_owner or owner == HexOwner.NONE:
			return neighbor_id
	return ""


static func apply_casualty(casualty: Dictionary) -> void:
	var brigade_id := String(casualty["brigade_id"])
	var casualty_type := String(casualty["type"])
	var brigade: Brigade = GameData.get_brigade(brigade_id)
	if brigade == null:
		push_error("Combat casualty references unknown brigade_id: %s" % brigade_id)
		return

	for index in range(brigade.composition.size()):
		var battalion: Battalion = brigade.composition[index]
		if battalion.type != casualty_type:
			continue
		battalion.qty -= 1
		if battalion.qty <= 0:
			brigade.composition.remove_at(index)
		if brigade.get_battalion_count() == 0:
			brigade.destroyed = true
			GameData.remove_brigade_from_map(brigade_id)
		return

	push_error("Combat casualty references missing battalion type '%s' in brigade %s" % [casualty_type, brigade_id])
