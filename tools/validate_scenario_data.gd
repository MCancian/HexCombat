# Run from the project root:
# C:\Godot_v4.7-stable_win64.exe --headless --path C:\Users\mdogg\Desktop\HexCombat -s res://tools/validate_scenario_data.gd
#
# Validates EVERY scenario (the default + data/scenarios/*.json via ScenarioCatalog): generic
# authoring-contract checks on each, plus the pinned expectations on the default scenario only
# (it is the calibration artifact the golden gate loads — its shape must not drift silently).
extends SceneTree

const PLA_OOB_PATH := "res://data/pla_ground_forces.json"
const ROC_OOB_PATH := "res://data/roc_ground_forces.json"
const HEX_GRID_PATH := "res://data/taiwan_hex_grid.json"
const BEACHES_PATH := "res://data/beaches.json"
# Pinned default-scenario expectations (change deliberately, never to make a red gate pass).
# 32 = the full ROC OOB (2026-07-09 USER call: the default carries the complete defense laydown).
const EXPECTED_DEFAULT_PLACEMENTS := 32
const EXPECTED_DEFAULT_RED_SHIP_RESERVE := 4
const VALID_LOSS_CHECK_ARMS := ["unconditional", "after_first_landing"]  # + "after_turn:<N>"

var _failures: Array[String] = []
var _coord_set: Dictionary = {}  # Vector2i -> true, for land-neighbor counts


func _initialize() -> void:
	print("=== Scenario data validation ===")
	var pla_data := _read_dictionary(PLA_OOB_PATH)
	var roc_data := _read_dictionary(ROC_OOB_PATH)
	var hex_grid_data := _read_hex_grid()
	var brigade_teams := _build_brigade_team_lookup([pla_data, roc_data])
	var hex_coords := _build_hex_coord_lookup(hex_grid_data)
	for coord in hex_coords.values():
		_coord_set[coord] = true
	var beach_ids := _read_beach_ids()

	var scenario_paths := ScenarioCatalog.list_scenario_paths()
	for path in scenario_paths:
		var scenario_data := _read_dictionary(path)
		if scenario_data.is_empty():
			continue
		_validate_scenario(path, scenario_data, brigade_teams, hex_coords, beach_ids)
	print("Scenarios checked: %d" % scenario_paths.size())

	_validate_default_pins(_read_dictionary(ScenarioCatalog.DEFAULT_SCENARIO_PATH), hex_coords)
	_finish()


# --- generic checks (every scenario) ---


