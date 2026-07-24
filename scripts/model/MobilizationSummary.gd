extends Resource
class_name MobilizationSummary

## Result of one mobilization phase (plan 0029 Tier A2) — which ROC brigades came out of
## mobilization onto the map this turn, and what is still forming. Carried in
## GameState.last_mobilization_summary / TurnResult / the event log / the EventBus
## mobilization_resolved signal. All-zero/empty when the scenario holds nobody back (the default),
## which is what keeps the mechanic byte-invisible until a scenario opts in.
## to_dict() is the JSON-serialization boundary; its key order and value types are the contract.

## Brigades that arrived this turn, in release order. Each entry:
##   {brigade_id: String, hex_id: String, battalions: int, displaced: bool}
@export var arrivals: Array = []

## Brigades whose release turn came up but had no reachable non-enemy arrival hex; they stay pending
## and retry next turn. Deterministic order (release order).
@export var deferred: Array[String] = []

@export var battalions_arrived: int = 0
@export var pending_brigades: int = 0
@export var pending_battalions: int = 0


func to_dict() -> Dictionary:
	return {
		"arrivals": arrivals.duplicate(true),
		"deferred": deferred.duplicate(),
		"battalions_arrived": battalions_arrived,
		"pending_brigades": pending_brigades,
		"pending_battalions": pending_battalions,
	}
