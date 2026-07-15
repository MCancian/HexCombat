## GdUnit4 tests for InfrastructureState, InfrastructureStateBuilder, InfrastructureResolver.
## Inline fixture: two ports + one airbridge across hexes/TOs.
extends GdUnitTestSuite

var _defs: Dictionary = {}


func before() -> void:
	var d1 := InfrastructureDef.new()
	d1.id = "port_a"
	d1.kind = "port"
	d1.hex_id = "hex_001"
	d1.to_number = 1

	var d2 := InfrastructureDef.new()
	d2.id = "port_b"
	d2.kind = "port"
	d2.hex_id = "hex_002"
	d2.to_number = 2

	var d3 := InfrastructureDef.new()
	d3.id = "airbridge_a"
	d3.kind = "airbridge"
	d3.hex_id = "hex_003"
	d3.to_number = 3

	_defs = {"port_a": d1, "port_b": d2, "airbridge_a": d3}


# ---------------------------------------------------------------------------
# 1. Builder: every def becomes taiwanese/none/0
# ---------------------------------------------------------------------------

func test_builder_creates_all_taiwanese() -> void:
	var state := InfrastructureStateBuilder.build(_defs)
	assert_int(state.nodes.size()).is_equal(3)
	for id in state.nodes.keys():
		var node_val: Variant = state.nodes[id]
		var node: Dictionary = node_val
		assert_str(String(node.get("status", ""))).is_equal(InfrastructureState.STATUS_TAIWANESE)
		assert_str(String(node.get("jlsf", ""))).is_equal(InfrastructureState.JLSF_NONE)
		assert_int(int(node.get("repair_turns_remaining", -1))).is_equal(0)

# ---------------------------------------------------------------------------
# 2. tick: taiwanese + red hex → seized + event; taiwanese + green or missing → unchanged
# ---------------------------------------------------------------------------

func test_tick_taiwanese_red_seizes() -> void:
	var state := InfrastructureStateBuilder.build(_defs)
	var owner_by_hex := {"hex_001": "red"}
	var result: Dictionary = InfrastructureResolver.tick(state, _defs, owner_by_hex)
	var node_val: Variant = state.nodes["port_a"]
	var node: Dictionary = node_val
	assert_str(String(node.get("status", ""))).is_equal(InfrastructureState.STATUS_SEIZED)
	assert_int(result.events.size()).is_equal(1)
	assert_str(String(result.events[0]["id"])).is_equal("port_a")
	assert_str(String(result.events[0]["event"])).is_equal("seized")


func test_tick_taiwanese_green_unchanged() -> void:
	var state := InfrastructureStateBuilder.build(_defs)
	var owner_by_hex := {"hex_001": "green"}
	var result: Dictionary = InfrastructureResolver.tick(state, _defs, owner_by_hex)
	var node_val: Variant = state.nodes["port_a"]
	var node: Dictionary = node_val
	assert_str(String(node.get("status", ""))).is_equal(InfrastructureState.STATUS_TAIWANESE)
	assert_int(result.events.size()).is_equal(0)


func test_tick_taiwanese_no_owner_unchanged() -> void:
	var state := InfrastructureStateBuilder.build(_defs)
	var owner_by_hex: Dictionary = {}
	var result: Dictionary = InfrastructureResolver.tick(state, _defs, owner_by_hex)
	var node_val: Variant = state.nodes["port_a"]
	var node: Dictionary = node_val
	assert_str(String(node.get("status", ""))).is_equal(InfrastructureState.STATUS_TAIWANESE)
	assert_int(result.events.size()).is_equal(0)

# ---------------------------------------------------------------------------
# 3. seized + jlsf none: three ticks, stays seized, no events
# ---------------------------------------------------------------------------

func test_tick_seized_no_jlsf_stays_seized() -> void:
	var state := InfrastructureStateBuilder.build(_defs)
	state.nodes["port_a"]["status"] = InfrastructureState.STATUS_SEIZED
	var owner_by_hex := {"hex_001": "red"}
	var result: Dictionary = InfrastructureResolver.tick(state, _defs, owner_by_hex)
	result = InfrastructureResolver.tick(state, _defs, owner_by_hex)
	result = InfrastructureResolver.tick(state, _defs, owner_by_hex)
	var node_val: Variant = state.nodes["port_a"]
	var node: Dictionary = node_val
	assert_str(String(node.get("status", ""))).is_equal(InfrastructureState.STATUS_SEIZED)
	assert_int(result.events.size()).is_equal(0)

# ---------------------------------------------------------------------------
# 4. seized + jlsf arrived + red: tick1 → degraded, tick2 → operational, tick3 → none
# ---------------------------------------------------------------------------

