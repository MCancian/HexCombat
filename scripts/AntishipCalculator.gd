class_name AntishipCalculator
extends RefCounted

## D3-B2 — anti-ship firing-plan stage. Faithful port of TIV:
##  - services/antiship_firing_plan.build_firing_plan
##  - services/antiship_allocation.allocate_firing_to_rows
##  - services/antiship_launch_attrition.resolve_launch_attrition
##
## HexCombat's AntishipSystem rows are pre-aggregated one-per-(TO, type_id) by AntishipLoaders, so
## the per-container row split is single-row here. allocate_firing_to_rows is still ported faithfully
## (proportional largest-remainder) for fidelity and direct unit testing.
##
## Key encoding: TIV keys dicts on (location, type_key) tuples; GDScript dicts can't key on
## value-arrays, so we encode them as "<to>:<type>" strings. firing_percentages,
## destroyed_fire_percentages, ijfs_destroyed and the returned destroyed_firing_plan all use this
## encoding. type_key is always int in HexCombat data (TIV's non-numeric-type str fallback is unused).
##
## RNG (launch attrition): inject a Dice; draw order mirrors the source exactly — per attempted shot,
## one randf() for detect/destroy, then a second randf() ONLY when the first kills (intercept-before-
## launch). The DB/pandas plumbing and the Final_Attrition_Pct reporting column are not ported.

const SYSTEM_TYPE_C2 := 99


static func encode_key(to_number: int, type_key: int) -> String:
	return "%d:%d" % [to_number, type_key]


# --- allocate_firing_to_rows (services/antiship_allocation.py) -----------------------------------

## Proportional largest-remainder allocation across availability rows, each capped at its available
## quantity; remainder ties go to earlier rows. Faithful port of allocate_firing_to_rows.
static func allocate_firing_to_rows(qty_available_list: Array, total_firing: int) -> Array:
	var n := qty_available_list.size()
	var total := 0
	for q in qty_available_list:
		total += int(q)
	if total == 0 or total_firing == 0:
		var zeros: Array = []
		for _i in range(n):
			zeros.append(0)
		return zeros

	var raw: Array = []
	var floors: Array = []
	var floor_sum := 0
	for q in qty_available_list:
		var r := float(int(q)) / float(total) * float(total_firing)
		raw.append(r)
		var f := int(r)
		floors.append(f)
		floor_sum += f

	var deficit := total_firing - floor_sum
	if deficit > 0:
		var order: Array = []
		for i in range(n):
			order.append(i)
		order.sort_custom(func(a: int, b: int) -> bool:
			var ra: float = raw[a] - float(floors[a])
			var rb: float = raw[b] - float(floors[b])
			if ra != rb:
				return ra > rb
			return a < b)
		for i in range(deficit):
			floors[order[i]] += 1

	var result: Array = []
	for i in range(n):
		result.append(mini(int(floors[i]), int(qty_available_list[i])))
	return result


# --- build_firing_plan (services/antiship_firing_plan.py) ----------------------------------------

## Build row-level intended firing allocations plus destroyed-system firing totals.
## Returns {"allocation_plan": Array[Dictionary], "destroyed_firing_plan": Dictionary}.
## Does NOT mutate `systems`; resolve_launch_attrition applies inventory effects by row_idx.
static func build_firing_plan(
		systems: Array,
		ijfs_destroyed: Dictionary,
		target_locations: Array,
		firing_percentages: Dictionary,
		destroyed_fire_percentages: Dictionary,
		magazine: AntishipMagazine = null) -> Dictionary:
	var allocation_plan: Array = []
	var destroyed_firing_plan: Dictionary = {}

	for location in target_locations:
		var loc := int(location)
		for idx in range(systems.size()):
			var system: AntishipSystem = systems[idx]
			if system.to_number != loc:
				continue
			if system.type_id == SYSTEM_TYPE_C2:
				continue

			var type_key := system.type_id
			var key := encode_key(loc, type_key)

			var truly_available := maxi(0, system.quantity)
			if magazine != null:
				truly_available = magazine.cap_launcher_count(type_key, truly_available)

			var destroyed_count := 0
			if not ijfs_destroyed.is_empty():
				destroyed_count = int(ijfs_destroyed.get(key, 0))
			else:
				destroyed_count = maxi(0, system.destroyed_this_turn)

			var fire_pct := float(firing_percentages.get(key, 0.0)) / 100.0
			var destroyed_fire_pct := float(destroyed_fire_percentages.get(key, 0.0)) / 100.0
			var initial_system_count := truly_available + destroyed_count
			var intended_to_fire := int(float(initial_system_count) * fire_pct)
			var available_firing := mini(intended_to_fire, truly_available)
			if magazine != null and available_firing > 0:
				available_firing = magazine.reserve_full_volley(type_key, available_firing)
			var destroyed_firing := int(float(destroyed_count) * destroyed_fire_pct)
			destroyed_firing_plan[key] = destroyed_firing

			if available_firing <= 0:
				continue

			var fired_per_row := allocate_firing_to_rows([system.quantity], available_firing)
			var intended := int(fired_per_row[0])
			if intended <= 0:
				continue
			allocation_plan.append({
				"row_idx": idx,
				"to": loc,
				"type": type_key,
				"type_key": type_key,
				"attempted_firing": intended,
			})

	return {
		"allocation_plan": allocation_plan,
		"destroyed_firing_plan": destroyed_firing_plan,
	}


