class_name IjfsPackageIngress
extends RefCounted

## Getting a four-airframe Organic package from the ramp to the target: assemble it, then fly it in
## past whatever defends the target's TO.
##
## Plan 0060 R8 fixes the ORDER, and the order is the mechanic:
##   1. assemble the package from the linked squadrons' currently available airframes;
##   2. same-TO SAMs engage, one at a time in stable target-id order, each hit killing at most one
##      member (plan 0060 R10);
##   3. if the target is a Maneuver Unit and at least one member survives, MANPADS takes exactly one
##      draw and produces exactly one outcome.
##
## Three things can then happen to the strike itself, and the caller needs all three distinguished:
## it presses (at `survivors / package_size` effect), it is DENIED because MANPADS drove the
## survivors home, or the package was wiped out on ingress — a spent sortie that delivered nothing,
## which is NOT the same as a strike that never launched for want of airframes.
##
## `scripts/calc/` because it changes no campaign state directly: every kill, every RTB booking and
## every launcher expenditure happens inside IjfsManpads, which applies at its own draw point.

const OUTCOME_PRESSED := "pressed"
const OUTCOME_ABORTED := "aborted"
const OUTCOME_DESTROYED := "ingress_destroyed"


## Assemble the package for one Organic strike, or return null when the linked squadrons cannot
## field a full one today. A short package never launches: R8 is explicit that four airframes is the
## package, not a maximum.
##
## `package_index` only makes the id unique within the day, so a ledger reader can tell two packages
## against the same target apart.
static func assemble(
	state: IjfsDailyState, munition_id: String, strike_target: IjfsTarget,
	package_index: int, dice: Dice
) -> Variant:
	var link := IjfsAirPackage.link_config(state.scenario, munition_id)
	if link.is_empty() or state.squadron_force == null:
		return null
	var linked_classes: Array = link["classes"]
	var candidates: Array = []
	for squadron: IjfsSquadron in (state.squadron_force as Array):
		if squadron.aircraft_class in linked_classes:
			candidates.append(squadron)
	var members := IjfsAirPackage.reserve(candidates, int(link["package_size"]), dice)
	if members.is_empty():
		return null
	var package := IjfsAirPackage.build(
		IjfsAirPackage.STRIKE, "%s#%s#%03d" % [munition_id, strike_target.target_id, package_index], members)
	package.munition_id = munition_id
	package.target_id = strike_target.target_id
	package.to_number = int(strike_target.metadata.get("to_number", IjfsAirPackage.NO_THEATRE))
	return package


## Fly the assembled package in. Appends the MANPADS ledger row when one is drawn, and returns
## `{"outcome": ..., "survivor_fraction": ...}` for the caller to turn into a strike-log row.
static func fly_in(
	state: IjfsDailyState, package: IjfsAirPackage, strike_target: IjfsTarget,
	ctx: IjfsStrikePhaseContext, dice: Dice
) -> Dictionary:
	if not ctx.ad_attrition_enabled:
		return {"outcome": OUTCOME_PRESSED, "survivor_fraction": package.survivor_fraction()}
	state.contest_log.append_array(
		IjfsEngagement.resolve_package_return_fire(package, state, ctx.attrition, dice))
	if package.is_empty():
		return {"outcome": OUTCOME_DESTROYED, "survivor_fraction": 0.0}
	var link := IjfsAirPackage.link_config(state.scenario, package.munition_id)
	var munition: IjfsMunition = state.munitions[package.munition_id]
	if IjfsManpads.engages(strike_target, munition, bool(link["manpads_eligible"]), state.targets):
		var row := IjfsManpads.engage_package(package, strike_target, state, ctx.attrition, dice)
		state.manpads_intercept_log.append(row)
		if String(row["outcome"]) == IjfsManpads.OUTCOME_ABORTED:
			return {"outcome": OUTCOME_ABORTED, "survivor_fraction": 0.0}
		# MANPADS can take the LAST survivor when SAMs already thinned the package. Without this the
		# strike would resolve at zero effect — spending a draw it must not spend, and destroying the
		# target on an exact-zero roll (diff review 2026-08-01, reproduced before fixing).
		if package.is_empty():
			return {"outcome": OUTCOME_DESTROYED, "survivor_fraction": 0.0}
	return {"outcome": OUTCOME_PRESSED, "survivor_fraction": package.survivor_fraction()}
