class_name IjfsStrikePhase
extends RefCounted

## One IJFS strike pass — port of run_daily_ijfs._run_strike_phase / _append_final_skips /
## _skip_log. Runs TWICE per day (pre-AD, then post-AD) against the shared IjfsStrikePhaseContext,
## which is what lets the second pass see what the first already hit.
##
## Extracted from IjfsEngine 2026-08-01 (plan 0060) alongside IjfsLedgers. The engine sat at its
## dependency ceiling of 14 while the plan adds three collaborators, so the ceiling is PAID by moving
## work out rather than raised. This half was the right one to move on its own merits too: the engine
## now reads as the ordering of a day's phases, and the mechanics of "select a munition, check the
## budget, roll the strike" live in one place with the target-by-target detail.
##
## `scripts/calc/`, not `scripts/interleaved/`, and the distinction is exact: this file changes NO
## campaign state. It appends to the day's strike log and marks targets attacked in the phase
## context — per-run outputs the mutation manifest deliberately leaves unregistered — while every
## application it triggers happens one call deeper, inside IjfsManpads (the interception denial and
## the round it spends) or IjfsStrike (destruction and suppression), each of which does apply at its
## own draw point and lives in `interleaved/` for that reason.


## Resolve every eligible target for one pass. `phase` stays an explicit argument rather than a field
## on the day-scoped context: it differs between the two passes, and reading it out of a mutable
## bundle is how a pass silently runs under the wrong label.
static func run(state: IjfsDailyState, ctx: IjfsStrikePhaseContext, phase: String, dice: Dice) -> void:
	for target in IjfsTargeting.targets_to_attack(state.targets, ctx.z_day, ctx.release_rules):
		if ctx.attacked.has(target.target_id):
			continue
		if _resolve_target(state, ctx, target, phase, dice):
			ctx.attacked[target.target_id] = true


## One target's whole story for this pass: pick a munition, prove the capacity and the airframes
## exist, fly the package in if there is one, and record what happened. Returns false when the target
## was SKIPPED and stays eligible for the next pass; true once a sortie has been spent on it, whether
## or not that sortie delivered anything.
static func _resolve_target(
	state: IjfsDailyState, ctx: IjfsStrikePhaseContext, target: IjfsTarget, phase: String, dice: Dice
) -> bool:
	var selection := IjfsTargeting.select_munition_with_doctrine(
		target, state.pairings, state.munitions, state.scenario, phase, ctx.munition_filter,
		ctx.capacity_budget, ctx.organic_budget)
	var pairing: Variant = selection["selected"]
	var strike_ctx := IjfsStrikeContext.for_strike(
		ctx.current_day, phase, selection["doctrine_name"], selection["selection"])
	if pairing == null:
		var reason: Variant = selection["reason"]
		return _skip(ctx, target, strike_ctx, reason if reason != null else "no_compatible_pairing")

	var munition: Variant = state.munitions.get(pairing.munition_id, null)
	var is_organic: bool = munition != null and munition.category == "Organic"
	var budget: Variant = ctx.organic_budget if is_organic else ctx.capacity_budget
	if budget != null and not budget.has_capacity(pairing.munition_id):
		return _skip(ctx, target, strike_ctx,
			"organic_capacity_exhausted" if is_organic else "firing_capacity_exhausted")

	# Assembly comes BEFORE the capacity seat is spent (plan 0060 R8): a package that cannot be manned
	# did not consume a sortie. `has_capacity` above is the non-consuming half of the same check the
	# selection stage already made, so the airframe draws below are never wasted on a strike the
	# budget would then have refused.
	var package: Variant = null
	if is_organic:
		package = IjfsPackageIngress.assemble(
			state, pairing.munition_id, target, ctx.packages_launched, ctx.air_engagement_dice)
		if package == null:
			return _skip(ctx, target, strike_ctx, "package_unavailable")
		ctx.packages_launched += 1
	if budget != null:
		budget.try_consume(pairing.munition_id)

	if package != null:
		# A denied package consumes NO strike kill/suppression draws — the ordnance never left the rail.
		var ingress := IjfsPackageIngress.fly_in(state, package, target, ctx, ctx.air_engagement_dice)
		var outcome := String(ingress["outcome"])
		if outcome != IjfsPackageIngress.OUTCOME_PRESSED:
			state.strike_log.append(
				denied_strike_log(target, pairing, strike_ctx, outcome))
			return true
		strike_ctx.survivor_fraction = float(ingress["survivor_fraction"])
	state.strike_log.append(IjfsStrike.resolve_strike(
		target, pairing, state.munitions, state.scenario, strike_ctx, dice))
	return true


