class_name SealiftTransitions
extends RefCounted

## THE mutation authority for the sealift/fleet aggregate (plan 0045) — the exact and only production
## writer of the `ShipState` fleet projection and of the persistent hull queues `SealiftState` holds.
## Living in scripts/transitions/ grants nothing by itself: authority is granted to this exact file by
## name in tools/mutation_authority_manifest.json, which is also the only home for the field and writer
## lists. Do not copy them here.
##
## The division of labour with the FORCE authority (ForceTransitions, plan 0044) is the thing to
## understand before touching either file. A cohort binds TROOPS to HULLS, so the two authorities share
## the object and split it by field:
##
##   ForceTransitions owns  — who is aboard: cohort membership, `bn_ids`, `mainland_pool`,
##                            `ship_reserve`, and every roster consequence of a landing or a drowning.
##   SealiftTransitions owns — what floats: the hull counts inside a cohort, its sent/offloading state,
##                            the return/reload pipeline, escort magazines, and the ShipState bins.
##
## Operations that move both (embark, crossing loss, offload) are two authority calls in one
## coordinator, each preflighted before either writes, never one call that reaches across.
##
## The shape every operation follows is the AntishipTransitions shape: a CALCULATOR returns an outcome,
## the coordinator (FiresPhases / ReinforcementPhases) hands that outcome to one job-shaped method here,
## and only this file turns it into state. Nothing here rolls dice, reads an autoload, or decides
## policy — ship classification, packing order and kill counts all arrive as arguments.
##
## Every public method leaves the fleet in a state that satisfies its own invariants: the projection is
## recomputed and checked before the method returns, so there is no window in which `ShipState`'s
## conservation equation is knowingly false. That window is exactly what this plan removed — hull losses
## used to be booked in one module and repaired in another, and any new step inserted between them
## would have shipped an invalid fleet.
##
## `_check_queues` / `_check_fleet` report with `push_error` and change nothing (a research batch must
## not die on one bad row, and a push_error guard is exercisable by a test via
## `assert_error(...).is_push_error(...)`). The two `assert`s inside `project_fleet` are deliberately NOT
## converted: they are the pre-0045 contract for an impossible projection, and only an assert turns such
## a state into a hard gate failure — `push_error` alone prints and continues.
##
## Two kinds of operation live here, and the difference is what each one promises:
##
##   * Operations that change HOW MANY hulls survive (`apply_hull_losses`) reproject the fleet before
##     returning. This is the window plan 0045 closed: booking a loss without reprojecting leaves
##     `ShipState`'s conservation equation false, and anything inserted after it would read an invalid
##     fleet.
##   * Operations that only change WHERE surviving hulls are (`tick_returns`, `tick_escort_reload`,
##     `apply_escort_consumption`, `release_hulls`) move them between sealift queues. `ShipState`'s
##     equation stays TRUE across those — its bins go STALE, not invalid — so they check the queues they
##     touched and leave the bins to the phase's closing `project_fleet`. Reprojecting inside each would
##     be four projections a turn to reach the same fleet.


# ── Fleet lifecycle ─────────────────────────────────────────────────────────────────────────────

## Replace the fleet with a fresh one built from the (possibly changed) scenario ship definitions.
## This is a scenario RESET of live state, not construction of unpublished state, which is why it
## routes through the authority instead of GameState assigning the builder's result itself.
static func rebuild_fleet(state: GameStateData, ship_defs: Dictionary) -> void:
	state.fleet = FleetBuilder.build(ship_defs)


## The ready hull count per type — the sailing capacity the embark planner packs against. Read here so
## coordinators never need to know that `ready` lives on a ShipState.
static func ready_by_type(state: GameStateData) -> Dictionary:
	var ready: Dictionary = {}
	for ship_type in state.fleet.keys():
		var ship_state: ShipState = state.fleet[ship_type]
		ready[String(ship_type)] = ship_state.ready
	return ready


# ── Return / reload pipeline ────────────────────────────────────────────────────────────────────

