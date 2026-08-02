class_name IjfsSeadStage
extends RefCounted

## Red's daily SEAD effort, in the three stages plan 0060 R11 ruled (USER, 2026-08-01). It replaced a
## single aggregate sweep in which the WHOLE air force's summed `sead_eff` engaged every SAM, which
## made SEAD strength a free-floating property of the OOB rather than of anything Red decided to do.
##
##   **A — expendable anti-radiation.** Up to `salvos_per_day` four-missile salvos, against the
##   highest-scoring ACTIVE emitters. This stage may home on an emitter whether or not Red detected
##   it: the target signal IS the emission, so detection gating belongs to the aircraft stage and not
##   to this weapon. Missiles are spent whether the salvo kills, suppresses or misses.
##
##   **B — weighted IADS health.** `remaining_unsuppressed_sam_score / initial_sam_score` over every
##   SAM instance. Weighted by SCORE, not by instance count: nine Patriots and fifty Antelopes are not
##   the same network, and a raw headcount would say they were.
##
##   **C — aircraft assignment with real effect.** Red commits `ceil(fraction x alive_strike_airframes
##   x weighted_health)` HEADS. Alive J-16Ds fill the dedicated places first; ordinary strike aircraft
##   make up the rest and each contributes a fraction of a J-16D's SEAD value. Those airframes leave
##   the Organic strike pool for the day — which is what makes SEAD cost something — but stay exposed
##   to return fire, because being assigned is exactly what puts them in the envelope.
##
## `scripts/interleaved/`, not `calc/`: it applies at its own draw point, and the whole design depends
## on that. Stage A's outcomes decide which emitters Stage C even looks at, and Stage C's assignments
## decide which airframes the strike phase can still use — deferring either application would change
## how many dice the rest of the day consumes.

const STAGE_ANTI_RADIATION := "anti_radiation"
const STAGE_AIRCRAFT := "aircraft"


## Run all three stages. Returns the SEAD engagement log (both stages, each row tagged with its
## `stage`), the assigned aircraft package for return fire to shoot at, and the weighted health that
## sized it.
static func resolve(
	state: IjfsDailyState, ctx: IjfsStrikePhaseContext, sead_enabled: bool
) -> Dictionary:
	for target in state.targets:
		if target.category in IjfsEngagement.SAM_CATEGORIES and not target.destroyed:
			IjfsTransitions.mark_sead_unengaged(target)

	var empty_package := IjfsAirPackage.build(IjfsAirPackage.SEAD, "sead", [] as Array[IjfsSquadron])
	if not sead_enabled or state.squadron_force == null:
		return {"engagement_log": [], "package": empty_package, "weighted_health": 1.0}

	var engagement_log := _run_anti_radiation(state, ctx)
	var weighted_health := weighted_iads_health(state.targets)
	var package := _assign_aircraft(state, weighted_health)
	engagement_log.append_array(_run_aircraft_sead(state, ctx, package))
	return {
		"engagement_log": engagement_log,
		"package": package,
		"weighted_health": weighted_health,
	}


# --- Stage A: expendable anti-radiation ---------------------------------------------------------

## Fire today's salvos at the highest-scoring active emitters. Bounded twice over: by the scenario's
## daily salvo allowance and by what is left in the magazine, so a campaign runs the stage dry rather
## than firing missiles it does not have.
static func _run_anti_radiation(state: IjfsDailyState, ctx: IjfsStrikePhaseContext) -> Array:
	var log: Array = []
	var config: Dictionary = state.scenario.get(IjfsLoaders.ANTI_RADIATION_BLOCK, {})
	if config.is_empty():
		return log
	var munition: IjfsMunition = state.munitions[String(config["munition_id"])]
	var per_salvo := int(config["missiles_per_salvo"])
	var affordable := munition.inventory_remaining / per_salvo
	var salvos := mini(int(config["salvos_per_day"]), affordable)
	if salvos <= 0:
		return log
	var power := float(config["salvo_effective_power"])
	for target in _salvo_targets(state.targets, salvos):
		if not IjfsTransitions.consume_munition(munition, per_salvo):
			break
		var row := IjfsEngagement.engage_sam_target(target, power, ctx.air_engagement_dice)
		row["stage"] = STAGE_ANTI_RADIATION
		row["missiles_expended"] = per_salvo
		log.append(row)
	return log


