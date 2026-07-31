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

## Rebuild the Red DOS pool for a (re)loaded scenario. GameState reaches the supply authority through
## this module rather than naming it directly, the same way `_rebuild_infrastructure_state` reaches
## `InfrastructureTransitions` through `ReinforcementPhases` — the phase's owner is its door.
static func rebuild_supply_state(state: GameStateData, red_dos_start: float) -> void:
	SupplyTransitions.rebuild_supply_state(state, red_dos_start)


static func resolve_supply_turn(state: GameStateData) -> Dictionary:
	assert(state.supply_state != null, "resolve_supply_turn requires supply_state")
	# A FRESH recompute, not the combat loop's cached map: the supply phase runs after combat, and a
	# future phase order could drain a pool in between. Pools are unchanged today, so this is the same
	# value TurnConductor.resolve_turn cached before the combat loop — but the bill must not depend on
	# that staying true. It is refreshed HERE, not inside SupplyBill, because the refresh writes a
	# cache that outlives the call and a calculator may not do that.
	var not_ashore := state.refresh_not_ashore_by_type()
	var consumption := SupplyBill.for_turn(GameData, not_ashore, state.turn_number)
	var summary := SupplyTransitions.apply_daily_bill(state.supply_state, consumption)
	if summary.is_empty():
		# The authority refused the bill and already said why. Emitting an empty Dictionary on
		# supply_updated would announce a billed day that never reached the ledger, which reads
		# downstream as a successful phase — so stay silent and let the day be visibly missing.
		push_error("TurnClosure.resolve_supply_turn: the day's bill was refused; no ledger row written")
		return {}
	EventBus.supply_updated.emit(summary)
	return summary


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
