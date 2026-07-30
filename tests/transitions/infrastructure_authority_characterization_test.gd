extends GdUnitTestSuite

## Plan 0047 step 1 — characterization. These pin the infrastructure node-lifecycle behaviours the
## plan is about to route through `InfrastructureTransitions`, BEFORE any of them moves.
##
## What is deliberately NOT re-tested here: the seizure/repair/rate matrix already covered by
## tests/infrastructure_resolver_test.gd, and the queue ordering already covered by
## tests/jlsf_pipeline_test.gd. This suite covers only what those leave open — and each of the three
## gaps below is a behaviour a plausible "make the resolver pure" refactor would silently change.

var _defs: Dictionary = {}


func before_test() -> void:
	_defs = {"port_a": _port("port_a", "hex_001", 1), "port_b": _port("port_b", "hex_002", 2)}


# --- 1. seizure and repair in the SAME tick ------------------------------------------------------
# InfrastructureResolver.tick's seizure branch WRITES status, and its repair branch a few lines later
# READS it in the same iteration. So a Taiwanese node that already has an arrived JLSF is seized and
# repaired in one tick.
#
# This is production-reachable, which is the whole point: an explicit `deploy_jlsf` order does NOT
# require a seized node (JlsfCargo.gd:82-86 queues any id whose marker is `none`), so a JLSF can be
# ordered, sail, and arrive at a port that Red only captures later.
#
# A pure calculator that evaluated both branches against the PRE-tick snapshot would leave this node
# SEIZED and quietly add a turn to the path. It must stage each node's transitions sequentially.

func test_taiwanese_with_arrived_jlsf_is_seized_and_degraded_in_one_tick() -> void:
	var state := InfrastructureStateBuilder.build(_defs)
	var node: InfrastructureNodeState = state.nodes["port_a"]
	node.jlsf = InfrastructureState.JLSF_ARRIVED

	var result := InfrastructureResolver.plan_tick(state, _defs, {"hex_001": HexOwner.RED})
	# The planner is pure: nothing has moved yet, however long the staged chain is.
	assert_str(node.node_status).override_failure_message(
		"plan_tick must not write — it stages the chain in locals"
	).is_equal(InfrastructureState.STATUS_TAIWANESE)
	InfrastructureTransitions.apply_node_plan(state, result)

	assert_str(node.node_status).override_failure_message(
		"seizure and repair chain within one tick — the repair branch reads the status seizure just wrote"
	).is_equal(InfrastructureState.STATUS_DEGRADED)

	# One node, TWO events, in application order. A plan carrying one label per node cannot express
	# this.
	assert_int(result.events.size()).is_equal(2)
	assert_str(String(result.events[0]["id"])).is_equal("port_a")
	assert_str(String(result.events[0]["event"])).is_equal("seized")
	assert_str(String(result.events[1]["id"])).is_equal("port_a")
	assert_str(String(result.events[1]["event"])).is_equal("degraded")


## At two turns per stage the same path stops one step short: seizure still happens on tick 1, the
## repair clock is armed and decremented to 1, and DEGRADED only lands on tick 2.
func test_same_tick_chain_at_two_turns_per_stage() -> void:
	var state := InfrastructureStateBuilder.build(_defs)
	var node: InfrastructureNodeState = state.nodes["port_a"]
	node.jlsf = InfrastructureState.JLSF_ARRIVED
	var owner_by_hex := {"hex_001": HexOwner.RED}

	var r1 := InfrastructureResolver.plan_tick(state, _defs, owner_by_hex, 2)
	InfrastructureTransitions.apply_node_plan(state, r1)
	assert_str(node.node_status).is_equal(InfrastructureState.STATUS_SEIZED)
	assert_int(node.repair_turns_remaining).is_equal(1)
	assert_int(r1.events.size()).is_equal(1)
	assert_str(String(r1.events[0]["event"])).is_equal("seized")

	var r2 := InfrastructureResolver.plan_tick(state, _defs, owner_by_hex, 2)
	InfrastructureTransitions.apply_node_plan(state, r2)
	assert_str(node.node_status).is_equal(InfrastructureState.STATUS_DEGRADED)
	assert_int(r2.events.size()).is_equal(1)
	assert_str(String(r2.events[0]["event"])).is_equal("degraded")


# --- 2. the queue loop reads back its own writes -------------------------------------------------
# `queue_deployments` emits one pool entry per port because the marker it wrote on the first pass is
# observed by the second. A calculator evaluating every request against the initial snapshot would
# emit a duplicate deployment — two lift charges and two pseudo-brigades for one port.

func test_duplicate_explicit_orders_produce_one_deployment() -> void:
	var state := InfrastructureStateBuilder.build(_defs)

	var entries := JlsfCargo.queue_deployments(
		["port_a", "port_a"], state, _defs, _beaches(), _beach_to_to(), false, 4)

	assert_int(entries.size()).override_failure_message(
		"the second pass must observe the QUEUED marker the first pass wrote"
	).is_equal(1)
	assert_str(String((state.nodes["port_a"] as InfrastructureNodeState).jlsf)).is_equal(
		InfrastructureState.JLSF_QUEUED)


