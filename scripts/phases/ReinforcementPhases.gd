class_name ReinforcementPhases
extends RefCounted

## The "force arrives" phases of the WeGo turn (plan 0038): sealift → offload → ROC mobilization →
## air insertion, plus the helpers each needs. They run consecutively in `TurnConductor.resolve_turn`
## and share one job — putting battalions that were off-map onto the map — so they own their
## resolvers here instead of adding to `TurnConductor`'s fan-out.
##
## `TurnConductor` keeps the ORDERING (the when); this module only owns the how. Same contract as
## every other resolver: static, first argument `state: GameStateData` mutated in place, reads the
## GameData content autoload but never the GameState autoload singleton. Roster-shrinking goes
## through `RosterMutations` (shared with combat and the crossing) so the two modules stay a DAG.


# --- Sealift phase (plan 0004) -----------------------------------------------------------------

## Advance the ship return pipeline and embark this turn's crossing wave. Dice-free and pure
## (SealiftResolver); this wrapper merges the newly-embarked BNs into the reserve, records the
## sailing fleet for the crossing, and reprojects the fleet ShipState bins from the advanced
## sealift state.
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
## Called from the crossing too (FiresPhases.resolve_antiship_turn) — hull losses reproject.
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


# --- Amphibious offload phase ------------------------------------------------------------------

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
		GameData.place_brigade_with_bearing(
			brigade_id, String(landing["beach_hex"]), float(landing["offset_bearing"]), "offload")
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


## Beach-landing order for the current reserve (test/UI-called surface via the GameState façade) —
## the priority policy itself lives in OffloadResolver.
static func ship_reserve_priority_order(state: GameStateData) -> Array[String]:
	return OffloadResolver.priority_order(state.ship_reserve)


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


# --- ROC mobilization (plan 0029 Tier A2) — Green reinforcement phase ---------------------------

## Release the Green brigades whose mobilization is complete onto the map. Runs immediately after
## amphibious offload and before movement/commit: the two sides' reinforcement steps then sit at the
## same seam, and a brigade that arrives during resolution first takes orders in the NEXT planning
## phase — exactly like a Red brigade that just landed. Consumes no dice; a scenario with an empty
## mobilization schedule (the default) leaves state and RNG untouched.
static func resolve_mobilization_turn(state: GameStateData) -> MobilizationSummary:
	var summary := MobilizationResolver.resolve(
		state.mobilization_state, state.turn_number, GameData.brigades,
		func(garrison_hex: String) -> String:
			return MobilizationResolver.find_arrival_hex(
				garrison_hex,
				func(hex_id: String) -> Array: return GameData.get_neighbors(hex_id),
				func(hex_id: String) -> bool: return hex_can_receive_mobilized(hex_id)))
	if summary.arrivals.is_empty():
		EventBus.mobilization_resolved.emit(summary.to_dict())
		return summary

	var arrived: Array = []
	for arrival_value in summary.arrivals:
		var arrival: Dictionary = arrival_value
		var brigade_id := String(arrival["brigade_id"])
		GameData.set_brigade_hex(brigade_id, String(arrival["hex_id"]))
		arrived.append(GameData.get_brigade(brigade_id))
	# A formation only becomes an IJFS maneuver target once it is on the island; append its
	# per-battalion targets now (append-only, so every existing target keeps its position in the
	# list and its detection continuity).
	if state.ijfs_state != null:
		IjfsResolver.add_maneuver_targets(state.ijfs_state, arrived, state._ijfs_day)
	GameData.recompute_hex_ownership()
	EventBus.mobilization_resolved.emit(summary.to_dict())
	return summary


## A mobilizing brigade may form up on a placed, passable hex that the enemy neither holds nor
## contests. Enemy-held ground is not a mobilization site — taking it back is a counterattack
## (plan 0029 Tier B), not a reinforcement.
static func hex_can_receive_mobilized(hex_id: String) -> bool:
	var hex_state: HexState = GameData.hex_states.get(hex_id, null)
	if hex_state == null:
		return false
	if hex_state.owner == HexOwner.RED or hex_state.owner == HexOwner.CONTESTED:
		return false
	var terrain: TerrainType = GameData.get_terrain(hex_id)
	return terrain != null and not terrain.impassable


# --- Air insertion (plan 0032) — Red's non-amphibious reinforcement phase ----------------------

