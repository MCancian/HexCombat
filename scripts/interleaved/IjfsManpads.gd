class_name IjfsManpads
extends RefCounted

## MANPADS layer (2026-07-10, USER-approved divergence from the TIV oracle). Stinger MANPADS are
## per-TO container bins (category "MANPADS", stock held in the typed `IjfsTarget.manpads_remaining`)
## deliberately OUTSIDE the SEAD / AD-health SAM categories: passive-IR shoulder launchers are not
## SEAD-targetable, but they contest low-altitude air operations. Drains: usage (missiles expended
## per engagement, here), bombardment (bins stay strikeable through the normal strike path), ground
## losses (IjfsResolver.sync_manpads_to_oob scales bins with TO infantry survival).
##
## ONE MECHANIC, ONE TRIGGER (plan 0060 R5/R6/R12, USER rulings 2026-08-01). MANPADS used to have two
## surfaces: an interception roll against every low-altitude strike, and an island-wide daily contest
## that taxed SEAD and strike squadrons for being in the campaign at all. BOTH are gone. A MANPADS
## engagement now exists only when a four-airframe manned package strikes a **Maneuver Unit** whose
## TO holds ready launchers — the shoulder-launched threat belongs to the low-altitude strike that
## actually flew into its envelope, and to nothing else. MANPADS does not protect SAM, radar,
## infrastructure or anti-ship targets, and it never touches ISR, SEAD or Attack UCAV aircraft.
##
## Kill and abort are MUTUALLY EXCLUSIVE and share ONE draw, so attrition is not a rider on a
## successful abort:
##   * **killed** — one selected member dies; the survivors press the attack at reduced effect;
##   * **aborted** — every survivor returns and books RTB; today's strike is denied;
##   * **unaffected** — the full surviving package presses.

const CATEGORY := "MANPADS"

## Threat saturates: >= SATURATION ready launchers ~ full coverage of the low-altitude
## environment; below that, coverage thins linearly. 2,500 launchers are not 5x deadlier than 500
## (only so many approach corridors), but the last teams still matter.
const SATURATION_SYSTEMS := 500.0

## p(abort) at full threat x munition manpads_vulnerability. Unchanged from the interception formula
## this mechanic grew out of, and deliberately carries no role/RCS modifier: being driven off is
## about the launcher's presence, not the airframe's signature.
const ABORT_FACTOR := 0.15

## Missiles fired per engagement, whatever the outcome — the attempt is what expends the launcher's
## stock, not the hit.
const EXPEND_PER_ENGAGEMENT := 3

const OUTCOME_KILLED := "killed"
const OUTCOME_ABORTED := "aborted"
const OUTCOME_UNAFFECTED := "unaffected"


## Ready (alive, unsuppressed) launcher count per TO plus "total". Suppressed bins keep their
## stock but contribute no threat this day.
static func ready_systems_by_to(targets: Array[IjfsTarget]) -> Dictionary:
	var by_to: Dictionary = {"total": 0}
	for target in targets:
		if target.category != CATEGORY or target.destroyed or target.suppressed:
			continue
		var remaining := systems_remaining(target)
		if remaining <= 0:
			continue
		var to_key := str(int(target.metadata.get("to_number", 0)))
		by_to[to_key] = int(by_to.get(to_key, 0)) + remaining
		by_to["total"] = int(by_to["total"]) + remaining
	return by_to


## The bin's authoritative launcher stock, seeded lazily on first read so data files stay
## declarative. A target rebuilt from a saved dict carries its stock in `metadata`, so that value
## wins over the declarative `systems_represented` when present — otherwise a mid-campaign
## round-trip would silently refill every bin.
static func systems_remaining(target: IjfsTarget) -> int:
	if target.manpads_remaining < 0:
		set_remaining(target, int(target.metadata.get(
			"systems_remaining", target.metadata.get("systems_represented", 0))))
	return target.manpads_remaining


## The ONE place the stock changes: the typed field and its serialization mirror move together, so
## they cannot describe different stocks.
static func set_remaining(target: IjfsTarget, value: int) -> void:
	IjfsTransitions.set_manpads_remaining(target, value)


static func threat_fraction(ready_systems: int) -> float:
	return clampf(float(ready_systems) / SATURATION_SYSTEMS, 0.0, 1.0)


## True when this strike is the one shape MANPADS engages: a Maneuver Unit, in a TO with ready
## launchers, struck by a munition whose package the USER ruled MANPADS-eligible. Checked before any
## die is drawn, so an ineligible strike costs nothing.
static func engages(strike_target: IjfsTarget, munition: IjfsMunition, eligible: bool, targets: Array[IjfsTarget]) -> bool:
	if not eligible or munition.manpads_vulnerability <= 0.0:
		return false
	if strike_target.category != "Maneuver Units":
		return false
	if not strike_target.metadata.has("to_number"):
		return false
	return _ready_in_to(targets, int(strike_target.metadata["to_number"])) > 0