func test_tick_repair_cycle_default_stages() -> void:
	var state := InfrastructureStateBuilder.build(_defs)
	state.nodes["port_a"]["status"] = InfrastructureState.STATUS_SEIZED
	state.nodes["port_a"]["jlsf"] = InfrastructureState.JLSF_ARRIVED
	var owner_by_hex := {"hex_001": "red"}

	var r1: Dictionary = InfrastructureResolver.tick(state, _defs, owner_by_hex)
	var node_val: Variant = state.nodes["port_a"]
	var node: Dictionary = node_val
	assert_str(String(node.get("status", ""))).is_equal(InfrastructureState.STATUS_DEGRADED)
	assert_int(r1.events.size()).is_equal(1)
	assert_str(String(r1.events[0]["event"])).is_equal("degraded")

	var r2: Dictionary = InfrastructureResolver.tick(state, _defs, owner_by_hex)
	assert_str(String(node.get("status", ""))).is_equal(InfrastructureState.STATUS_OPERATIONAL)
	assert_int(r2.events.size()).is_equal(1)
	assert_str(String(r2.events[0]["event"])).is_equal("operational")

	var r3: Dictionary = InfrastructureResolver.tick(state, _defs, owner_by_hex)
	assert_str(String(node.get("status", ""))).is_equal(InfrastructureState.STATUS_OPERATIONAL)
	assert_int(r3.events.size()).is_equal(0)

# ---------------------------------------------------------------------------
# 5. repair pause: seized + jlsf arrived but owner flips green → no progression
# ---------------------------------------------------------------------------

func test_tick_repair_pauses_on_green_hex() -> void:
	var state := InfrastructureStateBuilder.build(_defs)
	state.nodes["port_a"]["status"] = InfrastructureState.STATUS_SEIZED
	state.nodes["port_a"]["jlsf"] = InfrastructureState.JLSF_ARRIVED
	var node_val: Variant = state.nodes["port_a"]
	var node: Dictionary = node_val

	# Green owner — no progression
	var owner_by_hex := {"hex_001": "green"}
	InfrastructureResolver.tick(state, _defs, owner_by_hex)
	assert_str(String(node.get("status", ""))).is_equal(InfrastructureState.STATUS_SEIZED)

	# Flips back red — progression resumes
	owner_by_hex = {"hex_001": "red"}
	InfrastructureResolver.tick(state, _defs, owner_by_hex)
	assert_str(String(node.get("status", ""))).is_equal(InfrastructureState.STATUS_DEGRADED)

# ---------------------------------------------------------------------------
# 6. repair_turns_per_stage = 2: arrival → degraded on tick2, operational on tick4
# ---------------------------------------------------------------------------

func test_tick_repair_slower_stages() -> void:
	var state := InfrastructureStateBuilder.build(_defs)
	state.nodes["port_a"]["status"] = InfrastructureState.STATUS_SEIZED
	state.nodes["port_a"]["jlsf"] = InfrastructureState.JLSF_ARRIVED
	var owner_by_hex := {"hex_001": "red"}
	var node_val: Variant = state.nodes["port_a"]
	var node: Dictionary = node_val

	# Tick 1: countdown starts at 2 → decrement to 1, no transition
	InfrastructureResolver.tick(state, _defs, owner_by_hex, 2)
	assert_str(String(node.get("status", ""))).is_equal(InfrastructureState.STATUS_SEIZED)

	# Tick 2: countdown reaches 0 → degraded
	InfrastructureResolver.tick(state, _defs, owner_by_hex, 2)
	assert_str(String(node.get("status", ""))).is_equal(InfrastructureState.STATUS_DEGRADED)

	# Tick 3: new stage countdown 2 → 1, no transition
	InfrastructureResolver.tick(state, _defs, owner_by_hex, 2)
	assert_str(String(node.get("status", ""))).is_equal(InfrastructureState.STATUS_DEGRADED)

	# Tick 4: countdown reaches 0 → operational
	InfrastructureResolver.tick(state, _defs, owner_by_hex, 2)
	assert_str(String(node.get("status", ""))).is_equal(InfrastructureState.STATUS_OPERATIONAL)

# ---------------------------------------------------------------------------
# 7. red_offload_nodes: correct rates by (kind, status); taiwanese/seized excluded
# ---------------------------------------------------------------------------

func test_red_offload_rates() -> void:
	var state := InfrastructureStateBuilder.build(_defs)
	state.nodes["port_a"]["status"] = InfrastructureState.STATUS_DEGRADED
	state.nodes["port_b"]["status"] = InfrastructureState.STATUS_OPERATIONAL
	state.nodes["airbridge_a"]["status"] = InfrastructureState.STATUS_DEGRADED
	var owner_by_hex := {"hex_001": "red", "hex_002": "red", "hex_003": "red"}

	var nodes_result: Array = InfrastructureResolver.red_offload_nodes(state, _defs, owner_by_hex)
	assert_int(nodes_result.size()).is_equal(3)

	for entry_val in nodes_result:
		var entry: Dictionary = entry_val
		var id: String = String(entry.get("id", ""))
		if id == "port_a":
			assert_float(float(entry.get("rate_tons", 0))).is_equal(OffloadRates.DEGRADED_PORT)
		elif id == "port_b":
			assert_float(float(entry.get("rate_tons", 0))).is_equal(OffloadRates.OPERATIONAL_PORT)
		elif id == "airbridge_a":
			assert_float(float(entry.get("rate_tons", 0))).is_equal(OffloadRates.DEGRADED_AIRBRIDGE)


