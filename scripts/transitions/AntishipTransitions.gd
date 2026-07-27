class_name AntishipTransitions
extends RefCounted

## THE mutation authority for the Green anti-ship establishment (plan 0043) — the exact and only
## production writer of AntishipSystem's protected fields and of the anti-ship arrays GameStateData
## hosts. Living in scripts/transitions/ grants nothing by itself: authority is granted to this exact
## file by name in tools/mutation_authority_manifest.json, which is also the only home for the field
## and writer lists. Do not copy them here.
##
## The shape every operation follows: a CALCULATOR returns a typed outcome, the coordinator
## (FiresPhases) hands that outcome to one job-shaped method here, and only this file turns it into
## state. Nothing here rolls dice, reads an autoload, or decides policy — if a change needs a
## judgement call, it belongs in the calculator that produced the outcome.
##
## Every method refuses a request it cannot make sense of rather than absorbing it quietly: an unknown
## (TO, type) key, a self-inconsistent outcome row, cumulative losses moving backwards or past the
## establishment, and the same crossing applied twice all `push_error` and change nothing. They do NOT
## `assert(false)`: a research batch should not die on one bad row, and — more usefully — a guard that
## only push_errors can be exercised by a test (`assert_error(...).is_push_error(...)`), which is how
## tests/transitions/antiship_establishment_test.gd pins each of them.
##
## The one thing that is clamped rather than rejected is the SUM of the two loss categories, which may
## exceed the establishment by double-counting — see AntishipSystem's header for why.
##
## What holds the boundary is a SOURCE gate (tools/validate_mutation_authority.gd), not the runtime:
## GDScript has no readonly, so nothing stops `system.quantity = 0` being typed somewhere else — it
## is caught when the gate runs, by resolving the receiver's type. That is the enforcement this
## design has, and it is why the projections are recomputed here in one place rather than assigned
## by whoever happens to know the arithmetic.


# ── Establishment lifecycle ─────────────────────────────────────────────────────────────────────

## Build the persistent arsenal on first use. Both views come from one build so the firing rows and
## the container-level IJFS targets can never describe different arsenals.
static func ensure_establishment(state: GameStateData) -> void:
	if state._antiship_built:
		return
	var built := AntishipSystemsBuilder.build()
	state.antiship_systems = built["systems"]
	state.antiship_containers = built["containers"]
	state._antiship_built = true


## Drop the arsenal so the next use rebuilds it from the (possibly changed) scenario.
static func reset_establishment(state: GameStateData) -> void:
	state.antiship_systems = []
	state.antiship_containers = []
	state._antiship_built = false
	state._antiship_launch_turn = -1


# ── IJFS effects ────────────────────────────────────────────────────────────────────────────────

## Apply the IJFS writeback to the establishment. `antiship_destroyed_by_type` is CUMULATIVE across
## every IJFS day (see the IjfsResolver writeback invariant), so a reported total is ASSIGNED to this
## row's IJFS total, never added — re-reporting the same kills on a later crossing must not kill twice.
##
## An ABSENT key means "no report for this row", NOT "zero kills": the writeback only carries rows the
## IJFS actually destroyed, so a row it has never touched has no entry at all. Reading absence as zero
## would resurrect every launcher the moment a turn resolved without an IJFS writeback — the same class
## of bug this plan removed, arriving by the back door.
##
## The launch-attrition total is a separate field and is deliberately untouched here. Overwriting one
## total with the other is exactly the resurrection this plan removed. Suppression is the opposite kind
## of number: it describes THIS IJFS cycle only, so it is replaced outright and never becomes a loss.
static func apply_ijfs_effects(systems: Array, writeback: IjfsWriteback) -> void:
	if writeback == null:
		return
	var ijfs_destroyed: Dictionary = writeback.antiship_destroyed_by_type
	var ijfs_suppressed: Dictionary = writeback.antiship_suppressed_by_type
	for system_value in systems:
		var system: AntishipSystem = system_value
		var key := AntishipCalculator.encode_key(system.to_number, system.type_id)
		if ijfs_destroyed.has(key):
			system.ijfs_destroyed_cumulative = _cumulative(
				system, "IJFS", system.ijfs_destroyed_cumulative, int(ijfs_destroyed[key]))
		system.suppressed_now = maxi(0, int(ijfs_suppressed.get(key, 0)))
		_reproject(system)


# ── Launch attrition ────────────────────────────────────────────────────────────────────────────