# --- resolve_launch_attrition (services/antiship_launch_attrition.py) ----------------------------

## Resolve per-launcher pre/post launch kills and mutate the AntishipSystem rows (by row_idx).
## Returns {"systems_fired": Array[Dictionary], "launch_attrition": Array[Dictionary]}.
static func resolve_launch_attrition(
		systems: Array,
		allocation_plan: Array,
		destroyed_firing_plan: Dictionary,
		config: Dictionary,
		dice: Dice) -> Dictionary:
	var grouped: Dictionary = {}
	for entry in allocation_plan:
		# Rolls happen per entry in allocation-plan order (the port's draw-order contract).
		var attrition := _attrit_allocation_entry(systems, entry, config, dice)
		_accumulate_attrition_group(grouped, attrition)

	var meta := _report_key_meta(grouped, destroyed_firing_plan)
	return _build_attrition_reports(_sorted_report_keys(meta), meta, grouped, destroyed_firing_plan)


## One allocation-plan entry: per-shot detection/intercept rolls, then the sanctioned mutation of
## the fired AntishipSystem row. Returns the tallies keyed for grouping.
static func _attrit_allocation_entry(systems: Array, entry: Dictionary, config: Dictionary, dice: Dice) -> Dictionary:
	var row_idx := int(entry["row_idx"])
	var attempted := int(entry["attempted_firing"])

	var type_key := int(entry["type_key"])
	var type_cfg := _resolve_type_config(config, type_key)
	var p_detect := float(type_cfg.get("p_detect", 0.0))
	var p_destroy_if_detected := float(type_cfg.get("p_destroy_if_detected", 0.0))
	var p_destroy := clampf(p_detect * p_destroy_if_detected, 0.0, 1.0)
	var p_intercept_before_launch := clampf(float(type_cfg.get("p_intercept_before_launch", 0.0)), 0.0, 1.0)

	var system: AntishipSystem = systems[row_idx]
	system.active = true

	var launched := 0
	var prelaunch_destroyed := 0
	var postlaunch_destroyed := 0
	for _shot in range(attempted):
		var destroyed := dice.randf() < p_destroy
		if not destroyed:
			launched += 1
			continue
		if dice.randf() < p_intercept_before_launch:
			prelaunch_destroyed += 1
		else:
			postlaunch_destroyed += 1
			launched += 1

	system.quantity = maxi(0, system.quantity - attempted)
	system.fired += launched
	system.expended += launched
	system.destroyed_this_turn += prelaunch_destroyed + postlaunch_destroyed
	system.destroyed += prelaunch_destroyed + postlaunch_destroyed

	return {
		"to": int(entry["to"]),
		"type": entry["type"],
		"type_key": type_key,
		"attempted": attempted,
		"launched": launched,
		"prelaunch_destroyed": prelaunch_destroyed,
		"postlaunch_destroyed": postlaunch_destroyed,
	}


