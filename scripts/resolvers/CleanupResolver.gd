class_name CleanupResolver
extends RefCounted

## Pure resolver for the D5-C cleanup phase (refactor_audit item 10, Phase C): resets the
## anti-ship per-turn flags, runs the end-of-cleanup victory census + verdict, and latches each
## brigade's this-turn activity into the prior-turn flags that next turn's IJFS detection posture
## reads. Consumes NO dice. Mutates passed-in Resources (antiship systems, brigades) — the
## sanctioned pattern; no autoload/engine access. GameState's wrapper owns
## GameData.recompute_hex_ownership(), the game_over/winner/_china_has_landed state writes, and
## the EventBus.cleanup_resolved emit.


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
static func resolve(
	antiship_systems: Array,
	brigades: Dictionary,
	pending_pools: Array,
	victory_config: Dictionary,
	turn_number: int,
	china_has_landed_before: bool,
) -> Dictionary:
	var reset_count := 0
	for system_value in antiship_systems:
		var system: AntishipSystem = system_value
		system.fired = 0
		system.expended = 0
		system.destroyed_this_turn = 0
		system.suppressed = false
		system.active = false
		reset_count += 1
	# NOTE: TIV's Quantity_Moved/Quantity_Unavailable->Quantity_Available restore has no HexCombat
	# equivalent (AntishipSystem has no moved/unavailable split; quantity is recomputed each turn).
	# Brigade per-turn flags are reset in begin_next_turn, so cleanup does not duplicate them.

	var census_counts := census(brigades, pending_pools, victory_config)
	var china_has_landed := china_has_landed_before or int(census_counts[Brigade.TEAM_KEY_RED]) > 0
	var arm := String(victory_config.get("loss_check_arm", "unconditional"))
	var verdict := VictoryConditions.evaluate(
		int(census_counts[Brigade.TEAM_KEY_RED]), int(census_counts[Brigade.TEAM_KEY_GREEN]), arm, turn_number, china_has_landed)

	# Latch this turn's activity into prior-turn flags (for next turn's IJFS detection posture)
	# BEFORE begin_next_turn resets the per-turn flags.
	for brigade_value in brigades.values():
		var brigade: Brigade = brigade_value
		brigade.moved_last_turn = brigade.moved_this_turn or brigade.moved_admin_this_turn
		brigade.fought_last_turn = brigade.fought_this_turn

	var summary := CleanupSummary.new()
	summary.antiship_systems_reset = reset_count
	summary.china_battalions_on_taiwan = int(census_counts[Brigade.TEAM_KEY_RED])
	summary.taiwan_battalions_on_taiwan = int(census_counts[Brigade.TEAM_KEY_GREEN])
	summary.game_over = bool(verdict["game_over"])
	summary.winner = String(verdict["winner"])
	summary.victory_reason = String(verdict["reason"])
	return {"summary": summary, "china_has_landed": china_has_landed}