## Record why this target was passed over, and report "not attacked" so the caller leaves it eligible.
static func _skip(
	ctx: IjfsStrikePhaseContext, target: IjfsTarget, strike_ctx: IjfsStrikeContext, reason: String
) -> bool:
	ctx.skip_reasons[target.target_id] = [
		reason, strike_ctx.doctrine_rule_name, strike_ctx.doctrine_selection]
	return false


## Every still-eligible target that neither pass attacked gets one skip row, so the day's strike log
## accounts for the whole target list rather than only the parts of it that fired.
static func append_final_skips(state: IjfsDailyState, ctx: IjfsStrikePhaseContext) -> void:
	for target in IjfsTargeting.targets_to_attack(state.targets, ctx.z_day, ctx.release_rules):
		if ctx.attacked.has(target.target_id):
			continue
		var entry: Array = ctx.skip_reasons.get(target.target_id, ["no_compatible_pairing", null, null])
		state.strike_log.append(_skip_log(target, ctx.current_day, entry))


## `entry` is the [reason, doctrine_name, doctrine_selection] triple `run` recorded.
## `phase` is always null on this path: a final skip belongs to the day, not to one of the two passes.
static func _skip_log(target: IjfsTarget, current_day: int, entry: Array) -> Dictionary:
	var row := target.to_dict()
	row["current_day"] = current_day
	row["phase"] = null
	row["doctrine_rule_name"] = entry[1]
	row["doctrine_selection"] = entry[2]
	row["attack_executed"] = false
	row["skip_reason"] = entry[0]
	return row


## Strike-log row for a sortie that flew and delivered nothing: capacity is spent, the target is
## untouched, and NO strike kill/suppression draws were consumed. Key-compatible with
## IjfsStrike.resolve_strike so IjfsLedgers.summarize_run and the narratives read it unchanged.
##
## `denial` separates the two ways that happens — MANPADS drove the survivors home, or the package
## was wiped out on ingress — which a single boolean could not.
static func denied_strike_log(
	strike_target: IjfsTarget, pairing: IjfsPairing, context: IjfsStrikeContext, denial: String
) -> Dictionary:
	return {
		"current_day": context.current_day,
		"target_id": strike_target.target_id,
		"source_target_id": strike_target.source_target_id,
		"category": strike_target.category,
		"subcategory": strike_target.subcategory,
		"mobility": strike_target.mobility,
		"posture": strike_target.posture,
		"metadata": strike_target.metadata,
		"phase": context.phase,
		"doctrine_rule_name": context.doctrine_rule_name,
		"doctrine_selection": context.doctrine_selection,
		"attack_executed": true,
		"skip_reason": null,
		"pairing_id": pairing.pairing_id,
		"munition_id": pairing.munition_id,
		"rounds_expended": int(pairing.rounds_expended_per_engagement),
		"package_survivor_fraction": 0.0,
		"package_denial": denial,
		"probability_destroyed": 0.0,
		"roll": null,
		"destroyed": false,
		"probability_suppressed_if_not_destroyed": 0.0,
		"suppression_roll": null,
		"suppressed": false,
	}
