extends Node
class_name GameDataStore

const HexResource = preload("res://scripts/model/Hex.gd")
const BrigadeResource = preload("res://scripts/model/Brigade.gd")
const BattalionResource = preload("res://scripts/model/Battalion.gd")
const BeachDefResource = preload("res://scripts/model/BeachDef.gd")
const ShipDefResource = preload("res://scripts/model/ShipDef.gd")

const OOB_PATHS := ["res://data/pla_ground_forces.json", "res://data/roc_ground_forces.json"]
const DEFAULT_SCENARIO_PATH := "res://data/scenario_default.json"
const BEACHES_PATH := "res://data/beaches.json"
const THEATERS_PATH := "res://data/theaters.json"
const SHIPS_PATH := "res://data/ships.json"

var scenario_name: String = ""
var turn_length_days: int = 0
var red_dos_start: int = 0
var stacking_soft_cap: int = 0

var hexes: Array[Hex] = []
var hex_lookup: Dictionary = {}  # hex_id -> Hex
var coord_lookup: Dictionary = {}  # Vector2i -> hex_id
var neighbor_lookup: Dictionary = {}  # hex_id -> Array[String]
var hex_states: Dictionary = {}  # hex_id -> {owner, feba_km}
var red_ship_reserve: Array = []  # raw scenario dicts: {brigade_id, locked_beach, beach_hex, offset_bearing}

var brigades: Dictionary = {}  # brigade_id -> Brigade
var brigades_by_hex: Dictionary = {}  # hex_id -> Array[String]

var beaches: Dictionary = {}  # beach_id (int) -> BeachDef
var ship_defs: Dictionary = {}  # id (int) -> ShipDef

var active_tos: Array[int] = []
var to_adjacency: Dictionary = {}  # to_number (int) -> Array[int]
var beach_to_to: Dictionary = {}  # beach_id (int) -> to_number (int)


func _ready() -> void:
	load_all()


func load_all() -> void:
	load_hex_grid()
	build_neighbor_lookup()
	load_brigades()
	load_scenario(DEFAULT_SCENARIO_PATH)
	load_theaters()
	load_beaches()
	load_ships()
	print_debug("GameData ready: %d hexes, %d brigades, %d beaches, %d TOs, %d ship types" % [hexes.size(), brigades.size(), beaches.size(), active_tos.size(), ship_defs.size()])


func load_hex_grid() -> void:
	hexes.clear()
	hex_lookup.clear()
	coord_lookup.clear()
	hex_states.clear()

	var json = _read_json("res://data/taiwan_hex_grid.json")
	if json == null:
		return

	var hexes_data: Array = []
	if json is Array:
		hexes_data = json
	elif json is Dictionary and "hexes" in json:
		hexes_data = json["hexes"]
	else:
		push_error("taiwan_hex_grid.json format not recognized")
		return

	for hex_data in hexes_data:
		var hex: Hex = HexResource.new()
		hex.id = hex_data.get("id", "")
		hex.row = int(hex_data.get("row", 0))
		hex.col = int(hex_data.get("col", 0))
		hex.coord = Vector2i(hex.row, hex.col)

		var center_data: Dictionary = hex_data.get("center", {})
		hex.center = Vector2(float(center_data.get("lat", 0.0)), float(center_data.get("lon", 0.0)))

		var vertices := PackedVector2Array()
		for vertex_data in hex_data.get("vertices", []):
			vertices.append(Vector2(float(vertex_data.get("lat", 0.0)), float(vertex_data.get("lon", 0.0))))
		hex.vertices = vertices

		if hex.id == "":
			continue
		hexes.append(hex)
		hex_lookup[hex.id] = hex
		coord_lookup[hex.coord] = hex.id
		hex_states[hex.id] = {
			"owner": HexOwner.GREEN,
			"feba_km": 0.0
		}

	print_debug("Loaded %d hexes" % hexes.size())


func build_neighbor_lookup() -> void:
	neighbor_lookup.clear()
	for hex in hexes:
		var neighbors: Array[String] = []
		for coord in HexMath.neighbor_coords(hex.coord):
			if coord in coord_lookup:
				neighbors.append(coord_lookup[coord])
		neighbor_lookup[hex.id] = neighbors
	print_debug("Built neighbor lookup for %d hexes" % neighbor_lookup.size())


func load_brigades() -> void:
	brigades.clear()
	brigades_by_hex.clear()

	for path in OOB_PATHS:
		_load_oob_file(path)

	print_debug("Loaded %d brigades" % brigades.size())


