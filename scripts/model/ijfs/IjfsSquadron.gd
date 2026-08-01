class_name IjfsSquadron
extends Resource

@export var squadron_id: String = ""
@export var aircraft_class: String = ""
@export var role: String = "unused"
@export var initial: int = 0
@export var alive: int = 0
@export var rtb_today: int = 0
## Airframes lost on the CURRENT day only — reset by IjfsTransitions.carry_to_next_day, which runs at
## the head of every day before run_daily accumulates into it. Until 2026-08-01 this field was
## campaign-cumulative despite its name; the USER's call was to report both numbers rather than pick
## one, so the honest per-day count kept the name and the running total moved to losses_campaign.
@export var losses_today: int = 0
## Airframes lost since the campaign began. Nothing resets it between days; the loader zeroes it when
## a game is built. This is the number the field above used to carry.
@export var losses_campaign: int = 0
