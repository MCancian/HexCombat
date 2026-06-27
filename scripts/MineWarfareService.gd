class_name MineWarfareService
extends RefCounted

## D3-C — mine warfare. Simplified, geometry-free port of TIV
## services/antiship/mine_warfare_service.py (MineWarfareService.resolve_ship_losses).
##
## Each turn, per target beach (processed in ascending beach_id order so the surviving fleet pool
## depletes deterministically and a hull never sinks at two beaches):
##  1. Assigned minesweepers clear mines — `newly_swept = min(remaining, assigned * mines_per_sweeper)`.
##  2. Each remaining unswept mine sinks one ship (1 mine == 1 hull). The ship TYPE is drawn from the
##     surviving-crossing fleet pool, weighted by remaining count, via the injected Dice; the draw
##     stops once the pool is empty. The pool is mutated in place across beaches.
##
## Mutates the matched Minefield resources (remaining_mines, dangerous_mines, minesweepers_assigned,
## lane_cleared, ships_destroyed) and the fleet_pool dict; returns a per-beach resolution list.
##
## DROPPED vs TIV (documented divergences — see PLAN.md Decisions 2026-06-27 D3-C):
##  - Geometric danger model (random mine positions, ship-path danger-radius filter, beach/lane
##    polygons): UI-only, driven by Python's string-seeded Mersenne Twister (not reproducible in
##    Godot), and absent from HexCombat's Minefield resource. So "dangerous mines" == "remaining
##    unswept mines" (in TIV's own test configs the danger radius spans the whole beach, so its
##    dangerous count equals num_mines there too).
##  - Same-day re-preview baseline recompute (last_resolved_day / *_day_start): a TIV web-UI
##    idempotency concern; HexCombat resolves each turn exactly once through the action layer.
##
## RNG: ship-type selection mirrors the source formula + draw order (one weighted pick per sinking)
## through the injected Dice instead of Python's non-portable string-seeded random.choices.


## Resolve mine sinkings against ships surviving the crossing.
## minefields: Array[Minefield] (only those whose beach_id is a target are touched).
## target_beaches: Array[int]. assignments: beach_id -> minesweepers (int or String keys accepted).
## fleet_pool: ship_type -> surviving hull count (mutated/depleted). Returns Array[Dictionary].
static func resolve_ship_losses(
		minefields: Array,
		target_beaches: Array,
		assignments: Dictionary,
		fleet_pool: Dictionary,
		dice: Dice) -> Array:
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
		var dangerous_before := maxi(0, mf.remaining_mines)
		var assigned_raw: Variant = assignments.get(
			beach_id, assignments.get(str(beach_id), mf.minesweepers_assigned))
		var assigned := maxi(0, int(assigned_raw))
		var mines_per_sweeper := maxi(0, mf.mines_per_sweeper_per_day)
		var newly_swept := mini(dangerous_before, assigned * mines_per_sweeper)
		var dangerous_after_sweep := maxi(0, dangerous_before - newly_swept)

		# 1 unswept dangerous mine == 1 ship sunk; ship TYPES drawn from the surviving pool weighted
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
		mf.dangerous_mines = mf.remaining_mines
		mf.ships_destroyed += newly_detonated
		mf.lane_cleared = mf.remaining_mines == 0

		resolutions.append({
			"beach_id": beach_id,
			"ship_loss_counts": ship_loss_counts,
			"ships_destroyed": newly_detonated,
			"newly_swept": newly_swept,
			"dangerous_before": dangerous_before,
			"dangerous_after": mf.remaining_mines,
			"remaining_after": mf.remaining_mines,
			"lane_cleared": mf.lane_cleared,
			"minesweepers_assigned": assigned,
			"status_color": status_color(mf.remaining_mines, mf.lane_cleared),
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
