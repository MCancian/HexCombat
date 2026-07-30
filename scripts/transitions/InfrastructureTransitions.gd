class_name InfrastructureTransitions
extends RefCounted

## THE mutation authority for the `infrastructure` aggregate (plan 0047) — the exact and only
## production writer of a port/airbridge node's lifecycle (`node_status`, `repair_turns_remaining`,
## `jlsf`), of the `InfrastructureState.nodes` container, and of the `GameStateData.infrastructure_state`
## handle. Living in scripts/transitions/ grants nothing by itself: authority is granted to this exact
## file by name in tools/mutation_authority_manifest.json, which is also the only home for the field and
## writer lists. Do not copy them here.
##
## The shape is the house shape: a CALCULATOR (`InfrastructureResolver.plan_tick`) returns an outcome,
## the coordinator (`ReinforcementPhases`) hands that outcome to one job-shaped method here, and only
## this file turns it into state. Nothing here rolls dice, reads an autoload, or decides policy.
##
## Two design choices are load-bearing and were made against measured precedent:
##
##   * **There is no `force_status`.** An authority method taking an arbitrary status — whose only
##     caller would have been a scripted validator — is an authority bypass in sanctioned clothing: it
##     lets any caller express nearly every forbidden assignment through the permitted file. The
##     validator that wanted one now drives the real repair clock instead (plan 0047 step 4).
##   * **The JLSF marker gets four job-shaped methods, not one setter.** `queue_jlsf` additionally
##     REPORTS whether it queued, because `JlsfCargo.queue_deployments` decides whether to emit a pool
##     entry from exactly that fact — its second iteration over a duplicate explicit order must observe
##     the `QUEUED` the first one wrote. That is why the marker write stays inside its sequential loop
##     rather than becoming a snapshot plan (same reason as plan 0046's IJFS stages).
##
## Guards `push_error` and change nothing rather than `assert(false)`: a research batch must not die on
## one bad row, and a push_error guard is exercisable by a test via `assert_error(...).is_push_error(...)`.
## The closing `assert(state.validate())` is the debug-build audit that no applied transition left the
## aggregate structurally invalid.

const _VALID_STATUSES := [
	InfrastructureState.STATUS_TAIWANESE,
	InfrastructureState.STATUS_SEIZED,
	InfrastructureState.STATUS_DEGRADED,
	InfrastructureState.STATUS_OPERATIONAL,
]


# ── Aggregate lifecycle ─────────────────────────────────────────────────────────────────────────

## Replace the infrastructure state with a fresh one built from the (possibly changed) scenario
## definitions. This is a scenario RESET of live state, not construction of unpublished state, which is
## why it routes through the authority instead of GameState assigning the builder's result itself —
## the same division `SealiftTransitions.rebuild_fleet` draws.
static func rebuild_infrastructure(state: GameStateData, infra_defs: Dictionary) -> void:
	state.infrastructure_state = InfrastructureStateBuilder.build(infra_defs)


# ── Node lifecycle ──────────────────────────────────────────────────────────────────────────────

## Apply one tick's plan. Every staged entry is checked BEFORE it is written — an unknown node, an
## illegal status or a negative repair timer is refused with a push_error and leaves that node alone,
## so one malformed row cannot corrupt the rest of the map.
static func apply_node_plan(state: InfrastructureState, plan: InfrastructureTickPlan) -> void:
	if state == null or plan == null:
		return
	for id_value in plan.node_states.keys():
		var id := String(id_value)
		var staged: Dictionary = plan.node_states[id_value]
		var node := _node(state, id, "apply_node_plan")
		if node == null:
			continue
		var staged_status := String(staged.get("node_status", ""))
		var staged_repair_turns := int(staged.get("repair_turns_remaining", 0))
		if not staged_status in _VALID_STATUSES:
			push_error("InfrastructureTransitions.apply_node_plan: illegal status '%s' for node %s" % [
				staged_status, id])
			continue
		if staged_repair_turns < 0:
			push_error("InfrastructureTransitions.apply_node_plan: negative repair_turns_remaining %d for node %s" % [
				staged_repair_turns, id])
			continue
		node.node_status = staged_status
		node.repair_turns_remaining = staged_repair_turns
	assert(state.validate(), "InfrastructureTransitions.apply_node_plan left the aggregate invalid")


