class_name AntishipLoaders
extends RefCounted

## Loaders for the D3 anti-ship / mine-warfare data layer (data/antiship/*.json, ported verbatim
## from TIV defaults). Pure static funcs, fail-loud on missing files/keys (per AGENTS.md). The
## combat catalog / crossing config / magazine defaults are returned as Dictionaries (consumed by
## the D3-B calculator); systems and minefields expand into typed Resources.

const AntishipSystemResource = preload("res://scripts/model/AntishipSystem.gd")
const MinefieldResource = preload("res://scripts/model/Minefield.gd")


## type_id -> {name, detectability, deprecated, special} from antiship_systems_consolidated.json.
static func load_system_types(path: String) -> Dictionary:
	var body: Dictionary = _read_json(path)
	var types: Dictionary = {}
	for entry_value in body.get("systems", []):
		var entry: Dictionary = entry_value
		types[int(entry["id"])] = {
			"name": String(entry.get("name", "")),
			"detectability": String(entry.get("detectability", "")),
			"deprecated": bool(entry.get("deprecated", false)),
			"special": String(entry.get("special", "")),
		}
	return types


## Expand antiship_grouping_spec.json platform groups into AntishipSystem rows aggregated by
## (to_number, type_id). group_sizes[] and to_assignments[] are index-aligned; the same (type, TO)
## may appear across multiple group entries (e.g. aircraft) and is summed.
static func load_systems(grouping_path: String, types: Dictionary) -> Array[AntishipSystem]:
	var body: Dictionary = _read_json(grouping_path)
	# Mines-only baseline (plan 0012): an override can zero out the crossing interceptors so the
	# only D3 attrition source left is the minefields. Containers are untouched — the IJFS target
	# set stays real. Optional key; absent = false is the one documented default.
	if bool(body.get("disable_antiship_systems", false)):
		var no_systems: Array[AntishipSystem] = []
		return no_systems
	var groups: Dictionary = body.get("taiwan_platform_groups", {})
	# key "<to>:<type_id>" -> aggregate dict
	var aggregated: Dictionary = {}
	var order: Array = []
	for group_name in groups.keys():
		var group: Dictionary = groups[group_name]
		var type_id := int(group["type_id"])
		var sizes: Array = group.get("group_sizes", [])
		var tos: Array = group.get("to_assignments", [])
		if sizes.size() != tos.size():
			_fail("Anti-ship group '%s' has mismatched group_sizes (%d) / to_assignments (%d)" % [group_name, sizes.size(), tos.size()])
		var ijfs_profile: Dictionary = group.get("ijfs_profile", {})
		var detectability := String(group.get("mainline_detectability", ""))
		for i in range(sizes.size()):
			var to_number := int(tos[i])
			var key := "%d:%d" % [to_number, type_id]
			if not aggregated.has(key):
				aggregated[key] = {
					"to_number": to_number,
					"type_id": type_id,
					"quantity": 0,
					"detectability": detectability,
					"ijfs_profile": ijfs_profile,
				}
				order.append(key)
			aggregated[key]["quantity"] = int(aggregated[key]["quantity"]) + int(sizes[i])

	var systems: Array[AntishipSystem] = []
	for key in order:
		var agg: Dictionary = aggregated[key]
		var type_id: int = agg["type_id"]
		var type_def: Dictionary = types.get(type_id, {})
		var system: AntishipSystem = AntishipSystemResource.new()
		system.to_number = agg["to_number"]
		system.type_id = type_id
		system.type_name = String(type_def.get("name", ""))
		system.detectability = String(type_def.get("detectability", agg["detectability"]))
		system.quantity = int(agg["quantity"])
		system.original_quantity = system.quantity
		system.special = String(type_def.get("special", ""))
		system.ijfs_profile = agg["ijfs_profile"]
		systems.append(system)
	# Stable sort by (to_number, type_id) for deterministic firing-plan iteration.
	systems.sort_custom(func(a: AntishipSystem, b: AntishipSystem) -> bool:
		if a.to_number != b.to_number:
			return a.to_number < b.to_number
		return a.type_id < b.type_id)
	return systems