## Advance the return pipeline one turn: every slot's timer drops by one, and a slot that reaches zero
## releases its hulls. Returns {ship_type -> hulls released this turn} — the sealift phase adds those to
## the ready pool it packs the next wave against, which is why the release is REPORTED rather than
## written straight into the fleet: the hulls sail again the same turn they arrive back.
static func tick_returns(state: SealiftState) -> Dictionary:
	var returned: Dictionary = {}
	for ship_type in state.return_pipeline.keys():
		var kept: Array = []
		for slot_value in (state.return_pipeline[ship_type] as Array):
			var slot: Dictionary = slot_value
			var remaining := int(slot["turns_remaining"]) - 1
			if remaining <= 0:
				returned[String(ship_type)] = int(returned.get(String(ship_type), 0)) + int(slot["count"])
			else:
				slot["turns_remaining"] = remaining
				kept.append(slot)
		state.return_pipeline[ship_type] = kept
	# Drop emptied type buckets to keep to_dict() minimal.
	for ship_type in returned.keys():
		if (state.return_pipeline.get(ship_type, []) as Array).is_empty():
			state.return_pipeline.erase(ship_type)
	_check_queues(state)
	return returned


## Put the hulls of this turn's drained cohorts into the return pipeline. `return_time <= 0` means the
## scenario models no turnaround at all: the hulls are simply ready again, so nothing is queued and the
## projection finds them in `ready` on its next pass.
static func release_hulls(
		state: SealiftState, plan: SealiftHullReleasePlan, return_time: int) -> void:
	if return_time <= 0 or plan == null:
		return
	for batch_value in plan.batches:
		var batch: Dictionary = batch_value
		for ship_type_value in batch.keys():
			var count := int(batch[ship_type_value])
			if count <= 0:
				continue
			var ship_type := String(ship_type_value)
			if not state.return_pipeline.has(ship_type):
				state.return_pipeline[ship_type] = []
			(state.return_pipeline[ship_type] as Array).append({
				"count": count,
				"turns_remaining": return_time,
			})
	_check_queues(state)


# ── Escort SAM magazines ────────────────────────────────────────────────────────────────────────

## Deplete each escort type's SAM magazine by what it fired this crossing, then divert any type that
## dropped to/below its reload threshold into a reload for `reload_time` turns. No-op when the magazine
## is unmodelled (escort_sam empty — the pre-0004 unlimited-interception behavior) or reload_time <= 0.
##
## A type already reloading is skipped rather than restarted: it is not on the screen, so it fired
## nothing and its timer must not be extended by a crossing it sat out.
static func apply_escort_consumption(
		state: SealiftState, consumed: Dictionary, reload_time: int) -> void:
	for ship_type in consumed.keys():
		var st := String(ship_type)
		if state.escort_sam.has(st):
			state.escort_sam[st] = maxi(0, int(state.escort_sam[st]) - int(consumed[ship_type]))
	if reload_time <= 0:
		_check_queues(state)
		return
	for ship_type in state.escort_sam.keys():
		var st := String(ship_type)
		if state.escort_reload.has(st):
			continue
		if int(state.escort_sam[st]) <= int(state.escort_sam_threshold.get(st, 0)):
			state.escort_reload[st] = reload_time
	_check_queues(state)


## Advance escort reloads; a type whose timer hits 0 refills to its loadout max and rejoins the screen.
static func tick_escort_reload(state: SealiftState) -> void:
	var done: Array = []
	for ship_type in state.escort_reload.keys():
		var remaining := int(state.escort_reload[ship_type]) - 1
		if remaining <= 0:
			state.escort_sam[String(ship_type)] = int(state.escort_sam_max.get(
				String(ship_type), int(state.escort_sam.get(String(ship_type), 0))))
			done.append(ship_type)
		else:
			state.escort_reload[ship_type] = remaining
	for ship_type in done:
		state.escort_reload.erase(ship_type)
	_check_queues(state)


# ── Cohort legs ─────────────────────────────────────────────────────────────────────────────────

## After the crossing, every cohort still afloat is ashore-bound: flip it from sent to offloading. The
## battalions aboard have not moved — this is a statement about the SHIPPING, which is why it lives here
## and not with the force authority that owns the manifest.
static func apply_sent_to_offloading(state: SealiftState) -> void:
	if state == null:
		return
	for cohort in state.cohorts:
		if cohort.is_sent():
			cohort.cohort_state = SealiftState.STATE_OFFLOADING
	_check_queues(state)


# ── Crossing hull losses ────────────────────────────────────────────────────────────────────────

