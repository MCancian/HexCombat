# Validates the JSON-style API intended for LLM playtesting harnesses.
# Run:
# C:\Godot_v4.7-stable_win64.exe --headless --path C:\Users\mdogg\Desktop\HexCombat -s res://tools/validate_llm_api.gd
extends SceneTree

const RED_MOVER_ID := "PLA-71-2-Amphibious"
const START_HEX := "hex_44_16"
const TARGET_HEX := "hex_43_17"
const DICE_SEED := 20260624
const REQUIRED_RESULT_KEYS := [
	"protocol_version",
	"schema",
	"ok",
	"errors",
	"resolved",
	"seed",
	"turn_result",
	"observation"
]
const REQUIRED_OBSERVATION_KEYS := [
	"protocol_version",
	"schema",
	"scenario",
	"turn",
	"phase",
	"turn_length_days",
	"perspective_team",
	"rules_summary",
	"field_glossary",
	"map_summary",
	"brigades",
	"occupied_hexes",
	"ship_reserve",
	"supply_state",
	"ijfs",
	"antiship",
	"legal_moves",
	"legal_commits",
	"pending_orders",
	"pending_commitments",
	"last_contested_hexes",
	"last_combat",
	"objectives"
]
const EXAMPLE_PATHS := [
	"res://docs/examples/llm_observation_red_turn1.json",
	"res://docs/examples/llm_action_response_move_end_turn.json",
	"res://docs/examples/llm_result_after_turn.json",
	"res://schemas/llm_observation.schema.json",
	"res://schemas/llm_action_response.schema.json",
	"res://schemas/llm_action_result.schema.json"
]

var _failures: Array[String] = []


func _game_data() -> Node:
	return get_root().get_node("GameData")


func _game_state() -> Node:
	return get_root().get_node("GameState")


func _initialize() -> void:
	_game_data().load_all()
	_game_state().reset_to_scenario()
	_provision_red_mover_for_validation()

	_validate_observation_shape()
	_validate_action_application()
	_validate_missing_seed_rejected()
	_validate_examples_parse_and_apply()
	_validate_result_schema_conformance()
	_finish()


func _validate_observation_shape() -> void:
	var observation := LLMGameAPI.observation("Red")
	for key in REQUIRED_OBSERVATION_KEYS:
		if not observation.has(key):
			_fail("observation missing required key: %s" % key)
	_assert_equal_string("protocol_version", String(observation.get("protocol_version", "")), LLMGameAPI.PROTOCOL_VERSION)
	_assert_equal_string("schema", String(observation.get("schema", "")), LLMGameAPI.OBSERVATION_SCHEMA)
	_assert_equal_string("initial phase", String(observation.get("phase", "")), "planning")
	_assert_true("brigades present", (observation["brigades"] as Array).size() > 0)
	_assert_true("Red legal moves include mover", RED_MOVER_ID in (observation["legal_moves"] as Dictionary))

	var legal_for_mover: Dictionary = (observation["legal_moves"] as Dictionary)[RED_MOVER_ID]
	_assert_equal_string("mover from hex", String(legal_for_mover["from_hex"]), START_HEX)
	_assert_true("legal_moves has tactical string key", legal_for_mover.has("tactical"))
	_assert_true("legal_moves has administrative string key", legal_for_mover.has("administrative"))
	_assert_true("target reachable tactically", TARGET_HEX in (legal_for_mover["tactical"] as Array))

	var map_summary: Dictionary = observation["map_summary"]
	_assert_true("map_summary movement_modes includes tactical", "tactical" in (map_summary["movement_modes"] as Array))
	_assert_true("map_summary movement_modes includes administrative", "administrative" in (map_summary["movement_modes"] as Array))
	_assert_true("map_summary owner_values includes lowercase red", "red" in (map_summary["owner_values"] as Array))
	_assert_true("map_summary owner_values includes lowercase contested", "contested" in (map_summary["owner_values"] as Array))
	_assert_true("objectives currently array", observation["objectives"] is Array)
	_assert_true("last_contested_hexes currently array", observation["last_contested_hexes"] is Array)
	_assert_true("last_combat currently array", observation["last_combat"] is Array)