## Book one crossing's launch-attrition outcomes onto the establishment, exactly once. The crossing
## is identified by the turn: at most one crossing resolves per turn, so re-applying the same turn's
## outcomes is a double-kill and is refused rather than silently absorbed.
##
## Only reported DESTRUCTION reduces the establishment. Having attempted to fire does not: a launcher
## that shot and lived is on the line again next crossing, which is what separates TIV's
## moved/unavailable bookkeeping from a permanent loss.
## It is ALL-OR-NOTHING: every outcome is matched to a row and checked before any of them is booked,
## so a bad row cannot leave the arsenal half-updated with the crossing still marked unapplied.
static func apply_launch_attrition(state: GameStateData, outcomes: Array) -> void:
	if state._antiship_launch_turn == state.turn_number:
		push_error("AntishipTransitions: launch attrition for turn %d already applied" % state.turn_number)
		return
	var rows := _rows_for(state.antiship_systems, outcomes)
	if rows.size() != outcomes.size():
		return
	for index in range(outcomes.size()):
		var outcome: AntishipLaunchOutcome = outcomes[index]
		var system: AntishipSystem = rows[index]
		system.active = true
		system.fired += outcome.launched
		system.destroyed_this_turn += outcome.destroyed_total()
		system.launch_destroyed_cumulative = _cumulative(
			system, "launch", system.launch_destroyed_cumulative,
			system.launch_destroyed_cumulative + outcome.destroyed_total())
		_reproject(system)
	state._antiship_launch_turn = state.turn_number


# ── End of turn ─────────────────────────────────────────────────────────────────────────────────

## Clear the per-turn crossing flags. Returns how many rows were reset (the cleanup summary reports
## it, and a zero count is how a scenario with no arsenal is distinguished from a phase that failed
## to run). The cumulative loss fields are deliberately untouched.
static func reset_transient_flags(systems: Array) -> int:
	var reset_count := 0
	for system_value in systems:
		var system: AntishipSystem = system_value
		system.fired = 0
		system.destroyed_this_turn = 0
		system.suppressed_now = 0
		system.active = false
		reset_count += 1
	return reset_count


# ── Helpers ─────────────────────────────────────────────────────────────────────────────────────

## The new value of one cumulative loss total, bounded by the establishment. `floor_value` is the
## total it may not fall below — a campaign count that moves BACKWARD means its source recomputed
## history, which would silently resurrect launchers, so it fails loudly rather than being accepted.
static func _cumulative(
		system: AntishipSystem, source: String, floor_value: int, proposed: int) -> int:
	if proposed < floor_value:
		push_error("AntishipTransitions: %s losses for %d:%d moved backwards, %d -> %d" % [
			source, system.to_number, system.type_id, floor_value, proposed])
		return floor_value
	if proposed > system.original_quantity:
		push_error("AntishipTransitions: %s losses for %d:%d exceed the establishment, %d of %d" % [
			source, system.to_number, system.type_id, proposed, system.original_quantity])
		return system.original_quantity
	return proposed


## Recompute the two projections from the establishment and the two loss totals, then check the row
## against its own definition of consistency. Every campaign write ends here, so there is exactly one
## place where `destroyed` and `quantity` are decided.
##
## The consistency check cannot fail on any path that exists today — `_cumulative` has just bounded
## whichever total changed, and the two projections are assigned on the lines above. It is kept
## because it guards the NEXT campaign write added to this file: a new operation that sets a
## cumulative total without going through `_cumulative` fails here instead of shipping a quietly
## impossible arsenal.
static func _reproject(system: AntishipSystem) -> void:
	system.destroyed = system.projected_destroyed()
	system.quantity = system.projected_quantity()
	var problem := system.establishment_error()
	if problem != "":
		push_error("AntishipTransitions: establishment invariant broken for %d:%d — %s" % [
			system.to_number, system.type_id, problem])


## The rows the outcomes name, in the same order, or a SHORT array if any outcome is unusable — the
## caller treats a short result as "apply nothing". An outcome naming a row that does not exist means
## the calculator and the establishment have drifted apart, which would otherwise surface much later
## as a quietly missing loss.
static func _rows_for(systems: Array, outcomes: Array) -> Array[AntishipSystem]:
	var by_key: Dictionary = {}
	for system_value in systems:
		var system: AntishipSystem = system_value
		by_key[AntishipCalculator.encode_key(system.to_number, system.type_id)] = system
	var rows: Array[AntishipSystem] = []
	for outcome_value in outcomes:
		var outcome: AntishipLaunchOutcome = outcome_value
		var problem := outcome.consistency_error()
		if problem != "":
			push_error("AntishipTransitions: refusing the whole crossing — %s" % problem)
			return []
		var key := AntishipCalculator.encode_key(outcome.to_number, outcome.type_id)
		if not by_key.has(key):
			push_error("AntishipTransitions: refusing the whole crossing — launch outcome names unknown anti-ship row %s" % key)
			return []
		rows.append(by_key[key])
	return rows
