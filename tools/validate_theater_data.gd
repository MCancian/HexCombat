# Run from the project root:
# C:\Godot_v4.7-stable_win64.exe --headless --path C:\Users\mdogg\Desktop\HexCombat -s res://tools/validate_theater_data.gd
extends SceneTree

const THEATERS_PATH := "res://data/theaters.json"
const BEACHES_PATH := "res://data/beaches.json"
const EXPECTED_ACTIVE_TOS: Array[int] = [2, 3, 4, 5]
const EXPECTED_BEACH_COUNT := 9

var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Theater data validation ===")
	var theaters_json: Variant = _read_json(THEATERS_PATH)
	var beaches_json: Variant = _read_json(BEACHES_PATH)
	if theaters_json == null or beaches_json == null:
		_finish()
		return

	var active_tos: Array[int] = _parse_int_array(theaters_json.get("active_tos", []))
	var to_adjacency: Dictionary = _parse_int_array_map(theaters_json.get("to_adjacency", {}), "to_adjacency")
	var beach_to_to: Dictionary = _parse_int_int_map(theaters_json.get("beach_to_to", {}), "beach_to_to")
	var beaches_data: Array = beaches_json.get("beaches", [])

	_assert_active_tos(active_tos)
	_assert_adjacency(to_adjacency, active_tos)
	_assert_beach_to_to(beach_to_to)
	_assert_beaches_agree(beaches_data, beach_to_to)
	_finish()


func _read_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("Could not open %s" % path)
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		_fail("%s did not parse to a Dictionary" % path)
		return null
	return parsed


func _parse_int_array(value: Variant) -> Array[int]:
	var result: Array[int] = []
	if not (value is Array):
		_fail("Expected Array, got %s" % type_string(typeof(value)))
		return result
	for item in value:
		result.append(int(item))
	return result


func _parse_int_array_map(value: Variant, field_name: String) -> Dictionary:
	var result: Dictionary = {}
	if not (value is Dictionary):
		_fail("%s must be a Dictionary" % field_name)
		return result
	for key in value.keys():
		var map_value = value[key]
		if not (map_value is Array):
			_fail("%s[%s] must be an Array" % [field_name, String(key)])
			continue
		result[int(String(key))] = _parse_int_array(map_value)
	return result


func _parse_int_int_map(value: Variant, field_name: String) -> Dictionary:
	var result: Dictionary = {}
	if not (value is Dictionary):
		_fail("%s must be a Dictionary" % field_name)
		return result
	for key in value.keys():
		result[int(String(key))] = int(value[key])
	return result


func _assert_active_tos(active_tos: Array[int]) -> void:
	if active_tos != EXPECTED_ACTIVE_TOS:
		_fail("active_tos changed: expected %s, got %s" % [EXPECTED_ACTIVE_TOS, active_tos])
	else:
		print("Active TOs: %s" % [active_tos])


func _assert_adjacency(to_adjacency: Dictionary, active_tos: Array[int]) -> void:
	for to in to_adjacency.keys():
		var to_number := int(to)
		if to_number not in active_tos:
			_fail("Adjacency key is not an active TO: %d" % to_number)
		var neighbors: Array[int] = to_adjacency[to_number]
		for neighbor in neighbors:
			if neighbor not in active_tos:
				_fail("TO %d adjacency endpoint is not active: %d" % [to_number, neighbor])
			elif not (neighbor in to_adjacency):
				_fail("TO %d adjacency endpoint missing adjacency list: %d" % [to_number, neighbor])
			else:
				var reverse_neighbors: Array[int] = to_adjacency[neighbor]
				if to_number not in reverse_neighbors:
					_fail("TO adjacency is not symmetric: %d -> %d exists, but reverse is missing" % [to_number, neighbor])

	for active_to in active_tos:
		if active_to not in to_adjacency:
			_fail("Active TO missing adjacency list: %d" % active_to)

	print("TO adjacency: %d active TOs checked" % active_tos.size())


func _assert_beach_to_to(beach_to_to: Dictionary) -> void:
	if beach_to_to.size() != EXPECTED_BEACH_COUNT:
		_fail("beach_to_to count changed: expected %d, got %d" % [EXPECTED_BEACH_COUNT, beach_to_to.size()])
	for beach_id in range(1, EXPECTED_BEACH_COUNT + 1):
		if beach_id not in beach_to_to:
			_fail("beach_to_to missing beach id: %d" % beach_id)
	print("beach_to_to: %d beaches checked" % beach_to_to.size())


func _assert_beaches_agree(beaches_data: Array, beach_to_to: Dictionary) -> void:
	if beaches_data.size() != EXPECTED_BEACH_COUNT:
		_fail("beaches.json count changed: expected %d, got %d" % [EXPECTED_BEACH_COUNT, beaches_data.size()])
	for beach_data in beaches_data:
		var beach_id := int(beach_data.get("id", 0))
		if beach_id == 0:
			_fail("beaches.json beach missing id")
			continue
		if beach_id not in beach_to_to:
			_fail("beaches.json beach %d missing from theater beach_to_to" % beach_id)
			continue
		var beach_to_number := int(beach_data.get("to_number", 0))
		var theater_to_number := int(beach_to_to[beach_id])
		if beach_to_number != theater_to_number:
			_fail("Beach %d to_number mismatch: beaches.json=%d theaters.json=%d" % [beach_id, beach_to_number, theater_to_number])
	print("Beach/TO cross-file agreement: %d beaches checked" % beaches_data.size())


func _fail(message: String) -> void:
	_failures.append(message)
	push_error(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: Theater data validation succeeded")
		quit(0)
		return
	print("FAIL: Theater data validation found %d issue(s):" % _failures.size())
	for failure in _failures:
		print("  - %s" % failure)
	quit(1)