func _validate_scenario(path: String, scenario_data: Dictionary, brigade_teams: Dictionary, hex_coords: Dictionary, beach_ids: Dictionary) -> void:
	var label := ScenarioCatalog.scenario_id(path)
	if String(scenario_data.get("name", "")).strip_edges().is_empty():
		_fail("%s: scenario name is missing/empty" % label)
	if int(scenario_data.get("turn_length_days", 0)) < 1:
		_fail("%s: turn_length_days must be >= 1" % label)
	if int(scenario_data.get("red_dos_start", 0)) <= 0:
		_fail("%s: red_dos_start must be > 0 (an empty Red DOS pool is almost certainly an authoring error)" % label)

	var placements := _placements(label, scenario_data)
	var reserve := _red_ship_reserve(label, scenario_data)
	var used_brigades := {}

	var seen_hexes := {}
	for placement in placements:
		var brigade_id := String(placement.get("brigade_id", ""))
		var team := String(placement.get("team", ""))
		var hex_id := String(placement.get("hex", ""))
		if not brigade_teams.has(brigade_id):
			_fail("%s: placement references unknown brigade_id: %s" % [label, brigade_id])
		elif team != String(brigade_teams[brigade_id]):
			_fail("%s: placement team mismatch for %s: OOB says %s, scenario says %s" % [label, brigade_id, String(brigade_teams[brigade_id]), team])
		if not hex_coords.has(hex_id):
			_fail("%s: placement references unknown hex: %s" % [label, hex_id])
		if seen_hexes.has(hex_id):
			_fail("%s: placement hex is not unique: %s" % [label, hex_id])
		seen_hexes[hex_id] = true
		if used_brigades.has(brigade_id):
			_fail("%s: brigade appears twice: %s" % [label, brigade_id])
		used_brigades[brigade_id] = true

	for entry_value in reserve:
		var entry: Dictionary = entry_value
		var brigade_id := String(entry.get("brigade_id", ""))
		var locked_beach := int(entry.get("locked_beach", 0))
		var beach_hex := String(entry.get("beach_hex", ""))
		if not brigade_teams.has(brigade_id):
			_fail("%s: red_ship_reserve references unknown brigade_id: %s" % [label, brigade_id])
		elif String(brigade_teams[brigade_id]) != "Red":
			_fail("%s: red_ship_reserve references non-Red brigade_id: %s" % [label, brigade_id])
		if not beach_ids.has(locked_beach):
			_fail("%s: red_ship_reserve locked_beach %d is not a beach in %s (for %s)" % [label, locked_beach, BEACHES_PATH, brigade_id])
		if not hex_coords.has(beach_hex):
			_fail("%s: red_ship_reserve references unknown beach_hex: %s" % [label, beach_hex])
		elif _land_neighbor_count(hex_coords[beach_hex], _coord_set) == 6:
			_fail("%s: red_ship_reserve beach_hex %s is fully inland (6 land neighbors) — an amphibious landing must target a coastal hex (for %s)" % [label, beach_hex, brigade_id])
		if used_brigades.has(brigade_id):
			_fail("%s: brigade is both placed and in red_ship_reserve (it would never land): %s" % [label, brigade_id])
		used_brigades[brigade_id] = true

	_validate_victory(label, scenario_data, hex_coords)
	print("%s: placements=%d red_ship_reserve=%d" % [label, placements.size(), reserve.size()])


func _validate_victory(label: String, scenario_data: Dictionary, hex_coords: Dictionary) -> void:
	var victory_value: Variant = scenario_data.get("victory", null)
	if victory_value == null:
		return
	if not (victory_value is Dictionary):
		_fail("%s: victory block must be a Dictionary" % label)
		return
	var victory: Dictionary = victory_value
	var arm := String(victory.get("loss_check_arm", "unconditional"))
	if arm not in VALID_LOSS_CHECK_ARMS and not arm.begins_with("after_turn:"):
		_fail("%s: unknown victory loss_check_arm: %s" % [label, arm])
	var taiwan_hexes: Variant = victory.get("taiwan_hexes", null)
	if taiwan_hexes == null:
		return
	if not (taiwan_hexes is Array):
		_fail("%s: victory taiwan_hexes must be null or an Array of hex ids" % label)
		return
	for hex_value in taiwan_hexes:
		if not hex_coords.has(String(hex_value)):
			_fail("%s: victory taiwan_hexes references unknown hex: %s" % [label, String(hex_value)])


# --- pinned checks (default scenario only) ---


func _validate_default_pins(scenario_data: Dictionary, hex_coords: Dictionary) -> void:
	var placements := _placements("scenario_default", scenario_data)
	var reserve := _red_ship_reserve("scenario_default", scenario_data)

	if placements.size() != EXPECTED_DEFAULT_PLACEMENTS:
		_fail("Default scenario placement count changed: expected %d, got %d" % [EXPECTED_DEFAULT_PLACEMENTS, placements.size()])
	if reserve.size() != EXPECTED_DEFAULT_RED_SHIP_RESERVE:
		_fail("Default red_ship_reserve count changed: expected %d, got %d" % [EXPECTED_DEFAULT_RED_SHIP_RESERVE, reserve.size()])

	var green_count := 0
	for placement in placements:
		if String(placement.get("team", "")) == "Green":
			green_count += 1
	if green_count != EXPECTED_DEFAULT_PLACEMENTS:
		_fail("Default scenario expected %d Green placements, got %d" % [EXPECTED_DEFAULT_PLACEMENTS, green_count])

	# Every reserve entry's beach_hex must be defended: a Green placement ON the hex or on an
	# odd-r neighbor (the full-defense geometry — beaches garrisoned on-hex or covered from
	# beside; replaces the pre-2026-07-09 index-paired rule from the 4-placement starter laydown).
	var green_hex_coords: Dictionary = {}  # Vector2i -> true
	for placement in placements:
		var green_hex := String((placement as Dictionary).get("hex", ""))
		if hex_coords.has(green_hex):
			green_hex_coords[hex_coords[green_hex]] = true
	for index in range(reserve.size()):
		var beach_hex := String((reserve[index] as Dictionary).get("beach_hex", ""))
		if not hex_coords.has(beach_hex):
			continue  # unknown beach hexes already fail the per-scenario checks
		var beach_coord: Vector2i = hex_coords[beach_hex]
		var defended: bool = green_hex_coords.has(beach_coord)
		if not defended:
			for neighbor_coord in HexMath.neighbor_coords(beach_coord):
				if green_hex_coords.has(neighbor_coord):
					defended = true
					break
		if not defended:
			_fail("Default red_ship_reserve entry %d beach_hex %s has no Green placement on it or adjacent to it" % [index, beach_hex])
	print("Default pins checked: %d placements (all Green), %d reserve entries, beach adjacency" % [EXPECTED_DEFAULT_PLACEMENTS, EXPECTED_DEFAULT_RED_SHIP_RESERVE])


