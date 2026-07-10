class_name IjfsManpads
extends RefCounted

## MANPADS layer (2026-07-10, USER-approved divergence from the TIV oracle — see PLAN.md
## Decisions). Stinger MANPADS are per-TO container bins (category "MANPADS", mutable
## `systems_remaining` in metadata) deliberately OUTSIDE the SEAD / AD-health SAM categories:
## passive-IR shoulder launchers are not SEAD-targetable, but they contest low-altitude air
## operations. Effects: (1) each low-altitude strike into a TO with ready launchers risks
## interception (roll BEFORE the strike's own rolls); (2) SEAD/strike squadrons take island-wide
## contest losses each day. Drains: usage (missiles expended per engagement, here), bombardment
## (bins stay strikeable through the normal strike path), ground losses
## (IjfsResolver.sync_manpads_to_oob scales bins with TO infantry survival).

const CATEGORY := "MANPADS"

## Threat saturates: >= SATURATION ready launchers ~ full coverage of the low-altitude
## environment; below that, coverage thins linearly. 2,500 launchers are not 5x deadlier than 500
## (only so many approach corridors), but the last teams still matter.
const SATURATION_SYSTEMS := 500.0
const INTERCEPT_FACTOR := 0.15          # p(intercept) at full threat x munition manpads_vulnerability
const SQUADRON_LOSS_FACTOR := 0.01      # per-aircraft p(loss) at full island-wide threat
const EXPEND_PER_INTERCEPT := 3         # missiles fired per interception attempt (usage drain)
const EXPEND_PER_CONTEST_AIRCRAFT := 1  # missiles fired per aircraft engaged in the day's contest
const CONTESTED_ROLES := ["sead", "strike"]  # low-altitude attack profiles; ISR flies high


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


static func systems_remaining(target: IjfsTarget) -> int:
	# systems_remaining is seeded lazily from systems_represented so data files stay declarative.
	if not target.metadata.has("systems_remaining"):
		target.metadata["systems_remaining"] = int(target.metadata.get("systems_represented", 0))
	return int(target.metadata["systems_remaining"])


static func threat_fraction(ready_systems: int) -> float:
	return clampf(float(ready_systems) / SATURATION_SYSTEMS, 0.0, 1.0)


## Roll interception for one about-to-execute strike. Returns null when MANPADS cannot engage
## (invulnerable munition, target outside any TO, no ready launchers there) — in that case NO
## dice are consumed. Otherwise consumes exactly one draw, expends missiles from the TO's bins
## (attempt fired whether or not it hits), and returns the log entry with "intercepted" set.
static func roll_strike_interception(
	strike_target: IjfsTarget, munition: IjfsMunition, targets: Array[IjfsTarget], dice: Dice
) -> Variant:
	if munition.manpads_vulnerability <= 0.0:
		return null
	if not strike_target.metadata.has("to_number"):
		return null
	var to_number := int(strike_target.metadata["to_number"])
	var ready := _ready_in_to(targets, to_number)
	if ready <= 0:
		return null
	var p_intercept := clampf(
		threat_fraction(ready) * INTERCEPT_FACTOR * munition.manpads_vulnerability, 0.0, 1.0)
	var roll := dice.randf()
	var intercepted := roll <= p_intercept
	expend(targets, to_number, EXPEND_PER_INTERCEPT)
	return {
		"target_id": strike_target.target_id,
		"to_number": to_number,
		"munition_id": munition.munition_id,
		"ready_systems": ready,
		"p_intercept": p_intercept,
		"roll": roll,
		"intercepted": intercepted,
		"systems_expended": EXPEND_PER_INTERCEPT,
	}


