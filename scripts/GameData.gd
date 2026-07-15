extends Node
class_name GameDataStore

const HexResource = preload("res://scripts/model/Hex.gd")
const BrigadeResource = preload("res://scripts/model/Brigade.gd")
const BattalionResource = preload("res://scripts/model/Battalion.gd")
const BeachDefResource = preload("res://scripts/model/BeachDef.gd")
const InfrastructureDefResource = preload("res://scripts/model/InfrastructureDef.gd")
const ShipDefResource = preload("res://scripts/model/ShipDef.gd")
const TerrainTypeResource = preload("res://scripts/model/TerrainType.gd")

const OOB_PATHS := ["res://data/pla_ground_forces.json", "res://data/roc_ground_forces.json"]
const DEFAULT_SCENARIO_PATH := ScenarioCatalog.DEFAULT_SCENARIO_PATH
const BEACHES_PATH := "res://data/beaches.json"
const INFRASTRUCTURE_PATH := "res://data/infrastructure.json"
const OFFLOAD_WEIGHTS_PATH := "res://data/offload_weights.json"
const THEATERS_PATH := "res://data/theaters.json"
const SHIPS_PATH := "res://data/ships.json"

var scenario_name: String = ""
# Path of the currently loaded scenario (set by load_scenario). GameState.reset_to_scenario
# reloads THIS, not the default, so a process-level scenario selection survives resets.
var scenario_path: String = ""
var turn_length_days: int = 0
var red_dos_start: int = 0
var stacking_soft_cap: int = 0
# Base FEBA shift (km) per combat. Defaults to TIV's configured value (3.5; see
# TaiwanInvasionViewer tests/python/unit/test_boots_attack_mode.py::_load_feba_base_km).
var feba_base_km: float = 3.5
# Combat effectiveness multiplier for Red maneuver units when the Red DOS supply pool is exhausted
# (mirrors TIV's per-unit supply_effectiveness, adapted to HexCombat's single pool; see PLAN.md
# Decisions 2026-06-29 supply→combat). 1.0 while the pool is positive.
var red_out_of_supply_effectiveness: float = 0.5
var victory_config: Dictionary = {}  # scenario 'victory' block (loss_check_arm, taiwan_hexes)

var hexes: Array[Hex] = []
var hex_lookup: Dictionary = {}  # hex_id -> Hex
var terrain_types: Dictionary = {}  # class name -> TerrainType
var coord_lookup: Dictionary = {}  # Vector2i -> hex_id
var neighbor_lookup: Dictionary = {}  # hex_id -> Array[String]
var hex_states: Dictionary = {}  # hex_id -> HexState
var red_ship_reserve: Array = []  # raw scenario dicts: {brigade_id, locked_beach, beach_hex, offset_bearing}
# Follow-on brigades that embark AFTER the first echelon as ready amphibious lift frees up (plan
# 0004). Same entry shape as red_ship_reserve; empty when a scenario has no explicit echelon.
var red_followon_reserve: Array = []
# Opt-in deep-pool auto-seed: when true (and red_followon_reserve is empty) the mainland pool is
# seeded from the OOB (every RED brigade not in the first wave). scenario_default sets it; the golden
# fixture and minimal scenarios leave it false so they stay a one-shot assault.
var auto_seed_followon_pool: bool = false
# Turns a freed amphibious hull spends returning/reloading before it is ready to sail again (plan
# 0004). 0 => hulls re-ready as soon as their cargo is ashore (no cross-turn lift constraint).
var amphibious_return_time_turns: int = 0
# Turns an escort type spends reloading SAMs after its magazine drops below threshold (plan 0004 D5).
# 0 => escort SAM magazine unmodelled (unlimited interception, pre-0004 behavior).
var escort_reload_time_turns: int = 0

var brigades: Dictionary = {}  # brigade_id -> Brigade
var brigades_by_hex: Dictionary = {}  # hex_id -> Array[String]

