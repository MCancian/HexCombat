# Run from the project root:
# C:\Godot_v4.7-stable_win64.exe --headless --path C:\Users\mdogg\Desktop\HexCombat -s res://tools/validate_combat_data.gd
extends SceneTree

const OOB_PATH := "res://data/pla_ground_forces.json"
const EXPECTED_BRIGADE_STRENGTHS := {
	"PLA-71-2-Amphibious": 8.3,
	"PLA-71-35-Heavy-Armored": 9.5,
	"PLA-71-160-Light-Mechanized": 9.5
}
const EXPECTED_ARTILLERY_TYPES := [
	"Field Artillery Battalion",
	"Mechanized Artillery Battalion",
	"Rocket Artillery Battalion"
]

var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Combat data validation ===")
	var data := _read_json(OOB_PATH)
	if data.is_empty():
		_fail("Unable to load %s" % OOB_PATH)
		_finish()
		return

	_validate_unit_types(data)
	_validate_support_normalization()
	_validate_regression_samples(data)
	_validate_artillery_classification(data)
	_finish()


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed
	return {}


func _validate_unit_types(data: Dictionary) -> void:
	var unit_types := _distinct_unit_types(data)
	print("Distinct battalion types (%d):" % unit_types.size())
	for unit_type in unit_types:
		if not UnitStats.has_known_type(unit_type):
			_fail("Unknown battalion type: %s" % unit_type)
		var category := UnitStats.category_for_type(unit_type)
		var strength := UnitStats.strength_for_type(unit_type)
		if category.is_empty():
			_fail("No category resolved for battalion type: %s" % unit_type)
		print("  %s => %s %.1f" % [unit_type, category, strength])


func _validate_support_normalization() -> void:
	var support := CombatCalculator.normalize_support({"artillery": 5, "rocket_artillery": null, "cas": -2})
	_assert_equal_int("support artillery preserves nonzero count", support["artillery"], 5)
	_assert_equal_int("support explicit null becomes zero", support["rocket_artillery"], 0)
	_assert_equal_int("support missing key becomes zero", support["crbm"], 0)
	_assert_equal_int("support negative clamps to zero", support["cas"], 0)
	print("Support normalization: artillery=5, null=0, missing=0, negative=0")


func _validate_regression_samples(data: Dictionary) -> void:
	print("Regression sample brigade maneuver strengths:")
	for brigade_id in EXPECTED_BRIGADE_STRENGTHS:
		var brigade := _brigade_by_id(data, brigade_id)
		if brigade.is_empty():
			_fail("Missing regression brigade: %s" % brigade_id)
			continue
		var strength := _brigade_maneuver_strength(brigade)
		var expected := float(EXPECTED_BRIGADE_STRENGTHS[brigade_id])
		if not is_equal_approx(strength, expected):
			_fail("Brigade %s strength changed: expected %.1f, got %.1f" % [brigade_id, expected, strength])
		print("  %s before %.1f / after %.1f" % [brigade_id, expected, strength])


func _validate_artillery_classification(data: Dictionary) -> void:
	var expected: Array[String] = []
	for unit_type in EXPECTED_ARTILLERY_TYPES:
		expected.append(unit_type)
	expected.sort()

	var actual: Array[String] = []
	for unit_type in _distinct_unit_types(data):
		if UnitStats.has_tag(unit_type, "artillery"):
			actual.append(unit_type)
	actual.sort()

	if actual != expected:
		_fail("Artillery classification changed: expected %s, got %s" % [", ".join(expected), ", ".join(actual)])
	print("Artillery classification before/after: %s / %s" % [", ".join(expected), ", ".join(actual)])


func _distinct_unit_types(data: Dictionary) -> Array[String]:
	var unit_types: Array[String] = []
	var brigades: Array = data.get("brigades", [])
	for brigade in brigades:
		var composition: Array = brigade.get("composition", [])
		for battalion in composition:
			var unit_type := String(battalion.get("type", ""))
			if not unit_type.is_empty() and unit_type not in unit_types:
				unit_types.append(unit_type)
	unit_types.sort()
	return unit_types


func _brigade_by_id(data: Dictionary, brigade_id: String) -> Dictionary:
	var brigades: Array = data.get("brigades", [])
	for brigade in brigades:
		if String(brigade.get("brigade_id", "")) == brigade_id:
			return brigade
	return {}


func _brigade_maneuver_strength(brigade: Dictionary) -> float:
	var total := 0.0
	var composition: Array = brigade.get("composition", [])
	for battalion in composition:
		var unit_type := String(battalion.get("type", ""))
		var qty := int(battalion.get("qty", 0))
		total += UnitStats.strength_for_type(unit_type) * float(qty)
	return total


func _assert_equal_int(label: String, actual: int, expected: int) -> void:
	if actual != expected:
		_fail("%s: expected %d, got %d" % [label, expected, actual])


func _fail(message: String) -> void:
	_failures.append(message)
	push_error(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: combat data validation succeeded")
		quit(0)
		return

	print("FAIL: combat data validation found %d issue(s):" % _failures.size())
	for failure in _failures:
		print("  - %s" % failure)
	quit(1)