func _load_oob_file(path: String) -> void:
	var json = _read_json(path)
	if json == null or not (json is Dictionary):
		push_error("%s format not recognized: expected Dictionary with brigades array" % path)
		return

	var brigades_data = json.get("brigades", null)
	if not (brigades_data is Array):
		push_error("%s format not recognized: expected Dictionary with brigades array" % path)
		return

	for brigade_data in brigades_data:
		var brigade_id := String(brigade_data.get("brigade_id", ""))
		if brigade_id == "":
			push_warning("Skipping brigade with missing brigade_id")
			continue

		var brigade: Brigade = BrigadeResource.new()
		brigade.id = brigade_id
		brigade.name = brigade_data.get("name", "")
		brigade.team = _parse_team(brigade_data.get("team", "Red"))
		brigade.nato_type = brigade_data.get("nato_type", "")
		brigade.hex_id = String(brigade_data.get("hex_id", ""))

		for battalion_data in brigade_data.get("composition", []):
			var battalion: Battalion = BattalionResource.new()
			battalion.type = battalion_data.get("type", "")
			battalion.qty = int(battalion_data.get("qty", 0))
			if battalion.type != "" and battalion.qty > 0:
				brigade.composition.append(battalion)

		brigades[brigade.id] = brigade
		if brigade.hex_id != "":
			_add_brigade_to_hex(brigade.id, brigade.hex_id)


func load_scenario(path: String) -> void:
	var json = _read_json(path)
	if json == null:
		push_error("Could not load scenario %s" % path)
		return
	if not (json is Dictionary):
		push_error("%s format not recognized: expected Dictionary with placements array" % path)
		return

	var scenario: Dictionary = json
	var placements = scenario.get("placements", null)
	if not (placements is Array):
		push_error("%s format not recognized: expected Dictionary with placements array" % path)
		return

	scenario_name = String(scenario.get("name", ""))
	turn_length_days = int(scenario.get("turn_length_days", 0))
	red_dos_start = int(scenario.get("red_dos_start", 0))
	if red_dos_start <= 0:
		push_warning("Scenario red_dos_start is <= 0; Red DOS supply pool will start empty")
	stacking_soft_cap = int(scenario.get("stacking_soft_cap", 0))
	_parse_red_ship_reserve(scenario.get("red_ship_reserve", []))

	var count := 0
	for placement in placements:
		var brigade_id := String(placement.get("brigade_id", ""))
		var brigade: Brigade = get_brigade(brigade_id)
		if brigade == null:
			push_error("Scenario placement references unknown brigade_id: %s" % brigade_id)
			continue

		var placement_team := _parse_team(String(placement.get("team", "")))
		if placement_team != brigade.team:
			push_error("Scenario placement team mismatch for %s: placement=%s OOB=%s" % [brigade_id, String(placement.get("team", "")), _team_to_string(brigade.team)])

		set_brigade_hex(brigade_id, String(placement.get("hex", "")))
		brigade.entry_bearing = float(placement.get("offset_bearing", 0.0))
		count += 1

	print_debug("Loaded scenario '%s': %d placements" % [scenario_name, count])


func _parse_red_ship_reserve(entries) -> void:
	red_ship_reserve.clear()
	if not (entries is Array):
		push_error("Scenario red_ship_reserve must be an Array")
		return

	for entry_value in entries:
		if not (entry_value is Dictionary):
			push_error("Scenario red_ship_reserve entry must be a Dictionary")
			continue
		var entry: Dictionary = entry_value
		var brigade_id := String(entry.get("brigade_id", ""))
		if brigade_id == "":
			push_error("Scenario red_ship_reserve entry missing brigade_id")
			continue
		var brigade: Brigade = get_brigade(brigade_id)
		if brigade == null:
			push_error("Scenario red_ship_reserve references unknown brigade_id: %s" % brigade_id)
			continue
		if brigade.team != Brigade.Team.RED:
			push_error("Scenario red_ship_reserve references non-Red brigade_id: %s" % brigade_id)
			continue
		var beach_hex := String(entry.get("beach_hex", ""))
		if beach_hex not in hex_lookup:
			push_error("Scenario red_ship_reserve references unknown beach_hex: %s" % beach_hex)
			continue
		red_ship_reserve.append({
			"brigade_id": brigade_id,
			"locked_beach": int(entry.get("locked_beach", 0)),
			"beach_hex": beach_hex,
			"offset_bearing": float(entry.get("offset_bearing", 0.0))
		})


func get_hex(hex_id: String) -> Hex:
	return hex_lookup.get(hex_id, null)