var beaches: Dictionary = {}  # beach_id (int) -> BeachDef
var infrastructure: Dictionary = {}  # infra_id (String) -> InfrastructureDef
var offload_weights: Dictionary = {}  # parsed data/offload_weights.json (OffloadCostModel config)
# Scenario opt-in (plan 0006): when true the offload phase costs BNs via the offload_weights
# matrix (per-type transport weight x bn_class/ship_category multiplier); false = flat
# TONS_PER_BN (pre-0006 behavior, keeps scenario_golden byte-stable).
var use_offload_weight_matrix: bool = false
# JLSF knobs (plan 0006): auto_jlsf auto-queues a JLSF deployment to every newly seized
# port/airbridge (research default); jlsf_lift_bn_equiv is the abstract lift cost of one
# deployment in BN-equivalents (TIV JLSF_RESERVED_TONS ~= 4 BN heavy brigade).
var auto_jlsf: bool = false
var jlsf_lift_bn_equiv: int = 4
var ship_defs: Dictionary = {}  # id (int) -> ShipDef

var active_tos: Array[int] = []
var to_adjacency: Dictionary = {}  # to_number (int) -> Array[int]
var beach_to_to: Dictionary = {}  # beach_id (int) -> to_number (int)


func _ready() -> void:
	load_all()


# scenario_override: force a specific scenario path, bypassing the --scenario/HEXCOMBAT_SCENARIO
# selection. Used to load a fixed fixture regardless of process selection — e.g. the golden gate
# runs against scenario_golden while a deep-pool coverage check explicitly loads scenario_default.
func load_all(scenario_override: String = "") -> void:
	load_hex_grid()
	load_terrain()
	build_neighbor_lookup()
	load_brigades()
	load_scenario(scenario_override if not scenario_override.is_empty() else ScenarioCatalog.selected_path())
	load_theaters()
	load_beaches()
	load_infrastructure()
	load_offload_weights()
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
		hex_states[hex.id] = HexState.new()

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


# Restore every hex to the HexState defaults (GREEN owner, feba 0) without re-parsing the grid
# JSON. Combat/frontline mutate HexState in place across a play-through, so a reset that skips
# this leaks run 1's ownership/FEBA map into run 2 (surfaced 2026-07-09: in-process replay of
# the 40-turn golden diverged 24/88 -> 25/90 on the second run).
func reset_hex_states() -> void:
	for hex_id in hex_states:
		hex_states[hex_id] = HexState.new()


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
		var to_number_val: Variant = brigade_data.get("to_number")  # PLA brigades store null (at sea)
		brigade.to_number = int(to_number_val) if to_number_val != null else 0
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
	scenario_path = path
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
	feba_base_km = float(scenario.get("feba_base_km", 3.5))
	red_out_of_supply_effectiveness = float(scenario.get("red_out_of_supply_effectiveness", 0.5))
	var victory_value: Variant = scenario.get("victory", {})
	victory_config = victory_value if victory_value is Dictionary else {}
	red_ship_reserve = _parse_ship_reserve_entries(scenario.get("red_ship_reserve", []), "red_ship_reserve")
	red_followon_reserve = _parse_ship_reserve_entries(scenario.get("red_followon_reserve", []), "red_followon_reserve")
	# Opt-in ONLY: when true and no explicit red_followon_reserve is given, the mainland pool
	# auto-seeds from the deep OOB (every RED brigade not in the first wave). Absent/false => no
	# follow-on (the minimal assault laydown, e.g. scenario_golden). See SealiftStateBuilder.
	auto_seed_followon_pool = bool(scenario.get("auto_seed_followon_pool", false))
	amphibious_return_time_turns = maxi(0, int(scenario.get("amphibious_return_time_turns", 0)))
	escort_reload_time_turns = maxi(0, int(scenario.get("escort_reload_time_turns", 0)))
	use_offload_weight_matrix = bool(scenario.get("use_offload_weight_matrix", false))
	auto_jlsf = bool(scenario.get("auto_jlsf", false))
	jlsf_lift_bn_equiv = maxi(1, int(scenario.get("jlsf_lift_bn_equiv", 4)))

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