## Book one crossing's hull losses. `destroyed_by_type` is what the crossing calculator reported it
## killed; `ship_defs_by_name` classifies each type, because WHERE a hull dies is a property of the
## type: carriers are busy inside this turn's "sent" cohorts, escorts screen the wave out of the ready
## pool and are never bound to a cohort.
##
## Losses are CAPPED at what the source bucket actually holds and the cap is reported in the receipt
## (see SealiftHullLossReceipt for why a crossing can legitimately over-report). A type the fleet does
## not have, or a non-positive count, is skipped — the same tolerance the pre-0045 code had, since the
## calculator's report is keyed by whatever fired at whatever sailed.
##
## The projection is recomputed before returning, so the fleet is never left with `destroyed` booked
## and `ready` stale.
static func apply_hull_losses(
		state: GameStateData, destroyed_by_type: Dictionary,
		ship_defs_by_name: Dictionary) -> SealiftHullLossReceipt:
	var receipt := SealiftHullLossReceipt.for_cause(SealiftHullLossReceipt.CAUSE_CROSSING)
	for ship_type_value in destroyed_by_type.keys():
		var ship_type := String(ship_type_value)
		var requested := int(destroyed_by_type[ship_type_value])
		if requested <= 0:
			continue
		var ship_state: ShipState = state.fleet.get(ship_type, null)
		if ship_state == null:
			continue
		var ship_def: ShipDef = ship_defs_by_name.get(ship_type, null)
		var from_cohorts := ship_def != null and ship_def.is_carrier()
		var applied := 0
		if from_cohorts:
			applied = _remove_carrier_hulls(state.sealift_state, ship_type, requested)
		else:
			applied = mini(requested, ship_state.fleet_surviving_total)
		ship_state.destroyed += applied
		ship_state.fleet_surviving_total -= applied
		receipt.record(ship_type, requested, applied, SealiftHullLossReceipt.SOURCE_SENT_COHORTS \
			if from_cohorts else SealiftHullLossReceipt.SOURCE_READY_SCREEN)
	project_fleet(state)
	return receipt


## Remove up to `count` carrier hulls of `ship_type` from this turn's "sent" cohorts, in cohort order.
## Returns how many were actually removed (<= count, capped by the hulls present). Escort types never
## reach here: they are not bound to cohorts, so a request against one would silently find nothing and
## look like a cap instead of the classification error it is — which is why the caller classifies.
static func _remove_carrier_hulls(state: SealiftState, ship_type: String, count: int) -> int:
	var removed := 0
	for cohort in state.cohorts:
		if removed >= count:
			break
		if not cohort.is_sent():
			continue
		var have := int(cohort.hulls_by_type.get(ship_type, 0))
		if have <= 0:
			continue
		var take := mini(have, count - removed)
		cohort.hulls_by_type[ship_type] = have - take
		removed += take
	return removed


# ── Fleet projection ────────────────────────────────────────────────────────────────────────────

## Recompute the fleet's bins from the sealift state, which is the single source of truth for where a
## hull is: surviving_sent/offloading from cohorts, returning from the return pipeline, ready as the
## remainder of the surviving fleet. Every write of a ShipState bin in production happens here, so the
## arithmetic exists once (plan 0004's invariants, plan 0045's single writer).
static func project_fleet(state: GameStateData) -> void:
	if state.sealift_state == null:
		return
	var busy := _busy_hulls(state)
	for ship_type in state.fleet.keys():
		var ship_state: ShipState = state.fleet[ship_type]
		var sent := int((busy["sent"] as Dictionary).get(String(ship_type), 0))
		var offloading := int((busy["offloading"] as Dictionary).get(String(ship_type), 0))
		var returning := int((busy["returning"] as Dictionary).get(String(ship_type), 0))
		ship_state.surviving_sent = sent
		ship_state.offloading = offloading
		ship_state.returning = returning
		ship_state.ready = ship_state.fleet_surviving_total - sent - offloading - returning
		assert(ship_state.ready >= 0, "sealift projection: negative ready for %s (surviving=%d busy=%d)" % [
			ship_type, ship_state.fleet_surviving_total, sent + offloading + returning])
		assert(ship_state.validate(), "sealift projection broke ShipState invariant for %s" % ship_type)
	_check_fleet(state, busy)