func get_neighbors(hex_id: String) -> Array:
	return neighbor_lookup.get(hex_id, [])


func get_distance(hex_id_a: String, hex_id_b: String) -> int:
	var hex_a: Hex = get_hex(hex_id_a)
	var hex_b: Hex = get_hex(hex_id_b)
	if hex_a == null or hex_b == null:
		return -1
	return HexMath.distance(hex_a.coord, hex_b.coord)


func find_path(start_id: String, goal_id: String, blocked: Array = []) -> Array:
	if start_id not in hex_lookup or goal_id not in hex_lookup:
		return []
	return HexMath.find_path(start_id, goal_id, Callable(self, "get_neighbors"), blocked)


func find_reachable(start_id: String, max_distance: int, blocked: Array = []) -> Array:
	if start_id not in hex_lookup:
		return []
	return HexMath.find_reachable(start_id, max_distance, Callable(self, "get_neighbors"), blocked)


func get_brigade(brigade_id: String) -> Brigade:
	return brigades.get(brigade_id, null)


func get_brigades_in_hex(hex_id: String) -> Array:
	return brigades_by_hex.get(hex_id, [])


func set_brigade_hex(brigade_id: String, hex_id: String) -> void:
	var brigade: Brigade = get_brigade(brigade_id)
	if brigade == null:
		return

	var old_hex := brigade.hex_id
	brigade.hex_id = hex_id
	if old_hex != "" and old_hex in brigades_by_hex:
		brigades_by_hex[old_hex] = brigades_by_hex[old_hex].filter(func(id): return id != brigade_id)
	if hex_id != "":
		_add_brigade_to_hex(brigade_id, hex_id)


func remove_brigade_from_map(brigade_id: String) -> void:
	set_brigade_hex(brigade_id, "")


func recompute_hex_ownership() -> void:
	for hex_id_value in hex_lookup.keys():
		var hex_id := String(hex_id_value)
		var has_red := false
		var has_green := false
		for brigade_id_value in get_brigades_in_hex(hex_id):
			var brigade: Brigade = get_brigade(String(brigade_id_value))
			if brigade == null or brigade.destroyed:
				continue
			match brigade.team:
				Brigade.Team.RED:
					has_red = true
				Brigade.Team.GREEN:
					has_green = true
		if has_red and has_green:
			hex_states[hex_id]["owner"] = HexOwner.CONTESTED
		elif has_red:
			hex_states[hex_id]["owner"] = HexOwner.RED
		elif has_green:
			hex_states[hex_id]["owner"] = HexOwner.GREEN


func set_hex_owner(hex_id: String, owner: String) -> void:
	if hex_id in hex_states:
		hex_states[hex_id]["owner"] = owner


func set_hex_feba(hex_id: String, feba_km: float) -> void:
	if hex_id in hex_states:
		hex_states[hex_id]["feba_km"] = feba_km


func get_unit_count_in_hex(hex_id: String, team: Brigade.Team = Brigade.Team.RED) -> int:
	var total := 0
	for brigade_id in get_brigades_in_hex(hex_id):
		var brigade: Brigade = get_brigade(brigade_id)
		if brigade != null and brigade.team == team:
			total += brigade.get_battalion_count()
	return total


func load_theaters() -> void:
	active_tos.clear()
	to_adjacency.clear()
	beach_to_to.clear()

	var json = _read_json(THEATERS_PATH)
	if json == null or not (json is Dictionary):
		push_error("theaters.json format not recognized: expected Dictionary")
		return

	var active_tos_data = json.get("active_tos", null)
	if not (active_tos_data is Array):
		push_error("theaters.json missing active_tos array")
		return
	for to_value in active_tos_data:
		active_tos.append(int(to_value))

	var adjacency_data = json.get("to_adjacency", null)
	if not (adjacency_data is Dictionary):
		push_error("theaters.json missing to_adjacency object")
		return
	for to_key in adjacency_data.keys():
		var to_number := int(String(to_key))
		var neighbors_data = adjacency_data[to_key]
		if not (neighbors_data is Array):
			push_error("theaters.json to_adjacency[%d] must be an Array" % to_number)
			continue
		var neighbors: Array[int] = []
		for neighbor_value in neighbors_data:
			neighbors.append(int(neighbor_value))
		to_adjacency[to_number] = neighbors

	var beach_to_to_data = json.get("beach_to_to", null)
	if not (beach_to_to_data is Dictionary):
		push_error("theaters.json missing beach_to_to object")
		return
	for beach_key in beach_to_to_data.keys():
		beach_to_to[int(String(beach_key))] = int(beach_to_to_data[beach_key])

	print_debug("Loaded %d active TOs" % active_tos.size())


