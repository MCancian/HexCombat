# Run from the project root:
# C:\Godot_v4.7-stable_win64.exe --headless --path C:\Users\mdogg\Desktop\HexCombat -s res://tools/validate_victory_hexes.gd
#
# Validates that each scenario's victory.taiwan_hexes matches the largest connected
# component of the hex grid (main island) and excludes known offshore ids.
extends SceneTree

const HEX_GRID_PATH := "res://data/taiwan_hex_grid.json"
const OFFSHORE_IDS: Array[String] = ["hex_11_16", "hex_12_16", "hex_12_17", "hex_4_18"]

var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Victory hexes validation ===")

	var hex_grid := _read_hex_grid()
	if hex_grid.is_empty():
		_fail("Could not load hex grid")
		_finish()
		return

	var hex_ids_by_coord := _build_coord_lookup(hex_grid)
	var main_island_set := _compute_largest_component_set(hex_ids_by_coord)

	var scenario_paths := ScenarioCatalog.list_scenario_paths()
	for path in scenario_paths:
		var scenario_data := _read_dictionary(path)
		if scenario_data.is_empty():
			continue
		var label := ScenarioCatalog.scenario_id(path)
		_validate_scenario_victory_hexes(label, scenario_data, main_island_set)

	print("Scenarios checked: %d" % scenario_paths.size())
	_finish()


func _validate_scenario_victory_hexes(label: String, scenario_data: Dictionary, main_island_set: Dictionary) -> void:
	var victory_value: Variant = scenario_data.get("victory", null)
	if victory_value == null:
		return
	if not (victory_value is Dictionary):
		return
	var victory: Dictionary = victory_value
	var taiwan_hexes_value: Variant = victory.get("taiwan_hexes", null)
	if taiwan_hexes_value == null:
		# null = census counts all placed hexes (legitimate; the golden default keeps this).
		print("SKIP: %s victory.taiwan_hexes is null (census unrestricted)" % label)
		return
	if not (taiwan_hexes_value is Array):
		_fail("%s: victory.taiwan_hexes must be an Array" % label)
		return
	var taiwan_hexes: Array = taiwan_hexes_value

	var declared_set: Dictionary = {}
	for hex_id in taiwan_hexes:
		declared_set[String(hex_id)] = true

	var expected_count: int = main_island_set.size()

	if declared_set != main_island_set:
		_fail("%s: victory.taiwan_hexes mismatch — declared=%d, expected=%d" % [label, taiwan_hexes.size(), expected_count])
		var extra: Array[String] = []
		var missing: Array[String] = []
		for key in declared_set:
			if not main_island_set.has(key):
				extra.append(key)
		for key in main_island_set:
			if not declared_set.has(key):
				missing.append(key)
		extra.sort()
		missing.sort()
		if not extra.is_empty():
			_fail("  extra ids (%d): %s" % [extra.size(), str(extra.slice(0, mini(5, extra.size())))])
		if not missing.is_empty():
			_fail("  missing ids (%d): %s" % [missing.size(), str(missing.slice(0, mini(5, missing.size())))])
		return

	var found_offshore: Array[String] = []
	for oid in OFFSHORE_IDS:
		if declared_set.has(oid):
			found_offshore.append(oid)
	if not found_offshore.is_empty():
		_fail("%s: victory.taiwan_hexes includes offshore ids: %s" % [label, str(found_offshore)])
		return

	print("PASS: %s victory taiwan_hexes matches main island (%d hexes)" % [label, expected_count])


func _build_coord_lookup(hexes: Array) -> Dictionary:
	var lookup: Dictionary = {}
	for hex_data in hexes:
		var hex_id := String(hex_data.get("id", ""))
		if not hex_id.is_empty():
			lookup[Vector2i(int(hex_data.get("row", 0)), int(hex_data.get("col", 0)))] = hex_id
	return lookup


func _compute_largest_component_set(coord_to_id: Dictionary) -> Dictionary:
	var id_to_coord: Dictionary = {}
	for coord in coord_to_id:
		id_to_coord[coord_to_id[coord]] = coord

	var all_ids := id_to_coord.keys()
	var unvisited: Dictionary = {}
	for hid in all_ids:
		unvisited[hid] = true

	var largest: Array[String] = []

	while not unvisited.is_empty():
		var keys := unvisited.keys()
		var start: String = keys[0]
		unvisited.erase(start)

		var stack: Array[String] = [start]
		var component: Array[String] = []

		while not stack.is_empty():
			var hex_id: String = stack.pop_back()
			component.append(hex_id)
			var coord: Vector2i = id_to_coord[hex_id]
			for neighbor in HexMath.neighbor_coords(coord):
				var neighbor_id: Variant = coord_to_id.get(neighbor, null)
				if neighbor_id != null and unvisited.has(neighbor_id as String):
					unvisited.erase(neighbor_id as String)
					stack.append(neighbor_id as String)

		if component.size() > largest.size():
			largest = component

	var result: Dictionary = {}
	for hid in largest:
		result[hid] = true
	return result


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


func _fail(message: String) -> void:
	_failures.append(message)
	push_error(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: Victory hexes validation succeeded")
		quit(0)
		return

	print("FAIL: Victory hexes validation found %d issue(s):" % _failures.size())
	for failure in _failures:
		print("  - %s" % failure)
	quit(1)