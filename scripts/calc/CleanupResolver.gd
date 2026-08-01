class_name CleanupResolver
extends RefCounted

## Pure resolver for the D5-C cleanup phase (refactor_audit item 10, Phase C): runs the
## end-of-cleanup victory census + verdict and reports it. Consumes NO dice; no autoload/engine
## access; **applies no campaign state by any route** — which is what puts it in `calc/`.
##
## It used to apply two things and no longer does (plan 0055). The anti-ship transient-flag reset
## and the brigade activity latch both moved up into `TurnClosure.resolve_cleanup_phase`. Neither
## belonged here: nothing in this file READS either mutation, so deferring them to the caller
## changes no decision and no die — the test `scripts/interleaved/` applies. `resolve` now takes the
## reset COUNT the caller already obtained rather than the systems array it would have reset.
## `TurnClosure` owns GameData.recompute_hex_ownership() and the
## EventBus.cleanup_resolved emit; the game_over / winner / _china_has_landed writes belong to
## `TurnLifecycleTransitions` (plan 0049), which derives all three from the CleanupSummary below.
## The `china_has_landed` key this file returns is consumed only by its own VictoryConditions call and
## is report-only to the outside — the authority re-derives it from the summary's census so the two
## cannot disagree.


## Count PLA (RED) vs ROC (GREEN) battalions on the hexes that count as "on Taiwan".
## victory_config.taiwan_hexes null => every placed hex counts (correct for the main-island
## scenario; offshore islands can't be distinguished until terrain/land data exists). Counts
## PRESENT (landed) battalions only: brigades wholly off-map (no hex_id) are excluded, AND a
## partially-arrived brigade's battalions that have not made it ashore yet are subtracted, so they
## don't inflate China's count.
##
## `pending_pools` is every off-map battalion pool, in the shared {brigade_id, bns} entry shape —
## assemble it with GameStateData.pending_battalion_pools(), the one place that knows the full list.
## Passing a partial list here is the ghost-landing failure mode: the omitted pool's battalions get
## counted as ashore (plan 0034).
static func census(
	brigades: Dictionary, pending_pools: Array, victory_config: Dictionary
) -> Dictionary:
	var counted: Variant = victory_config.get("taiwan_hexes", null)
	var use_filter := counted is Array
	var hex_filter: Dictionary = {}
	if use_filter:
		for h in counted:
			hex_filter[String(h)] = true
	var not_ashore_by_brigade := PendingBattalions.by_brigade(pending_pools)

	var red := 0
	var green := 0
	for brigade_value in brigades.values():
		var brigade: Brigade = brigade_value
		if brigade.hex_id == "":
			continue
		if use_filter and not hex_filter.has(brigade.hex_id):
			continue
		var not_ashore := int(not_ashore_by_brigade.get(brigade.id, 0))
		var bn := maxi(0, brigade.get_battalion_count() - not_ashore)
		if brigade.team == Brigade.Team.RED:
			red += bn
		elif brigade.team == Brigade.Team.GREEN:
			green += bn
	return {Brigade.TEAM_KEY_RED: red, Brigade.TEAM_KEY_GREEN: green}


## Returns {"summary": CleanupSummary, "china_has_landed": bool}. china_has_landed_before is the
## latch state going in; the returned value is the (possibly newly latched) state the caller
## stores back — the "after_first_landing" victory arm reads it.
##
## `antiship_systems_reset` is REPORTED, not performed: the caller resets the flags and passes the
## count it got back, so this function stays free of any route to campaign state. TIV's
## Quantity_Moved/Quantity_Unavailable->Quantity_Available restore has no HexCombat equivalent —
## attempting to fire never takes a launcher off the board, so there is no unavailable pool to
## restore. Brigade per-turn flags are reset in begin_next_turn, so cleanup does not duplicate them.
static func resolve(
	antiship_systems_reset: int,
	brigades: Dictionary,
	pending_pools: Array,
	victory_config: Dictionary,
	turn_number: int,
	china_has_landed_before: bool,
) -> Dictionary:
	var census_counts := census(brigades, pending_pools, victory_config)
	var china_has_landed := china_has_landed_before or int(census_counts[Brigade.TEAM_KEY_RED]) > 0
	var arm := String(victory_config.get("loss_check_arm", "unconditional"))
	var verdict := VictoryConditions.evaluate(
		int(census_counts[Brigade.TEAM_KEY_RED]), int(census_counts[Brigade.TEAM_KEY_GREEN]), arm, turn_number, china_has_landed)

	var summary := CleanupSummary.new()
	summary.antiship_systems_reset = antiship_systems_reset
	summary.china_battalions_on_taiwan = int(census_counts[Brigade.TEAM_KEY_RED])
	summary.taiwan_battalions_on_taiwan = int(census_counts[Brigade.TEAM_KEY_GREEN])
	summary.game_over = bool(verdict["game_over"])
	summary.winner = String(verdict["winner"])
	summary.victory_reason = String(verdict["reason"])
	return {"summary": summary, "china_has_landed": china_has_landed}