## The emitters worth a salvo: active (neither destroyed nor already suppressed), richest first by
## `sam_score`, then by `target_id` so the order is stable across runs and platforms.
static func _salvo_targets(targets: Array[IjfsTarget], limit: int) -> Array[IjfsTarget]:
	var candidates: Array[IjfsTarget] = []
	for target in targets:
		if target.category in IjfsEngagement.SAM_CATEGORIES and not target.destroyed and not target.suppressed:
			candidates.append(target)
	candidates.sort_custom(func(a: IjfsTarget, b: IjfsTarget) -> bool:
		if a.sam_score != b.sam_score:
			return a.sam_score > b.sam_score
		return a.target_id < b.target_id)
	return candidates.slice(0, limit)


# --- Stage B: weighted IADS health --------------------------------------------------------------

## The share of Taiwan's SAM network still shooting, weighted by capability. Destroyed and currently
## suppressed systems contribute zero; the denominator is every SAM instance the campaign started
## with, so the number falls monotonically as the network dies rather than renormalising to whatever
## survives.
static func weighted_iads_health(targets: Array[IjfsTarget]) -> float:
	var initial := 0
	var remaining := 0
	for target in targets:
		if not (target.category in IjfsEngagement.SAM_CATEGORIES):
			continue
		var score := maxi(0, target.sam_score)
		initial += score
		if not target.destroyed and not target.suppressed:
			remaining += score
	if initial <= 0:
		return 0.0
	return float(remaining) / float(initial)


# --- Stage C: aircraft assignment ---------------------------------------------------------------

## Book today's SEAD package. Dedicated SEAD squadrons fill their places first — that is what they
## are for — and ordinary strike aircraft make up the balance, allocated across squadrons in
## proportion to their alive strength by largest remainder so the whole requirement is met exactly
## and the same squadrons are picked on every run.
static func _assign_aircraft(state: IjfsDailyState, weighted_health: float) -> IjfsAirPackage:
	var config: Dictionary = state.scenario.get(IjfsLoaders.SEAD_ASSIGNMENT_BLOCK, {})
	var force: Array = state.squadron_force
	var alive_strike := 0
	var dedicated: Array[IjfsSquadron] = []
	var ordinary: Array[IjfsSquadron] = []
	for squadron: IjfsSquadron in force:
		if squadron.role == "strike":
			alive_strike += squadron.alive
			if squadron.available_today() > 0:
				ordinary.append(squadron)
		elif squadron.role == "sead" and squadron.available_today() > 0:
			dedicated.append(squadron)

	var requirement := ceili(float(config["strike_airframe_fraction"]) * float(alive_strike) * weighted_health)
	var members: Array[IjfsSquadron] = []
	for squadron in dedicated:
		var take := mini(squadron.available_today(), requirement - members.size())
		for _i in range(take):
			members.append(squadron)
	var dedicated_heads := members.size()
	for entry in _largest_remainder(ordinary, requirement - dedicated_heads):
		for _i in range(int(entry[1])):
			members.append(entry[0])

	var package := IjfsAirPackage.build(IjfsAirPackage.SEAD, "sead", members)
	package.dedicated_size = dedicated_heads
	_book_assignments(package)
	return package


## Hand each squadron its share of the package in one call, so `sead_assigned_today` is written once
## per squadron rather than once per airframe.
static func _book_assignments(package: IjfsAirPackage) -> void:
	var by_squadron: Dictionary = {}
	for squadron in package.members:
		by_squadron[squadron] = int(by_squadron.get(squadron, 0)) + 1
	for squadron in by_squadron:
		IjfsTransitions.assign_to_sead(squadron, int(by_squadron[squadron]))


