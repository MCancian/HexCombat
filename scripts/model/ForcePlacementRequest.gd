class_name ForcePlacementRequest
extends Resource

@export var brigade_id: String = ""
@export var destination_hex: String = ""
@export var destination: ForceLocation.Kind = ForceLocation.Kind.ASHORE
@export var turn: int = 0
@export var phase: String = ""
@export var has_entry_bearing: bool = false
@export var entry_bearing: float = 0.0


static func ashore(p_brigade_id: String, p_hex_id: String, p_phase: String = "") -> ForcePlacementRequest:
	var request := ForcePlacementRequest.new()
	request.brigade_id = p_brigade_id
	request.destination_hex = p_hex_id
	request.destination = ForceLocation.Kind.ASHORE
	request.phase = p_phase
	return request


static func off_map(p_brigade_id: String, p_phase: String = "") -> ForcePlacementRequest:
	var request := ForcePlacementRequest.new()
	request.brigade_id = p_brigade_id
	request.destination_hex = ""
	request.destination = ForceLocation.Kind.MOBILIZING
	request.phase = p_phase
	return request
