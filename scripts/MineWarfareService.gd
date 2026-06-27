class_name MineWarfareService
extends RefCounted

## D3-C — mine warfare. Simplified, geometry-free port of TIV
## services/antiship/mine_warfare_service.py (MineWarfareService.resolve_ship_losses).
##
## Each turn, per target beach (processed in ascending beach_id order so the surviving fleet pool
## depletes deterministically and a hull never sinks at two beaches):
##  1. Dangerous mines are BOUNDED to a per-lane cap — `dangerous_in_lane = min(remaining,
##     max_dangerous_per_lane)` — modelling the mines a transit actually encounters in its lane (see
##     decision 2-iii below). An already-cleared lane exposes 0.
##  2. Assigned minesweepers clear lane mines first — `newly_swept = min(dangerous_in_lane,
##     assigned * mines_per_sweeper)`.
##  3. Each remaining unswept LANE mine sinks one ship (1 mine == 1 hull). The ship TYPE is drawn
##     from the surviving-crossing fleet pool, weighted by remaining count, via the injected Dice;
##     the draw stops once the pool is empty. The pool is mutated in place across beaches.
##  4. The first SUCCESSFUL TRANSIT clears the lane (a path is forced/swept through) and marks it
##     `lane_cleared = true`; subsequent transits at that beach are safe even with mines remaining in
##     the wider field. A transit counts as successful when ships were crossing (non-empty pool) or
##     the lane was swept free of danger.
##
## Mutates the matched Minefield resources (remaining_mines, dangerous_mines, minesweepers_assigned,
## lane_cleared, ships_destroyed) and the fleet_pool dict; returns a per-beach resolution list.
##
## DESIGN — bounded lane danger (decision 2-iii, see PLAN.md Decisions 2026-06-27 D3-D). TIV's real
## limiter is geometry: only mines inside the ship-path danger radius are dangerous (random mine
## positions / beach-lane polygons, driven by Python's string-seeded Mersenne Twister — not portable
## to Godot and absent from HexCombat's Minefield resource). The geometry-free D3-C port set
## "dangerous" == all remaining mines, which made the shipped 100-mine fields sink ~all transiting
## hulls. 2-iii replaces the geometry with a per-lane danger CAP plus one-time lane clearing: bounded
## losses on first contact, then a marked safe lane. The cap is a balance knob (default couples with
## the status_color "red" threshold).
##
## DROPPED vs TIV: same-day re-preview baseline recompute (last_resolved_day / *_day_start) — a TIV
## web-UI idempotency concern; HexCombat resolves each turn exactly once through the action layer.
##
## RNG: ship-type selection mirrors the source formula + draw order (one weighted pick per sinking)
## through the injected Dice instead of Python's non-portable string-seeded random.choices.


# Default per-lane danger cap (decision 2-iii). Set to the status_color "red" threshold so a fully
# mined, uncleared lane reads red, falls to amber as it is swept down, and green once cleared.
const DEFAULT_MAX_DANGEROUS_PER_LANE := 10


