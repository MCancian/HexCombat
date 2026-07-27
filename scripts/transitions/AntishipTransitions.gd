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
## (TO, type) key, a self-inconsistent outcome row, and the same crossing applied twice all
## `push_error` and change nothing. They do NOT `assert(false)`: a research batch should not die on one
## bad row, and a guard that only push_errors can be exercised by a test.
##
## NOTE (plan 0043 step 3): apply_ijfs_effects and apply_launch_attrition below carry the PRE-FIX
## arithmetic verbatim — surviving quantity is still rebuilt from the IJFS total alone, so launch
## losses are still erased at the next crossing. That is deliberate: this commit moves the writes
## WITHOUT changing a single result, which is what makes the gate's byte-stability meaningful. The
## next commit replaces both bodies with the cumulative model the fields already describe.
##
## What holds the boundary is a SOURCE gate (tools/validate_mutation_authority.gd), not the runtime:
## GDScript has no readonly, so nothing stops `system.quantity = 0` being typed somewhere else — it
## is caught when the gate runs, by resolving the receiver's type. That is the enforcement this
## design has, and it is why every write to those rows is funnelled through this one file.


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
## every IJFS day (see the IjfsResolver writeback invariant), so surviving quantity is rebuilt from
## `original_quantity` and is idempotent across turns.
static func apply_ijfs_effects(systems: Array, writeback: IjfsWriteback) -> void:
	var ijfs_destroyed: Dictionary = writeback.antiship_destroyed_by_type if writeback != null else {}
	for system_value in systems:
		var system: AntishipSystem = system_value
		var key := AntishipCalculator.encode_key(system.to_number, system.type_id)
		var killed := int(ijfs_destroyed.get(key, 0))
		system.quantity = maxi(0, system.original_quantity - killed)
		system.destroyed = killed


# ── Launch attrition ────────────────────────────────────────────────────────────────────────────

## Book one crossing's launch-attrition outcomes onto the establishment, exactly once. The crossing is
## identified by the turn: at most one crossing resolves per turn, so re-applying the same turn's
## outcomes is a double-kill and is refused rather than silently absorbed.
##
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
		system.quantity = maxi(0, system.quantity - outcome.attempted)
		system.fired += outcome.launched
		system.expended += outcome.launched
		system.destroyed_this_turn += outcome.destroyed_total()
		system.destroyed += outcome.destroyed_total()
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
		system.expended = 0
		system.destroyed_this_turn = 0
		system.suppressed = false
		system.active = false
		reset_count += 1
	return reset_count


# ── Helpers ─────────────────────────────────────────────────────────────────────────────────────

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