# Validates + normalizes a ship-reserve-shaped scenario list (first echelon or follow-on pool) and
# returns it; label names the scenario key in error messages. Entries failing validation are skipped
# (fail loud). Shared by red_ship_reserve and red_followon_reserve (plan 0004) — same contract.
func _parse_ship_reserve_entries(entries, label: String) -> Array:
	var parsed: Array = []
	if not (entries is Array):
		push_error("Scenario %s must be an Array" % label)
		return parsed

	for entry_value in entries:
		if not (entry_value is Dictionary):
			push_error("Scenario %s entry must be a Dictionary" % label)
			continue
		var entry: Dictionary = entry_value
		var brigade_id := String(entry.get("brigade_id", ""))
		if brigade_id == "":
			push_error("Scenario %s entry missing brigade_id" % label)
			continue
		var brigade: Brigade = get_brigade(brigade_id)
		if brigade == null:
			push_error("Scenario %s references unknown brigade_id: %s" % [label, brigade_id])
			continue
		if brigade.team != Brigade.Team.RED:
			push_error("Scenario %s references non-Red brigade_id: %s" % [label, brigade_id])
			continue
		var beach_hex := String(entry.get("beach_hex", ""))
		if beach_hex not in hex_lookup:
			push_error("Scenario %s references unknown beach_hex: %s" % [label, beach_hex])
			continue
		parsed.append({
			"brigade_id": brigade_id,
			"locked_beach": int(entry.get("locked_beach", 0)),
			"beach_hex": beach_hex,
			"offset_bearing": float(entry.get("offset_bearing", 0.0))
		})
	return parsed


func load_terrain() -> void:
	terrain_types.clear()

	var types_json = _read_json("res://data/terrain/terrain_types.json")
	if types_json == null or not (types_json is Dictionary):
		push_error("terrain_types.json format not recognized")
		return
	var types_data = types_json.get("types", null)
	if not (types_data is Dictionary):
		push_error("terrain_types.json missing 'types' key")
		return

	for class_name_key in types_data.keys():
		var data: Dictionary = types_data[class_name_key]
		if not (data is Dictionary):
			push_error("terrain_types.json types.%s: expected Dictionary" % class_name_key)
			return
		if not data.has("defender_modifier"):
			push_error("terrain_types.json types.%s missing defender_modifier" % class_name_key)
			return
		if not data.has("move_cost"):
			push_error("terrain_types.json types.%s missing move_cost" % class_name_key)
			return
		if not data.has("impassable"):
			push_error("terrain_types.json types.%s missing impassable" % class_name_key)
			return
		if not data.has("color"):
			push_error("terrain_types.json types.%s missing color" % class_name_key)
			return
		var t: TerrainType = TerrainTypeResource.new()
		t.name = class_name_key
		t.defender_modifier = float(data.get("defender_modifier", 1.0))
		t.move_cost = int(data.get("move_cost", 1))
		t.impassable = bool(data.get("impassable", false))
		t.color = String(data.get("color", ""))
		terrain_types[class_name_key] = t

	var hex_json = _read_json("res://data/terrain/hex_terrain.json")
	if hex_json == null or not (hex_json is Dictionary):
		push_error("hex_terrain.json format not recognized")
		return
	var class_map = hex_json.get("classes", {})
	if not (class_map is Dictionary):
		push_error("hex_terrain.json missing classes key")
		return

	var missing_count := 0
	for hex_id in hex_lookup.keys():
		if hex_id in class_map:
			var terrain_class := String(class_map[hex_id])
			if terrain_class not in terrain_types:
				push_error("hex_terrain.json: hex %s references unknown terrain class '%s'" % [hex_id, terrain_class])
				return
			hex_lookup[hex_id].terrain = terrain_class
		else:
			missing_count += 1

	if missing_count > 0:
		push_error("hex_terrain.json: %d hexes in grid have no terrain class" % missing_count)
		return

	for hex_id in class_map.keys():
		if hex_id not in hex_lookup:
			push_error("hex_terrain.json references unknown hex_id: %s" % hex_id)
			return

	print_debug("Loaded %d terrain types, %d classified hexes" % [terrain_types.size(), hex_lookup.size()])


