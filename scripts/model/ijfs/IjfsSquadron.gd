class_name IjfsSquadron
extends Resource

@export var squadron_id: String = ""
@export var aircraft_class: String = ""
@export var role: String = "unused"
@export var initial: int = 0
@export var alive: int = 0
## Airframes driven home today without being shot down — MANPADS aborted the package they were
## flying in, so they are unavailable for the rest of the day but still alive tomorrow. Written for
## the first time on 2026-08-01 (plan 0059 step 2, folded into plan 0060 R5/R8); before that the
## field existed with NO runtime writer at all. Cleared by IjfsTransitions.carry_to_next_day.
@export var rtb_today: int = 0
## Airframes booked to today's SEAD package (plan 0060 R11 stage C). They are unavailable to Organic
## strikes for the rest of the day but remain exposed to SAM return fire — being assigned to SEAD is
## precisely what puts them in the envelope. Cleared with rtb_today at the day boundary.
@export var sead_assigned_today: int = 0
## Airframes lost on the CURRENT day only — reset by IjfsTransitions.carry_to_next_day, which runs at
## the head of every day before run_daily accumulates into it. Until 2026-08-01 this field was
## campaign-cumulative despite its name; the USER's call was to report both numbers rather than pick
## one, so the honest per-day count kept the name and the running total moved to losses_campaign.
@export var losses_today: int = 0
## Airframes lost since the campaign began. Nothing resets it between days; the loader zeroes it when
## a game is built. This is the number the field above used to carry.
@export var losses_campaign: int = 0


## Airframes this squadron can still commit today. An aircraft already flown home (rtb_today) or
## already booked to the SEAD package (sead_assigned_today) is alive but spoken for, and no
## attrition or package-assembly path may select one — plan 0060 R2/R5: "no path may select an
## aircraft already unavailable today".
func available_today() -> int:
	return maxi(0, alive - rtb_today - sead_assigned_today)