func _validate_action_application() -> void:
	_game_data().load_all()
	_game_state().reset_to_scenario()
	_provision_red_mover_for_validation()
	var result := LLMGameAPI.apply_agent_response(_sample_action_response())
	_assert_true("agent response ok", bool(result["ok"]))
	_assert_true("turn resolved", bool(result["resolved"]))
	_assert_equal_int("result seed", int(result["seed"]), DICE_SEED)
	_assert_equal_int("advanced turn", _game_state().turn_number, 2)
	_assert_equal_string("mover advanced", _game_data().get_brigade(RED_MOVER_ID).hex_id, TARGET_HEX)
	var post_observation: Dictionary = result["observation"]
	_assert_equal_string("post perspective team", String(post_observation["perspective_team"]), "Red")
	_assert_true("last_contested_hexes array after turn", post_observation["last_contested_hexes"] is Array)
	_assert_true("last_combat array after turn", post_observation["last_combat"] is Array)

	var has_turn_result := result.has("turn_result") and result["turn_result"] is Dictionary
	_assert_true("result has turn_result dict", has_turn_result)
	if has_turn_result:
		var tr: Dictionary = result["turn_result"]
		_assert_equal_int("turn_result turn_number", int(tr.get("turn_number", 0)), 1)
		var contested: Array = tr.get("contested_hexes", [])
		_assert_true("hex_43_17 in contested_hexes", TARGET_HEX in contested)
		var events: Array = tr.get("events", [])
		_assert_true("turn_result events non-empty", not events.is_empty())
		_assert_true("events has move for PLA-71-2-Amphibious to hex_43_17", _find_event(events, "move", "hex_43_17", RED_MOVER_ID))
		_assert_true("events has combat at hex_43_17", _find_combat_event(events, "hex_43_17"))


func _validate_missing_seed_rejected() -> void:
	_game_data().load_all()
	_game_state().reset_to_scenario()
	_provision_red_mover_for_validation()
	var result := LLMGameAPI.apply_agent_response({
		"protocol_version": LLMGameAPI.PROTOCOL_VERSION,
		"schema": LLMGameAPI.ACTION_RESPONSE_SCHEMA,
		"perspective_team": "Red",
		"actions": [
			{"type": "end_turn"}
		]
	})
	_assert_true("missing seed rejected", not bool(result["ok"]))
	_assert_true("missing seed does not resolve", not bool(result["resolved"]))
	_assert_equal_int("missing seed keeps turn", _game_state().turn_number, 1)
	var tr_empty := true
	if result.has("turn_result") and result["turn_result"] is Dictionary:
		tr_empty = (result["turn_result"] as Dictionary).is_empty()
	_assert_true("turn_result empty when not resolved", tr_empty)


func _validate_examples_parse_and_apply() -> void:
	for path in EXAMPLE_PATHS:
		var parsed = _read_json(path)
		if parsed == null:
			_fail("example/schema failed to parse: %s" % path)

	var example_action = _read_json("res://docs/examples/llm_action_response_move_end_turn.json")
	if not (example_action is Dictionary):
		_fail("action example is not a Dictionary")
		return
	_game_data().load_all()
	_game_state().reset_to_scenario()
	_provision_red_mover_for_validation()
	var result := LLMGameAPI.apply_agent_response(example_action)
	_assert_true("action example applies", bool(result["ok"]))

	var example_observation = _read_json("res://docs/examples/llm_observation_red_turn1.json")
	if example_observation is Dictionary:
		for key in REQUIRED_OBSERVATION_KEYS:
			if not (example_observation as Dictionary).has(key):
				_fail("observation example missing required key: %s" % key)


func _provision_red_mover_for_validation() -> void:
	_game_state().resolve_offload_turn(SeededDice.new(DICE_SEED))


