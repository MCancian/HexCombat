class_name ForceMobilizationRequest
extends Resource

@export var turn_number: int = 0

## Arrivals computed by MobilizationResolver:
## {brigade_id, hex_id, battalions: int, displaced: bool}
@export var arrivals: Array = []

## Brigade ids that were deferred (stay pending, no arrival hex found).
@export var deferred: Array[String] = []


static func from_resolver(
	p_turn_number: int, p_arrivals: Array, p_deferred: Array[String],
) -> ForceMobilizationRequest:
	var req := ForceMobilizationRequest.new()
	req.turn_number = p_turn_number
	req.arrivals = p_arrivals.duplicate(true)
	req.deferred = p_deferred.duplicate()
	return req
