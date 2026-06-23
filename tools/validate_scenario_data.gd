# Run from the project root:
# C:\Godot_v4.7-stable_win64.exe --headless --path C:\Users\mdogg\Desktop\HexCombat -s res://tools/validate_scenario_data.gd
extends SceneTree

const SCENARIO_PATH := "res://data/scenario_default.json"
const PLA_OOB_PATH := "res://data/pla_ground_forces.json"
const ROC_OOB_PATH := "res://data/roc_ground_forces.json"
const HEX_GRID_PATH := "res://data/taiwan_hex_grid.json"
const EXPECTED_PLACEMENTS := 8

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

	_validate_placement_count(placements)
	_validate_placements(placements, brigade_teams, hex_coords)
	_validate_beach_adjacency(placements, hex_coords)
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
	var team_counts := {"Red": 0, "Green": 0}

	for placement in placements:
		var brigade_id := String(placement.get("brigade_id", ""))
		var team := String(placement.get("team", ""))
		var hex_id := String(placement.get("hex", ""))

		if not brigade_teams.has(brigade_id):
			_fail("Placement references unknown brigade_id: %s" % brigade_id)
		elif team != String(brigade_teams[brigade_id]):
			_fail("Placement team mismatch for %s: expected %s, got %s" % [brigade_id, String(brigade_teams[brigade_id]), team])

		if not hex_coords.has(hex_id):
			_fail("Placement references unknown hex: %s" % hex_id)
		if seen_hexes.has(hex_id):
			_fail("Placement hex is not unique: %s" % hex_id)
		seen_hexes[hex_id] = true

		if team_counts.has(team):
			team_counts[team] += 1
		else:
			_fail("Placement has unexpected team: %s" % team)

	if int(team_counts["Red"]) != 4:
		_fail("Expected 4 Red placements, got %d" % int(team_counts["Red"]))
	if int(team_counts["Green"]) != 4:
		_fail("Expected 4 Green placements, got %d" % int(team_counts["Green"]))
	print("Team counts: Red=%d Green=%d" % [int(team_counts["Red"]), int(team_counts["Green"])])


func _validate_beach_adjacency(placements: Array, hex_coords: Dictionary) -> void:
	var red_by_beach := {}
	var green_by_beach := {}

	for placement in placements:
		var beach := int(placement.get("beach", 0))
		var team := String(placement.get("team", ""))
		if team == "Red":
			red_by_beach[beach] = placement
		elif team == "Green":
			green_by_beach[beach] = placement

	for beach in red_by_beach.keys():
		if not green_by_beach.has(beach):
			_fail("Beach %d has Red placement but no Green placement" % int(beach))
			continue

		var red_hex := String(red_by_beach[beach].get("hex", ""))
		var green_hex := String(green_by_beach[beach].get("hex", ""))
		if not hex_coords.has(red_hex) or not hex_coords.has(green_hex):
			continue

		var red_coord: Vector2i = hex_coords[red_hex]
		var green_coord: Vector2i = hex_coords[green_hex]
		if green_coord not in HexMath.neighbor_coords(red_coord):
			_fail("Beach %d Green hex %s is not adjacent to Red hex %s" % [int(beach), green_hex, red_hex])

	for beach in green_by_beach.keys():
		if not red_by_beach.has(beach):
			_fail("Beach %d has Green placement but no Red placement" % int(beach))

	print("Beach adjacency checked: %d beach(es)" % red_by_beach.size())


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
