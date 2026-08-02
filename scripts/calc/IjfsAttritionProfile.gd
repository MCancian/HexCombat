class_name IjfsAttritionProfile
extends RefCounted

## How survivable one Red airframe is, per attrition source. Built once per IJFS day from the
## scenario and air_classes, then handed to every path that can kill an aircraft, so all of them
## agree on the two modifiers and none of them re-derives one.
##
## Two modifiers, and they are deliberately CUMULATIVE (plan 0060 R2, USER ruling 2026-08-01):
##
##   * **RCS survival** — signature. A low-observable airframe is harder to engage at all. This one
##     has been live since the port.
##   * **Role exposure** — altitude and profile. `isr 0.7 / sead 1.0 / strike 1.2`: an ISR aircraft
##     orbits high and clean, a strike aircraft comes in low with ordnance on the wings. Until
##     2026-08-01 `red_aircraft_attrition_and_sead.role_exposure_multipliers` was DEAD DATA —
##     IjfsLoaders required the block to exist and nothing read a single field in it — so the only
##     per-aircraft modifier in the whole model was RCS.
##
## They are not alternatives and they do not replace one another: signature and flight profile are
## different survival advantages, and a stealthy striker should get both.
##
## The class table is reached through here as well, rather than by every caller doing
## `air_classes["classes"].get(name, {})` with its own default, which is how two call sites drift
## apart on what a missing class means.

## Per-airframe RCS survival: `1 + rcs * RCS_SURVIVAL_FACTOR`, floored so an implausibly low
## signature cannot make an airframe effectively unkillable.
const RCS_SURVIVAL_FACTOR := 0.1
const MIN_RCS_SURVIVAL_MOD := 0.2

## What an unknown role or an absent multiplier block means: no exposure adjustment. It is the
## identity rather than a guess, so a scenario that declines to model role exposure gets exactly the
## pre-2026-08-01 behaviour instead of a silently invented one.
const NEUTRAL_EXPOSURE := 1.0

const ROLE_EXPOSURE_KEY := "role_exposure_multipliers"
const ATTRITION_BLOCK := "red_aircraft_attrition_and_sead"

var _classes: Dictionary = {}
var _role_exposure: Dictionary = {}


## `scenario` and `air_classes` are Variant because both are legitimately absent in unit fixtures
## that only care about one of the two modifiers.
static func build(scenario: Variant, air_classes: Variant) -> IjfsAttritionProfile:
	var profile := IjfsAttritionProfile.new()
	if air_classes is Dictionary:
		profile._classes = (air_classes as Dictionary).get("classes", {})
	if scenario is Dictionary:
		var block: Dictionary = (scenario as Dictionary).get(ATTRITION_BLOCK, {})
		profile._role_exposure = block.get(ROLE_EXPOSURE_KEY, {})
	return profile


## The air_classes row for a class, or an empty dictionary when the profile carries no class table.
func class_entry(aircraft_class: String) -> Dictionary:
	return _classes.get(aircraft_class, {})


func class_value(aircraft_class: String, field: String) -> float:
	return float(class_entry(aircraft_class).get(field, 0))


func rcs_survival(aircraft_class: String) -> float:
	return maxf(MIN_RCS_SURVIVAL_MOD, 1.0 + class_value(aircraft_class, "rcs") * RCS_SURVIVAL_FACTOR)


func role_exposure(role: String) -> float:
	return float(_role_exposure.get(role, NEUTRAL_EXPOSURE))


## One airframe's probability of being lost to a source whose un-modified rate is `base_rate`.
## Clamped into [0, 1] here so every caller gets a usable probability and none has to remember to.
func p_loss(base_rate: float, aircraft_class: String, role: String) -> float:
	return clampf(base_rate * role_exposure(role) * rcs_survival(aircraft_class), 0.0, 1.0)
