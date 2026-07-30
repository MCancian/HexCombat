class_name ReinforcementPhases
extends RefCounted

## The "force arrives" phases of the WeGo turn (plan 0038): sealift → offload → ROC mobilization →
## air insertion, plus the helpers each needs. They run consecutively in `TurnConductor.resolve_turn`
## and share one job — putting battalions that were off-map onto the map — so they own their
## resolvers here instead of adding to `TurnConductor`'s fan-out.
##
## `TurnConductor` keeps the ORDERING (the when); this module only owns the how. Same contract as
## every other resolver: static, first argument `state: GameStateData` mutated in place, reads the
## GameData content autoload but never the GameState autoload singleton. Every force write is applied
## by `ForceTransitions` and every hull/fleet write by `SealiftTransitions`; the resolvers below only
## calculate transition plans.


# --- Sealift phase (plan 0004) -----------------------------------------------------------------

static func initialize_ship_reserve(state: GameStateData, reserve: Array) -> void:
	ForceTransitions.initialize_ship_reserve(state, reserve)


## Scenario reset of the fleet, for GameState's reset_to_scenario. Thin pass-through to the fleet's
## authority, in the same style as FiresPhases.reset_antiship_establishment — GameState reaches the
## sealift phase's state through this module, never around it (and so keeps its dependency ceiling).
static func rebuild_fleet(state: GameStateData, ship_defs: Dictionary) -> void:
	SealiftTransitions.rebuild_fleet(state, ship_defs)


## Scenario reset of the infrastructure map, for GameState's reset_to_scenario. Same pass-through
## shape and same reason as rebuild_fleet above: GameState reaches this phase's aggregate through the
## module that owns the phase, never around it, and so keeps its own dependency ceiling.
static func rebuild_infrastructure(state: GameStateData, infra_defs: Dictionary) -> void:
	InfrastructureTransitions.rebuild_infrastructure(state, infra_defs)


## Advance the ship return pipeline and embark this turn's crossing wave. Dice-free and pure
## (SealiftResolver); this wrapper routes force mutations through ForceTransitions, hull/fleet
## mutations through SealiftTransitions, and performs companion updates (JLSF markers).
static func resolve_sealift_turn(state: GameStateData) -> void:
	if state.sealift_state == null:
		return
	var ready_by_type := SealiftTransitions.ready_by_type(state)

	consume_jlsf_orders(state)
	# The hull queues advance first, through their authority: hulls whose return timer expires today
	# sail again today, so the planner below packs against ready + just-returned. Escort reloads finish
	# here too, which is what puts a diverted escort type back on the screen.
	var returned_by_type := SealiftTransitions.tick_returns(state.sealift_state)
	SealiftTransitions.tick_escort_reload(state.sealift_state)
	var outcome := SealiftResolver.resolve(
		state.sealift_state, state.ship_reserve, ready_by_type, returned_by_type, GameData.ship_defs)

	# Apply adopt plan (orphan BNs already in reserve → sent cohort).
	var adopt_plan: Dictionary = outcome.get("adopt_plan", {})
	if not adopt_plan.is_empty():
		var adopt_bn_ids: Array = adopt_plan.get("bn_ids", [])
		var adopt_hulls: Dictionary = adopt_plan.get("hulls_by_type", {})
		var adopt_receipt := ForceTransitions.apply_sent_cohort(
			state.sealift_state, adopt_bn_ids, adopt_hulls, state.ship_reserve,
			adopt_plan.get("ship_categories", {}))
		if not adopt_receipt.success:
			push_error("ForceTransitions adopt cohort refused: %s" % adopt_receipt.error)

	# Apply the whole mainland → reserve + sent-cohort force transaction in one authority call.
	var embark_request = outcome.get("embark_request")
	if embark_request != null:
		var embark_receipts := ForceTransitions.apply_embark(
			state.sealift_state, embark_request, state.ship_reserve)
		for receipt in embark_receipts:
			if not receipt.success:
				push_error("ForceTransitions embark refused: %s" % receipt.error)

	# JLSF is companion cargo sharing the same physical batch; only its infrastructure marker lives
	# outside the force aggregate.
	for entry_value in outcome["embarked_reserve_entries"]:
		var entry: Dictionary = entry_value
		if JlsfCargo.is_jlsf_entry(entry) and state.infrastructure_state != null:
			var port_id := String(entry.get("port_id", ""))
			if state.infrastructure_state.nodes.has(port_id):
				InfrastructureTransitions.mark_jlsf_enroute(state.infrastructure_state, port_id)

	state.last_sealift_sent_by_type = outcome["sent_by_type"]
	SealiftTransitions.project_fleet(state)


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
	ForceTransitions.apply_queue_jlsf(state.sealift_state, entries)


# --- Amphibious offload phase ------------------------------------------------------------------

## Test/operator façade for resolving an unopposed offload outside the full turn conductor. Build
## the same cohort bindings the normal sealift phase would, then advance them past the intentionally
## skipped crossing so ForceTransitions still receives a valid OFFLOADING source location.
static func resolve_unopposed_offload_turn(
		state: GameStateData, dice: Dice, temporary_sealift: SealiftState) -> Dictionary:
	var campaign_sealift := state.sealift_state
	state.sealift_state = temporary_sealift
	var manifest := resolve_offload_turn(state, dice)
	state.sealift_state = campaign_sealift
	return manifest


