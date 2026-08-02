# Validates the JSON-style API intended for LLM playtesting harnesses.
# Run:
# C:\Godot_v4.7-stable_win64.exe --headless --path C:\Users\mdogg\Desktop\HexCombat -s res://tools/validate_llm_api.gd
extends SceneTree

# Scripted-turn shape lives in tools/GoldenScript.gd (shared by all golden validators).
const RED_MOVER_ID := GoldenScript.RED_MOVER_ID
const START_HEX := GoldenScript.START_HEX
const TARGET_HEX := GoldenScript.TARGET_HEX
const DICE_SEED := GoldenScript.SEED
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
## Required observation keys come from the schema, not a second hand-maintained copy: the schema's
## `required` array IS the contract, and keeping a duplicate list here meant every new observation
## block had to be added twice (and could silently be added only once).
var _required_observation_keys: Array = []
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
	_required_observation_keys = _schema_required_keys("res://schemas/llm_observation.schema.json")
	if _required_observation_keys.is_empty():
		_fail("observation schema declared no required keys — the contract cannot be checked")
	_game_data().load_all()
	_game_state().reset_to_scenario()
	_provision_red_mover_for_validation()

	_validate_observation_shape()
	_validate_action_application()
	_validate_missing_seed_rejected()
	_validate_deploy_jlsf_cross_team_rejected()
	_validate_examples_parse_and_apply()
	_validate_result_schema_conformance()
	_validate_dispatch_arms()
	_finish()


func _validate_dispatch_arms() -> void:
	var schema_data = _read_json("res://schemas/llm_action_response.schema.json")
	var items = schema_data.get("properties", {}).get("actions", {}).get("items", {}).get("oneOf", [])
	var schema_types := []
	for item in items:
		schema_types.append(String(item.get("properties", {}).get("type", {}).get("const", "")))
	schema_types.sort()

	var api_arms := _extract_dispatch_arms("res://scripts/api/LLMGameAPI.gd", "match action_type:")
	if schema_types != api_arms:
		_fail("LLMGameAPI action_type dispatch arms %s do not match schema variants %s" % [api_arms, schema_types])

	var order_arms := _extract_dispatch_arms("res://scripts/transitions/OrderTransitions.gd", "match kind:")
	var expected_order_arms := schema_types.duplicate()
	expected_order_arms.erase("end_turn")
	if order_arms != expected_order_arms:
		_fail("OrderTransitions order kind dispatch arms %s do not match schema variants minus end_turn %s" % [order_arms, expected_order_arms])


func _extract_dispatch_arms(path: String, match_statement: String) -> Array:
	if not FileAccess.file_exists(path):
		_fail("Could not read %s" % path)
		return []
	var text := FileAccess.get_file_as_string(path)

	var lines := text.split("\n")
	var arms := []
	var match_indent := -1
	for line in lines:
		if match_indent == -1:
			if line.find(match_statement) != -1:
				match_indent = 0
				for i in line.length():
					if line[i] == '\t':
						match_indent += 1
					else:
						break
			continue

		var s := line.strip_edges()
		if s == "" or s.begins_with("#"):
			continue

		var indent := 0
		for i in line.length():
			if line[i] == '\t':
				indent += 1
			else:
				break

		if indent <= match_indent and s != "":
			break

		if indent == match_indent + 1 and s.begins_with('"') and s.ends_with('":'):
			arms.append(s.trim_prefix('"').trim_suffix('":'))

	arms.sort()
	return arms


func _validate_observation_shape() -> void:
	var observation := LLMGameAPI.observation("Red")
	for key in _required_observation_keys:
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
		_assert_true("%s in contested_hexes" % TARGET_HEX, TARGET_HEX in contested)
		var events: Array = tr.get("events", [])
		_assert_true("turn_result events non-empty", not events.is_empty())
		_assert_true("events has move for %s to %s" % [RED_MOVER_ID, TARGET_HEX], _find_event(events, "move", TARGET_HEX, RED_MOVER_ID))
		_assert_true("events has combat at %s" % TARGET_HEX, _find_combat_event(events, TARGET_HEX))


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


func _validate_deploy_jlsf_cross_team_rejected() -> void:
	_game_data().load_all()
	_game_state().reset_to_scenario()

	var port_id := ""
	for id in _game_data().infrastructure.keys():
		port_id = id
		break

	# Case 1: Green seat sends team=Red — caught at the API boundary (spoofing).
	var spoof_result := LLMGameAPI.apply_agent_response({
		"protocol_version": LLMGameAPI.PROTOCOL_VERSION,
		"schema": LLMGameAPI.ACTION_RESPONSE_SCHEMA,
		"perspective_team": "Green",
		"actions": [
			{"type": "deploy_jlsf", "team": "Red", "port_id": port_id}
		]
	})

	_assert_true("cross-team spoof is rejected", not bool(spoof_result["ok"]))
	var found_spoof := false
	for err in spoof_result.get("errors", []):
		if "does not match seat" in String(err):
			found_spoof = true
			break
	_assert_true("error describes seat mismatch", found_spoof)
	_assert_true("jlsf orders remain empty after spoof", _game_state().jlsf_orders.is_empty())

	# Case 2: Green seat honestly sends team=Green — reaches OrderValidator TEAM_MISMATCH.
	var honest_result := LLMGameAPI.apply_agent_response({
		"protocol_version": LLMGameAPI.PROTOCOL_VERSION,
		"schema": LLMGameAPI.ACTION_RESPONSE_SCHEMA,
		"perspective_team": "Green",
		"actions": [
			{"type": "deploy_jlsf", "team": "Green", "port_id": port_id}
		]
	})

	_assert_true("honest Green deploy_jlsf is rejected", not bool(honest_result["ok"]))
	var found_domain_mismatch := false
	for err in honest_result.get("errors", []):
		if "is a red order" in String(err).to_lower():
			found_domain_mismatch = true
			break
	_assert_true("error reaches TEAM_MISMATCH in OrderValidator", found_domain_mismatch)
	_assert_true("jlsf orders remain empty after honest Green", _game_state().jlsf_orders.is_empty())


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
		for key in _required_observation_keys:
			if not (example_observation as Dictionary).has(key):
				_fail("observation example missing required key: %s" % key)


## The schema's `required` array is the observation contract; this validator reads it rather than
## keeping a second copy that could drift (or be updated only on one side).
func _schema_required_keys(path: String) -> Array:
	var parsed = _read_json(path)
	if not (parsed is Dictionary):
		return []
	var required = (parsed as Dictionary).get("required", [])
	return required if required is Array else []


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