# ── JLSF marker ─────────────────────────────────────────────────────────────────────────────────

## Accept a JLSF deployment for `port_id`, reporting whether it was accepted. A node already carrying
## a marker refuses SILENTLY — a second deployment order for a port that is already queued/enroute/
## arrived is ordinary play, not an error — and the caller uses the `false` to skip emitting a lift
## entry for it.
static func queue_jlsf(state: InfrastructureState, port_id: String) -> bool:
	var node := _node(state, port_id, "queue_jlsf")
	if node == null:
		return false
	if node.jlsf != InfrastructureState.JLSF_NONE:
		return false
	node.jlsf = InfrastructureState.JLSF_QUEUED
	assert(state.validate(), "InfrastructureTransitions.queue_jlsf left the aggregate invalid")
	return true


## The deployment has been loaded onto a sailing cohort.
static func mark_jlsf_enroute(state: InfrastructureState, port_id: String) -> void:
	_set_marker(state, port_id, InfrastructureState.JLSF_ENROUTE, "mark_jlsf_enroute")


## The deployment came ashore at its port; from here the repair clock runs.
static func mark_jlsf_arrived(state: InfrastructureState, port_id: String) -> void:
	_set_marker(state, port_id, InfrastructureState.JLSF_ARRIVED, "mark_jlsf_arrived")


## Return the node to "no deployment", so a new one can be ordered or auto-queued. Used when a
## deployment is lost whole at sea and leaves no pool or reserve trace to reconcile against.
static func clear_jlsf(state: InfrastructureState, port_id: String) -> void:
	_set_marker(state, port_id, InfrastructureState.JLSF_NONE, "clear_jlsf")


## Node ids whose deployment is ordered but not yet ashore, in node order — the set
## `ReinforcementPhases.reconcile_lost_jlsf` sweeps for deployments that drowned in the crossing.
## A read query on the authority, matching `SealiftTransitions.ready_by_type`: it is what lets the
## coordinator sweep the markers without naming `InfrastructureState` and its constants at all.
static func jlsf_in_transit_ids(state: InfrastructureState) -> Array[String]:
	var ids: Array[String] = []
	if state == null:
		return ids
	for id_value in state.nodes.keys():
		var node_value: Variant = state.nodes[id_value]
		if not (node_value is InfrastructureNodeState):
			continue
		var node: InfrastructureNodeState = node_value
		if node.jlsf == InfrastructureState.JLSF_QUEUED or node.jlsf == InfrastructureState.JLSF_ENROUTE:
			ids.append(String(id_value))
	return ids


# ── Internals ───────────────────────────────────────────────────────────────────────────────────

## The one place a marker is assigned. Private on purpose: exposed, it would be the generic
## `set_marker(node, value)` this file exists to not have.
static func _set_marker(state: InfrastructureState, port_id: String, marker: String, operation: String) -> void:
	var node := _node(state, port_id, operation)
	if node == null:
		return
	node.jlsf = marker
	assert(state.validate(), "InfrastructureTransitions.%s left the aggregate invalid" % operation)


## Resolve a node id, reporting rather than crashing when it is absent or the container holds
## something that is not a node — `nodes` is an untyped Dictionary, so both are expressible.
static func _node(state: InfrastructureState, port_id: String, operation: String) -> InfrastructureNodeState:
	if state == null:
		return null
	var node_value: Variant = state.nodes.get(port_id)
	if node_value == null:
		push_error("InfrastructureTransitions.%s: no infrastructure node '%s'" % [operation, port_id])
		return null
	if not (node_value is InfrastructureNodeState):
		push_error("InfrastructureTransitions.%s: node '%s' is not an InfrastructureNodeState" % [
			operation, port_id])
		return null
	return node_value
