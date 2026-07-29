class_name ForceAirInsertionRequest
extends Resource

@export var turn_number: int = 0

## Landings the resolver computed, same shape as AirInsertionResolver.resolve() returns:
## {brigade_id, hex_id, first_landing, landed_bns, lost_bns}
@export var landings: Array = []


static func from_landings(
	p_turn_number: int, p_landings: Array
) -> ForceAirInsertionRequest:
	var req := ForceAirInsertionRequest.new()
	req.turn_number = p_turn_number
	req.landings = p_landings.duplicate(true)
	return req
