# Run from the project root:
# C:\Godot_v4.7-stable_win64.exe --headless --path C:\Users\mdogg\Desktop\HexCombat -s res://tools/validate_oob_data.gd
extends SceneTree

const PLA_OOB_PATH := "res://data/pla_ground_forces.json"
const ROC_OOB_PATH := "res://data/roc_ground_forces.json"
# 111 line/support brigades + the 6-brigade PLAAF Airborne Corps added by plan 0032.
const EXPECTED_PLA_BRIGADES := 117
const EXPECTED_ROC_BRIGADES := 32
const EXPECTED_COMBINED_BRIGADES := 149

var _h := ValidatorHarness.new("OOB data validation")


func _initialize() -> void:
	print("=== OOB data validation ===")
	var pla_data := _read_oob(PLA_OOB_PATH)
	var roc_data := _read_oob(ROC_OOB_PATH)

	_validate_counts(pla_data, roc_data)
	_validate_team(pla_data, "Red", "PLA")
	_validate_team(roc_data, "Green", "ROC")
	_validate_brigade_contracts(pla_data, "PLA")
	_validate_brigade_contracts(roc_data, "ROC")
	_validate_known_battalion_types([pla_data, roc_data])
	_h.finish(self)


func _read_oob(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_h.fail("Could not open %s" % path)
		return {}

	var parsed = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		_h.fail("%s did not parse to a Dictionary" % path)
		return {}

	var data: Dictionary = parsed
	var brigades = data.get("brigades", null)
	if not (brigades is Array):
		_h.fail("%s missing brigades array" % path)
		return {}
	if brigades.is_empty():
		_h.fail("%s brigades array is empty" % path)

	return data


func _validate_counts(pla_data: Dictionary, roc_data: Dictionary) -> void:
	var pla_count := _brigades(pla_data).size()
	var roc_count := _brigades(roc_data).size()
	var combined_count := pla_count + roc_count

	if pla_count != EXPECTED_PLA_BRIGADES:
		_h.fail("PLA brigade count changed: expected %d, got %d" % [EXPECTED_PLA_BRIGADES, pla_count])
	if roc_count != EXPECTED_ROC_BRIGADES:
		_h.fail("ROC brigade count changed: expected %d, got %d" % [EXPECTED_ROC_BRIGADES, roc_count])
	if combined_count != EXPECTED_COMBINED_BRIGADES:
		_h.fail("Combined brigade count changed: expected %d, got %d" % [EXPECTED_COMBINED_BRIGADES, combined_count])

	print("Brigade counts: PLA=%d ROC=%d combined=%d" % [pla_count, roc_count, combined_count])


func _validate_team(data: Dictionary, expected_team: String, label: String) -> void:
	for brigade in _brigades(data):
		var brigade_id := String(brigade.get("brigade_id", ""))
		var actual_team := String(brigade.get("team", ""))
		if actual_team != expected_team:
			_h.fail("%s brigade %s team changed: expected %s, got %s" % [label, brigade_id, expected_team, actual_team])


func _validate_brigade_contracts(data: Dictionary, label: String) -> void:
	for brigade in _brigades(data):
		var brigade_id := String(brigade.get("brigade_id", ""))
		if brigade_id.is_empty():
			_h.fail("%s brigade has empty brigade_id" % label)

		var composition = brigade.get("composition", null)
		if not (composition is Array) or composition.is_empty():
			_h.fail("%s brigade %s has empty composition" % [label, brigade_id])


func _validate_known_battalion_types(oobs: Array[Dictionary]) -> void:
	var offending_types: Array[String] = []
	for data in oobs:
		for brigade in _brigades(data):
			var composition: Array = brigade.get("composition", [])
			for battalion in composition:
				var unit_type := String(battalion.get("type", ""))
				if not unit_type.is_empty() and not UnitStats.has_known_type(unit_type) and unit_type not in offending_types:
					offending_types.append(unit_type)

	offending_types.sort()
	for unit_type in offending_types:
		_h.fail("Unknown battalion type: %s" % unit_type)
	print("Known battalion type check: %d offending type(s)" % offending_types.size())


func _brigades(data: Dictionary) -> Array:
	return data.get("brigades", [])
