class_name InfrastructureResolver
extends RefCounted

## Pure resolver for infrastructure seizure + JLSF repair clock. Source oracle: TIV
## infrastructure_manager.py (refresh_status_from_hex = seizure; progress_status = JLSF repair
## clock). Differences: in-memory state, repair requires hex still Red-held (pauses otherwise),
## status never regresses on recapture (contribution gated by ownership at read time in
## red_offload_nodes). No dice, no autoload access, and since plan 0047 no writes either: the tick is
## CALCULATED here and applied by InfrastructureTransitions, the aggregate's mutation authority.

## Decide what one turn of seizure + repair should do, writing nothing. owner_by_hex: hex_id -> owner
## string (HexOwner.* values, e.g. "red"). repair_turns_per_stage: ticks per repair stage
## (seized->degraded, degraded->operational); default 1 mirrors TIV (+1 turn per stage).
##
## THE SEQUENTIAL-STAGING RULE. Each node's transitions are staged in LOCALS and the repair branch
## reads what the seizure branch just staged — exactly as the pre-0047 mutating `tick` read the status
## it had just written. That chain is production-reachable (see InfrastructureTickPlan's header), and
## a planner that evaluated both branches against the pre-tick snapshot would silently add a turn to
## it. Deferring application is safe DESPITE that only because nodes never read each other and no dice
## are involved — unlike the IJFS stages of plan 0046, where deferral would have changed which draws
## were consumed.
##
## ONE DELIBERATE NON-EQUIVALENCE, on an unreachable path. `repair_turns_per_stage <= 0` used to arm a
## stage at 0 and decrement it to -1, writing a negative timer that `InfrastructureState.validate()`
## itself calls illegal. It is still STAGED that way here, but `InfrastructureTransitions.apply_node_plan`
## refuses the entry and leaves the node alone, so invalid state is no longer written. This is not a
## behaviour change in practice: the only production caller is `ReinforcementPhases.resolve_offload_turn`,
## which passes no argument at all and so takes the default of 1, and the value is not a scenario knob.
## Named here because the diff review round asked the question, and the answer should not have to be
## re-derived. (Verified independently by the tier-1 reviewer: a caller passing <= 0 is ABSENT.)
static func plan_tick(
		state: InfrastructureState, infra_defs: Dictionary, owner_by_hex: Dictionary,
		repair_turns_per_stage: int = 1) -> InfrastructureTickPlan:
	var plan := InfrastructureTickPlan.new()
	var ids: Array = state.nodes.keys()
	ids.sort()
	for id in ids:
		var def_val: Variant = infra_defs.get(id)
		if def_val == null:
			push_error("InfrastructureResolver.plan_tick: no def for node %s" % id)
			continue
		var def_data: InfrastructureDef = def_val
		var node: InfrastructureNodeState = state.nodes[id]
		var is_red := String(owner_by_hex.get(def_data.hex_id, "")) == HexOwner.RED

		var staged_status := node.node_status
		var staged_repair_turns := node.repair_turns_remaining

		# Seizure
		if staged_status == InfrastructureState.STATUS_TAIWANESE and is_red:
			staged_status = InfrastructureState.STATUS_SEIZED
			staged_repair_turns = 0
			plan.record_event(id, InfrastructureTickPlan.EVENT_SEIZED)

		# Repair — reads the status seizure just staged, deliberately.
		if node.jlsf == InfrastructureState.JLSF_ARRIVED and is_red:
			if staged_status == InfrastructureState.STATUS_SEIZED \
					or staged_status == InfrastructureState.STATUS_DEGRADED:
				if staged_repair_turns == 0:
					staged_repair_turns = repair_turns_per_stage
				staged_repair_turns -= 1
				if staged_repair_turns == 0:
					if staged_status == InfrastructureState.STATUS_SEIZED:
						staged_status = InfrastructureState.STATUS_DEGRADED
						plan.record_event(id, InfrastructureTickPlan.EVENT_DEGRADED)
					elif staged_status == InfrastructureState.STATUS_DEGRADED:
						staged_status = InfrastructureState.STATUS_OPERATIONAL
						plan.record_event(id, InfrastructureTickPlan.EVENT_OPERATIONAL)

		if staged_status != node.node_status or staged_repair_turns != node.repair_turns_remaining:
			plan.stage(id, staged_status, staged_repair_turns)

	return plan


## Red-usable offload nodes this turn: Red-held (owner "red") AND status degraded/operational.
## Returns Array (sorted by id) of {"id": String, "kind": String, "to_number": int,
## "rate_tons": float, "hex_id": String}. Rates: OffloadRates.OPERATIONAL_PORT / DEGRADED_PORT /
## OPERATIONAL_AIRBRIDGE / DEGRADED_AIRBRIDGE by (kind, status). hex_id lets the offload wrapper
## place a brigade whose first landed BN came ashore through the node at the node's hex.
static func red_offload_nodes(state: InfrastructureState, infra_defs: Dictionary, owner_by_hex: Dictionary) -> Array:
	var result: Array = []
	var ids: Array = state.nodes.keys()
	ids.sort()
	for id in ids:
		var def_val: Variant = infra_defs.get(id)
		if def_val == null:
			continue
		var def_data: InfrastructureDef = def_val
		var node: InfrastructureNodeState = state.nodes[id]
		var status := node.node_status
		if status != InfrastructureState.STATUS_DEGRADED and status != InfrastructureState.STATUS_OPERATIONAL:
			continue
		var owner: String = String(owner_by_hex.get(def_data.hex_id, ""))
		if owner != HexOwner.RED:
			continue
		var rate: float = 0.0
		if def_data.kind == "port":
			if status == InfrastructureState.STATUS_OPERATIONAL:
				rate = OffloadRates.OPERATIONAL_PORT
			else:
				rate = OffloadRates.DEGRADED_PORT
		elif def_data.kind == "airbridge":
			if status == InfrastructureState.STATUS_OPERATIONAL:
				rate = OffloadRates.OPERATIONAL_AIRBRIDGE
			else:
				rate = OffloadRates.DEGRADED_AIRBRIDGE
		result.append({"id": id, "kind": def_data.kind, "to_number": def_data.to_number, "rate_tons": rate, "hex_id": def_data.hex_id})
	return result
