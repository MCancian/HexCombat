extends Node
class_name GameDataStore

const HexResource = preload("res://scripts/model/Hex.gd")
const BrigadeResource = preload("res://scripts/model/Brigade.gd")
const BattalionResource = preload("res://scripts/model/Battalion.gd")

var hexes: Array[Hex] = []
var hex_lookup: Dictionary = {}  # hex_id -> Hex
var coord_lookup: Dictionary = {}  # Vector2i -> hex_id
var neighbor_lookup: Dictionary = {}  # hex_id -> Array[String]
var hex_states: Dictionary = {}  # hex_id -> {owner, feba_km}

var brigades: Dictionary = {}  # brigade_id -> Brigade
var brigades_by_hex: Dictionary = {}  # hex_id -> Array[String]


func _ready() -> void:
	load_all()


func load_all() -> void:
	load_hex_grid()
	build_neighbor_lookup()
	load_brigades()
	print_debug("GameData ready: %d hexes, %d brigades" % [hexes.size(), brigades.size()])


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

		var center_data := hex_data.get("center", {})
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
			"owner": "green",
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

	var json = _read_json("res://data/pla_ground_forces.json")
	if json == null or not (json is Dictionary):
		return

	for brigade_data in json.get("brigades", []):
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

	print_debug("Loaded %d brigades" % brigades.size())


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


func _read_json(path: String):
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not open %s" % path)
		return null

	var json = JSON.parse_string(file.get_as_text())
	if json == null:
		push_error("JSON parsing failed for %s" % path)
	return json