func _sample_action_response() -> Dictionary:
	return {
		"protocol_version": LLMGameAPI.PROTOCOL_VERSION,
		"schema": LLMGameAPI.ACTION_RESPONSE_SCHEMA,
		"perspective_team": "Red",
		"actions": [
			{"type": "move", "team": "Red", "brigade_id": RED_MOVER_ID, "target_hex": TARGET_HEX, "mode": Movement.MODE_TACTICAL},
			{"type": "end_turn", "seed": DICE_SEED}
		],
		"notes": "Validation fixture: move one Red brigade into combat and resolve."
	}


func _read_json(path: String):
	if not FileAccess.file_exists(path):
		_fail("JSON file missing: %s" % path)
		return null
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	var error := json.parse(text)
	if error != OK:
		_fail("JSON parse failed for %s at line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


func _assert_true(label: String, value: bool) -> void:
	if not value:
		_fail("%s: expected true" % label)


func _assert_equal_int(label: String, actual: int, expected: int) -> void:
	if actual != expected:
		_fail("%s: expected %d, got %d" % [label, expected, actual])


func _assert_equal_string(label: String, actual: String, expected: String) -> void:
	if actual != expected:
		_fail("%s: expected %s, got %s" % [label, expected, actual])


func _fail(message: String) -> void:
	_failures.append(message)
	push_error(message)


static func _find_event(events: Array, kind: String, target_hex: String, brigade_id: String) -> bool:
	for e in events:
		if not (e is Dictionary):
			continue
		var ev: Dictionary = e
		if ev.get("kind", "") != kind:
			continue
		var data: Dictionary = ev.get("data", {})
		if data.get("brigade_id", "") == brigade_id and data.get("target_hex", "") == target_hex:
			return true
	return false


static func _find_combat_event(events: Array, hex_id: String) -> bool:
	for e in events:
		if not (e is Dictionary):
			continue
		var ev: Dictionary = e
		if ev.get("kind", "") == "combat" and ev.get("hex_id", "") == hex_id:
			return true
	return false


func _validate_result_schema_conformance() -> void:
	var schema_data = _read_json("res://schemas/llm_action_result.schema.json")
	if not (schema_data is Dictionary):
		_fail("result schema is not a Dictionary")
		return
	var sd: Dictionary = schema_data
	_assert_equal_string("result schema $id", String(sd.get("$id", "")), "hexcombat.llm_action_result")

	var schema_required: Array = sd.get("required", [])
	var schema_sorted := schema_required.duplicate()
	schema_sorted.sort()
	var expected_sorted := REQUIRED_RESULT_KEYS.duplicate()
	expected_sorted.sort()
	if schema_sorted.size() != expected_sorted.size():
		_fail("result schema required size %d != expected %d" % [schema_sorted.size(), expected_sorted.size()])
	else:
		for i in schema_sorted.size():
			if String(schema_sorted[i]) != String(expected_sorted[i]):
				_fail("result schema required[%d]: expected %s, got %s" % [i, String(expected_sorted[i]), String(schema_sorted[i])])

	_game_data().load_all()
	_game_state().reset_to_scenario()
	_provision_red_mover_for_validation()
	var result := LLMGameAPI.apply_agent_response(_sample_action_response())
	for key in REQUIRED_RESULT_KEYS:
		if not result.has(key):
			_fail("fresh result missing required key: %s" % key)

	var fixture = _read_json("res://docs/examples/llm_result_after_turn.json")
	if fixture is Dictionary:
		var f: Dictionary = fixture
		for key in REQUIRED_RESULT_KEYS:
			if not f.has(key):
				_fail("result fixture missing required key: %s" % key)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: LLM playtesting API validation succeeded")
		quit(0)
		return

	print("FAIL: LLM playtesting API validation found %d issue(s):" % _failures.size())
	for failure in _failures:
		print("  - %s" % failure)
	quit(1)
