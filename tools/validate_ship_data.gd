# Run from the project root:
# C:\Godot_v4.7-stable_win64.exe --headless --path C:\Users\mdogg\Desktop\HexCombat -s res://tools/validate_ship_data.gd
extends SceneTree

const SHIPS_PATH := "res://data/ships.json"
const EXPECTED_SHIP_COUNT := 27
const EXPECTED_CATEGORIES := ["Escort", "Military_Amphibious", "Civilian_Amphibious", "Civilian_Non_Amphibious", "Infrastructure"]

const ShipStateResource = preload("res://scripts/model/ShipState.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Ship data validation ===")
	var json: Variant = _read_json(SHIPS_PATH)
	if json == null:
		_finish()
		return

	var ships_data: Array = json.get("ships", [])
	_validate_count_and_ids(ships_data)
	_validate_ship_contracts(ships_data)
	_validate_fresh_fleet(ships_data)
	_finish()


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


func _validate_count_and_ids(ships_data: Array) -> void:
	var count := ships_data.size()
	if count != EXPECTED_SHIP_COUNT:
		_fail("Ship count changed: expected %d, got %d" % [EXPECTED_SHIP_COUNT, count])
	else:
		print("Ship count: %d" % count)

	var ids_seen: Array[int] = []
	for ship_data in ships_data:
		ids_seen.append(int(ship_data.get("id", 0)))
	ids_seen.sort()
	if 26 in ids_seen:
		_fail("Ship id 26 should be absent")
	if ids_seen.back() != 28:
		_fail("Max ship id changed: expected 28, got %d" % ids_seen.back())
	for expected_id in range(1, 26):
		if expected_id not in ids_seen:
			_fail("Missing ship id: %d" % expected_id)
	for expected_id in [27, 28]:
		if expected_id not in ids_seen:
			_fail("Missing ship id: %d" % expected_id)


func _validate_ship_contracts(ships_data: Array) -> void:
	var names_seen: Array[String] = []
	var found_decoys := false
	for ship_data in ships_data:
		var ship_id := int(ship_data.get("id", 0))
		var ship_name := String(ship_data.get("name", ""))
		if ship_name.is_empty():
			_fail("Ship %d missing name" % ship_id)
		if ship_name in names_seen:
			_fail("Duplicate ship name: %s" % ship_name)
		names_seen.append(ship_name)

		var category := String(ship_data.get("category", ""))
		if category not in EXPECTED_CATEGORIES:
			_fail("Ship %s has unknown category: %s" % [ship_name, category])

		var carrying_capacity := float(ship_data.get("carrying_capacity_bn_equiv", -1.0))
		if category == "Escort" or category == "Infrastructure":
			if carrying_capacity != 0.0:
				_fail("%s ship %s has non-zero carrying capacity: %s" % [category, ship_name, carrying_capacity])

		var total_count := int(ship_data.get("total_count", -1))
		var initial_ready := int(ship_data.get("initial_ready", -2))
		if initial_ready != total_count:
			_fail("Ship %s initial_ready != total_count (%d != %d)" % [ship_name, initial_ready, total_count])

		if ship_name == "Decoys":
			found_decoys = true
			if not bool(ship_data.get("is_decoy", false)):
				_fail("Decoys must have is_decoy true")
	if not found_decoys:
		_fail("Missing Decoys ship entry")
	print("Ship contract check: %d ships validated" % names_seen.size())


func _validate_fresh_fleet(ships_data: Array) -> void:
	for ship_data in ships_data:
		var ship_state: ShipState = ShipStateResource.new()
		ship_state.ship_type = String(ship_data.get("name", ""))
		ship_state.fleet_total = int(ship_data.get("total_count", 0))
		ship_state.fleet_surviving_total = int(ship_data.get("total_count", 0))
		ship_state.ready = int(ship_data.get("total_count", 0))
		ship_state.sent_original = 0
		ship_state.surviving_sent = 0
		ship_state.offloading = 0
		ship_state.returning = 0
		ship_state.destroyed = 0
		if not ship_state.validate():
			_fail("Fresh fleet state invalid for %s" % ship_state.ship_type)
	print("Fresh fleet invariant check: %d ship states validated" % ships_data.size())


func _fail(message: String) -> void:
	_failures.append(message)
	push_error(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: Ship data validation succeeded")
		quit(0)
		return
	print("FAIL: Ship data validation found %d issue(s):" % _failures.size())
	for failure in _failures:
		print("  - %s" % failure)
	quit(1)