## Container-level view of the grouping spec: one Dictionary per platform-group container (each
## group_sizes[i]/to_assignments[i] entry), preserving the bin granularity that load_systems
## aggregates away. Used by IjfsLoaders.build_antiship_targets so IJFS strikes hit whole operating
## bins (see that func). Each: {to_number, type_id, type_name, systems_represented, detectability,
## ijfs_profile, platform_group, platform_group_index}.
static func load_containers(grouping_path: String, types: Dictionary) -> Array:
	var body: Dictionary = _read_json(grouping_path)
	var groups: Dictionary = body.get("taiwan_platform_groups", {})
	var containers: Array = []
	for group_name in groups.keys():
		var group: Dictionary = groups[group_name]
		var type_id := int(group["type_id"])
		var sizes: Array = group.get("group_sizes", [])
		var tos: Array = group.get("to_assignments", [])
		if sizes.size() != tos.size():
			_fail("Anti-ship group '%s' has mismatched group_sizes (%d) / to_assignments (%d)" % [group_name, sizes.size(), tos.size()])
		var ijfs_profile: Dictionary = group.get("ijfs_profile", {})
		var group_detectability := String(group.get("mainline_detectability", ""))
		var type_def: Dictionary = types.get(type_id, {})
		for i in range(sizes.size()):
			containers.append({
				"to_number": int(tos[i]),
				"type_id": type_id,
				"type_name": String(type_def.get("name", "")),
				"systems_represented": int(sizes[i]),
				"detectability": String(type_def.get("detectability", group_detectability)),
				"ijfs_profile": ijfs_profile,
				"platform_group": group_name,
				"platform_group_index": i,
			})
	containers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["to_number"]) != int(b["to_number"]):
			return int(a["to_number"]) < int(b["to_number"])
		if int(a["type_id"]) != int(b["type_id"]):
			return int(a["type_id"]) < int(b["type_id"])
		return int(a["platform_group_index"]) < int(b["platform_group_index"]))
	return containers


static func load_combat_catalog(path: String) -> Dictionary:
	var body: Dictionary = _read_json(path)
	for key in ["munitions", "launchers", "store_groups"]:
		if not body.has(key):
			_fail("Anti-ship combat catalog missing required key: %s" % key)
	return body


static func load_crossing_config(path: String) -> Dictionary:
	var body: Dictionary = _read_json(path)
	for key in ["missile_group_size", "escort_interception", "terminal_defense", "neutralization_likelihoods", "ship_profiles"]:
		if not body.has(key):
			_fail("Anti-ship crossing config missing required key: %s" % key)
	return body


static func load_magazines(path: String) -> Dictionary:
	var body: Dictionary = _read_json(path)
	for key in ["magazines", "loadout"]:
		if not body.has(key):
			_fail("Anti-ship magazine defaults missing required key: %s" % key)
	return body


static func load_minefields(path: String) -> Array[Minefield]:
	var body: Dictionary = _read_json(path)
	var minefields: Array[Minefield] = []
	for row_value in body.get("minefields", []):
		var row: Dictionary = row_value
		var minefield: Minefield = MinefieldResource.new()
		minefield.beach_id = int(row["beach_id"])
		minefield.name = String(row.get("name", ""))
		minefield.to_number = int(row.get("to_number", 0))
		minefield.num_mines = int(row.get("num_mines", 0))
		minefield.mines_per_sweeper_per_day = int(row.get("mines_per_sweeper_per_day", 0))
		minefield.remaining_mines = minefield.num_mines
		minefields.append(minefield)
	return minefields


static func available_minesweepers(path: String) -> int:
	return int(_read_json(path).get("available_minesweepers", 0))


## The geometric danger-model + transit knobs (port of TaiwanDefenseRefactor/mine_warfare.py). Returns
## the merged {geometry, transit} config consumed by MineWarfareService.resolve_ship_losses.
static func load_mine_config(path: String) -> Dictionary:
	var body: Dictionary = _read_json(path)
	return {
		"geometry": body.get("geometry", {}),
		"transit": body.get("transit", {}),
	}


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		_fail("Anti-ship data file not found: %s" % path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		_fail("Anti-ship data file is not a JSON object: %s" % path)
		return {}
	return DataOverrides.apply(path, parsed) as Dictionary


static func _fail(message: String) -> void:
	push_error(message)
	assert(false, message)