## Strike-log entry for an intercepted strike: the round is spent (attack_executed, inventory
## decremented by the caller's budget/inventory path) but delivers nothing. Key-compatible with
## IjfsStrike.resolve_strike entries so summarize_run / narratives read it unchanged.
static func intercepted_strike_log(
	target: IjfsTarget, pairing: IjfsPairing, current_day: int,
	phase: Variant, doctrine_rule_name: Variant, doctrine_selection: Variant
) -> Dictionary:
	return {
		"current_day": current_day,
		"target_id": target.target_id,
		"source_target_id": target.source_target_id,
		"category": target.category,
		"subcategory": target.subcategory,
		"mobility": target.mobility,
		"posture": target.posture,
		"metadata": target.metadata,
		"phase": phase,
		"doctrine_rule_name": doctrine_rule_name,
		"doctrine_selection": doctrine_selection,
		"attack_executed": true,
		"skip_reason": null,
		"pairing_id": pairing.pairing_id,
		"munition_id": pairing.munition_id,
		"rounds_expended": int(pairing.rounds_expended_per_engagement),
		"probability_destroyed": 0.0,
		"roll": null,
		"destroyed": false,
		"probability_suppressed_if_not_destroyed": 0.0,
		"suppression_roll": null,
		"suppressed": false,
		"intercepted_by_manpads": true,
	}


## Island-wide contest of low-altitude squadrons (SEAD + strike roles), one bernoulli draw per
## alive aircraft — the IjfsEngagement return-fire/free-shot shape, with the same RCS survival
## modifier. Expends missiles per aircraft engaged. Returns contest-style log entries
## (source "manpads"); caller folds losses into red_air_losses.
static func contest_squadrons(
	targets: Array[IjfsTarget], squadron_force: Variant, air_classes: Variant, dice: Dice
) -> Array:
	var log: Array = []
	if squadron_force == null:
		return log
	var ready := int(ready_systems_by_to(targets).get("total", 0))
	if ready <= 0:
		return log
	var classes: Dictionary = {}
	if air_classes != null:
		classes = (air_classes as Dictionary).get("classes", {})
	var threat := threat_fraction(ready)
	for sq: IjfsSquadron in (squadron_force as Array):
		if sq.alive <= 0 or sq.role not in CONTESTED_ROLES:
			continue
		var cls: Dictionary = classes.get(sq.aircraft_class, {})
		var rcs := float(cls.get("rcs", 0))
		var rcs_survival := maxf(
			IjfsEngagement.MIN_RCS_SURVIVAL_MOD, 1.0 + rcs * IjfsEngagement.RCS_SURVIVAL_FACTOR)
		var p_loss := clampf(threat * SQUADRON_LOSS_FACTOR * rcs_survival, 0.0, 1.0)
		var engaged := sq.alive
		var losses := 0
		for _i in range(engaged):
			if dice.randf() <= p_loss:
				losses += 1
		_expend_island_wide(targets, engaged * EXPEND_PER_CONTEST_AIRCRAFT)
		if losses > 0:
			sq.alive -= losses
			sq.losses_today += losses
		log.append({
			"squadron_id": sq.squadron_id,
			"aircraft_class": sq.aircraft_class,
			"engaged": engaged,
			"losses": losses,
			"p_loss": p_loss,
			"source": "manpads",
		})
	return log


## Drain `count` missiles from a TO's ready bins, lowest target_id first (deterministic).
static func expend(targets: Array[IjfsTarget], to_number: int, count: int) -> void:
	var remaining := count
	for target in _sorted_ready_bins(targets, to_number):
		if remaining <= 0:
			return
		var stock := systems_remaining(target)
		var spent := mini(stock, remaining)
		target.metadata["systems_remaining"] = stock - spent
		remaining -= spent


static func _expend_island_wide(targets: Array[IjfsTarget], count: int) -> void:
	# Spread usage across TOs proportionally is over-modeling; drain lowest target_id first
	# island-wide (bins sort TO2 < TO3 < ... by id, so forward TOs deplete first — acceptable).
	var remaining := count
	for target in _sorted_ready_bins(targets, -1):
		if remaining <= 0:
			return
		var stock := systems_remaining(target)
		var spent := mini(stock, remaining)
		target.metadata["systems_remaining"] = stock - spent
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


## Ready bins (alive, unsuppressed, stock > 0), sorted by target_id; to_number -1 = all TOs.
static func _sorted_ready_bins(targets: Array[IjfsTarget], to_number: int) -> Array[IjfsTarget]:
	var bins: Array[IjfsTarget] = []
	for target in targets:
		if target.category != CATEGORY or target.destroyed or target.suppressed:
			continue
		if to_number != -1 and int(target.metadata.get("to_number", 0)) != to_number:
			continue
		if systems_remaining(target) > 0:
			bins.append(target)
	bins.sort_custom(func(a: IjfsTarget, b: IjfsTarget) -> bool: return a.target_id < b.target_id)
	return bins
