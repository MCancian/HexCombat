extends GdUnitTestSuite

## The `infrastructure` aggregate's authority (plan 0047 step 5): what InfrastructureTransitions
## refuses, and what its read query reports.
##
## The tick SEMANTICS live in tests/infrastructure_resolver_test.gd, and the sequencing rules the
## calculate/apply split must not break live in infrastructure_authority_characterization_test.gd.
## What is left — and what is here — is the authority's own contract: every guard reports and changes
## nothing rather than dying, because a research batch must not lose a run to one malformed row.

var _defs: Dictionary = {}


func before_test() -> void:
	_defs = {"port_a": _port("port_a", "hex_001", 1), "port_b": _port("port_b", "hex_002", 2)}


func _port(id: String, hex_id: String, to_number: int) -> InfrastructureDef:
	var def := InfrastructureDef.new()
	def.id = id
	def.kind = "port"
	def.hex_id = hex_id
	def.to_number = to_number
	return def


# --- apply_node_plan refusals --------------------------------------------------------------------

func test_apply_refuses_an_illegal_status_and_leaves_the_node_alone() -> void:
	var state := InfrastructureStateBuilder.build(_defs)
	var plan := InfrastructureTickPlan.new()
	plan.stage("port_a", "bogus", 0)

	await assert_error(func() -> void:
		InfrastructureTransitions.apply_node_plan(state, plan)
	).is_push_error("InfrastructureTransitions.apply_node_plan: illegal status 'bogus' for node port_a")

	assert_str((state.nodes["port_a"] as InfrastructureNodeState).node_status).is_equal(
		InfrastructureState.STATUS_TAIWANESE)


func test_apply_refuses_a_negative_repair_timer() -> void:
	var state := InfrastructureStateBuilder.build(_defs)
	var plan := InfrastructureTickPlan.new()
	plan.stage("port_a", InfrastructureState.STATUS_SEIZED, -1)

	await assert_error(func() -> void:
		InfrastructureTransitions.apply_node_plan(state, plan)
	).is_push_error("InfrastructureTransitions.apply_node_plan: negative repair_turns_remaining -1 for node port_a")

	var node: InfrastructureNodeState = state.nodes["port_a"]
	assert_str(node.node_status).is_equal(InfrastructureState.STATUS_TAIWANESE)
	assert_int(node.repair_turns_remaining).is_equal(0)


## One bad entry must not cost the rest of the map its turn.
func test_apply_keeps_going_past_a_refused_entry() -> void:
	var state := InfrastructureStateBuilder.build(_defs)
	var plan := InfrastructureTickPlan.new()
	plan.stage("port_a", "bogus", 0)
	plan.stage("port_b", InfrastructureState.STATUS_SEIZED, 0)

	await assert_error(func() -> void:
		InfrastructureTransitions.apply_node_plan(state, plan)
	).is_push_error("InfrastructureTransitions.apply_node_plan: illegal status 'bogus' for node port_a")

	assert_str((state.nodes["port_b"] as InfrastructureNodeState).node_status).is_equal(
		InfrastructureState.STATUS_SEIZED)


func test_apply_refuses_an_unknown_node() -> void:
	var state := InfrastructureStateBuilder.build(_defs)
	var plan := InfrastructureTickPlan.new()
	plan.stage("port_ghost", InfrastructureState.STATUS_SEIZED, 0)

	await assert_error(func() -> void:
		InfrastructureTransitions.apply_node_plan(state, plan)
	).is_push_error("InfrastructureTransitions.apply_node_plan: no infrastructure node 'port_ghost'")

	assert_bool(state.nodes.has("port_ghost")).is_false()


# --- JLSF marker ---------------------------------------------------------------------------------

