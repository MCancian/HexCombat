class_name IjfsEngagement
extends RefCounted

## Port of ijfs_standalone/engagement.py — V1 SEAD engagement + post-phase-2 free shot.
## RNG: every Python rng.random() maps to dice.randf(), preserving draw order:
## SEAD loop iterates targets sorted by target_id (destroy roll, then a suppression roll
## whenever the target survives); return-fire / free-shot loops iterate squadrons in force
## order, drawing once per alive aircraft.

const SAM_CATEGORIES := ["Moveable SAMs", "Static SAMs", "Mobile SAMs"]
const SUPPRESSION_FACTOR := 0.4
const SEAD_RETURN_FIRE_FACTOR := 0.02
const FREE_SHOT_FACTOR := 0.05
const WVR_FACTOR := 0.1
const RCS_FACTOR := 0.05
const RCS_SURVIVAL_FACTOR := 0.1
const MIN_RCS_SURVIVAL_MOD := 0.2


static func resolve_sead_engagement(
	targets: Array[IjfsTarget],
	squadron_force: Variant,
	air_classes: Variant,
	dice: Dice,
	sead_enabled: bool = true,
	ad_attrition_enabled: bool = true
) -> Dictionary:
	var classes: Dictionary = {}
	if air_classes != null:
		classes = (air_classes as Dictionary).get("classes", {})

	var engagement_log: Array = []
	var contest_log: Array = []
	if squadron_force == null:
		return {"engagement_log": engagement_log, "contest_log": contest_log}
	var squadrons: Array = squadron_force

	var total_sead_eff := 0.0
	var total_wvr := 0.0
	var total_rcs := 0.0
	var total_alive := 0
	for sq: IjfsSquadron in squadrons:
		if sq.alive > 0 and sq.role != "unused":
			var cls: Dictionary = classes.get(sq.aircraft_class, {})
			total_sead_eff += float(sq.alive) * float(cls.get("sead_eff", 0))
			total_wvr += float(sq.alive) * float(cls.get("wvr", 0))
			total_rcs += float(sq.alive) * float(cls.get("rcs", 0))
			total_alive += sq.alive

	for target in targets:
		if target.category in SAM_CATEGORIES and not target.destroyed:
			target.sead_result = "unengaged"

	if not sead_enabled or total_alive <= 0 or total_sead_eff <= 0.0:
		return {"engagement_log": engagement_log, "contest_log": contest_log}

	var avg_wvr := total_wvr / float(total_alive)
	var avg_rcs := total_rcs / float(total_alive)
	var wvr_mod := 1.0 + avg_wvr * WVR_FACTOR
	var rcs_mod := 1.0 - avg_rcs * RCS_FACTOR
	var effective_power := total_sead_eff * wvr_mod * rcs_mod

	for target in _sorted_by_id(targets):
		if target.destroyed or not (target.category in SAM_CATEGORIES):
			continue
		var score := target.sam_score if target.sam_score != 0 else 1
		var p_destroy := clampf(effective_power / (effective_power + float(score)), 0.0, 1.0)

		var roll := dice.randf()
		var destroyed := roll <= p_destroy
		var suppressed := false
		if destroyed:
			target.destroyed = true
			target.suppressed = false
			target.suppressed_this_turn = false
			target.detected_this_turn = false
			target.known_to_red = false
			target.sead_result = "destroyed"
		else:
			var p_suppress := p_destroy * SUPPRESSION_FACTOR
			var supp_roll := dice.randf()
			suppressed = supp_roll <= p_suppress
			if suppressed:
				target.suppressed = true
				target.suppressed_this_turn = true
				target.sead_result = "suppressed"
			else:
				target.sead_result = "unengaged"

		engagement_log.append({
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
		})

	if ad_attrition_enabled:
		var surviving_sam_score := 0
		for target in targets:
			if target.category in SAM_CATEGORIES and not target.destroyed and not target.suppressed:
				surviving_sam_score += target.sam_score if target.sam_score != 0 else 0
		if surviving_sam_score > 0 and total_alive > 0:
			var loss_rate := clampf(float(surviving_sam_score) * SEAD_RETURN_FIRE_FACTOR, 0.0, 1.0)
			for sq: IjfsSquadron in squadrons:
				if sq.alive <= 0:
					continue
				var cls: Dictionary = classes.get(sq.aircraft_class, {})
				var rcs := float(cls.get("rcs", 0))
				var rcs_survival := maxf(MIN_RCS_SURVIVAL_MOD, 1.0 + rcs * RCS_SURVIVAL_FACTOR)
				var sq_loss_rate := clampf(loss_rate * rcs_survival, 0.0, 1.0)
				var losses := _bernoulli_count(sq.alive, sq_loss_rate, dice)
				if losses > 0:
					sq.alive -= losses
					sq.losses_today += losses
					contest_log.append({
						"squadron_id": sq.squadron_id,
						"aircraft_class": sq.aircraft_class,
						"losses": losses,
						"p_loss": sq_loss_rate,
						"source": "sead_return_fire",
					})

	return {"engagement_log": engagement_log, "contest_log": contest_log}


static func apply_post_phase_2_free_shot(
	squadron_force: Variant,
	air_classes: Variant,
	raw_sam_health: float,
	dice: Dice,
	ad_attrition_enabled: bool = true
) -> Array:
	var log: Array = []
	if not ad_attrition_enabled or raw_sam_health <= 0.0 or squadron_force == null:
		return log
	var classes: Dictionary = {}
	if air_classes != null:
		classes = (air_classes as Dictionary).get("classes", {})
	var loss_rate := clampf(raw_sam_health * FREE_SHOT_FACTOR, 0.0, 1.0)
	for sq: IjfsSquadron in (squadron_force as Array):
		if sq.alive <= 0:
			continue
		var cls: Dictionary = classes.get(sq.aircraft_class, {})
		var rcs := float(cls.get("rcs", 0))
		var rcs_mod := maxf(MIN_RCS_SURVIVAL_MOD, 1.0 + rcs * RCS_SURVIVAL_FACTOR)
		var p_loss := clampf(loss_rate * rcs_mod, 0.0, 1.0)
		var losses := _bernoulli_count(sq.alive, p_loss, dice)
		if losses > 0:
			sq.alive -= losses
			sq.losses_today += losses
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


static func _sorted_by_id(targets: Array[IjfsTarget]) -> Array[IjfsTarget]:
	var sorted: Array[IjfsTarget] = targets.duplicate()
	sorted.sort_custom(func(a: IjfsTarget, b: IjfsTarget) -> bool: return a.target_id < b.target_id)
	return sorted
