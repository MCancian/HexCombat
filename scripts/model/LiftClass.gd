extends RefCounted
class_name LiftClass

## How a formation reaches Taiwan (plan 0032). The sole home for the OOB `nato_type` -> lift-class
## mapping: both the sea path (SealiftStateBuilder, which must NOT sweep air-lifted brigades into
## the amphibious follow-on pool) and the air path (AirInsertionStateBuilder, which builds its pool
## from exactly these) read it here rather than each spelling out the nato_type strings.
##
## A brigade is either sea-lifted (lift class "", the overwhelming majority) or air-inserted under
## one of the two per-turn lift budgets. The class also selects which budget an insertion draws
## from and which attrition model applies: AIRBORNE is fixed-wing at altitude and faces the SAM/
## radar layer only, AIR_ASSAULT is rotary-wing down low and faces MANPADS on top of it.

const AIRBORNE := "airborne"
const AIR_ASSAULT := "air_assault"

## OOB nato_type -> lift class. Any nato_type absent here is sea-lifted.
const NATO_TYPE_TO_CLASS := {
	"airborne": AIRBORNE,
	"air-assault": AIR_ASSAULT,
}

## Every lift class, in the order summaries and caps report them.
const ALL: Array[String] = [AIRBORNE, AIR_ASSAULT]


## The lift class a brigade belongs to, or "" when it crosses by sea.
static func for_brigade(brigade: Brigade) -> String:
	if brigade == null:
		return ""
	return String(NATO_TYPE_TO_CLASS.get(brigade.nato_type, ""))


## True when the brigade reaches Taiwan by air and must therefore be kept out of the sealift pools.
static func is_air_lifted(brigade: Brigade) -> bool:
	return for_brigade(brigade) != ""


## Fail-loud guard for config that names a lift class (scenario caps, knob paths).
static func is_known(lift_class: String) -> bool:
	return lift_class in ALL