static func _accumulate_attrition_group(grouped: Dictionary, attrition: Dictionary) -> void:
	var group_key := encode_key(int(attrition["to"]), int(attrition["type_key"]))
	var group: Dictionary = grouped.get(group_key, {
		"to": attrition["to"],
		"type": attrition["type"],
		"type_key": attrition["type_key"],
		"attempted_firing": 0,
		"available_firing": 0,
		"prelaunch_destroyed": 0,
		"postlaunch_destroyed": 0,
	})
	group["attempted_firing"] = int(group["attempted_firing"]) + int(attrition["attempted"])
	group["available_firing"] = int(group["available_firing"]) + int(attrition["launched"])
	group["prelaunch_destroyed"] = int(group["prelaunch_destroyed"]) + int(attrition["prelaunch_destroyed"])
	group["postlaunch_destroyed"] = int(group["postlaunch_destroyed"]) + int(attrition["postlaunch_destroyed"])
	grouped[group_key] = group


## All report keys = grouped ∪ destroyed_firing_plan, each mapped to [to, type_key] for ordering.
static func _report_key_meta(grouped: Dictionary, destroyed_firing_plan: Dictionary) -> Dictionary:
	var meta: Dictionary = {}
	for key in grouped.keys():
		var group: Dictionary = grouped[key]
		meta[key] = [int(group["to"]), group["type_key"]]
	for key in destroyed_firing_plan.keys():
		if not meta.has(key):
			meta[key] = _decode_key(key)
	return meta


## Ordered by (to, str(type_key)) like the source.
static func _sorted_report_keys(meta: Dictionary) -> Array:
	var sorted_keys: Array = meta.keys()
	sorted_keys.sort_custom(func(a: String, b: String) -> bool:
		var meta_a: Array = meta[a]
		var meta_b: Array = meta[b]
		if int(meta_a[0]) != int(meta_b[0]):
			return int(meta_a[0]) < int(meta_b[0])
		return str(meta_a[1]) < str(meta_b[1]))
	return sorted_keys


## Shape the two output lists: systems_fired (crossing input) and launch_attrition (the ledger).
static func _build_attrition_reports(
		sorted_keys: Array, meta: Dictionary, grouped: Dictionary,
		destroyed_firing_plan: Dictionary) -> Dictionary:
	var systems_fired: Array = []
	var launch_attrition: Array = []
	for key in sorted_keys:
		var key_meta: Array = meta[key]
		var summary: Dictionary = grouped.get(key, {
			"to": int(key_meta[0]),
			"type": key_meta[1],
			"attempted_firing": 0,
			"available_firing": 0,
			"prelaunch_destroyed": 0,
			"postlaunch_destroyed": 0,
		})
		var destroyed_firing := int(destroyed_firing_plan.get(key, 0))
		var total_firing := int(summary["available_firing"]) + destroyed_firing
		if total_firing > 0:
			systems_fired.append({
				"to": int(summary["to"]),
				"type": summary["type"],
				"available_firing": int(summary["available_firing"]),
				"destroyed_firing": destroyed_firing,
				"systems_fired": total_firing,
				"attempted_firing": int(summary["attempted_firing"]),
				"prelaunch_destroyed": int(summary["prelaunch_destroyed"]),
				"postlaunch_destroyed": int(summary["postlaunch_destroyed"]),
			})
		if int(summary["attempted_firing"]) > 0:
			launch_attrition.append({
				"to": int(summary["to"]),
				"type": summary["type"],
				"attempted_firing": int(summary["attempted_firing"]),
				"prelaunch_destroyed": int(summary["prelaunch_destroyed"]),
				"postlaunch_destroyed": int(summary["postlaunch_destroyed"]),
				"launched": int(summary["available_firing"]),
			})

	return {
		"systems_fired": systems_fired,
		"launch_attrition": launch_attrition,
	}


# --- helpers -------------------------------------------------------------------------------------

## Per-type attrition params with _default fallback; a flat config (p_detect present) is returned
## as-is. Mirrors antiship_launch_attrition._resolve_type_config.
static func _resolve_type_config(launch_cfg: Dictionary, type_key: int) -> Dictionary:
	if launch_cfg.has("p_detect"):
		return launch_cfg
	var type_str := str(type_key)
	if launch_cfg.has(type_str):
		return launch_cfg[type_str]
	return launch_cfg.get("_default", {})


## Decode an "<to>:<type>" key back to [to_number, type_key]; type_key stays int when numeric.
static func _decode_key(key: String) -> Array:
	var parts := key.split(":")
	var to_number := int(parts[0])
	var type_part := parts[1] if parts.size() > 1 else ""
	var type_key: Variant = int(type_part) if type_part.is_valid_int() else type_part
	return [to_number, type_key]
