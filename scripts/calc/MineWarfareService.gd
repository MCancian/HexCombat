class_name MineWarfareService
extends RefCounted

## D3-C — mine warfare. GEOMETRIC danger model, port of
## TaiwanDefenseRefactor/mine_warfare.py (create_minefield / calculate_ship_path /
## count_dangerous_mines / process_mine_hits), adapted to HexCombat's per-turn count-based fleet.
##
## The premise the user asked for: mines are pre-seeded across ALL candidate landing beaches, so a
## minefield only matters if the assault wave actually crosses that beach (some are never encountered).
## For an encountered field the goal is NOT to clear every mine but to push a LANE through it:
##
##  1. GEOMETRY (per beach, per turn until the lane is open). `num_mines` are scattered uniformly in a
##     `length x width` field; the fleet takes a *randomized* straight approach path (random incident
##     angle + entry point). Only mines within `danger_radius` (50 m) of that path line are DANGEROUS
##     (typically a handful, not all `num_mines`). Each encounter re-rolls the layout + path via the
##     injected Dice, so the dangerous count is "somewhat random".
##  2. PRE-LANDING CLEARING (knob). Assigned minesweepers clear the closest
##     `assigned * prelanding_clear_per_sweeper` dangerous mines. The default is deliberately weak
##     (~1-2): pre-landing sweeping mainly LOCATES the field, it does not open the lane.
##  3. TRANSIT. The surviving crossing fleet runs the lane in order — DECOYS first, then real ships by
##     ascending value — each ship detonating the next dangerous mine. A decoy that survives a
##     detonation continues down the lane and can trigger SUBSEQUENT mines (decoys are sponges). A ship
##     that detonates a mine is neutralized with a probability set by its hardness
##     (`neutralization_likelihood`). Amphibs (high-value carriers) are only at risk once dangerous
##     mines remain after the decoys + sweepers have absorbed them. The first transit opens the lane
##     (`lane_cleared`); later waves at that beach are safe.
##
## Mutates the matched Minefield resources and the fleet_pool dict; returns a per-beach resolution list.
## Pure: geometry RNG + neutralization rolls go through the injected Dice (formula + draw order ported;
## NOT numpy's bitstream). Beaches are processed in ascending beach_id order so the shared fleet pool
## depletes deterministically and a hull never sinks at two beaches.

# Geometry defaults (overridable via config.geometry; see data/antiship/minefields.json).
const DEFAULT_LENGTH := 1000.0
const DEFAULT_WIDTH := 500.0
const DEFAULT_DANGER_RADIUS := 50.0
const DEFAULT_ANGLE_MIN_DEG := 30.0
const DEFAULT_ANGLE_MAX_DEG := 60.0
const DEFAULT_ENTRY_MIN := 0.3
const DEFAULT_ENTRY_MAX := 0.7

# Transit defaults (overridable via config.transit).
const DEFAULT_PRELANDING_CLEAR_PER_SWEEPER := 1
const DEFAULT_NEUT_PROBS := {"high": 0.9, "medium": 0.5, "low": 0.25}
const DEFAULT_DECOY_LIKELIHOOD := "high"
const DEFAULT_SHIP_LIKELIHOOD := "high"


## Resolve mine sinkings against the ships surviving the crossing.
## minefields: Array[Minefield] (only those whose beach_id is a target are touched).
## target_beaches: Array[int].
## assignments: beach_id -> minesweepers assigned (int or String keys accepted).
## fleet_pool: ship_type(String) -> surviving hull count (mutated/depleted in transit order).
## dice: injected Dice.
## ship_meta: ship_type -> {is_decoy: bool, value: float, likelihood: String("high"/"medium"/"low")}.
## config: {geometry: {...}, transit: {...}} (see the DEFAULT_* constants). Returns Array[Dictionary].
static func resolve_ship_losses(
		minefields: Array,
		target_beaches: Array,
		assignments: Dictionary,
		fleet_pool: Dictionary,
		dice: Dice,
		ship_meta: Dictionary = {},
		config: Dictionary = {}) -> Array:
	var geometry := _geometry_config(config)
	var transit: Dictionary = config.get("transit", {})
	var clear_per_sweeper := int(transit.get("prelanding_clear_per_sweeper", DEFAULT_PRELANDING_CLEAR_PER_SWEEPER))
	var neutralization_probabilities: Dictionary = transit.get("neutralization_probabilities", DEFAULT_NEUT_PROBS)

	var minefield_by_beach: Dictionary = {}
	for minefield_value in minefields:
		var registered_minefield: Minefield = minefield_value
		minefield_by_beach[int(registered_minefield.beach_id)] = registered_minefield

	var sorted_beaches: Array = []
	for beach_id_value in target_beaches:
		sorted_beaches.append(int(beach_id_value))
	sorted_beaches.sort()

	var resolutions: Array = []
	for beach_id in sorted_beaches:
		# A target beach with no minefield is "disabled" (TIV: Enabled=False) — no losses.
		if not minefield_by_beach.has(beach_id):
			resolutions.append({
				"beach_id": beach_id,
				"status": "disabled",
				"ship_loss_counts": {},
				"ships_destroyed": 0,
			})
			continue

		var minefield: Minefield = minefield_by_beach[beach_id]

		# An already-open lane exposes nothing (persisted from an earlier wave).
		if minefield.lane_cleared:
			minefield.dangerous_mines = 0
			resolutions.append(_beach_result(beach_id, minefield, {}, 0, 0, 0, 0, int(_assigned(assignments, beach_id, minefield))))
			continue

		# 1. Geometry: how many of this field's mines lie within danger_radius of a random approach path.
		var dangerous := _count_dangerous_mines(
			minefield.num_mines, geometry["length"], geometry["width"], geometry["danger_radius"],
			geometry["angle_min"], geometry["angle_max"], geometry["entry_min"], geometry["entry_max"], dice)

		# 2. Pre-landing clearing (weak by default — mostly locates the field).
		var assigned := _assigned(assignments, beach_id, minefield)
		var newly_swept := mini(dangerous, assigned * maxi(0, clear_per_sweeper))
		var remaining_dangerous := maxi(0, dangerous - newly_swept)

		# 3. Transit: decoys first, then ships ascending value; detonations + neutralization.
		var pool_had_ships := _pool_has_ships(fleet_pool)
		var transit_result := _run_lane_transit(fleet_pool, ship_meta, neutralization_probabilities, remaining_dangerous, dice)
		var ship_loss_counts: Dictionary = transit_result["ship_loss_counts"]
		var detonated := int(transit_result["detonated"])
		remaining_dangerous = int(transit_result["remaining_dangerous"])

		_apply_beach_outcome(minefield, assigned, newly_swept, detonated, ship_loss_counts, remaining_dangerous, pool_had_ships)

		resolutions.append(_beach_result(beach_id, minefield, ship_loss_counts, dangerous, newly_swept, detonated, remaining_dangerous, assigned))
	return resolutions