## Resolve mine sinkings against ships surviving the crossing.
## minefields: Array[Minefield] (only those whose beach_id is a target are touched).
## target_beaches: Array[int]. assignments: beach_id -> minesweepers (int or String keys accepted).
## fleet_pool: ship_type -> surviving hull count (mutated/depleted).
## max_dangerous_per_lane: per-lane danger cap (balance knob; see decision 2-iii). Returns Array[Dictionary].
static func resolve_ship_losses(
		minefields: Array,
		target_beaches: Array,
		assignments: Dictionary,
		fleet_pool: Dictionary,
		dice: Dice,
		max_dangerous_per_lane: int = DEFAULT_MAX_DANGEROUS_PER_LANE) -> Array:
	var by_beach: Dictionary = {}
	for mf_value in minefields:
		var mf: Minefield = mf_value
		by_beach[int(mf.beach_id)] = mf

	var sorted_beaches: Array = []
	for b in target_beaches:
		sorted_beaches.append(int(b))
	sorted_beaches.sort()

	var resolutions: Array = []
	for beach_id in sorted_beaches:
		# A target beach with no minefield is "disabled" (TIV: Enabled=False) — no losses.
		if not by_beach.has(beach_id):
			resolutions.append({
				"beach_id": beach_id,
				"status": "disabled",
				"ship_loss_counts": {},
				"ships_destroyed": 0,
			})
			continue

		var mf: Minefield = by_beach[beach_id]
		# Danger is bounded to the per-lane cap; an already-cleared lane exposes nothing (2-iii).
		var dangerous_before := 0
		if not mf.lane_cleared:
			dangerous_before = mini(maxi(0, mf.remaining_mines), maxi(0, max_dangerous_per_lane))
		var pool_had_ships := false
		for hull_count in fleet_pool.values():
			if int(hull_count) > 0:
				pool_had_ships = true
				break
		var assigned_raw: Variant = assignments.get(
			beach_id, assignments.get(str(beach_id), mf.minesweepers_assigned))
		var assigned := maxi(0, int(assigned_raw))
		var mines_per_sweeper := maxi(0, mf.mines_per_sweeper_per_day)
		var newly_swept := mini(dangerous_before, assigned * mines_per_sweeper)
		var dangerous_after_sweep := maxi(0, dangerous_before - newly_swept)

		# 1 unswept LANE mine == 1 ship sunk; ship TYPES drawn from the surviving pool weighted
		# by remaining count. Re-derive the sorted eligible set each sinking (pool shrinks).
		var ship_loss_counts: Dictionary = {}
		for _sinking in range(dangerous_after_sweep):
			var eligible: Array = []
			for ship_type in fleet_pool.keys():
				if int(fleet_pool[ship_type]) > 0:
					eligible.append(ship_type)
			if eligible.is_empty():
				break
			eligible.sort()
			var weights: Array = []
			for t in eligible:
				weights.append(int(fleet_pool[t]))
			var idx := dice.weighted_choice(weights)
			var chosen: Variant = eligible[idx]
			fleet_pool[chosen] = int(fleet_pool[chosen]) - 1
			ship_loss_counts[chosen] = int(ship_loss_counts.get(chosen, 0)) + 1

		var newly_detonated := 0
		for count in ship_loss_counts.values():
			newly_detonated += int(count)

		# Both swept and detonated mines are consumed from the remaining pool.
		mf.minesweepers_assigned = assigned
		mf.remaining_mines = maxi(0, mf.remaining_mines - newly_swept - newly_detonated)
		mf.ships_destroyed += newly_detonated
		# First successful transit clears + marks the lane: ships crossed (non-empty pool) or the lane
		# was swept free of danger, or the field is mined out entirely (2-iii).
		if pool_had_ships or dangerous_after_sweep == 0 or mf.remaining_mines == 0:
			mf.lane_cleared = true
		mf.dangerous_mines = 0 if mf.lane_cleared else mini(mf.remaining_mines, maxi(0, max_dangerous_per_lane))

		resolutions.append({
			"beach_id": beach_id,
			"ship_loss_counts": ship_loss_counts,
			"ships_destroyed": newly_detonated,
			"newly_swept": newly_swept,
			"dangerous_before": dangerous_before,
			"dangerous_after": mf.dangerous_mines,
			"remaining_after": mf.remaining_mines,
			"lane_cleared": mf.lane_cleared,
			"minesweepers_assigned": assigned,
			"status_color": status_color(mf.dangerous_mines, mf.lane_cleared),
		})
	return resolutions


## Beach status color from dangerous-mine count + lane state. Faithful port of status_color.
static func status_color(dangerous_mines: int, lane_cleared: bool) -> String:
	if lane_cleared:
		return "green"
	if dangerous_mines >= 10:
		return "red"
	if dangerous_mines > 0:
		return "amber"
	return "green"
