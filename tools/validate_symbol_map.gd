# Run from the project root:
# C:\Godot_v4.7-stable_win64.exe --headless --path C:\Users\mdogg\Desktop\HexCombat -s res://tools/validate_symbol_map.gd
#
# Asserts every brigade nato_type used by the OOBs maps to a NATO symbol SVG that
# actually loads as a Texture2D, and that every map entry points at a real file.
extends SceneTree

const SYMBOL_MAP_PATH := "res://data/nato_symbol_map.json"
const OOB_PATHS := ["res://data/pla_ground_forces.json", "res://data/roc_ground_forces.json"]

var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Symbol map validation ===")
	var map_doc := _read_json(SYMBOL_MAP_PATH)
	var symbol_dir := String(map_doc.get("symbol_dir", "res://assets/symbols"))
	var mapping = map_doc.get("nato_type_to_symbol", null)
	if not (mapping is Dictionary) or (mapping as Dictionary).is_empty():
		_fail("nato_type_to_symbol missing or empty in %s" % SYMBOL_MAP_PATH)
		_finish()
		return

	# 1) Every map entry resolves to a loadable Texture2D.
	for nato_type in mapping:
		_check_symbol_loads(symbol_dir, String(mapping[nato_type]), "map entry '%s'" % nato_type)

	# 2) Every nato_type used by either OOB has a map entry.
	var used := _used_nato_types()
	print("Distinct nato_types in OOBs (%d): %s" % [used.size(), ", ".join(used)])
	for nato_type in used:
		if not (mapping as Dictionary).has(nato_type):
			_fail("OOB nato_type '%s' has no symbol mapping" % nato_type)

	_finish()


func _check_symbol_loads(symbol_dir: String, filename: String, context: String) -> void:
	if filename.is_empty():
		_fail("%s: empty symbol filename" % context)
		return
	var path := "%s/%s" % [symbol_dir, filename]
	if not ResourceLoader.exists(path):
		_fail("%s: symbol resource not found: %s" % [context, path])
		return
	var res := load(path)
	if res == null or not (res is Texture2D):
		_fail("%s: %s did not load as Texture2D" % [context, path])


func _used_nato_types() -> Array[String]:
	var types: Array[String] = []
	for path in OOB_PATHS:
		var data := _read_json(path)
		for brigade in data.get("brigades", []):
			var nato_type := String(brigade.get("nato_type", ""))
			if not nato_type.is_empty() and nato_type not in types:
				types.append(nato_type)
	types.sort()
	return types


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("Could not open %s" % path)
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		_fail("%s did not parse to a Dictionary" % path)
		return {}
	return parsed


func _fail(message: String) -> void:
	_failures.append(message)
	push_error(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: symbol map validation succeeded")
		quit(0)
		return
	print("FAIL: symbol map validation found %d issue(s):" % _failures.size())
	for failure in _failures:
		print("  - %s" % failure)
	quit(1)
