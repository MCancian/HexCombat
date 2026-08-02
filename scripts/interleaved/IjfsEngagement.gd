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


## R10 (USER ruling 2026-08-01): a SAM may only attrit an aircraft that actually entered its
## envelope. This replaced a POOLED force tax that drew once per alive airframe in the whole OOB —
## `loss_rate = surviving_sam_score * 0.02` applied to every squadron, including aircraft parked
## outside any engagement. Losses now scale with real SAM-package contacts and are bounded by the
## exposed package's four actual members.
##
## Geography: a strike package is engaged only by SAMs in ITS TO; the day's SEAD package carries
## `to_number` -1 and is engaged island-wide, because suppressing the network is not a local errand.
## SAMs fire in stable target-id order and stop once the package is empty.
##
## One draw per engaging SAM, doing two jobs exactly as the MANPADS engagement does: `u * N` picks the
## candidate and the fractional remainder is that candidate's hit roll. A second victim draw would be
## a second place for draw order to drift, and R10 rules it out for that reason.
static func resolve_package_return_fire(
	package: IjfsAirPackage, state: IjfsDailyState, profile: IjfsAttritionProfile, dice: Dice
) -> Array:
	var log: Array = []
	# `p_loss = factor x sam_score x role_exposure x rcs_survival`. Absent = 0.0 = SAMs never shoot
	# back, a legitimate configuration and not a silent default. IjfsLoaders owns the key.
	var factor := float(state.scenario.get(IjfsLoaders.SAM_RETURN_FIRE_KNOB, 0.0))
	if factor <= 0.0 or package.is_empty():
		return log
	for target in _engaging_sams(state.targets, package):
		if package.is_empty():
			break
		log.append(_engage_package_member(target, package, profile, factor, dice))
	return log


## One SAM's shot at one package. Mutates the package (a hit removes a member) and the squadron that
## loses the airframe; returns the ledger row either way, because a miss is a contact that happened.
static func _engage_package_member(
	target: IjfsTarget, package: IjfsAirPackage, profile: IjfsAttritionProfile,
	factor: float, dice: Dice
) -> Dictionary:
	var members_before := package.size()
	var draw := dice.randf()
	var scaled := draw * float(members_before)
	var candidate := mini(int(floor(scaled)), members_before - 1)
	var roll := clampf(scaled - float(candidate), 0.0, 1.0)
	var victim: IjfsSquadron = package.members[candidate]
	var score := maxi(1, target.sam_score)
	# R10 requires this band to be asserted in [0, 1], not merely clamped into it. The difference
	# matters: `IjfsAttritionProfile.p_loss` clamps, so a factor set too high would SATURATE — every
	# Patriot killing an airframe with certainty — and the sam_score gradient the formula exists to
	# express would silently stop meaning anything. The assert is what makes a mis-set knob loud.
	var raw := factor * float(score) * profile.role_exposure(victim.role) * profile.rcs_survival(victim.aircraft_class)
	assert(raw <= 1.0,
		"SAM return-fire p_loss %f exceeds 1.0 for score %d vs %s — %s is too high to keep the sam_score gradient meaningful" % [
			raw, score, victim.aircraft_class, IjfsLoaders.SAM_RETURN_FIRE_KNOB])
	var p_loss := profile.p_loss(factor * float(score), victim.aircraft_class, victim.role)
	# `p_loss > 0.0 and` guards the zero band: `randf()` can return exactly 0.0, so a bare
	# `roll <= p` makes a probability-ZERO outcome fire.
	var hit := p_loss > 0.0 and roll <= p_loss
	if hit:
		var victim_squadron := package.remove_member(candidate)
		# A killed SEAD-package member stops being ASSIGNED as well as alive; without the release,
		# `available_today()` would subtract the same casualty twice from the later strike pool.
		if package.kind == IjfsAirPackage.SEAD:
			IjfsTransitions.release_sead_assignment(victim_squadron, 1)
		IjfsTransitions.apply_squadron_losses(victim_squadron, 1)
	return {
		"target_id": target.target_id,
		"to_number": int(target.metadata.get("to_number", -1)),
		"sam_score": score,
		"package_kind": package.kind,
		"package_id": package.package_id,
		"munition_id": package.munition_id if package.munition_id != "" else null,
		"members_before": members_before,
		"members_after": package.size(),
		"victim_squadron_id": victim.squadron_id if hit else null,
		"victim_class": victim.aircraft_class if hit else null,
		"p_loss": p_loss,
		"roll": roll,
		"losses": 1 if hit else 0,
		"source": "sam_return_fire",
	}


## The SAMs entitled to shoot at this package: alive, unsuppressed, and — for a STRIKE package — in
## the struck target's theatre. A strike against a target in no theatre meets no SAM at all, which is
## a different thing from the SEAD package: that one is engaged island-wide because suppressing the
## network is not a local errand. The two cases are told apart by `kind`, never by the TO sentinel.
static func _engaging_sams(targets: Array[IjfsTarget], package: IjfsAirPackage) -> Array[IjfsTarget]:
	var engaging: Array[IjfsTarget] = []
	var island_wide := package.kind == IjfsAirPackage.SEAD
	for target in targets:
		if not (target.category in SAM_CATEGORIES) or target.destroyed or target.suppressed:
			continue
		if not island_wide and int(target.metadata.get("to_number", IjfsAirPackage.NO_THEATRE)) != package.to_number:
			continue
		engaging.append(target)
	engaging.sort_custom(func(a: IjfsTarget, b: IjfsTarget) -> bool: return a.target_id < b.target_id)
	return engaging


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
		# AVAILABLE, not alive (plan 0060 R2): "subtract rtb_today from every later pool so an
		# aircraft already home cannot be killed", and the same for airframes booked to SEAD — the
		# free shot is a parting shot at a departing package, not at the whole ramp.
		var exposed := sq.available_today()
		if exposed <= 0:
			continue
		var p_loss := profile.p_loss(loss_rate, sq.aircraft_class, sq.role)
		var losses := _bernoulli_count(exposed, p_loss, dice)
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

