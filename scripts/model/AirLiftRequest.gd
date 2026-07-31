class_name AirLiftRequest
extends Resource

## What one resolved air-insertion phase costs the LIFT (plan 0048) — the input
## `AirInsertionTransitions` applies. Companion to `ForceAirInsertionRequest`, which carries the same
## phase's effect on the FORCE: one resolver outcome, two aggregates, two typed requests.
##
## Deliberately carries the packet ROWS rather than a post-state. The authority derives the new lift
## budget from these rows, so "the cap fell by exactly the reported losses" holds by construction and
## the log can never disagree with the erosion — they are computed from one array. Handing an
## authority a finished `caps_after` would make that a number it has to trust.
##
## Build it with `AirInsertionTransitions.lift_request()`, never directly: the factory lives on the
## authority so a coordinator does not have to name this type at all.

@export var turn_number: int = 0

## One row per packet that flew, in resolution order. Same shape as `AirInsertionSummary.drops`:
##   {brigade_id: String, lift_class: String, hex_id: String, landed: int, lost: int, …}
## Extra keys the summary carries for reporting (`sent`, `attrition_rate`, `first_landing`) are
## ignored here.
@export var drops: Array = []


static func from_drops(p_turn_number: int, p_drops: Array) -> AirLiftRequest:
	var request := AirLiftRequest.new()
	request.turn_number = p_turn_number
	request.drops = p_drops.duplicate(true)
	return request