func load_beaches() -> void:
	beaches.clear()
	var json = _read_json(BEACHES_PATH)
	if json == null or not (json is Dictionary):
		push_error("beaches.json format not recognized: expected Dictionary")
		return
	var beaches_data = json.get("beaches", null)
	if not (beaches_data is Array):
		push_error("beaches.json missing beaches array")
		return
	for beach_data in beaches_data:
		var beach: BeachDef = BeachDefResource.new()
		beach.id = int(beach_data.get("id", 0))
		beach.name_en = String(beach_data.get("name_en", ""))
		beach.category = String(beach_data.get("category", ""))
		beach.to_number = int(beach_data.get("to_number", 0))
		beach.offload_rate = float(beach_data.get("offload_rate", 0.0))
		beach.capacity_battalions = int(beach_data.get("capacity_battalions", 0))
		beach.floating_piers = int(beach_data.get("floating_piers", 0))
		beach.jackup_barge = int(beach_data.get("jackup_barge", 0))
		beach.advance_direction = float(beach_data.get("advance_direction", 0.0))
		beach.lat = float(beach_data.get("lat", 0.0))
		beach.lng = float(beach_data.get("lng", 0.0))
		if beach.id == 0:
			push_error("Beach entry missing id field")
			continue
		beaches[beach.id] = beach
	print_debug("Loaded %d beaches" % beaches.size())


func get_beach(beach_id: int) -> BeachDef:
	return beaches.get(beach_id, null)


func load_ships() -> void:
	ship_defs.clear()
	var json = _read_json(SHIPS_PATH)
	if json == null or not (json is Dictionary):
		push_error("ships.json format not recognized: expected Dictionary")
		return
	var ships_data = json.get("ships", null)
	if not (ships_data is Array):
		push_error("ships.json missing ships array")
		return
	var categories_data = json.get("categories", null)
	if not (categories_data is Dictionary):
		push_error("ships.json missing categories object")
		return
	for ship_data_value in ships_data:
		if not (ship_data_value is Dictionary):
			push_error("ships.json ship entry must be a Dictionary")
			continue
		var ship_data: Dictionary = ship_data_value
		var ship_def: ShipDef = ShipDefResource.new()
		ship_def.id = int(ship_data.get("id", 0))
		ship_def.name = String(ship_data.get("name", ""))
		ship_def.display_name = String(ship_data.get("display_name", ""))
		ship_def.category = String(ship_data.get("category", ""))
		ship_def.infrastructure = bool(ship_data.get("infrastructure", false))
		ship_def.total_count = int(ship_data.get("total_count", 0))
		ship_def.initial_ready = int(ship_data.get("initial_ready", 0))
		ship_def.carrying_capacity_bn_equiv = float(ship_data.get("carrying_capacity_bn_equiv", 0.0))
		ship_def.is_decoy = bool(ship_data.get("is_decoy", false))
		ship_def.setup_group = String(ship_data.get("setup_group", ""))
		if ship_def.id == 0:
			push_error("Ship entry missing id field")
			continue
		if ship_def.name.is_empty():
			push_error("Ship %d missing name" % ship_def.id)
		if ship_def.category not in categories_data:
			push_error("Ship %d has unknown category: %s" % [ship_def.id, ship_def.category])
		if ship_def.initial_ready != ship_def.total_count:
			push_error("Ship %s initial_ready must equal total_count" % ship_def.name)
		ship_defs[ship_def.id] = ship_def
	print_debug("Loaded %d ship types" % ship_defs.size())


func get_ship_def(ship_id: int) -> ShipDef:
	return ship_defs.get(ship_id, null)


func _add_brigade_to_hex(brigade_id: String, hex_id: String) -> void:
	if hex_id not in brigades_by_hex:
		brigades_by_hex[hex_id] = []
	if brigade_id not in brigades_by_hex[hex_id]:
		brigades_by_hex[hex_id].append(brigade_id)


func _parse_team(team_value: String) -> Brigade.Team:
	match team_value.to_lower():
		"green":
			return Brigade.Team.GREEN
		_:
			return Brigade.Team.RED


func _team_to_string(team: Brigade.Team) -> String:
	match team:
		Brigade.Team.GREEN:
			return "Green"
		_:
			return "Red"


func _read_json(path: String):
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not open %s" % path)
		return null

	var json = JSON.parse_string(file.get_as_text())
	if json == null:
		push_error("JSON parsing failed for %s" % path)
	return json
