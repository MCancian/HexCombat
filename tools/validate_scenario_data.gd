# Run from the project root:
# C:\Godot_v4.7-stable_win64.exe --headless --path C:\Users\mdogg\Desktop\HexCombat -s res://tools/validate_scenario_data.gd
extends SceneTree

const SCENARIO_PATH := "res://data/scenario_default.json"
const PLA_OOB_PATH := "res://data/pla_ground_forces.json"
const ROC_OOB_PATH := "res://data/roc_ground_forces.json"
const HEX_GRID_PATH := "res://data/taiwan_hex_grid.json"
const EXPECTED_PLACEMENTS := 4
const EXPECTED_RED_SHIP_RESERVE := 4

var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Scenario data validation ===")
	var scenario_data := _read_dictionary(SCENARIO_PATH)
	var pla_data := _read_dictionary(PLA_OOB_PATH)
	var roc_data := _read_dictionary(ROC_OOB_PATH)
	var hex_grid_data := _read_hex_grid()

	var brigade_teams := _build_brigade_team_lookup([pla_data, roc_data])
	var hex_coords := _build_hex_coord_lookup(hex_grid_data)
	var placements := _placements(scenario_data)
	var red_ship_reserve := _red_ship_reserve(scenario_data)

	_validate_placement_count(placements)
	_validate_placements(placements, brigade_teams, hex_coords)
	_validate_red_ship_reserve(red_ship_reserve, placements, brigade_teams, hex_coords)
	_finish()


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


func _placements(scenario_data: Dictionary) -> Array:
	var placements = scenario_data.get("placements", null)
	if not (placements is Array):
		_fail("%s missing placements array" % SCENARIO_PATH)
		return []
	if placements.is_empty():
		_fail("%s placements array is empty" % SCENARIO_PATH)
		return []
	return placements


func _red_ship_reserve(scenario_data: Dictionary) -> Array:
	var reserve = scenario_data.get("red_ship_reserve", null)
	if not (reserve is Array):
		_fail("%s missing red_ship_reserve array" % SCENARIO_PATH)
		return []
	return reserve


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


func _validate_placement_count(placements: Array) -> void:
	if placements.size() != EXPECTED_PLACEMENTS:
		_fail("Scenario placement count changed: expected %d, got %d" % [EXPECTED_PLACEMENTS, placements.size()])
	print("Placement count: %d" % placements.size())


func _validate_placements(placements: Array, brigade_teams: Dictionary, hex_coords: Dictionary) -> void:
	var seen_hexes := {}
	var green_count := 0

	for placement in placements:
		var brigade_id := String(placement.get("brigade_id", ""))
		var team := String(placement.get("team", ""))
		var hex_id := String(placement.get("hex", ""))

		if not brigade_teams.has(brigade_id):
			_fail("Placement references unknown brigade_id: %s" % brigade_id)
		elif team != String(brigade_teams[brigade_id]):
			_fail("Placement team mismatch for %s: expected %s, got %s" % [brigade_id, String(brigade_teams[brigade_id]), team])

		if team != "Green":
			_fail("Expected all placements to be Green, got %s for %s" % [team, brigade_id])
		else:
			green_count += 1

		if not hex_coords.has(hex_id):
			_fail("Placement references unknown hex: %s" % hex_id)
		if seen_hexes.has(hex_id):
			_fail("Placement hex is not unique: %s" % hex_id)
		seen_hexes[hex_id] = true

	if green_count != EXPECTED_PLACEMENTS:
		_fail("Expected %d Green placements, got %d" % [EXPECTED_PLACEMENTS, green_count])
	print("Team counts: Red=0 Green=%d" % green_count)


func _validate_red_ship_reserve(reserve: Array, placements: Array, brigade_teams: Dictionary, hex_coords: Dictionary) -> void:
	if reserve.size() != EXPECTED_RED_SHIP_RESERVE:
		_fail("red_ship_reserve count changed: expected %d, got %d" % [EXPECTED_RED_SHIP_RESERVE, reserve.size()])

	for index in range(reserve.size()):
		var entry: Dictionary = reserve[index]
		var brigade_id := String(entry.get("brigade_id", ""))
		var locked_beach := int(entry.get("locked_beach", 0))
		var beach_hex := String(entry.get("beach_hex", ""))

		if not brigade_teams.has(brigade_id):
			_fail("red_ship_reserve references unknown brigade_id: %s" % brigade_id)
		elif String(brigade_teams[brigade_id]) != "Red":
			_fail("red_ship_reserve references non-Red brigade_id: %s" % brigade_id)
		if locked_beach < 1 or locked_beach > 9:
			_fail("red_ship_reserve locked_beach out of range for %s: %d" % [brigade_id, locked_beach])
		if not hex_coords.has(beach_hex):
			_fail("red_ship_reserve references unknown beach_hex: %s" % beach_hex)

		if index < placements.size() and hex_coords.has(beach_hex):
			var green_hex := String((placements[index] as Dictionary).get("hex", ""))
			if hex_coords.has(green_hex):
				var beach_coord: Vector2i = hex_coords[beach_hex]
				var green_coord: Vector2i = hex_coords[green_hex]
				if green_coord not in HexMath.neighbor_coords(beach_coord):
					_fail("red_ship_reserve entry %d beach_hex %s is not adjacent to Green placement hex %s" % [index, beach_hex, green_hex])

	print("Red ship reserve checked: %d brigade(s)" % reserve.size())


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
