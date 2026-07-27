class_name ForceCrossingCasualtyRequest
extends Resource

@export var lost_ids: Array = []
@export var ship_reserve: Array = []
@export var sealift_state: SealiftState = null


static func from_crossing(
		p_lost_ids: Array, p_ship_reserve: Array, p_sealift_state: SealiftState) -> ForceCrossingCasualtyRequest:
	var request := ForceCrossingCasualtyRequest.new()
	request.lost_ids = p_lost_ids
	request.ship_reserve = p_ship_reserve
	request.sealift_state = p_sealift_state
	return request