func _land_neighbor_count(coord: Vector2i, coord_set: Dictionary) -> int:
	var count := 0
	for neighbor in HexMath.neighbor_coords(coord):
		if coord_set.has(neighbor):
			count += 1
	return count


# --- shared readers ---


func _placements(label: String, scenario_data: Dictionary) -> Array:
	var placements = scenario_data.get("placements", null)
	if not (placements is Array):
		_fail("%s: missing placements array" % label)
		return []
	if placements.is_empty():
		_fail("%s: placements array is empty" % label)
		return []
	return placements


func _red_ship_reserve(label: String, scenario_data: Dictionary) -> Array:
	var reserve = scenario_data.get("red_ship_reserve", null)
	if not (reserve is Array):
		_fail("%s: missing red_ship_reserve array" % label)
		return []
	return reserve


func _read_dictionary(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("Could not open %s" % path)
		return {}

	var parsed = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		_fail("%s did not parse to a Dictionary" % path)
		return {}
	return parsed


func _read_hex_grid() -> Array:
	var file := FileAccess.open(HEX_GRID_PATH, FileAccess.READ)
	if file == null:
		_fail("Could not open %s" % HEX_GRID_PATH)
		return []

	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Array:
		return parsed
	if parsed is Dictionary and parsed.has("hexes") and parsed["hexes"] is Array:
		return parsed["hexes"]

	_fail("%s did not parse to a hex Array or Dictionary with hexes array" % HEX_GRID_PATH)
	return []


func _read_beach_ids() -> Dictionary:
	var data := _read_dictionary(BEACHES_PATH)
	var ids := {}
	for beach in data.get("beaches", []):
		ids[int((beach as Dictionary).get("id", 0))] = true
	if ids.is_empty():
		_fail("%s yielded no beach ids" % BEACHES_PATH)
	return ids


func _build_brigade_team_lookup(oobs: Array[Dictionary]) -> Dictionary:
	var lookup := {}
	for data in oobs:
		var brigades: Array = data.get("brigades", [])
		for brigade in brigades:
			var brigade_id := String(brigade.get("brigade_id", ""))
			if not brigade_id.is_empty():
				lookup[brigade_id] = String(brigade.get("team", ""))
	return lookup


func _build_hex_coord_lookup(hexes: Array) -> Dictionary:
	var lookup := {}
	for hex_data in hexes:
		var hex_id := String(hex_data.get("id", ""))
		if not hex_id.is_empty():
			lookup[hex_id] = Vector2i(int(hex_data.get("row", 0)), int(hex_data.get("col", 0)))
	return lookup


func _fail(message: String) -> void:
	_failures.append(message)
	push_error(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: Scenario data validation succeeded")
		quit(0)
		return

	print("FAIL: Scenario data validation found %d issue(s):" % _failures.size())
	for failure in _failures:
		print("  - %s" % failure)
	quit(1)