func get_terrain(hex_id: String) -> TerrainType:
	if hex_id not in hex_lookup:
		return null
	return terrain_types.get(hex_lookup[hex_id].terrain, null)


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
	return HexMath.find_path(start_id, goal_id, Callable(self, "get_neighbors"), _with_impassable(blocked), Callable(self, "_terrain_entry_cost"))


func find_reachable(start_id: String, max_distance: int, blocked: Array = []) -> Array:
	if start_id not in hex_lookup:
		return []
	return HexMath.find_reachable(start_id, max_distance, Callable(self, "get_neighbors"), _with_impassable(blocked), Callable(self, "_terrain_entry_cost"))


# Merges the caller-supplied blocked list with every hex whose terrain is impassable (mountains
# today). Ground movement must never select an impassable hex as a destination or waypoint.
func _with_impassable(blocked: Array) -> Array:
	var merged: Array = blocked.duplicate()
	for hex_id in hex_lookup.keys():
		var terrain := get_terrain(hex_id)
		if terrain != null and terrain.impassable and hex_id not in merged:
			merged.append(hex_id)
	return merged


# Movement-point cost to ENTER hex_id, per its TerrainType.move_cost. Missing/unclassified
# terrain costs 1 (fail-loud-adjacent: load_terrain already errors on unclassified hexes, so this
# fallback only guards call sites that run before terrain finishes loading).
func _terrain_entry_cost(hex_id) -> int:
	var terrain := get_terrain(String(hex_id))
	if terrain == null:
		return 1
	return terrain.move_cost


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
			hex_states[hex_id].owner = HexOwner.CONTESTED
		elif has_red:
			hex_states[hex_id].owner = HexOwner.RED
		elif has_green:
			hex_states[hex_id].owner = HexOwner.GREEN


func set_hex_owner(hex_id: String, owner: String) -> void:
	if hex_id in hex_states:
		hex_states[hex_id].owner = owner


func set_hex_feba(hex_id: String, feba_km: float) -> void:
	if hex_id in hex_states:
		hex_states[hex_id].feba_km = feba_km


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
		beach.hex_id = String(beach_data.get("hex_id", ""))
		beach.category = String(beach_data.get("category", ""))
		beach.to_number = int(beach_data.get("to_number", 0))
		beach.offload_rate = float(beach_data.get("offload_rate", 0.0))
		beach.capacity_battalions = int(beach_data.get("capacity_battalions", 0))
		beach.depth = int(beach_data.get("depth", 2))
		beach.floating_piers = int(beach_data.get("floating_piers", 0))
		beach.jackup_barge = int(beach_data.get("jackup_barge", 0))
		beach.advance_direction = float(beach_data.get("advance_direction", 0.0))
		beach.lat = float(beach_data.get("lat", 0.0))
		beach.lng = float(beach_data.get("lng", 0.0))
		if beach.id == 0:
			push_error("Beach entry missing id field")
			continue
		if beach.hex_id == "" or beach.hex_id not in hex_lookup:
			push_error("beaches.json beach %d hex_id '%s' missing or not in grid" % [beach.id, beach.hex_id])
			continue
		beaches[beach.id] = beach
	print_debug("Loaded %d beaches" % beaches.size())


func get_beach(beach_id: int) -> BeachDef:
	return beaches.get(beach_id, null)