func test_red_offload_excludes_seized_and_taiwanese() -> void:
	var state := InfrastructureStateBuilder.build(_defs)
	# All start taiwanese — none should appear
	var owner_by_hex := {"hex_001": "red", "hex_002": "red", "hex_003": "red"}
	var nodes_result: Array = InfrastructureResolver.red_offload_nodes(state, _defs, owner_by_hex)
	assert_int(nodes_result.size()).is_equal(0)

	# Set port_a to seized — still excluded
	state.nodes["port_a"]["status"] = InfrastructureState.STATUS_SEIZED
	nodes_result = InfrastructureResolver.red_offload_nodes(state, _defs, owner_by_hex)
	assert_int(nodes_result.size()).is_equal(0)

# ---------------------------------------------------------------------------
# 8. degraded node on green-owned hex → excluded (status unchanged)
# ---------------------------------------------------------------------------

func test_red_offload_green_hex_excluded() -> void:
	var state := InfrastructureStateBuilder.build(_defs)
	state.nodes["port_a"]["status"] = InfrastructureState.STATUS_DEGRADED
	var owner_by_hex := {"hex_001": "green"}

	var nodes_result: Array = InfrastructureResolver.red_offload_nodes(state, _defs, owner_by_hex)
	assert_int(nodes_result.size()).is_equal(0)
	# Status stays degraded
	var node_val: Variant = state.nodes["port_a"]
	var node: Dictionary = node_val
	assert_str(String(node.get("status", ""))).is_equal(InfrastructureState.STATUS_DEGRADED)

# ---------------------------------------------------------------------------
# 9. Output ordering: events and red_offload_nodes sorted by node id
# ---------------------------------------------------------------------------

func test_output_ordering_sorted() -> void:
	var state := InfrastructureStateBuilder.build(_defs)
	# Set all three to degraded + red-held so they appear in red_offload_nodes
	state.nodes["port_a"]["status"] = InfrastructureState.STATUS_DEGRADED
	state.nodes["port_b"]["status"] = InfrastructureState.STATUS_DEGRADED
	state.nodes["airbridge_a"]["status"] = InfrastructureState.STATUS_DEGRADED
	state.nodes["port_a"]["jlsf"] = InfrastructureState.JLSF_ARRIVED
	state.nodes["port_b"]["jlsf"] = InfrastructureState.JLSF_ARRIVED
	state.nodes["airbridge_a"]["jlsf"] = InfrastructureState.JLSF_ARRIVED
	var owner_by_hex := {"hex_001": "red", "hex_002": "red", "hex_003": "red"}

	# Events from tick — sorted by id
	var tick_result: Dictionary = InfrastructureResolver.tick(state, _defs, owner_by_hex)
	assert_int(tick_result.events.size()).is_equal(3)
	assert_str(String(tick_result.events[0]["id"])).is_equal("airbridge_a")
	assert_str(String(tick_result.events[1]["id"])).is_equal("port_a")
	assert_str(String(tick_result.events[2]["id"])).is_equal("port_b")

	# red_offload_nodes — sorted by id
	var offload_result: Array = InfrastructureResolver.red_offload_nodes(state, _defs, owner_by_hex)
	assert_int(offload_result.size()).is_equal(3)
	var e0: Dictionary = offload_result[0]
	var e1: Dictionary = offload_result[1]
	var e2: Dictionary = offload_result[2]
	assert_str(String(e0.get("id", ""))).is_equal("airbridge_a")
	assert_str(String(e1.get("id", ""))).is_equal("port_a")
	assert_str(String(e2.get("id", ""))).is_equal("port_b")

# ---------------------------------------------------------------------------
# 10. validate(): legal state true; illegal status or negative repair → false
# ---------------------------------------------------------------------------

func test_validate_legal_state() -> void:
	var state := InfrastructureStateBuilder.build(_defs)
	assert_bool(state.validate()).is_true()


func test_validate_illegal_status() -> void:
	var state := InfrastructureStateBuilder.build(_defs)
	var node_val: Variant = state.nodes["port_a"]
	var node: Dictionary = node_val
	node["status"] = "bogus"
	assert_bool(state.validate()).is_false()


func test_validate_negative_repair_turns() -> void:
	var state := InfrastructureStateBuilder.build(_defs)
	var node_val: Variant = state.nodes["port_a"]
	var node: Dictionary = node_val
	node["repair_turns_remaining"] = -1
	assert_bool(state.validate()).is_false()
