# Run from the project root:
# godot --headless --path . -s res://tools/validate_offload_weights.gd
extends SceneTree

const OFFLOAD_WEIGHTS_PATH := "res://data/offload_weights.json"
const SHIPS_PATH := "res://data/ships.json"

var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Offload weights validation ===")
	_validate_structure()
	_validate_ship_categories()
	_validate_spot_checks()
	_finish()


func _validate_structure() -> void:
	var file := FileAccess.open(OFFLOAD_WEIGHTS_PATH, FileAccess.READ)
	if file == null:
		_fail("Could not open %s" % OFFLOAD_WEIGHTS_PATH)
		return

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		_fail("offload_weights.json did not parse to a Dictionary")
		return

	var default_tons: Variant = parsed.get("default_tons", 0)
	if not (default_tons is float or default_tons is int) or float(default_tons) <= 0.0:
		_fail("default_tons must be > 0, got %s" % default_tons)

	var weights: Dictionary = parsed.get("weights", {})
	if weights.is_empty():
		_fail("missing or empty 'weights' Dictionary")
		return

	for key in weights.keys():
		if not UnitStats.TYPE_DEFS.has(key):
			_fail("weights key '%s' is not a known UnitStats type" % key)

	for key in UnitStats.TYPE_DEFS.keys():
		if not weights.has(key):
			_fail("TYPE_DEFS key '%s' missing from weights" % key)

	for key in weights.keys():
		var val: Variant = weights[key]
		if not (val is float or val is int) or float(val) <= 0.0:
			_fail("weight for '%s' must be > 0, got %s" % [key, val])

	var bn_class_of: Dictionary = parsed.get("bn_class_of", {})
	for key in bn_class_of.keys():
		if not UnitStats.TYPE_DEFS.has(key):
			_fail("bn_class_of key '%s' is not a known UnitStats type" % key)

	var multipliers: Dictionary = parsed.get("multipliers", {})
	var allowed_kinds := {"beach": true, "port": true, "airbridge": true, "default": true}
	for key in multipliers.keys():
		if not allowed_kinds.has(key):
			_fail("multipliers top-level key '%s' not in {beach, port, airbridge, default}" % key)

	_validate_multiplier_leaves(multipliers, "multipliers")

	print("offload_weights.json: structure valid (%d types, %d multipliers)" % [weights.size(), multipliers.size()])


func _validate_multiplier_leaves(d: Dictionary, path: String) -> void:
	for key in d.keys():
		var val: Variant = d[key]
		var child_path := "%s.%s" % [path, key]
		if val is Dictionary:
			_validate_multiplier_leaves(val, child_path)
		elif val is float or val is int:
			if float(val) <= 0.0:
				_fail("multiplier leaf at '%s' must be > 0, got %s" % [child_path, val])
		else:
			_fail("multiplier at '%s' is neither Dictionary nor number: %s" % [child_path, val])


func _validate_ship_categories() -> void:
	var file := FileAccess.open(SHIPS_PATH, FileAccess.READ)
	if file == null:
		_fail("Could not open %s" % SHIPS_PATH)
		return

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		_fail("ships.json did not parse to a Dictionary")
		return

	var ship_entries: Array = parsed.get("ships", [])
	var known_categories: Dictionary = {}
	for entry in ship_entries:
		var cat: String = String(entry.get("category", ""))
		if not cat.is_empty():
			known_categories[cat] = true

	var parsed_weights: Variant = JSON.parse_string(FileAccess.get_file_as_string(OFFLOAD_WEIGHTS_PATH))
	if not (parsed_weights is Dictionary):
		return

	var multipliers: Dictionary = parsed_weights.get("multipliers", {})
	var found: Dictionary = {}
	_collect_ship_category_keys(multipliers, found)
	for cat in found.keys():
		if cat != "default" and not known_categories.has(cat):
			_fail("ship_category '%s' in multipliers not found in ships.json entries" % cat)

	print("offload_weights.json: all ship categories valid")


func _collect_ship_category_keys(d: Dictionary, out: Dictionary) -> void:
	for key in d.keys():
		var val: Variant = d[key]
		if val is Dictionary and _is_innermost_dict(val):
			for inner_key in (val as Dictionary).keys():
				out[inner_key] = true
		elif val is Dictionary:
			_collect_ship_category_keys(val, out)


# Heuristic: a Dictionary is innermost if all its values are numbers.
func _is_innermost_dict(d: Dictionary) -> bool:
	for val in d.values():
		if val is Dictionary:
			return false
	return true


func _validate_spot_checks() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(OFFLOAD_WEIGHTS_PATH))
	if not (parsed is Dictionary):
		return

	var config := parsed as Dictionary

	var check1 := OffloadCostModel.bn_cost_tons("Amphibious Infantry Battalion", "Military_Amphibious", "beach", config)
	if not is_equal_approx(check1, 1100.0):
		_fail("spot-check 1: expected 1100.0, got %s" % check1)

	var check2 := OffloadCostModel.bn_cost_tons("Combined Arms Battalion", "Civilian_Non_Amphibious", "beach", config)
	if not is_equal_approx(check2, 4400.0):
		_fail("spot-check 2: expected 4400.0, got %s" % check2)

	var check3 := OffloadCostModel.bn_cost_tons("Amphibious Infantry Battalion", "Military_Amphibious", "port", config)
	if not is_equal_approx(check3, 2200.0):
		_fail("spot-check 3: expected 2200.0, got %s" % check3)

	var check4 := OffloadCostModel.bn_cost_tons("Tank Battalion", "Military_Amphibious", "beach", OffloadCostModel.flat_config())
	if not is_equal_approx(check4, OffloadRates.TONS_PER_BN):
		_fail("spot-check 4: expected %s, got %s" % [OffloadRates.TONS_PER_BN, check4])

	print("OffloadCostModel spot-checks: all passed")


func _fail(message: String) -> void:
	_failures.append(message)
	push_error(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: Offload weights validation succeeded")
		quit(0)
		return
	print("FAIL: Offload weights validation found %d issue(s):" % _failures.size())
	for failure in _failures:
		print("  - %s" % failure)
	quit(1)