## Geometry knobs with defaults applied (see data/antiship/minefields.json).
static func _geometry_config(config: Dictionary) -> Dictionary:
	var geometry: Dictionary = config.get("geometry", {})
	return {
		"length": float(geometry.get("minefield_length", DEFAULT_LENGTH)),
		"width": float(geometry.get("minefield_width", DEFAULT_WIDTH)),
		"danger_radius": float(geometry.get("danger_radius", DEFAULT_DANGER_RADIUS)),
		"angle_min": float(geometry.get("incident_angle_min_deg", DEFAULT_ANGLE_MIN_DEG)),
		"angle_max": float(geometry.get("incident_angle_max_deg", DEFAULT_ANGLE_MAX_DEG)),
		"entry_min": float(geometry.get("entry_point_min", DEFAULT_ENTRY_MIN)),
		"entry_max": float(geometry.get("entry_point_max", DEFAULT_ENTRY_MAX)),
	}


## Run the fleet down the lane: decoys first (sponges), then real ships by ascending value; each
## detonation rolls neutralization. Mutates fleet_pool (losses depleted). Skipped bodily when the
## lane holds no danger or the pool is empty — the callers' dice draw order depends on that.
## Returns {"ship_loss_counts": type -> sunk, "detonated": int, "remaining_dangerous": int}.
static func _run_lane_transit(
		fleet_pool: Dictionary, ship_meta: Dictionary, neutralization_probabilities: Dictionary,
		remaining_dangerous: int, dice: Dice) -> Dictionary:
	var ship_loss_counts: Dictionary = {}
	var detonated := 0
	if remaining_dangerous > 0 and _pool_has_ships(fleet_pool):
		var order := _transit_order(fleet_pool, ship_meta)
		for ship_type in order:
			if remaining_dangerous <= 0:
				break
			var available := int(fleet_pool.get(ship_type, 0))
			if available <= 0:
				continue
			var meta: Dictionary = ship_meta.get(ship_type, {})
			var is_decoy := bool(meta.get("is_decoy", false))
			var p_neutralized := _neutralization_probability(meta, neutralization_probabilities, is_decoy)
			var losses := 0
			var instance := 0
			while instance < available and remaining_dangerous > 0:
				if is_decoy:
					# A decoy keeps detonating mines until it is neutralized or the lane is clear.
					var sunk := false
					while remaining_dangerous > 0:
						remaining_dangerous -= 1
						detonated += 1
						if dice.randf() < p_neutralized:
							sunk = true
							break
					if sunk:
						losses += 1
				else:
					# A real ship detonates one mine; amphibs only get here if mines remain.
					remaining_dangerous -= 1
					detonated += 1
					if dice.randf() < p_neutralized:
						losses += 1
				instance += 1
			if losses > 0:
				ship_loss_counts[ship_type] = losses
				fleet_pool[ship_type] = available - losses
	return {
		"ship_loss_counts": ship_loss_counts,
		"detonated": detonated,
		"remaining_dangerous": remaining_dangerous,
	}