## The three busy buckets, keyed ship_type -> hull count. Cohorts hold carrier hulls (sent while they
## cross, offloading once ashore-bound); the return pipeline holds hulls cycling back to reload.
##
## Escort types RELOADING their SAM magazine are a whole-type exception (plan 0004 D5): the type has
## left the screen, so every surviving hull of it is busy, not just a counted few. Those hulls are
## never in a cohort or the pipeline, so this cannot double-count them.
static func _busy_hulls(state: GameStateData) -> Dictionary:
	var sent: Dictionary = {}
	var offloading: Dictionary = {}
	var returning: Dictionary = {}
	for cohort in state.sealift_state.cohorts:
		var bucket: Dictionary = sent if cohort.is_sent() else offloading
		for ship_type in cohort.hulls_by_type.keys():
			bucket[String(ship_type)] = int(bucket.get(String(ship_type), 0)) \
				+ int(cohort.hulls_by_type[ship_type])
	for ship_type in state.sealift_state.return_pipeline.keys():
		for slot_value in (state.sealift_state.return_pipeline[ship_type] as Array):
			var slot: Dictionary = slot_value
			returning[String(ship_type)] = int(returning.get(String(ship_type), 0)) + int(slot["count"])
	for ship_type in state.sealift_state.escort_reload.keys():
		var reloading_state: ShipState = state.fleet.get(String(ship_type), null)
		if reloading_state != null:
			returning[String(ship_type)] = int(returning.get(String(ship_type), 0)) \
				+ reloading_state.fleet_surviving_total
	return {"sent": sent, "offloading": offloading, "returning": returning}


# ── Invariants ──────────────────────────────────────────────────────────────────────────────────

## The cross-cutting checks `ShipState.validate()` cannot make on its own, reported at the transition
## that created the problem rather than at whatever reads the fleet next. Each is reachable only by a
## future authority operation getting something wrong — none can fail on a path that exists today,
## which is the point: they guard the NEXT write, the way AntishipTransitions._reproject does.
static func _check_fleet(state: GameStateData, busy: Dictionary) -> void:
	if not _check_queues(state.sealift_state):
		return
	_check_known_hull_types(state, busy)


## The checks that need only the sealift queues, so every queue-moving operation can run them without a
## fleet in hand. Returns false when the structural check already failed, so a caller does not pile
## consequential errors on top of a state that is known malformed.
static func _check_queues(state: SealiftState) -> bool:
	if not state.validate():
		return false
	_check_escort_magazines(state)
	_check_one_cohort_per_bn(state)
	return true


## A hull the fleet does not have cannot be afloat. Hull counts only ever enter a cohort or the
## pipeline from the ready pool, which is derived FROM the fleet, so a positive count under an unknown
## type means a cohort and the fleet have drifted apart — the projection would silently ignore those
## hulls and the conservation equation would read as satisfied while hulls went missing.
static func _check_known_hull_types(state: GameStateData, busy: Dictionary) -> void:
	for bucket_name in busy.keys():
		var bucket: Dictionary = busy[bucket_name]
		for ship_type in bucket.keys():
			if int(bucket[ship_type]) > 0 and not state.fleet.has(String(ship_type)):
				push_error("SealiftTransitions: %s hulls of unknown ship type %s" % [
					bucket_name, ship_type])


## A magazine may not hold more than its loadout, and the three per-type maps describe one magazine
## each, so a type present in one must be present in all three. A missing threshold would read as 0 and
## silently stop a type ever diverting to reload.
static func _check_escort_magazines(state: SealiftState) -> void:
	if state.escort_sam.is_empty():
		return
	for ship_type_value in state.escort_sam.keys():
		var ship_type := String(ship_type_value)
		if not state.escort_sam_max.has(ship_type) or not state.escort_sam_threshold.has(ship_type):
			push_error("SealiftTransitions: escort magazine for %s has an incomplete key set" % ship_type)
			continue
		if int(state.escort_sam[ship_type]) > int(state.escort_sam_max[ship_type]):
			push_error("SealiftTransitions: escort magazine for %s holds %d of a %d loadout" % [
				ship_type, int(state.escort_sam[ship_type]), int(state.escort_sam_max[ship_type])])
	for ship_type_value in state.escort_reload.keys():
		if not state.escort_sam.has(String(ship_type_value)):
			push_error("SealiftTransitions: %s is reloading a magazine it does not have" % ship_type_value)


## A battalion is aboard exactly one cohort. The force authority enforces this when it binds ids, but a
## hull operation that split or merged a cohort could break it, and the same id in two cohorts means
## hulls are freed twice — once per cohort that thinks it carried the last battalion.
static func _check_one_cohort_per_bn(state: SealiftState) -> void:
	var seen: Dictionary = {}
	for cohort in state.cohorts:
		for bn_id in cohort.bn_ids:
			if seen.has(bn_id):
				push_error("SealiftTransitions: BN %s is bound to more than one cohort" % bn_id)
				return
			seen[bn_id] = true
