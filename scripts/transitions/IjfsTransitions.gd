class_name IjfsTransitions
extends RefCounted

## THE mutation authority for persistent IJFS campaign state (plan 0046) — the exact and only
## production writer of `IjfsTarget` / `IjfsMunition` / `IjfsSquadron`, of the three containers
## `IjfsDailyState` carries across days, and of the IJFS handles `GameStateData` hosts. Living in
## scripts/transitions/ grants nothing by itself: authority is granted to this exact file by name in
## tools/mutation_authority_manifest.json, which is also the only home for the field and writer
## lists. Do not copy them here.
##
## WHY THIS ONE LOOKS DIFFERENT FROM AntishipTransitions. There, a calculator returns a typed outcome
## and the phase coordinator hands it over — one call per phase, at the end. IJFS cannot work that
## way: its six stages consume dice CONDITIONALLY on state an earlier stage just wrote, and later
## target selection reads that state (IjfsTargeting.targets_to_attack filters on `destroyed` and
## `detected_this_turn`; IjfsManpads sorts on ready stock). Deferring application to end-of-day would
## change which targets are iterated and therefore how many draws are consumed — the one thing this
## plan may not do. So the stages call in here at the exact point they used to assign, and what the
## authority buys is a named, checked, single-file boundary rather than a deferred one.
##
## Guards `push_error` and change nothing rather than `assert(false)`: a research batch should not die
## on one bad row, and a guard that only push_errors can be exercised by a test
## (`assert_error(...).is_push_error(...)`), which is how tests/transitions/ijfs_transitions_test.gd
## pins each of them.


# ── Munition inventory ──────────────────────────────────────────────────────────────────────────

## Spend `rounds` from a munition, or refuse. Returns false when the magazine cannot cover the
## engagement, which is NORMAL — it is how a strike is skipped, not an error.
##
## Both callers reach here at their existing point: IjfsStrike for a delivered strike, and IjfsEngine
## for a round MANPADS intercepted (spent, delivers nothing). Organic munitions never come here —
## strike aircraft draw from a sortie budget, not a magazine.
##
## Insufficiency is unreachable through the engine today, because selection already refuses an
## unaffordable pairing (IjfsTargeting._rule_affordable) and nothing decrements between selection and
## here. It is still checked and still tested directly: the day a selection path stops checking, this
## is what stands between that and a negative magazine.
static func consume_munition(munition: IjfsMunition, rounds: int) -> bool:
	if munition == null:
		push_error("IjfsTransitions: consume_munition called with no munition")
		return false
	if rounds < 0:
		push_error("IjfsTransitions: refusing a negative consumption of %d rounds of %s" % [
			rounds, munition.munition_id])
		return false
	if munition.inventory_remaining < rounds:
		return false
	munition.inventory_remaining -= rounds
	return true


# ── Target lifecycle ────────────────────────────────────────────────────────────────────────────
#
# There is deliberately NO method anywhere in this file that clears `destroyed`. Monotonic
# destruction is not enforced by a guard that could be argued with — it is enforced by the absence of
# a way to express it. Suppression resets (carry_to_next_day) and detection passes leave it alone.


## Stamp one detection pass onto every target. Both passes (satellite, then aircraft) call this, and
## the second overwrites the first — a target detected only by satellite and missed by aircraft ends
## the day undetected, which is the ported behaviour.
##
## A destroyed target is force-forgotten rather than skipped: it cannot be detected, and leaving
## `known_to_red` set would keep feeding a dead row to the targeting stage.
static func apply_detection_results(
		targets: Array[IjfsTarget], detected_ids: Array, current_day: int) -> void:
	for target in targets:
		target.detected_this_turn = false
		if target.destroyed:
			target.known_to_red = false
			continue
		var detected: bool = detected_ids.has(target.target_id)
		target.detected_this_turn = detected
		target.known_to_red = detected
		if detected:
			target.last_detected_day = current_day


## Warmup posture override: during the prelanding campaign the scenario can declare that everything
## mobile presents one posture. Static targets are exempt — their posture is a property of the site.
static func apply_warmup_posture_override(targets: Array[IjfsTarget], posture: String) -> void:
	for target in targets:
		if not target.destroyed and target.mobility != "static":
			target.posture = posture


## A maneuver unit that moved or fought recently presents an "active" posture and is easier to see.
static func apply_activity_posture(target: IjfsTarget, is_active: bool) -> void:
	target.posture = "active" if is_active else "hiding"


