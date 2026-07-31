class_name TurnLifecycleTransitions
extends RefCounted

## THE mutation authority for the `turn_lifecycle` aggregate (plan 0049). Living in
## scripts/transitions/ grants nothing by itself: authority is granted to this exact file by name in
## tools/mutation_authority_manifest.json, the only home for the protected-field and writer lists.
##
## Where the game IS: the turn counter, the phase, and the three victory latches the end-of-turn
## census sets together.
##
## **AN ARBITRARY PHASE ASSIGNMENT IS INEXPRESSIBLE.** There is no `set_phase`, no `set_turn_number`,
## no `set_winner` — the only phase operations are the three legal EDGES of the cycle
## (PLANNING → RESOLUTION → END → PLANNING), each named for what it does and each refusing to run from
## the wrong source phase without touching anything. So an illegal DESTINATION cannot be written at
## all, and an illegal SOURCE is refused; the two are different guarantees and only the first is
## absence. Compare `MapTransitions`, which has no owner setter because ownership is derived.
##
## **NO HELPER HERE TAKES A DESTINATION PHASE, AND THAT IS DELIBERATE.** The first draft factored the
## three edges through a private `_advance(state, from, to, label)`. Diff review killed it: a GDScript
## underscore is a naming convention, not access control, so `_advance(state, state.phase, ANY, "x")`
## was callable from anywhere in the project — and the mutation gate would have seen a perfectly
## authorized write, because the assignment lives in this file. "Private" is not a boundary here. Each
## edge now writes its own destination as a LITERAL at exactly one site, and the shared helper is
## read-only. Every destination in this file is greppable and there are exactly four.
##
## It decides no phase ORDER: `TurnConductor.resolve_turn` still holds the ordered call list and asks
## for the two edges around it. It calls no other authority either — cross-authority orchestration is
## the coordinator's job (`AGENTS.md`: "a coordinator may call two authorities; it writes neither's
## fields itself"), which is why `GameState.begin_next_turn` clears the order buffers itself rather
## than this file reaching into `OrderTransitions`.
##
## Nothing here consumes or derives Dice, and nothing here calculates: it applies decisions already
## made. Guards `push_error` and change nothing rather than `assert(false)`, so a research batch does
## not die on one bad call and a test can exercise the refusal.


# ── The turn cycle ──────────────────────────────────────────────────────────────────────────────

## PLANNING → RESOLUTION. Reports whether the edge was legal so the caller can abandon the turn.
static func begin_resolution(state: GameStateData) -> bool:
	if not _refuse_unless_in(state, GameStateData.Phase.PLANNING, "resolve turn"):
		return false
	state.phase = GameStateData.Phase.RESOLUTION
	return true


## RESOLUTION → END.
static func end_resolution(state: GameStateData) -> bool:
	if not _refuse_unless_in(state, GameStateData.Phase.RESOLUTION, "end turn"):
		return false
	state.phase = GameStateData.Phase.END
	return true


## END → PLANNING, advancing the turn counter. This is the ONLY place the counter moves, which is what
## makes "the turn increments exactly once per cycle" a property of the code rather than a convention:
## no other operation here touches it, and no setter exists to do it from outside.
static func begin_next_turn(state: GameStateData) -> bool:
	if not _refuse_unless_in(state, GameStateData.Phase.END, "begin next turn"):
		return false
	state.phase = GameStateData.Phase.PLANNING
	state.turn_number += 1
	return true


## Scenario reset: back to turn 1, PLANNING, and all three victory latches disarmed. Unlike the three
## edges this is legal from ANY phase — it is not a move within a game, it is the start of a new one.
static func reset_to_turn_one(state: GameStateData) -> void:
	state.turn_number = 1
	state.phase = GameStateData.Phase.PLANNING
	state.game_over = false
	state.winner = ""
	state._china_has_landed = false


## READ-ONLY source-phase check shared by the three edges. It reports; it never writes. Keeping it
## write-free is what stops it becoming the destination-taking back door the first draft shipped.
static func _refuse_unless_in(
	state: GameStateData, required_phase: GameStateData.Phase, what: String
) -> bool:
	if state.phase != required_phase:
		push_error("Cannot %s outside %s phase" % [what, _phase_name(required_phase)])
		return false
	return true


static func _phase_name(phase: GameStateData.Phase) -> String:
	match phase:
		GameStateData.Phase.PLANNING:
			return "PLANNING"
		GameStateData.Phase.RESOLUTION:
			return "RESOLUTION"
	return "END"


# ── The victory latches ─────────────────────────────────────────────────────────────────────────

## Apply the end-of-turn census verdict: all three latches, from ONE receipt.
##
## Every value is READ OFF the summary rather than accepted as a separate argument — including the
## landing latch, which is derived from `china_battalions_on_taiwan` rather than passed in. That is
## what makes "the three latches agree with each other and with the census that produced them" true by
## construction: there is no pair of arguments that could disagree (procedure doc §6).
##
## `_china_has_landed` is set with `or`, never assigned. Once Red has put a battalion ashore the
## "after_first_landing" loss-check arm is armed for the rest of the campaign, so a later turn holding
## nothing ashore must not disarm it — and with an `or` there is no way to express disarming it short
## of a scenario reset. `CleanupResolver` computes its own copy for `VictoryConditions.evaluate`; that
## copy is report-only, and `turn_lifecycle_transitions_test.gd` pins that the two agree.
static func apply_cleanup_verdict(state: GameStateData, summary: CleanupSummary) -> void:
	if summary == null:
		push_error("TurnLifecycleTransitions.apply_cleanup_verdict: no cleanup summary")
		return
	state._china_has_landed = state._china_has_landed or summary.china_battalions_on_taiwan > 0
	state.game_over = summary.game_over
	state.winner = summary.winner
