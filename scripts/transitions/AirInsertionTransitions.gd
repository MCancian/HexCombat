class_name AirInsertionTransitions
extends RefCounted

## THE mutation authority for the `air_insertion` aggregate (plan 0048): the PLAAF's per-lift-class
## lift budget and its append-only insertion log. Living in scripts/transitions/ grants nothing by
## itself — authority is granted to this exact file by name in
## tools/mutation_authority_manifest.json, the only home for the protected-field and writer lists.
##
## **This authority never moves a battalion.** `AirInsertionState.pool` and `.landed` belong to the
## force aggregate (plan 0044) and `ForceTransitions` stays their only writer: one model, two
## authorities, split by disjoint fields, exactly as `SealiftCohort` splits troops from hulls. What is
## owned here is what the lift COST and what the drop recorded — never who is where.
##
## **There is no way to give lift back, and no input that expresses one.** Every battalion the air
## defences kill destroys the airframe that carried it, so a cap only ever falls. That is not a guard
## here: `record_insertions` DERIVES the new budget by subtracting each packet's losses, so a higher
## cap cannot be asked for. Same technique as `IjfsTransitions`' monotonic destruction and
## `MapTransitions`' missing owner setter — an invariant no caller can express needs no guard a later
## reader can argue with. `initial_caps` has no runtime writer at all, so the `0 <= caps <=
## initial_caps` ceiling cannot move either.
##
## **There is no way to clear or rewrite the log.** The only expressible operation appends this turn's
## drops, so `history` is append-only by construction rather than by convention.
##
## Guards `push_error` and change NOTHING rather than asserting: a research batch of hundreds of games
## must not die on one malformed row, and a `push_error` guard is testable.

## The keys a drop row must carry for the ledger to read it. Checked before anything is written, so
## `record_insertions` can stage its whole result without a row raising part-way through.
const REQUIRED_DROP_KEYS: Array[String] = ["brigade_id", "lift_class", "hex_id", "landed", "lost"]


# ── Scenario lifecycle ──────────────────────────────────────────────────────────────────────────

## Install the air-insertion state a scenario reset produces. The state is BUILT here rather than
## accepted from the caller on purpose: there is then no seam through which anyone can hand this
## aggregate a state carrying caps it did not derive from scenario content. Same shape and same
## reason as `InfrastructureTransitions.rebuild_infrastructure`, so the host file earns no writer
## exemption.
static func rebuild_air_insertion_state(
		state: GameStateData, config: Dictionary, brigades: Dictionary) -> void:
	state.air_insertion_state = AirInsertionStateBuilder.build(config, brigades)


# ── The turn's lift accounting ──────────────────────────────────────────────────────────────────

## The typed request for `record_insertions`, from the resolver's drop rows. The factory lives HERE,
## not on the caller, so a coordinator never has to name `AirLiftRequest` — which is what keeps
## `ReinforcementPhases` at its dependency ceiling. Same reason `ForceTransitions` carries
## `ground_combat_casualty_request` and `ijfs_casualty_request`.
static func lift_request(turn_number: int, drops: Array) -> AirLiftRequest:
	return AirLiftRequest.from_drops(turn_number, drops)


## Whether `record_insertions` would accept this request, asked BEFORE anything is written.
##
## This exists because the force authority commits FIRST: by the time the lift ledger is applied,
## `ForceTransitions.apply_air_insertion_outcome` has already drained the pool, applied roster losses,
## placed brigades and appended to `landed`, and none of that can be rolled back. A refusal at that
## point would leave the roster moved and the lift unspent. So the coordinator asks this first, and a
## `false` means nothing anywhere has changed yet.
static func can_record_insertions(air_state: AirInsertionState, request: AirLiftRequest) -> bool:
	if air_state == null or request == null:
		push_error("AirInsertionTransitions: null air-insertion state or lift request")
		return false
	return _drops_are_legal(air_state, request.drops)


## Record one resolved air-insertion phase: the airframes its packets cost, and the log rows they
## produced, applied together as one job.
##
## The new budget is DERIVED here — for each packet, in resolution order,
## `caps[lift_class] = max(0, caps[lift_class] - lost)` — the identical arithmetic
## `AirInsertionResolver._resolve_order` used while flying them. The resolver's own `caps_after` is
## report-only and is deliberately not consumed: erosion and log are computed from one array, so they
## cannot drift apart, and no caller can assert a budget that no packet paid for.
## BOTH results are staged in locals before either is written. Appending the log while walking the
## rows would let a malformed row raise AFTER the budget had already been assigned, leaving the caps
## eroded and the log missing — the exact partial write this authority exists to prevent. The
## validation below is what makes staging safe to complete; the two assignments at the end cannot
## fail in between.
static func record_insertions(air_state: AirInsertionState, request: AirLiftRequest) -> void:
	if not can_record_insertions(air_state, request):
		return

	var eroded: Dictionary = air_state.caps.duplicate()
	var rows: Array = []
	for drop_value in request.drops:
		var drop: Dictionary = drop_value
		var lift_class := String(drop["lift_class"])
		eroded[lift_class] = maxi(0, int(eroded[lift_class]) - int(drop["lost"]))
		rows.append({
			"turn": request.turn_number,
			"brigade_id": String(drop["brigade_id"]),
			"lift_class": lift_class,
			"hex_id": String(drop["hex_id"]),
			"landed": int(drop["landed"]),
			"lost": int(drop["lost"]),
		})

	air_state.caps = eroded
	air_state.history.append_array(rows)


## Every drop must carry the keys the ledger reads, name a lift class this state actually budgets
## for, and report non-negative counts. A class the state does not know is refused rather than
## created: a budget key that appears mid-game reads in the observation as new lift arriving from
## nowhere. The key check is not defensive noise — it is what lets `record_insertions` stage the whole
## result knowing no row can raise halfway through.
static func _drops_are_legal(air_state: AirInsertionState, drops: Array) -> bool:
	for drop_value in drops:
		var drop: Dictionary = drop_value
		for key in REQUIRED_DROP_KEYS:
			if not drop.has(key):
				push_error("AirInsertionTransitions: drop is missing '%s': %s" % [key, drop])
				return false
		var lift_class := String(drop["lift_class"])
		if not LiftClass.is_known(lift_class):
			push_error("AirInsertionTransitions: drop names unknown lift class '%s'" % lift_class)
			return false
		if not air_state.caps.has(lift_class):
			push_error("AirInsertionTransitions: drop names lift class '%s', which this state does not budget for" % lift_class)
			return false
		if int(drop["lost"]) < 0 or int(drop["landed"]) < 0:
			push_error("AirInsertionTransitions: drop for %s reports negative counts (landed %d, lost %d)" % [
				String(drop["brigade_id"]), int(drop["landed"]), int(drop["lost"])])
			return false
	return true
