class_name IjfsEngagement
extends RefCounted

## Port of ijfs_standalone/engagement.py — what a SAM does, on both sides of the exchange: one SAM
## being engaged, and surviving SAMs shooting back.
##
## The ORCHESTRATION moved out on 2026-08-01 (plan 0060 R11): IjfsSeadStage decides which weapon
## engages which emitter and with how much power, and calls `engage_sam_target` per target. What
## stays here is the per-target and per-airframe arithmetic both stages share.
##
## RNG: every Python rng.random() maps to dice.randf(), preserving draw order — a destroy roll, then
## a suppression roll only when the target survives; return-fire / free-shot loops iterate squadrons
## in force order, drawing once per alive aircraft.
##
## Per-airframe survivability is NOT computed here: it comes from IjfsAttritionProfile, which every
## path that can kill an aircraft shares. Since 2026-08-01 (plan 0060 R2) that means loss
## probabilities carry role exposure as well as RCS survival.

const SAM_CATEGORIES := ["Moveable SAMs", "Static SAMs", "Mobile SAMs"]
const SUPPRESSION_FACTOR := 0.4
const SEAD_RETURN_FIRE_FACTOR := 0.02
const FREE_SHOT_FACTOR := 0.05
const WVR_FACTOR := 0.1
const RCS_FACTOR := 0.05


## One SAM target's engagement: destroy roll, then a suppression roll only if it survives
## (draw order is the port's contract). Mutates the target's state; returns the log row.
##
## Public since 2026-08-01 (plan 0060 R11): the anti-radiation salvo stage and the aircraft-SEAD
## stage are two different weapons against the same target with the same formula, so they share this
## rather than each growing a copy of the destroy/suppress pair.
static func engage_sam_target(target: IjfsTarget, effective_power: float, dice: Dice) -> Dictionary:
	var score := target.sam_score if target.sam_score != 0 else 1
	var p_destroy := clampf(effective_power / (effective_power + float(score)), 0.0, 1.0)

	var roll := dice.randf()
	var destroyed := roll <= p_destroy
	var suppressed := false
	if destroyed:
		IjfsTransitions.apply_sead_destruction(target)
	else:
		var p_suppress := p_destroy * SUPPRESSION_FACTOR
		var supp_roll := dice.randf()
		suppressed = supp_roll <= p_suppress
		if suppressed:
			IjfsTransitions.apply_sead_suppression(target)
		else:
			IjfsTransitions.mark_sead_unengaged(target)

	return {
		"target_id": target.target_id,
		"category": target.category,
		"subcategory": target.subcategory,
		"sam_score": score,
		"p_destroy": p_destroy,
		"destroy_roll": roll,
		"destroyed": destroyed,
		"p_suppress": (p_destroy * SUPPRESSION_FACTOR) if not destroyed else 0.0,
		"suppressed": suppressed,
		"sead_result": target.sead_result,
	}


## Surviving unsuppressed SAMs shoot back: one Bernoulli draw per alive airframe, per squadron in
## force order (draw order is the port's contract). Mutates squadron alive/losses_today.
static func sead_return_fire(
		squadron_force: Variant, profile: IjfsAttritionProfile, targets: Array[IjfsTarget], dice: Dice) -> Array:
	if squadron_force == null:
		return []
	var squadrons: Array = squadron_force
	var contest_log: Array = []
	var surviving_sam_score := 0
	for target in targets:
		if target.category in SAM_CATEGORIES and not target.destroyed and not target.suppressed:
			surviving_sam_score += target.sam_score if target.sam_score != 0 else 0
	if surviving_sam_score <= 0:
		return contest_log
	var loss_rate := clampf(float(surviving_sam_score) * SEAD_RETURN_FIRE_FACTOR, 0.0, 1.0)
	for sq: IjfsSquadron in squadrons:
		if sq.alive <= 0:
			continue
		var sq_loss_rate := profile.p_loss(loss_rate, sq.aircraft_class, sq.role)
		var losses := _bernoulli_count(sq.alive, sq_loss_rate, dice)
		if losses > 0:
			IjfsTransitions.apply_squadron_losses(sq, losses)
			contest_log.append({
				"squadron_id": sq.squadron_id,
				"aircraft_class": sq.aircraft_class,
				"losses": losses,
				"p_loss": sq_loss_rate,
				"source": "sead_return_fire",
			})
	return contest_log


static func apply_post_phase_2_free_shot(
	squadron_force: Variant,
	profile: IjfsAttritionProfile,
	raw_sam_health: float,
	dice: Dice,
	ad_attrition_enabled: bool = true
) -> Array:
	var log: Array = []
	if not ad_attrition_enabled or raw_sam_health <= 0.0 or squadron_force == null:
		return log
	var loss_rate := clampf(raw_sam_health * FREE_SHOT_FACTOR, 0.0, 1.0)
	for sq: IjfsSquadron in (squadron_force as Array):
		if sq.alive <= 0:
			continue
		var p_loss := profile.p_loss(loss_rate, sq.aircraft_class, sq.role)
		var losses := _bernoulli_count(sq.alive, p_loss, dice)
		if losses > 0:
			IjfsTransitions.apply_squadron_losses(sq, losses)
			log.append({
				"squadron_id": sq.squadron_id,
				"aircraft_class": sq.aircraft_class,
				"losses": losses,
				"p_loss": p_loss,
			})
	return log


static func _bernoulli_count(trials: int, p: float, dice: Dice) -> int:
	var count := 0
	for _i in range(trials):
		if dice.randf() <= p:
			count += 1
	return count

