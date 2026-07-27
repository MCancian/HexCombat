class_name TurnClosure
extends RefCounted

## The end-of-turn accounting pair (plan 0038 step 3): supply bills who fought, cleanup censuses who
## is left. They run last, back to back, and neither draws dice — supply reads the flags combat just
## set (`moved_this_turn`, `fought_this_turn`), cleanup then resets those flags, recounts both sides
## and decides whether the game is over.
##
## `TurnConductor` keeps the ORDERING (the when); this module only owns the how. Same contract as
## every other resolver: static, first argument `state: GameStateData` mutated in place, reads the
## GameData content autoload but never the GameState autoload singleton.


# --- Supply phase — the DOS bill for the day ---------------------------------------------------

static func resolve_supply_turn(state: GameStateData) -> Dictionary:
	assert(state.supply_state != null, "resolve_supply_turn requires supply_state")
	var units := active_red_battalion_units(state)
	var moved_ids: Array[String] = []
	var engaged_ids: Array[String] = []
	for brigade_value in GameData.brigades.values():
		var brigade: Brigade = brigade_value
		if brigade.team != Brigade.Team.RED or brigade.destroyed or brigade.hex_id.is_empty():
			continue
		if brigade.moved_this_turn:
			moved_ids.append(brigade.id)
		if brigade.fought_this_turn:
			engaged_ids.append(brigade.id)

	var summary := SupplyResolver.resolve(state.supply_state, units, moved_ids, engaged_ids, state.turn_number)
	EventBus.supply_updated.emit(summary)
	return summary


## Red battalions drawing Taiwan-theater supply. Only battalions ASHORE eat (plan 0037, USER call
## 2026-07-25): one still at sea, on the mainland, or waiting to fly is not being supplied across the
## strait by this pool. Same not-ashore definition combat uses, so a brigade's fighting strength and
## its ration bill always describe the same battalions.
static func active_red_battalion_units(state: GameStateData) -> Array:
	var units: Array = []
	# A FRESH recompute, not the combat loop's cached map: the supply phase runs after combat, and a
	# future phase order could drain a pool in between. Pools are unchanged today, so this is the same
	# value TurnConductor.resolve_turn cached before the combat loop — but the bill must not depend on
	# that staying true.
	var not_ashore := state.refresh_not_ashore_by_type()
	for brigade_value in GameData.brigades.values():
		var brigade: Brigade = brigade_value
		if brigade.team != Brigade.Team.RED or brigade.destroyed or brigade.hex_id.is_empty():
			continue
		var brigade_not_ashore: Dictionary = not_ashore.get(brigade.id, {})
		for battalion_value in brigade.composition:
			var battalion: Battalion = battalion_value
			for _qty_index in range(Brigade.landed_qty(battalion, brigade_not_ashore)):
				units.append({
					"brigade_id": brigade.id,
					"type": battalion.type,
					"brigade_type": brigade.nato_type,
				})
	return units


# --- D5-C Cleanup phase — end-of-turn per-system flag reset ------------------------------------

static func resolve_cleanup_phase(state: GameStateData) -> Dictionary:
	GameData.recompute_hex_ownership()
	# Pure work (flag reset, victory census + verdict, activity latch) lives in CleanupResolver;
	# consumes no dice, so the golden RNG stream is unaffected.
	var outcome := CleanupResolver.resolve(
		state.antiship_systems, GameData.brigades, state.pending_battalion_pools(),
		GameData.victory_config, state.turn_number, state._china_has_landed)
	state._china_has_landed = bool(outcome["china_has_landed"])
	state.last_cleanup_summary = outcome["summary"]
	state.game_over = state.last_cleanup_summary.game_over
	state.winner = state.last_cleanup_summary.winner
	EventBus.cleanup_resolved.emit(state.last_cleanup_summary.to_dict())
	return state.last_cleanup_summary.to_dict()


static func taiwan_battalion_census(state: GameStateData) -> Dictionary:
	return CleanupResolver.census(
		GameData.brigades, state.pending_battalion_pools(), GameData.victory_config)