## Exquisite intel: this target is now permanently located, so detection stops rolling for it.
static func mark_intel_locked(target: IjfsTarget) -> void:
	target.intel_locked = true


## Retire a maneuver target whose battalion is gone from the OOB. Modelled as destruction because
## that is what it is from the fires model's point of view, and because destruction is the one target
## state that survives every reset — the row will not come back next day.
static func retire_target(target: IjfsTarget) -> void:
	target.destroyed = true


## A strike destroyed this target. Suppression is cleared because a destroyed row is not "suppressed
## as well", and Red loses track of it.
static func apply_strike_destruction(target: IjfsTarget) -> void:
	target.destroyed = true
	target.known_to_red = false
	target.suppressed = false
	target.suppressed_this_turn = false


## A strike missed but suppressed. Both flags are set: one is read within the day, one carries to the
## next day's carry-over.
static func apply_strike_suppression(target: IjfsTarget) -> void:
	target.suppressed = true
	target.suppressed_this_turn = true


## Every live SAM starts the SEAD stage unengaged, so a SAM that SEAD never reaches reports that
## rather than keeping yesterday's verdict.
static func mark_sead_unengaged(target: IjfsTarget) -> void:
	target.sead_result = "unengaged"


## SEAD destroyed a SAM. Unlike a strike kill this also clears `detected_this_turn`: SEAD resolves
## between the two detection passes, and a destroyed row must not be carried into the second one as
## a live detection.
static func apply_sead_destruction(target: IjfsTarget) -> void:
	target.destroyed = true
	target.suppressed = false
	target.suppressed_this_turn = false
	target.detected_this_turn = false
	target.known_to_red = false
	target.sead_result = "destroyed"


static func apply_sead_suppression(target: IjfsTarget) -> void:
	target.suppressed = true
	target.suppressed_this_turn = true
	target.sead_result = "suppressed"


## MANPADS stock for one bin, with `metadata["systems_remaining"]` kept in step. The mirror exists
## because `metadata` is aliased LIVE into the strike, detection and target-status ledger rows, so
## the key has to keep appearing there; the typed field is what the mutation gate can actually see.
## Read the field, never the mirror.
static func set_manpads_remaining(target: IjfsTarget, value: int) -> void:
	if value < 0:
		push_error("IjfsTransitions: refusing a negative MANPADS stock (%d) for %s" % [
			value, target.target_id])
		return
	target.manpads_remaining = value
	target.metadata["systems_remaining"] = value


## Roll the persistent target state into the next day: suppression is temporary and the SEAD verdict
## belongs to the day that produced it. Destruction, detection continuity (known_to_red /
## last_detected_day), munition inventory and squadron STRENGTH all carry forward untouched — an
## airframe lost yesterday is still lost.
##
## What does NOT carry is each squadron's per-day loss COUNT (added 2026-08-01). This runs at the head
## of every day, before run_daily accumulates, which is what makes losses_today mean "today" in the
## ledger built at the end of that day. losses_campaign is deliberately not touched. The first warmup
## day never reaches here (IjfsResolver guards it with `i > 0`) and does not need to: the loader has
## already zeroed both counters.
##
## The two AVAILABILITY ledgers reset here for the same reason (plan 0060 R8/R11): an airframe driven
## home by a MANPADS abort, or booked to yesterday's SEAD package, flies again today. Leaving either
## set would silently retire the whole air force over a campaign.
static func carry_to_next_day(daily_state: IjfsDailyState) -> void:
	for target in daily_state.targets:
		target.suppressed = false
		target.suppressed_this_turn = false
		target.sead_result = ""
	if daily_state.squadron_force != null:
		for squadron: IjfsSquadron in (daily_state.squadron_force as Array):
			squadron.losses_today = 0
			squadron.rtb_today = 0
			squadron.sead_assigned_today = 0


# ── Squadron strength ───────────────────────────────────────────────────────────────────────────