static func resolve_offload_turn(state: GameStateData, dice: Dice) -> Dictionary:
	assert(dice != null, "resolve_offload_turn requires a Dice instance")
	# Infrastructure lifecycle ticks every offload phase (plan 0006), even with an empty reserve:
	# ground combat can seize a port hex long after the last beach landing. Ownership here is last
	# turn's post-combat state — the producer->consumer edge is combat ownership -> next offload.
	var infra_nodes: Array = []
	if state.infrastructure_state != null:
		var owner_by_hex_map := owner_by_hex()
		# Calculate, then apply through the aggregate's authority, then read. The apply stays HERE,
		# before red_offload_nodes, so this turn's seizures and repairs are visible to this turn's
		# throughput exactly as they were pre-0047.
		var tick_plan := InfrastructureResolver.plan_tick(
			state.infrastructure_state, GameData.infrastructure, owner_by_hex_map)
		InfrastructureTransitions.apply_node_plan(state.infrastructure_state, tick_plan)
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

	# Apply troop landings and JLSF cargo delivery as one physical reserve/cohort transaction.
	var offload_receipt := ForceTransitions.apply_offload(
		GameData, state.ship_reserve, state.sealift_state, outcome["force_request"])
	if not offload_receipt.success:
		push_error("ForceTransitions offload refused: %s" % offload_receipt.error)
		return outcome["manifest"]

	GameData.recompute_hex_ownership()

	var manifest: Dictionary = outcome["manifest"]
	for arrival_value in outcome.get("jlsf_arrivals", []):
		var arrival: Dictionary = arrival_value
		var port_id := String(arrival["port_id"])
		if state.infrastructure_state != null and state.infrastructure_state.nodes.has(port_id):
			InfrastructureTransitions.mark_jlsf_arrived(state.infrastructure_state, port_id)
	if state.sealift_state != null:
		SealiftTransitions.release_hulls(
			state.sealift_state, ForceTransitions.free_emptied_cohorts(state.sealift_state),
			GameData.amphibious_return_time_turns)
		SealiftTransitions.project_fleet(state)
	reconcile_lost_jlsf(state)

	manifest["lost_at_sea"] = state.pending_lost_at_sea
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
		owners[String(hex_id)] = String((GameData.hex_states[hex_id] as HexState).hex_owner)
	return owners


## A JLSF deployment lost whole at sea (its pseudo-BNs all drowned in the crossing) leaves no
## pool or reserve trace; reset its node marker so a new deployment can be ordered/auto-queued.
static func reconcile_lost_jlsf(state: GameStateData) -> void:
	if state.infrastructure_state == null:
		return
	for port_id in InfrastructureTransitions.jlsf_in_transit_ids(state.infrastructure_state):
		if not reserve_or_pool_has(state, JlsfCargo.brigade_id_for(port_id)):
			InfrastructureTransitions.clear_jlsf(state.infrastructure_state, port_id)


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

	var receipt := ForceTransitions.release_mobilized_brigades(
		GameData, state.mobilization_state, summary.force_request(state.turn_number))
	if not receipt.success:
		push_error("ForceTransitions mobilization release refused: %s" % receipt.error)
		EventBus.mobilization_resolved.emit(summary.to_dict())
		return summary

	var arrived: Array = []
	for receipt_brigade_value in receipt.placed_brigades:
		var placed_id := String(receipt_brigade_value)
		var brigade: Brigade = GameData.get_brigade(placed_id)
		if brigade != null:
			arrived.append(brigade)
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
	if hex_state.hex_owner == HexOwner.RED or hex_state.hex_owner == HexOwner.CONTESTED:
		return false
	var terrain: TerrainType = GameData.get_terrain(hex_id)
	return terrain != null and not terrain.impassable


# --- Air insertion (plan 0032) — Red's non-amphibious reinforcement phase ----------------------

## Fly this turn's ordered battalions onto the island. The resolver decides who flies, who dies and
## what the lift loses; this wrapper owns building the typed request, calling ForceTransitions to
## apply force mutations, then performing companion updates (caps erosion, history append, ownership
## recompute) and the EventBus emit.
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
	state.air_insert_orders = []
	var landings: Array = outcome["landings"]
	if landings.is_empty():
		EventBus.air_insertion_resolved.emit(summary.to_dict())
		return summary

	var receipt := ForceTransitions.apply_air_insertion_outcome(
		GameData, state.air_insertion_state, outcome["force_request"])
	if not receipt.success:
		push_error("ForceTransitions air insertion refused: %s" % receipt.error)
		EventBus.air_insertion_resolved.emit(summary.to_dict())
		return summary

	# Companion updates: caps erosion and history (NOT part of the force aggregate).
	state.air_insertion_state.caps = summary.caps_after.duplicate()
	for drop_value in summary.drops:
		var drop: Dictionary = drop_value
		state.air_insertion_state.history.append({
			"turn": state.turn_number,
			"brigade_id": String(drop["brigade_id"]),
			"lift_class": String(drop["lift_class"]),
			"hex_id": String(drop["hex_id"]),
			"landed": int(drop["landed"]),
			"lost": int(drop["lost"]),
		})
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
			return hex_state != null and hex_state.hex_owner == HexOwner.RED,
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
