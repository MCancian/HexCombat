# Run from the project root:
# C:\Godot_v4.7-stable_win64.exe --headless --path C:\Users\mdogg\Desktop\HexCombat -s res://tools/validate_terrain_data.gd
extends SceneTree

const TERRAIN_TYPES_PATH := "res://data/terrain/terrain_types.json"
const HEX_TERRAIN_PATH := "res://data/terrain/hex_terrain.json"
const HEX_GRID_PATH := "res://data/taiwan_hex_grid.json"
const SCENARIO_DEFAULT_PATH := "res://data/scenarios/scenario_default.json"
const SCENARIOS_DIR := "res://data/scenarios/"
const EXPECTED_CLASSES := ["mountain", "metropolis", "hills", "urban", "plains"]

var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Terrain data validation ===")
	_validate_terrain_types()
	_validate_hex_classification_keys()
	_validate_impassable_placements()
	_finish()


func _read_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("Could not open %s" % path)
		return null
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed == null:
		_fail("%s did not parse as JSON" % path)
	return parsed


func _validate_terrain_types() -> void:
	var json: Variant = _read_json(TERRAIN_TYPES_PATH)
	if json == null:
		return

	var types_data: Dictionary = json.get("types", {})
	if types_data.is_empty():
		_fail("terrain_types.json 'types' is empty or missing")
		return

	var keys: Array = types_data.keys()
	keys.sort()
	var expected := EXPECTED_CLASSES.duplicate()
	expected.sort()
	if keys != expected:
		_fail("terrain_types.json types keys mismatch: expected %s, got %s" % [EXPECTED_CLASSES, types_data.keys()])
		return

	for cls in EXPECTED_CLASSES:
		var entry: Dictionary = types_data[cls]
		if not (entry is Dictionary):
			_fail("terrain_types.json types.%s is not a Dictionary" % cls)
			continue

		var dm: Variant = entry.get("defender_modifier", null)
		if dm == null or not (dm is float):
			_fail("terrain_types.json types.%s.defender_modifier: expected float, got %s" % [cls, typeof(dm) if dm != null else "null"])
		elif dm < 1.0 or dm > 5.0:
			_fail("terrain_types.json types.%s.defender_modifier %s out of range [1.0, 5.0]" % [cls, dm])

		var mc: Variant = entry.get("move_cost", null)
		if mc == null or not (mc is float and mc == floorf(mc)):
			_fail("terrain_types.json types.%s.move_cost: expected whole number, got %s" % [cls, str(mc)])
		elif mc < 1 or mc > 5:
			_fail("terrain_types.json types.%s.move_cost %s out of range [1, 5]" % [cls, mc])

		var imp: Variant = entry.get("impassable", null)
		if imp == null or not (imp is bool):
			_fail("terrain_types.json types.%s.impassable: expected bool, got %s" % [cls, typeof(imp) if imp != null else "null"])

		var col: Variant = entry.get("color", "")
		if not (col is String) or col.is_empty():
			_fail("terrain_types.json types.%s.color: expected non-empty string" % cls)
		elif not col.begins_with("#") or col.length() != 7:
			_fail("terrain_types.json types.%s.color '%s' must be '#' + 6 hex chars" % [cls, col])

		if cls == "mountain" and imp != true:
			_fail("terrain_types.json types.mountain.impassable must be true")
		if cls != "mountain" and imp != false:
			_fail("terrain_types.json types.%s.impassable must be false (only mountain is impassable)" % cls)

	print("Terrain types: %d classes validated" % EXPECTED_CLASSES.size())


func _validate_hex_classification_keys() -> void:
	var hex_terrain_json: Variant = _read_json(HEX_TERRAIN_PATH)
	if hex_terrain_json == null:
		return
	var class_map: Dictionary = hex_terrain_json.get("classes", {})
	if not (class_map is Dictionary):
		_fail("hex_terrain.json missing 'classes' key")
		return

	var grid_json: Variant = _read_json(HEX_GRID_PATH)
	if grid_json == null:
		return
	var grid_hexes: Array = grid_json.get("hexes", [])
	if not (grid_hexes is Array):
		_fail("taiwan_hex_grid.json missing 'hexes' array")
		return

	var grid_ids: Dictionary = {}
	for h in grid_hexes:
		grid_ids[String(h.get("id", ""))] = true

	var class_ids: Dictionary = {}
	for hex_id in class_map.keys():
		class_ids[String(hex_id)] = true

	var missing_in_classes: Array[String] = []
	for hex_id in grid_ids.keys():
		if hex_id not in class_ids:
			missing_in_classes.append(hex_id)

	var extra_in_classes: Array[String] = []
	for hex_id in class_ids.keys():
		if hex_id not in grid_ids:
			extra_in_classes.append(hex_id)

	for hex_id in class_map.keys():
		var terrain_class := String(class_map[hex_id])
		if terrain_class not in EXPECTED_CLASSES:
			_fail("hex_terrain.json: hex %s has unknown terrain class '%s'" % [hex_id, terrain_class])

	if not missing_in_classes.is_empty():
		_fail("hex_terrain.json: %d grid hex(es) missing from classes: %s" % [missing_in_classes.size(), missing_in_classes])
	else:
		print("Hex classification: all grid hexes present in classes")

	if not extra_in_classes.is_empty():
		_fail("hex_terrain.json: %d extra class entry(ies) not in grid: %s" % [extra_in_classes.size(), extra_in_classes])
	else:
		print("Hex classification: no extra entries in classes")

	print("Hex classification: %d entries checked against all known classes" % class_map.size())


func _validate_impassable_placements() -> void:
	var types_json: Variant = _read_json(TERRAIN_TYPES_PATH)
	if types_json == null:
		return
	var types_data: Dictionary = types_json.get("types", {})

	var terrain_json: Variant = _read_json(HEX_TERRAIN_PATH)
	if terrain_json == null:
		return
	var class_map: Dictionary = terrain_json.get("classes", {})

	var scenario_paths: Array[String] = [SCENARIO_DEFAULT_PATH]
	var dir := DirAccess.open(SCENARIOS_DIR)
	if dir != null:
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if fname.ends_with(".json"):
				scenario_paths.append(SCENARIOS_DIR.path_join(fname))
			fname = dir.get_next()

	var impassable_hexes: Array[String] = []
	for sp in scenario_paths:
		var json: Variant = _read_json(sp)
		if json == null:
			continue
		var placements: Array = json.get("placements", [])
		for p in placements:
			var hex_id := String(p.get("hex", ""))
			if hex_id.is_empty():
				_fail("%s: placement entry missing 'hex'" % sp)
				continue
			var terrain_class := String(class_map.get(hex_id, ""))
			var class_def: Dictionary = types_data.get(terrain_class, {})
			if class_def.get("impassable", false) == true:
				impassable_hexes.append("%s (in %s)" % [hex_id, sp])

	if not impassable_hexes.is_empty():
		_fail("Placement hex(es) on impassable terrain: %s" % impassable_hexes)
	else:
		print("Placement impassable check: no placements on impassable terrain")


func _fail(message: String) -> void:
	_failures.append(message)
	push_error(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: Terrain data validation succeeded")
		quit(0)
		return
	print("FAIL: Terrain data validation found %d issue(s):" % _failures.size())
	for failure in _failures:
		print("  - %s" % failure)
	quit(1)