## Write the wave's outcome back onto the Minefield resource: consumed mines, sinkings, and the
## lane state (opens once a wave has transited with ships present or the danger hit zero).
static func _apply_beach_outcome(
		minefield: Minefield, assigned: int, newly_swept: int, detonated: int,
		ship_loss_counts: Dictionary, remaining_dangerous: int, pool_had_ships: bool) -> void:
	minefield.minesweepers_assigned = assigned
	minefield.remaining_mines = maxi(0, minefield.remaining_mines - newly_swept - detonated)
	var sunk_total := 0
	for loss_count in ship_loss_counts.values():
		sunk_total += int(loss_count)
	minefield.ships_destroyed += sunk_total
	if pool_had_ships or remaining_dangerous == 0:
		minefield.lane_cleared = true
	minefield.dangerous_mines = 0 if minefield.lane_cleared else remaining_dangerous


## Geometry port: scatter num_mines uniformly, take a randomized straight approach path, and count
## mines within danger_radius of that path line. Draw order (deterministic): angle, entry, then
## (x, y) per mine. Returns the dangerous-mine COUNT (positions are not retained — all dangerous mines
## are interchangeable for the count-based transit).
static func _count_dangerous_mines(
		num_mines: int, length: float, width: float, danger_radius: float,
		angle_min: float, angle_max: float, entry_min: float, entry_max: float, dice: Dice) -> int:
	if num_mines <= 0:
		return 0
	var angle_deg := angle_min + dice.randf() * (angle_max - angle_min)
	var entry_point := entry_min + dice.randf() * (entry_max - entry_min)
	var angle_rad := deg_to_rad(angle_deg)
	# side == "long" path (port of calculate_ship_path).
	var start_x := entry_point * length
	var start_y := 0.0
	var end_x := start_x + width * cos(angle_rad)
	var end_y := width / maxf(sin(angle_rad), 0.0001)
	var dx := end_x - start_x
	var dy := end_y - start_y
	var denom := sqrt(dy * dy + dx * dx)
	if denom <= 0.0:
		return 0
	var dangerous := 0
	for _i in range(num_mines):
		var mx := dice.randf() * length
		var my := dice.randf() * width
		var distance_to_path: float = abs(dy * mx - dx * my + end_x * start_y - end_y * start_x) / denom
		if distance_to_path <= danger_radius:
			dangerous += 1
	return dangerous


## Transit order: decoys first (sorted by type for determinism), then non-decoy ships by ascending
## value, ties broken by type name. Only types present in the pool are returned.
static func _transit_order(fleet_pool: Dictionary, ship_meta: Dictionary) -> Array:
	var decoys: Array = []
	var others: Array = []
	for ship_type in fleet_pool.keys():
		if int(fleet_pool[ship_type]) <= 0:
			continue
		var meta: Dictionary = ship_meta.get(ship_type, {})
		if bool(meta.get("is_decoy", false)):
			decoys.append(ship_type)
		else:
			others.append(ship_type)
	decoys.sort()
	others.sort_custom(func(a, b):
		var va := float((ship_meta.get(a, {}) as Dictionary).get("value", 0.0))
		var vb := float((ship_meta.get(b, {}) as Dictionary).get("value", 0.0))
		if va == vb:
			return String(a) < String(b)
		return va < vb)
	var order: Array = []
	order.append_array(decoys)
	order.append_array(others)
	return order


static func _neutralization_probability(meta: Dictionary, neut_probs: Dictionary, is_decoy: bool) -> float:
	var default_label := DEFAULT_DECOY_LIKELIHOOD if is_decoy else DEFAULT_SHIP_LIKELIHOOD
	var label := String(meta.get("likelihood", default_label)).to_lower()
	return float(neut_probs.get(label, neut_probs.get(default_label, 0.5)))


static func _assigned(assignments: Dictionary, beach_id: int, mf: Minefield) -> int:
	var raw: Variant = assignments.get(beach_id, assignments.get(str(beach_id), mf.minesweepers_assigned))
	return maxi(0, int(raw))


static func _pool_has_ships(fleet_pool: Dictionary) -> bool:
	for hull_count in fleet_pool.values():
		if int(hull_count) > 0:
			return true
	return false


static func _beach_result(
		beach_id: int, mf: Minefield, ship_loss_counts: Dictionary,
		dangerous: int, newly_swept: int, detonated: int, remaining_dangerous: int, assigned: int) -> Dictionary:
	var sunk := 0
	for c in ship_loss_counts.values():
		sunk += int(c)
	return {
		"beach_id": beach_id,
		"ship_loss_counts": ship_loss_counts,
		"ships_destroyed": sunk,
		"dangerous": dangerous,
		"newly_swept": newly_swept,
		"dangerous_detonated": detonated,
		"dangerous_after": mf.dangerous_mines,
		"remaining_after": mf.remaining_mines,
		"lane_cleared": mf.lane_cleared,
		"minesweepers_assigned": assigned,
		"status_color": status_color(mf.dangerous_mines, mf.lane_cleared),
	}


## Beach status color from dangerous-mine count + lane state. Faithful port of status_color.
static func status_color(dangerous_mines: int, lane_cleared: bool) -> String:
	if lane_cleared:
		return "green"
	if dangerous_mines >= 10:
		return "red"
	if dangerous_mines > 0:
		return "amber"
	return "green"
