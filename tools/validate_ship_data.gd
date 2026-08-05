# Run from the project root:
# C:\Godot_v4.7-stable_win64.exe --headless --path C:\Users\mdogg\Desktop\HexCombat -s res://tools/validate_ship_data.gd
extends SceneTree

const SHIPS_PATH := "res://data/ships.json"
const EXPECTED_SHIP_COUNT := 27
const EXPECTED_CATEGORIES := ["Escort", "Military_Amphibious", "Civilian_Amphibious", "Civilian_Non_Amphibious", "Infrastructure"]

const ShipDefResource = preload("res://scripts/model/ShipDef.gd")
const FleetBuilderScript = preload("res://scripts/builders/FleetBuilder.gd")

var _h := ValidatorHarness.new("Ship data validation")


func _initialize() -> void:
	print("=== Ship data validation ===")
	var json: Variant = _read_json(SHIPS_PATH)
	if json == null:
		_h.finish(self)
		return

	var ships_data: Array = json.get("ships", [])
	_validate_count_and_ids(ships_data)
	_validate_ship_contracts(ships_data)
	_validate_fresh_fleet(ships_data)
	_h.finish(self)


func _read_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_h.fail("Could not open %s" % path)
		return null
	var parsed = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		_h.fail("%s did not parse to a Dictionary" % path)
		return null
	return parsed


func _validate_count_and_ids(ships_data: Array) -> void:
	var count := ships_data.size()
	if count != EXPECTED_SHIP_COUNT:
		_h.fail("Ship count changed: expected %d, got %d" % [EXPECTED_SHIP_COUNT, count])
	else:
		print("Ship count: %d" % count)

	var ids_seen: Array[int] = []
	for ship_data in ships_data:
		ids_seen.append(int(ship_data.get("id", 0)))
	ids_seen.sort()
	if 26 in ids_seen:
		_h.fail("Ship id 26 should be absent")
	if ids_seen.back() != 28:
		_h.fail("Max ship id changed: expected 28, got %d" % ids_seen.back())
	for expected_id in range(1, 26):
		if expected_id not in ids_seen:
			_h.fail("Missing ship id: %d" % expected_id)
	for expected_id in [27, 28]:
		if expected_id not in ids_seen:
			_h.fail("Missing ship id: %d" % expected_id)


func _validate_ship_contracts(ships_data: Array) -> void:
	var names_seen: Array[String] = []
	var found_decoys := false
	for ship_data in ships_data:
		var ship_id := int(ship_data.get("id", 0))
		var ship_name := String(ship_data.get("name", ""))
		if ship_name.is_empty():
			_h.fail("Ship %d missing name" % ship_id)
		if ship_name in names_seen:
			_h.fail("Duplicate ship name: %s" % ship_name)
		names_seen.append(ship_name)

		var category := String(ship_data.get("category", ""))
		if category not in EXPECTED_CATEGORIES:
			_h.fail("Ship %s has unknown category: %s" % [ship_name, category])

		var carrying_capacity := float(ship_data.get("carrying_capacity_bn_equiv", -1.0))
		if category == "Escort" or category == "Infrastructure":
			if carrying_capacity != 0.0:
				_h.fail("%s ship %s has non-zero carrying capacity: %s" % [category, ship_name, carrying_capacity])

		var total_count := int(ship_data.get("total_count", -1))
		var initial_ready := int(ship_data.get("initial_ready", -2))
		if initial_ready != total_count:
			_h.fail("Ship %s initial_ready != total_count (%d != %d)" % [ship_name, initial_ready, total_count])

		if ship_name == "Decoys":
			found_decoys = true
			if not bool(ship_data.get("is_decoy", false)):
				_h.fail("Decoys must have is_decoy true")
	if not found_decoys:
		_h.fail("Missing Decoys ship entry")
	print("Ship contract check: %d ships validated" % names_seen.size())


## The fresh-fleet invariant is proven against the REAL builder rather than a hand-rolled copy of its
## arithmetic. FleetBuilder is the registered construction writer for ShipState (plan 0045); a second
## copy of the bin arithmetic here could pass while the builder itself was wrong, which is the failure
## mode this check exists to catch. FleetBuilder asserts each fresh row, so genuinely invalid data
## aborts with the ship named instead of reaching the report below.
func _validate_fresh_fleet(ships_data: Array) -> void:
	var ship_defs: Dictionary = {}
	for ship_data in ships_data:
		var ship_def: ShipDef = ShipDefResource.new()
		ship_def.name = String(ship_data.get("name", ""))
		ship_def.total_count = int(ship_data.get("total_count", 0))
		ship_defs[ship_def.name] = ship_def
	if ship_defs.size() != ships_data.size():
		_h.fail("Ship names are not unique: %d rows collapsed to %d fleet entries" % [
			ships_data.size(), ship_defs.size()])
	var fleet: Dictionary = FleetBuilderScript.build(ship_defs)
	for ship_type in fleet.keys():
		var ship_state: ShipState = fleet[ship_type]
		if not ship_state.validate():
			_h.fail("Fresh fleet state invalid for %s" % ship_state.ship_type)
	print("Fresh fleet invariant check: %d ship states validated" % fleet.size())