## Same seam from the other side: an explicitly ordered port that the auto policy would ALSO pick up
## is queued once, not twice.
func test_explicit_and_auto_overlap_produces_one_deployment() -> void:
	var state := InfrastructureStateBuilder.build(_defs)
	(state.nodes["port_a"] as InfrastructureNodeState).node_status = InfrastructureState.STATUS_SEIZED

	var entries := JlsfCargo.queue_deployments(
		["port_a"], state, _defs, _beaches(), _beach_to_to(), true, 4)

	assert_int(entries.size()).is_equal(1)
	assert_str(String((entries[0] as Dictionary)["port_id"])).is_equal("port_a")


# --- 3. a JLSF lost whole at sea frees the port for a new deployment ------------------------------
# ReinforcementPhases.reconcile_lost_jlsf: a deployment whose pseudo-BNs all drowned leaves no pool
# or reserve trace, so the marker must go back to `none` or the port is permanently un-redeployable.
# Nothing tested this before; the plan moves the marker write into the authority.

func test_marker_states_that_permit_a_new_deployment() -> void:
	var state := InfrastructureStateBuilder.build(_defs)
	var node: InfrastructureNodeState = state.nodes["port_a"]

	for blocked in [InfrastructureState.JLSF_QUEUED, InfrastructureState.JLSF_ENROUTE,
			InfrastructureState.JLSF_ARRIVED]:
		node.jlsf = String(blocked)
		var refused := JlsfCargo.queue_deployments(
			["port_a"], state, _defs, _beaches(), _beach_to_to(), false, 4)
		assert_int(refused.size()).override_failure_message(
			"a port whose marker is '%s' must refuse a new deployment" % blocked).is_equal(0)

	node.jlsf = InfrastructureState.JLSF_NONE
	var accepted := JlsfCargo.queue_deployments(
		["port_a"], state, _defs, _beaches(), _beach_to_to(), false, 4)
	assert_int(accepted.size()).override_failure_message(
		"clearing the marker back to 'none' is what makes a lost JLSF redeployable").is_equal(1)


# --- 4. the serialized shape the typed node must not move ----------------------------------------
# `InfrastructureState.to_dict()` has no caller today, so this is forward-compat rather than a
# fixture guard — but the typed node has to reproduce it exactly, keys and order included.

func test_state_to_dict_shape() -> void:
	var state := InfrastructureStateBuilder.build(_defs)
	# NON-DEFAULT values, deliberately: serialized from a fresh build, this test would also pass
	# against an implementation that hardcoded taiwanese/0/none.
	var live: InfrastructureNodeState = state.nodes["port_a"]
	live.node_status = InfrastructureState.STATUS_DEGRADED
	live.repair_turns_remaining = 3
	live.jlsf = InfrastructureState.JLSF_ENROUTE

	var as_dict := state.to_dict()

	assert_array(as_dict.keys()).is_equal(["nodes"])
	var nodes: Dictionary = as_dict["nodes"]
	assert_array(nodes.keys()).override_failure_message(
		"the builder inserts in sorted id order and to_dict must preserve it").is_equal(
		["port_a", "port_b"])

	# Deliberately Dictionary access: this is the SERIALIZED shape, not the typed node.
	var node: Dictionary = nodes["port_a"]
	assert_array(node.keys()).is_equal(["status", "repair_turns_remaining", "jlsf"])
	assert_str(String(node["status"])).is_equal(InfrastructureState.STATUS_DEGRADED)
	assert_int(int(node["repair_turns_remaining"])).is_equal(3)
	assert_str(String(node["jlsf"])).is_equal(InfrastructureState.JLSF_ENROUTE)

	# An untouched node still serializes its own values, not the mutated one's.
	var other: Dictionary = nodes["port_b"]
	assert_str(String(other["status"])).is_equal(InfrastructureState.STATUS_TAIWANESE)


## to_dict must be a deep copy: mutating the live node after serializing must not edit the snapshot.
func test_state_to_dict_is_a_deep_copy() -> void:
	var state := InfrastructureStateBuilder.build(_defs)
	var as_dict := state.to_dict()
	(state.nodes["port_a"] as InfrastructureNodeState).node_status = InfrastructureState.STATUS_SEIZED

	var snapshot_node: Dictionary = (as_dict["nodes"] as Dictionary)["port_a"]
	assert_str(String(snapshot_node["status"])).is_equal(InfrastructureState.STATUS_TAIWANESE)

	# ...and the other way round: editing the SNAPSHOT must not reach back into the live Resource.
	snapshot_node["jlsf"] = InfrastructureState.JLSF_ARRIVED
	assert_str((state.nodes["port_a"] as InfrastructureNodeState).jlsf).is_equal(
		InfrastructureState.JLSF_NONE)


func _port(id: String, hex_id: String, to_number: int) -> InfrastructureDef:
	var def_data := InfrastructureDef.new()
	def_data.id = id
	def_data.kind = "port"
	def_data.hex_id = hex_id
	def_data.to_number = to_number
	return def_data


func _beaches() -> Dictionary:
	var beach := BeachDef.new()
	beach.id = 1
	return {1: beach}


func _beach_to_to() -> Dictionary:
	return {1: 1}
