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
		var selection := IjfsTargeting.select_munition_with_doctrine(
			target, state.pairings, state.munitions, state.scenario, phase, ctx.munition_filter,
			ctx.capacity_budget, ctx.organic_budget)
		var pairing: Variant = selection["selected"]
		var strike_ctx := IjfsStrikeContext.for_strike(
			ctx.current_day, phase, selection["doctrine_name"], selection["selection"])
		if pairing == null:
			var reason: Variant = selection["reason"]
			ctx.skip_reasons[target.target_id] = [
				reason if reason != null else "no_compatible_pairing",
				strike_ctx.doctrine_rule_name, strike_ctx.doctrine_selection]
			continue
		var munition: Variant = state.munitions.get(pairing.munition_id, null)
		var is_organic: bool = munition != null and munition.category == "Organic"
		var budget: Variant = ctx.organic_budget if is_organic else ctx.capacity_budget
		var reason_key: String = "organic_capacity_exhausted" if is_organic else "firing_capacity_exhausted"
		if budget != null and not budget.try_consume(pairing.munition_id):
			ctx.skip_reasons[target.target_id] = [
				reason_key, strike_ctx.doctrine_rule_name, strike_ctx.doctrine_selection]
			continue
		if not IjfsManpads.resolve_pre_strike(state, target, pairing, strike_ctx, dice):
			state.strike_log.append(IjfsStrike.resolve_strike(
				target, pairing, state.munitions, state.scenario, strike_ctx, dice))
		ctx.attacked[target.target_id] = true


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
