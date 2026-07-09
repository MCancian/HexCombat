# Run from the project root:
# C:\Godot_v4.7-stable_win64.exe --headless --path C:\Users\mdogg\Desktop\HexCombat -s res://tools/validate_beaches_data.gd
extends SceneTree

const BEACHES_PATH := "res://data/beaches.json"
const HEX_GRID_PATH := "res://data/taiwan_hex_grid.json"
const EXPECTED_BEACH_COUNT := 9
const KNOWN_TO_NUMBERS := [2, 3, 4, 5]

var _failures: Array[String] = []
var _hex_ids: Array = []


func _initialize() -> void:
	print("=== Beach data validation ===")
	var json: Variant = _read_json(BEACHES_PATH)
	if json == null:
		_finish()
		return

	_hex_ids = _load_hex_ids()

	var beaches_data: Array = json.get("beaches", [])
	_validate_count(beaches_data)
	_validate_beach_contracts(beaches_data)
	_finish()


func _load_hex_ids() -> Array:
	var json: Variant = _read_json(HEX_GRID_PATH)
	if json == null:
		return []
	var hexes_data: Array = []
	if json is Array:
		hexes_data = json
	elif json is Dictionary and json.has("hexes"):
		hexes_data = json["hexes"]
	var ids: Array = []
	for hex_data in hexes_data:
		ids.append(String(hex_data.get("id", "")))
	return ids


func _read_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("Could not open %s" % path)
		return null
	var parsed = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		_fail("%s did not parse to a Dictionary" % path)
		return null
	return parsed


func _validate_count(beaches_data: Array) -> void:
	var count := beaches_data.size()
	if count != EXPECTED_BEACH_COUNT:
		_fail("Beach count changed: expected %d, got %d" % [EXPECTED_BEACH_COUNT, count])
	else:
		print("Beach count: %d" % count)


func _validate_beach_contracts(beaches_data: Array) -> void:
	var ids_seen: Array[int] = []
	for beach_data in beaches_data:
		var beach_id := int(beach_data.get("id", 0))
		if beach_id == 0:
			_fail("Beach missing id field")
			continue
		if beach_id in ids_seen:
			_fail("Duplicate beach id: %d" % beach_id)
		ids_seen.append(beach_id)

		var name_en := String(beach_data.get("name_en", ""))
		if name_en.is_empty():
			_fail("Beach %d missing name_en" % beach_id)

		var hex_id := String(beach_data.get("hex_id", ""))
		if hex_id.is_empty():
			_fail("Beach %d missing hex_id" % beach_id)
		elif hex_id not in _hex_ids:
			_fail("Beach %d hex_id '%s' not present in taiwan_hex_grid.json" % [beach_id, hex_id])

		var to_number := int(beach_data.get("to_number", -1))
		if to_number not in KNOWN_TO_NUMBERS:
			_fail("Beach %d has unknown to_number: %d" % [beach_id, to_number])

		var offload_rate := float(beach_data.get("offload_rate", 0.0))
		if offload_rate <= 0.0:
			_fail("Beach %d has non-positive offload_rate: %s" % [beach_id, offload_rate])

		var capacity_bns := int(beach_data.get("capacity_battalions", 0))
		if capacity_bns <= 0:
			_fail("Beach %d has non-positive capacity_battalions: %d" % [beach_id, capacity_bns])

		var lat := float(beach_data.get("lat", 0.0))
		var lng := float(beach_data.get("lng", 0.0))
		if lat == 0.0 or lng == 0.0:
			_fail("Beach %d missing lat/lng (got lat=%s lng=%s)" % [beach_id, lat, lng])

	print("Beach contract check: %d beaches validated" % ids_seen.size())


func _fail(message: String) -> void:
	_failures.append(message)
	push_error(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: Beach data validation succeeded")
		quit(0)
		return
	print("FAIL: Beach data validation found %d issue(s):" % _failures.size())
	for failure in _failures:
		print("  - %s" % failure)
	quit(1)