## Resolve the MANPADS engagement against one surviving package, consuming EXACTLY ONE draw.
##
## That single draw does two jobs, which is the transform R8 asks for and R10 reuses: `u * N` picks
## which of the N survivors is the candidate, and the FRACTIONAL REMAINDER of the same product is the
## candidate-specific outcome roll. A second draw for victim selection would be both wasteful and a
## second place for draw order to drift.
##
## Mutates the package (a kill removes a member), the squadrons (loss or RTB), and the TO's launcher
## stock. Returns the ledger row; the caller decides what the strike log says.
static func engage_package(
	package: IjfsAirPackage, strike_target: IjfsTarget, state: IjfsDailyState,
	profile: IjfsAttritionProfile, dice: Dice
) -> Dictionary:
	var to_number := int(strike_target.metadata["to_number"])
	var ready := _ready_in_to(state.targets, to_number)
	var munition: IjfsMunition = state.munitions[package.munition_id]
	var threat := threat_fraction(ready)
	# Absent = 0.0 = MANPADS can drive a package off but never shoot one down, a legitimate
	# configuration and not a silent default. IjfsLoaders owns and range-checks the key.
	var kill_factor := float(state.scenario.get(IjfsLoaders.MANPADS_KILL_FACTOR_KNOB, 0.0))
	var members_before := package.size()

	var draw := dice.randf()
	var scaled := draw * float(members_before)
	var candidate := mini(int(floor(scaled)), members_before - 1)
	var outcome_roll := clampf(scaled - float(candidate), 0.0, 1.0)
	var victim: IjfsSquadron = package.members[candidate]

	# Kill carries the airframe's own survivability (role exposure x RCS); abort does not.
	var p_kill := profile.p_loss(
		threat * kill_factor * munition.manpads_vulnerability, victim.aircraft_class, victim.role)
	var p_abort := clampf(threat * ABORT_FACTOR * munition.manpads_vulnerability, 0.0, 1.0)
	assert(p_kill + p_abort <= 1.0,
		"MANPADS kill+abort bands exceed 1.0 for %s (%f + %f) — the two outcomes are mutually exclusive and cannot overlap" % [
			victim.squadron_id, p_kill, p_abort])

	# `p > 0.0 and` guards the zero band: `randf()` can return exactly 0.0, so a bare `roll <= p`
	# makes a probability-ZERO outcome fire — an attrition factor of 0.0 has to mean "off".
	var outcome := OUTCOME_UNAFFECTED
	var losses := 0
	var returned := 0
	if p_kill > 0.0 and outcome_roll <= p_kill:
		outcome = OUTCOME_KILLED
		losses = 1
		# MANPADS only ever engages a STRIKE package, so nothing is released — but it goes through
		# the same authority operation, so there is one way for a package member to die.
		IjfsTransitions.apply_package_member_loss(package.remove_member(candidate), false)
	elif p_abort > 0.0 and outcome_roll <= p_kill + p_abort:
		outcome = OUTCOME_ABORTED
		returned = package.size()
		for squadron in package.members:
			IjfsTransitions.book_rtb(squadron, 1)

	expend(state.targets, to_number, EXPEND_PER_ENGAGEMENT)
	return {
		"target_id": strike_target.target_id,
		"to_number": to_number,
		"munition_id": munition.munition_id,
		"package_id": package.package_id,
		"members_before": members_before,
		"members_after": package.size(),
		"members_by_squadron": package.members_by_squadron(),
		"ready_systems": ready,
		"p_kill": p_kill,
		"p_abort": p_abort,
		"roll": outcome_roll,
		"outcome": outcome,
		"victim_squadron_id": victim.squadron_id if outcome == OUTCOME_KILLED else null,
		"victim_class": victim.aircraft_class if outcome == OUTCOME_KILLED else null,
		"losses": losses,
		"rtb": returned,
		# A kill that takes the LAST survivor denies the strike just as surely as an abort does.
		"strike_executed": outcome != OUTCOME_ABORTED and not package.is_empty(),
		"systems_expended": EXPEND_PER_ENGAGEMENT,
	}


## Drain `count` missiles from a TO's ready bins, lowest target_id first (deterministic).
static func expend(targets: Array[IjfsTarget], to_number: int, count: int) -> void:
	var remaining := count
	for target in _sorted_ready_bins(targets, to_number):
		if remaining <= 0:
			return
		var stock := systems_remaining(target)
		var spent := mini(stock, remaining)
		set_remaining(target, stock - spent)
		remaining -= spent


static func _ready_in_to(targets: Array[IjfsTarget], to_number: int) -> int:
	var ready := 0
	for target in targets:
		if target.category != CATEGORY or target.destroyed or target.suppressed:
			continue
		if int(target.metadata.get("to_number", 0)) != to_number:
			continue
		ready += systems_remaining(target)
	return ready


## Ready bins (alive, unsuppressed, stock > 0) in one TO, sorted by target_id.
static func _sorted_ready_bins(targets: Array[IjfsTarget], to_number: int) -> Array[IjfsTarget]:
	var bins: Array[IjfsTarget] = []
	for target in targets:
		if target.category != CATEGORY or target.destroyed or target.suppressed:
			continue
		if int(target.metadata.get("to_number", 0)) != to_number:
			continue
		if systems_remaining(target) > 0:
			bins.append(target)
	bins.sort_custom(func(a: IjfsTarget, b: IjfsTarget) -> bool: return a.target_id < b.target_id)
	return bins
