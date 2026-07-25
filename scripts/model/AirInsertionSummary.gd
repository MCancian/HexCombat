extends Resource
class_name AirInsertionSummary

## Result of one air insertion phase (plan 0032) — what flew, what landed, what the air defences
## killed, and what that cost the lift. Carried in GameState.last_air_insertion_summary /
## TurnResult / the event log / the EventBus air_insertion_resolved signal.
##
## All-zero/empty when nothing was ordered (the default), which is what keeps the phase invisible
## until a scenario and a player opt in.
## to_dict() is the JSON-serialization boundary; its key order and value types are the contract.

## Insertions resolved this turn, in order. Each entry:
##   {brigade_id: String, lift_class: String, hex_id: String, sent: int, landed: int, lost: int,
##    attrition_rate: float, first_landing: bool}
## `sent` is the packet that flew (landed + lost); `first_landing` marks the drop that puts the
## brigade on the map for the first time. Report only — the per-battalion manifests the caller must
## apply travel beside the summary, in resolve()'s "landings" (the shape OffloadResolver uses).
@export var drops: Array = []

## Orders that could not fly, in order. Each entry: {brigade_id: String, reason: String}.
## Reasons are the REASON_* constants below — a cap already spent, a pool already empty, a drop
## ordered before first_turn. Surfaced so a player (or an LLM seat) learns why nothing happened.
@export var rejected: Array = []

@export var battalions_landed: int = 0
@export var battalions_lost: int = 0

## Per-class attrition rate actually applied this turn, lift_class -> float. Empty when nothing
## flew. This is the number the researcher reads to see the air-defence suppression paying off.
@export var attrition_by_class: Dictionary = {}

## Lift budget before and after this turn's losses, lift_class -> int. The delta is airframes
## destroyed — permanent throughput loss, not a one-turn dip.
@export var caps_before: Dictionary = {}
@export var caps_after: Dictionary = {}

@export var pending_brigades: int = 0
@export var pending_battalions: int = 0

const REASON_CAP_EXHAUSTED := "cap_exhausted"
const REASON_POOL_EMPTY := "pool_empty"
const REASON_BEFORE_FIRST_TURN := "before_first_turn"


func to_dict() -> Dictionary:
	return {
		"drops": drops.duplicate(true),
		"rejected": rejected.duplicate(true),
		"battalions_landed": battalions_landed,
		"battalions_lost": battalions_lost,
		"attrition_by_class": attrition_by_class.duplicate(true),
		"caps_before": caps_before.duplicate(true),
		"caps_after": caps_after.duplicate(true),
		"pending_brigades": pending_brigades,
		"pending_battalions": pending_battalions,
	}