func test_queue_jlsf_accepts_once_then_refuses_silently() -> void:
	var state := InfrastructureStateBuilder.build(_defs)

	assert_bool(InfrastructureTransitions.queue_jlsf(state, "port_a")).is_true()
	assert_str((state.nodes["port_a"] as InfrastructureNodeState).jlsf).is_equal(
		InfrastructureState.JLSF_QUEUED)
	assert_bool(InfrastructureTransitions.queue_jlsf(state, "port_a")).override_failure_message(
		"a port already carrying a marker refuses a second deployment — ordinary play, not an error"
	).is_false()


func test_queue_jlsf_refuses_an_unknown_port() -> void:
	var state := InfrastructureStateBuilder.build(_defs)
	var accepted := false

	await assert_error(func() -> void:
		accepted = InfrastructureTransitions.queue_jlsf(state, "port_ghost")
	).is_push_error("InfrastructureTransitions.queue_jlsf: no infrastructure node 'port_ghost'")

	assert_bool(accepted).is_false()


## The marker walks queued -> enroute -> arrived and back to none, and a cleared port accepts a new
## deployment — the loss-and-redeploy path reconcile_lost_jlsf depends on.
func test_marker_lifecycle_and_redeployment() -> void:
	var state := InfrastructureStateBuilder.build(_defs)
	var node: InfrastructureNodeState = state.nodes["port_a"]

	assert_bool(InfrastructureTransitions.queue_jlsf(state, "port_a")).is_true()
	InfrastructureTransitions.mark_jlsf_enroute(state, "port_a")
	assert_str(node.jlsf).is_equal(InfrastructureState.JLSF_ENROUTE)
	InfrastructureTransitions.mark_jlsf_arrived(state, "port_a")
	assert_str(node.jlsf).is_equal(InfrastructureState.JLSF_ARRIVED)
	InfrastructureTransitions.clear_jlsf(state, "port_a")
	assert_str(node.jlsf).is_equal(InfrastructureState.JLSF_NONE)

	assert_bool(InfrastructureTransitions.queue_jlsf(state, "port_a")).override_failure_message(
		"a cleared port must accept a new deployment"
	).is_true()


func test_jlsf_in_transit_ids_reports_only_queued_and_enroute() -> void:
	var state := InfrastructureStateBuilder.build(_defs)
	InfrastructureTransitions.queue_jlsf(state, "port_a")
	InfrastructureTransitions.queue_jlsf(state, "port_b")
	InfrastructureTransitions.mark_jlsf_enroute(state, "port_b")

	assert_array(InfrastructureTransitions.jlsf_in_transit_ids(state)).is_equal(
		["port_a", "port_b"])

	# An ARRIVED deployment is ashore: it has a physical trace and is not swept for loss.
	InfrastructureTransitions.mark_jlsf_arrived(state, "port_b")
	assert_array(InfrastructureTransitions.jlsf_in_transit_ids(state)).is_equal(["port_a"])

	InfrastructureTransitions.clear_jlsf(state, "port_a")
	assert_array(InfrastructureTransitions.jlsf_in_transit_ids(state)).is_empty()


# --- Aggregate lifecycle -------------------------------------------------------------------------

## rebuild_infrastructure replaces the handle wholesale, discarding the previous game's node states —
## the two-games-in-one-process case, on the infrastructure side.
func test_rebuild_replaces_the_handle_and_discards_prior_state() -> void:
	var state := GameStateData.new()
	InfrastructureTransitions.rebuild_infrastructure(state, _defs)
	var first := state.infrastructure_state
	InfrastructureTransitions.mark_jlsf_arrived(first, "port_a")
	(first.nodes["port_a"] as InfrastructureNodeState).node_status = InfrastructureState.STATUS_OPERATIONAL

	InfrastructureTransitions.rebuild_infrastructure(state, _defs)

	assert_bool(state.infrastructure_state == first).override_failure_message(
		"rebuild must hand back a fresh aggregate, not reset the old one in place"
	).is_false()
	var node: InfrastructureNodeState = state.infrastructure_state.nodes["port_a"]
	assert_str(node.node_status).is_equal(InfrastructureState.STATUS_TAIWANESE)
	assert_str(node.jlsf).is_equal(InfrastructureState.JLSF_NONE)