func load_infrastructure() -> void:
	infrastructure.clear()
	var json = _read_json(INFRASTRUCTURE_PATH)
	if json == null or not (json is Dictionary):
		push_error("infrastructure.json format not recognized: expected Dictionary")
		return
	var infra_data = json.get("infrastructure", null)
	if not (infra_data is Array):
		push_error("infrastructure.json missing infrastructure array")
		return
	for entry_data in infra_data:
		var entry: InfrastructureDef = InfrastructureDefResource.new()
		entry.id = String(entry_data.get("id", ""))
		entry.kind = String(entry_data.get("kind", ""))
		entry.name = String(entry_data.get("name", ""))
		entry.hex_id = String(entry_data.get("hex_id", ""))
		entry.to_number = int(entry_data.get("to_number", 0))
		entry.lat = float(entry_data.get("lat", 0.0))
		entry.lng = float(entry_data.get("lng", 0.0))
		if entry.id.is_empty():
			push_error("Infrastructure entry missing id field")
			continue
		if entry.kind != "port" and entry.kind != "airbridge":
			push_error("infrastructure.json entry '%s' has unknown kind '%s'" % [entry.id, entry.kind])
			continue
		if entry.hex_id == "" or entry.hex_id not in hex_lookup:
			push_error("infrastructure.json entry '%s' hex_id '%s' missing or not in grid" % [entry.id, entry.hex_id])
			continue
		infrastructure[entry.id] = entry
	print_debug("Loaded %d infrastructure nodes" % infrastructure.size())


func get_infrastructure(infra_id: String) -> InfrastructureDef:
	return infrastructure.get(infra_id, null)


func load_offload_weights() -> void:
	offload_weights = {}
	var json = _read_json(OFFLOAD_WEIGHTS_PATH)
	if json == null or not (json is Dictionary):
		push_error("offload_weights.json format not recognized: expected Dictionary")
		return
	offload_weights = json
	print_debug("Loaded offload weights (%d types)" % (offload_weights.get("weights", {}) as Dictionary).size())


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
		ship_def.mine_neutralization_likelihood = String(ship_data.get("mine_neutralization_likelihood", ""))
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


## Read-only consistency check: verifies cross-references between the `brigades`
## and `brigades_by_hex` indexes are correct. Returns a list of human-readable
## violation strings (empty Array = healthy). Intended for debug asserts / the
## headless validation gate, NOT the per-frame hot path.
func validate_runtime_indexes() -> Array[String]:
	var violations: Array[String] = []

	# A — Forward: every placed brigade is listed in its hex bucket.
	for b in brigades.values():
		var brigade: Brigade = b
		if brigade.hex_id == "":
			continue
		var bucket: Array = brigades_by_hex.get(brigade.hex_id, [])
		if brigade.id not in bucket:
			violations.append("brigade %s at hex %s missing from brigades_by_hex" % [brigade.id, brigade.hex_id])

	# B — Reverse: every bucket entry references an existing brigade whose hex_id
	# matches, with no duplicates.
	for hex_id in brigades_by_hex.keys():
		var seen := {}
		for id_value in brigades_by_hex[hex_id]:
			var id := String(id_value)
			if seen.has(id):
				violations.append("brigade %s listed twice in brigades_by_hex[%s]" % [id, hex_id])
				continue
			seen[id] = true
			var b: Brigade = get_brigade(id)
			if b == null:
				violations.append("brigades_by_hex[%s] references unknown brigade %s" % [hex_id, id])
			elif b.hex_id != hex_id:
				violations.append("brigade %s in bucket %s but its hex_id is %s" % [id, hex_id, b.hex_id])

	return violations


## Deterministic, key-sorted state snapshot for golden-test / AI byte-comparison.
## Returns a plain Dictionary with brigade positions/status and hex ownership.
func snapshot_state() -> Dictionary:
	var brigade_snap := {}
	var bids := brigades.keys()
	bids.sort()
	for bid in bids:
		var b: Brigade = brigades[bid]
		brigade_snap[bid] = {
			"hex_id": b.hex_id,
			"battalions": b.get_battalion_count(),
			"destroyed": b.destroyed,
			"team": int(b.team)
		}
	var hex_snap := {}
	var hids := hex_states.keys()
	hids.sort()
	for hid in hids:
		hex_snap[hid] = hex_states[hid].to_dict()
	return {"brigades": brigade_snap, "hexes": hex_snap}


func _read_json(path: String):
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not open %s" % path)
		return null

	var json = JSON.parse_string(file.get_as_text())
	if json == null:
		push_error("JSON parsing failed for %s" % path)
	return json