## Book aircraft losses on one squadron. Every attrition source lands here: SAM return fire, the
## post-phase-2 free shot, and the MANPADS engagement against a four-airframe package.
##
## Books the loss twice, into two fields with two different lifetimes (USER call 2026-08-01): a per-day
## `losses_today`, reset by carry_to_next_day at the head of each day, and a `losses_campaign` running
## total that nothing resets. Before that call `losses_today` alone existed and was campaign-cumulative
## despite its name — a daily-looking number in the air_oob_after ledger that reported the whole
## campaign. Reporting both was preferred to renaming, so an OOB read shows current damage and
## accumulated wear at once. Before 2026-08-01 `losses_today` alone existed and was campaign-cumulative
## despite its name. All four counters are pinned by tests/ijfs/ijfs_authority_characterization_test.gd.
static func apply_squadron_losses(squadron: IjfsSquadron, losses: int) -> void:
	if squadron == null:
		push_error("IjfsTransitions: apply_squadron_losses called with no squadron")
		return
	if losses <= 0:
		return
	if losses > squadron.alive:
		push_error("IjfsTransitions: %s lost %d of only %d alive airframes" % [
			squadron.squadron_id, losses, squadron.alive])
		return
	squadron.alive -= losses
	squadron.losses_today += losses
	squadron.losses_campaign += losses


## Send airframes home for the rest of the day, alive. MANPADS aborting a package is the only writer
## (plan 0059 step 2, folded into plan 0060 R5): the aircraft was driven off, not shot down, so it
## costs Red today's sortie and nothing more.
##
## Bounded against `available_today()` rather than `alive`, which is what makes an airframe unable to
## be booked home twice, or booked home while it is assigned to the SEAD package. An aircraft can
## never be both RTB and killed, because a MANPADS engagement produces exactly one outcome.
static func book_rtb(squadron: IjfsSquadron, count: int) -> void:
	if squadron == null:
		push_error("IjfsTransitions: book_rtb called with no squadron")
		return
	if count <= 0:
		return
	if count > squadron.available_today():
		push_error("IjfsTransitions: %s sent %d home with only %d available today" % [
			squadron.squadron_id, count, squadron.available_today()])
		return
	squadron.rtb_today += count


## Book airframes to today's SEAD package (plan 0060 R11 stage C). They leave the Organic strike pool
## for the day but stay exposed to SAM return fire, so this is an availability transfer and not a loss.
static func assign_to_sead(squadron: IjfsSquadron, count: int) -> void:
	if squadron == null:
		push_error("IjfsTransitions: assign_to_sead called with no squadron")
		return
	if count <= 0:
		return
	if count > squadron.available_today():
		push_error("IjfsTransitions: %s assigned %d to SEAD with only %d available today" % [
			squadron.squadron_id, count, squadron.available_today()])
		return
	squadron.sead_assigned_today += count


# ── Daily-state lifecycle ───────────────────────────────────────────────────────────────────────

## Publish a freshly built IjfsDailyState and start its day count. `_ijfs_day` 0 means "the warmup
## has not run yet", which is what makes the FIRST IJFS of a game the multi-day prelanding campaign
## rather than one plain day — so installing a state and zeroing the counter is a single transition
## and must not be separable.
static func install_daily_state(state: GameStateData, built: IjfsDailyState) -> void:
	if built == null:
		push_error("IjfsTransitions: refusing to install a null IJFS daily state")
		return
	state.ijfs_state = built
	state._ijfs_day = 0


## Drop the IJFS state so the next resolve rebuilds it from the (possibly changed) scenario. The
## build is deliberately lazy — it pulls ~500KB of pairings and many Resource objects, and
## eager-loading it in every booted process triggered the Godot 4.7 teardown crash.
static func reset_daily_state(state: GameStateData) -> void:
	state.ijfs_state = null
	state._ijfs_day = 0


## Record which turn the IJFS last resolved on. Monotonic: turns do not run backwards, and a day
## count that moved backwards would re-run the prelanding warmup mid-campaign.
static func advance_day(state: GameStateData, turn_number: int) -> void:
	if turn_number < state._ijfs_day:
		push_error("IjfsTransitions: IJFS day moved backwards, %d -> %d" % [
			state._ijfs_day, turn_number])
		return
	state._ijfs_day = turn_number


## Append targets for formations that have just come onto the map. APPEND-ONLY, because the existing
## rows keep their list positions and their detection continuity (known_to_red / last_detected_day),
## and the maneuver sync only ever retires excess targets, so the new rows survive it.
static func add_targets(daily_state: IjfsDailyState, new_targets: Array[IjfsTarget]) -> int:
	if daily_state == null or new_targets.is_empty():
		return 0
	var known: Dictionary = {}
	for existing in daily_state.targets:
		known[existing.target_id] = true
	for candidate in new_targets:
		if known.has(candidate.target_id):
			push_error("IjfsTransitions: refusing the whole batch — duplicate target id '%s'" % candidate.target_id)
			return 0
	daily_state.targets.append_array(new_targets)
	return new_targets.size()
