# Run from the project root:
# godot --headless --path . -s res://tools/validate_headless_infrastructure.gd
#
# Scripted end-to-end check of the plan-0006 infrastructure gate wiring: seizure via hex
# ownership through GameState.resolve_offload_turn, JLSF repair progression, and the
# red_offload_nodes rates. Scripted (set_hex_owner) because empty-orders smoke runs never
# capture a port hex.
extends SceneTree

const DICE_SEED := 12345
const PORT_ID := "taichung"
const PORT_HEX := "hex_33_7"
const JLSF_PORT_ID := "kaohsiung"
const JLSF_PORT_HEX := "hex_11_4"

var _failures: Array[String] = []
var GameData: Node = null
var GameState: Node = null


func _initialize() -> void:
	print("=== Headless infrastructure validation ===")
	GameData = get_root().get_node("GameData")
	GameState = get_root().get_node("GameState")
	if GameData == null or GameState == null:
		_fail("Autoloads GameData/GameState not found on the SceneTree root")
		_finish()
		return

	GameData.load_all()
	GameState.reset_to_scenario()
	_validate_initial_state()
	_validate_seizure_via_offload_turn()
	_validate_rates_by_status()
	_validate_jlsf_repair_progression()
	_finish()


func _validate_initial_state() -> void:
	var state: InfrastructureState = GameState.infrastructure_state
	if state == null:
		_fail("GameState.infrastructure_state is null after reset_to_scenario")
		return
	_assert_equal_int("infrastructure node count", state.nodes.size(), GameData.infrastructure.size())
	for id in state.nodes.keys():
		var node: Dictionary = state.nodes[id]
		if String(node["status"]) != InfrastructureState.STATUS_TAIWANESE:
			_fail("node %s starts %s, expected taiwanese" % [id, node["status"]])
	_assert_true("initial red_offload_nodes empty",
		InfrastructureResolver.red_offload_nodes(state, GameData.infrastructure, _owners()).is_empty())


func _validate_seizure_via_offload_turn() -> void:
	GameData.set_hex_owner(PORT_HEX, "red")
	GameState.resolve_offload_turn(SeededDice.new(DICE_SEED))
	var state: InfrastructureState = GameState.infrastructure_state
	var node: Dictionary = state.nodes[PORT_ID]
	_assert_equal_string("%s status after Red seizure turn" % PORT_ID, String(node["status"]), InfrastructureState.STATUS_SEIZED)
	# Seized contributes nothing.
	for entry in InfrastructureResolver.red_offload_nodes(state, GameData.infrastructure, _owners()):
		if String(entry["id"]) == PORT_ID:
			_fail("seized %s must not appear in red_offload_nodes" % PORT_ID)


func _validate_rates_by_status() -> void:
	var state: InfrastructureState = GameState.infrastructure_state
	var node: Dictionary = state.nodes[PORT_ID]
	node["status"] = InfrastructureState.STATUS_DEGRADED
	_assert_equal_float("degraded port rate", _rate_of(PORT_ID), OffloadRates.DEGRADED_PORT)
	node["status"] = InfrastructureState.STATUS_OPERATIONAL
	_assert_equal_float("operational port rate", _rate_of(PORT_ID), OffloadRates.OPERATIONAL_PORT)


func _validate_jlsf_repair_progression() -> void:
	GameData.set_hex_owner(JLSF_PORT_HEX, "red")
	var state: InfrastructureState = GameState.infrastructure_state
	# Seize on the first offload tick, then simulate an arrived JLSF: +1 turn degraded, +2 operational.
	GameState.resolve_offload_turn(SeededDice.new(DICE_SEED))
	var node: Dictionary = state.nodes[JLSF_PORT_ID]
	_assert_equal_string("%s seized" % JLSF_PORT_ID, String(node["status"]), InfrastructureState.STATUS_SEIZED)
	node["jlsf"] = InfrastructureState.JLSF_ARRIVED
	GameState.resolve_offload_turn(SeededDice.new(DICE_SEED))
	_assert_equal_string("%s degraded after 1 repair turn" % JLSF_PORT_ID, String(node["status"]), InfrastructureState.STATUS_DEGRADED)
	GameState.resolve_offload_turn(SeededDice.new(DICE_SEED))
	_assert_equal_string("%s operational after 2 repair turns" % JLSF_PORT_ID, String(node["status"]), InfrastructureState.STATUS_OPERATIONAL)
	_assert_equal_float("repaired port rate", _rate_of(JLSF_PORT_ID), OffloadRates.OPERATIONAL_PORT)


func _rate_of(infra_id: String) -> float:
	var state: InfrastructureState = GameState.infrastructure_state
	for entry in InfrastructureResolver.red_offload_nodes(state, GameData.infrastructure, _owners()):
		if String(entry["id"]) == infra_id:
			return float(entry["rate_tons"])
	return -1.0


func _owners() -> Dictionary:
	var owners: Dictionary = {}
	for hex_id in GameData.hex_states.keys():
		owners[String(hex_id)] = String(GameData.hex_states[hex_id].owner)
	return owners


func _assert_equal_int(label: String, got: int, expected: int) -> void:
	if got != expected:
		_fail("%s: expected %d, got %d" % [label, expected, got])


func _assert_equal_float(label: String, got: float, expected: float) -> void:
	if not is_equal_approx(got, expected):
		_fail("%s: expected %s, got %s" % [label, expected, got])


func _assert_equal_string(label: String, got: String, expected: String) -> void:
	if got != expected:
		_fail("%s: expected '%s', got '%s'" % [label, expected, got])


func _assert_true(label: String, condition: bool) -> void:
	if not condition:
		_fail(label)


func _fail(message: String) -> void:
	_failures.append(message)
	push_error(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: Headless infrastructure validation succeeded")
		quit(0)
		return
	print("FAIL: Headless infrastructure validation found %d issue(s):" % _failures.size())
	for failure in _failures:
		print("  - %s" % failure)
	quit(1)