## Fly this turn's ordered battalions onto the island. The resolver decides who flies, who dies and
## what the lift loses; this wrapper owns the GameData mutation (set_brigade_hex for the survivors,
## RosterMutations.apply_casualty for the losses), the ownership recompute and the EventBus emit —
## the same split OffloadResolver and MobilizationResolver use.
##
## The air-defence picture comes from THIS turn's IJFS summary (post-strike), so suppressing SAMs
## before dropping visibly pays off; the MANPADS layer is read separately because it is deliberately
## outside the AD-health metric. An empty pool or no orders leaves state and RNG untouched.
static func resolve_air_insertion_turn(state: GameStateData, dice: Dice) -> AirInsertionSummary:
	var outcome := AirInsertionResolver.resolve(
		state.air_insertion_state, state.air_insert_orders, state.turn_number,
		AirInsertionResolver.threat_from_ijfs_summary(state.last_ijfs_summary),
		AirInsertionStateBuilder.attrition_config(GameData.red_air_insertion),
		func(hex_id: String) -> bool: return hex_can_receive_insertion(hex_id),
		dice)
	var summary: AirInsertionSummary = outcome["summary"]
	# One-shot orders, consumed on resolution like jlsf_orders — an unflown drop is not re-attempted
	# next turn behind the player's back.
	state.air_insert_orders = []
	var landings: Array = outcome["landings"]
	if landings.is_empty():
		EventBus.air_insertion_resolved.emit(summary.to_dict())
		return summary

	for landing_value in landings:
		var landing: Dictionary = landing_value
		var brigade_id := String(landing["brigade_id"])
		# Losses first: a battalion shot down on the way in never reaches the hex, and killing it
		# before the landing keeps a brigade that lost its whole packet off the map entirely.
		for lost_value in landing["lost_bns"]:
			RosterMutations.apply_casualty({
				"brigade_id": brigade_id,
				"type": String((lost_value as Dictionary)["type"]),
				"cause": "air_insertion",
			})
		if landing["first_landing"]:
			GameData.set_brigade_hex(brigade_id, String(landing["hex_id"]))
			continue
		# Follow-up packets reinforce the brigade where it already stands — a formation occupies one
		# hex, so a second drop cannot put half of it somewhere else. OrderValidator enforces that
		# the target matches; a mismatch here is an order that slipped through, not a game state.
		var landed_brigade: Brigade = GameData.get_brigade(brigade_id)
		if landed_brigade != null and landed_brigade.hex_id != String(landing["hex_id"]):
			push_error("Air insertion follow-up for %s targeted %s but the brigade is at %s" % [
				brigade_id, landing["hex_id"], landed_brigade.hex_id])
	GameData.recompute_hex_ownership()
	EventBus.air_insertion_resolved.emit(summary.to_dict())
	return summary


## Air-landed brigades currently cut off from the beachhead (plan 0032) — they fight out of supply
## even with a full theatre pool. Recomputed every combat, so a corridor punched through this turn
## supplies them and a corridor cut isolates them again.
static func isolated_air_landed_brigades(state: GameStateData) -> Dictionary:
	if state.air_insertion_state == null or state.air_insertion_state.landed.is_empty():
		return {}
	var brigade_hexes: Dictionary = {}
	for brigade_id_value in state.air_insertion_state.landed:
		var brigade: Brigade = GameData.get_brigade(String(brigade_id_value))
		if brigade != null and not brigade.destroyed:
			brigade_hexes[brigade.id] = brigade.hex_id
	return AirInsertionResolver.isolated_brigades(
		state.air_insertion_state.landed, brigade_hexes, red_lodgement_hexes(state),
		func(hex_id: String) -> bool:
			var hex_state: HexState = GameData.hex_states.get(hex_id, null)
			return hex_state != null and hex_state.owner == HexOwner.RED,
		func(hex_id: String) -> Array: return GameData.get_neighbors(hex_id))


## Where Red's supply enters the island: the scenario's landing beaches plus any port/airbridge Red
## can offload through. These are the roots the corridor flood starts from — the same nodes that
## physically feed the buildup, so "connected to the beach" means what it says.
static func red_lodgement_hexes(state: GameStateData) -> Array:
	var hexes: Array = []
	for reserve_entry_value in GameData.red_ship_reserve:
		var reserve_entry: Dictionary = reserve_entry_value
		hexes.append(String(reserve_entry["beach_hex"]))
	if state.infrastructure_state != null:
		for node_value in InfrastructureResolver.red_offload_nodes(
				state.infrastructure_state, GameData.infrastructure, owner_by_hex()):
			hexes.append(String((node_value as Dictionary)["hex_id"]))
	return hexes


## Any placed, passable hex is a drop zone (USER design call 2026-07-24: land on any hex). Unlike
## mobilization, enemy-held and contested ground is explicitly legal — bypassing the crossing is the
## whole point, and an opposed drop is paid for by the ground combat that follows in the same turn.
static func hex_can_receive_insertion(hex_id: String) -> bool:
	if not GameData.hex_states.has(hex_id):
		return false
	var terrain: TerrainType = GameData.get_terrain(hex_id)
	return terrain != null and not terrain.impassable