## Split `total` heads across squadrons in proportion to alive strength, capped by what each can
## actually field today. Largest-remainder rounding with a stable squadron-id tie break, so the parts
## sum to the whole and no run reorders them.
static func _largest_remainder(squadrons: Array[IjfsSquadron], total: int) -> Array:
	var result: Array = []
	if total <= 0 or squadrons.is_empty():
		return result
	var ordered := squadrons.duplicate()
	ordered.sort_custom(func(a: IjfsSquadron, b: IjfsSquadron) -> bool: return a.squadron_id < b.squadron_id)
	var pool := 0
	for squadron: IjfsSquadron in ordered:
		pool += squadron.available_today()
	var wanted := mini(total, pool)

	var shares: Array = []
	var assigned := 0
	for squadron: IjfsSquadron in ordered:
		var exact := float(wanted) * float(squadron.available_today()) / float(pool)
		var whole := mini(int(floor(exact)), squadron.available_today())
		assigned += whole
		shares.append([squadron, whole, exact - float(whole)])
	# Hand out the remainder to the largest fractional parts first; ties keep squadron-id order,
	# because `sort_custom` is not stable and an id tie break makes the outcome reproducible anyway.
	shares.sort_custom(func(a: Array, b: Array) -> bool:
		if not is_equal_approx(float(a[2]), float(b[2])):
			return float(a[2]) > float(b[2])
		return (a[0] as IjfsSquadron).squadron_id < (b[0] as IjfsSquadron).squadron_id)
	var index := 0
	while assigned < wanted and index < shares.size() * 2:
		var share: Array = shares[index % shares.size()]
		var squadron: IjfsSquadron = share[0]
		if int(share[1]) < squadron.available_today():
			share[1] = int(share[1]) + 1
			assigned += 1
		index += 1

	for share in shares:
		if int(share[1]) > 0:
			result.append([share[0], int(share[1])])
	return result


# --- Stage C: the engagement itself -------------------------------------------------------------

## SEAD power the assigned package actually brings: summed effect, scaled by the package's average
## within-visual-range advantage and signature penalty. Dedicated SEAD airframes contribute their
## class `sead_eff`; ordinary strike aircraft contribute the scenario's fraction of one, because a
## strike aircraft carrying a couple of anti-radiation rounds is not a J-16D.
static func effective_power(package: IjfsAirPackage, state: IjfsDailyState, ctx: IjfsStrikePhaseContext) -> float:
	if package.is_empty():
		return 0.0
	var ordinary_eff := float(state.scenario.get(IjfsLoaders.SEAD_ASSIGNMENT_BLOCK, {}).get("ordinary_aircraft_sead_eff", 0.0))
	var summed := 0.0
	var wvr := 0.0
	var rcs := 0.0
	for index in range(package.size()):
		var squadron := package.members[index]
		summed += ctx.attrition.class_value(squadron.aircraft_class, "sead_eff") if index < package.dedicated_size else ordinary_eff
		wvr += ctx.attrition.class_value(squadron.aircraft_class, "wvr")
		rcs += ctx.attrition.class_value(squadron.aircraft_class, "rcs")
	var count := float(package.size())
	var wvr_mod := 1.0 + (wvr / count) * IjfsEngagement.WVR_FACTOR
	var rcs_mod := 1.0 - (rcs / count) * IjfsEngagement.RCS_FACTOR
	return summed * wvr_mod * rcs_mod


## The aircraft sweep, against the SAMs Stage A left active. A target Stage A destroyed or suppressed
## is SKIPPED entirely rather than re-engaged, so that stage's verdict for the day stands.
static func _run_aircraft_sead(
	state: IjfsDailyState, ctx: IjfsStrikePhaseContext, package: IjfsAirPackage
) -> Array:
	var log: Array = []
	var power := effective_power(package, state, ctx)
	if power <= 0.0:
		return log
	# Undetected emitters are harder for AIRCRAFT to prosecute; 1.0 (the default) preserves full
	# engagement and is what the shipped scenario sets. Deliberately not applied to Stage A, whose
	# weapon homes on the emission itself.
	var undetected_scalar := float(state.scenario.get(IjfsLoaders.SEAD_ASSIGNMENT_BLOCK, {}).get("sead_undetected_engagement", 1.0))
	for target in _sorted_by_id(state.targets):
		if target.destroyed or target.suppressed or not (target.category in IjfsEngagement.SAM_CATEGORIES):
			continue
		var target_power := power if target.detected_this_turn else power * undetected_scalar
		var row := IjfsEngagement.engage_sam_target(target, target_power, ctx.air_engagement_dice)
		row["stage"] = STAGE_AIRCRAFT
		log.append(row)
	return log


static func _sorted_by_id(targets: Array[IjfsTarget]) -> Array[IjfsTarget]:
	var sorted: Array[IjfsTarget] = targets.duplicate()
	sorted.sort_custom(func(a: IjfsTarget, b: IjfsTarget) -> bool: return a.target_id < b.target_id)
	return sorted
