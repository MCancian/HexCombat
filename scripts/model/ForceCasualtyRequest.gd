class_name ForceCasualtyRequest
extends Resource

@export var brigade_id: String = ""
@export var battalion_type: String = ""
@export var count: int = 0
@export var cause: ForceCasualtyCause.Kind = ForceCasualtyCause.Kind.GROUND_COMBAT
@export var source_location: ForceLocation.Kind = ForceLocation.Kind.ASHORE


static func one(
		p_brigade_id: String,
		p_battalion_type: String,
		p_cause: ForceCasualtyCause.Kind,
		p_source: ForceLocation.Kind = ForceLocation.Kind.ASHORE) -> ForceCasualtyRequest:
	var request := ForceCasualtyRequest.new()
	request.brigade_id = p_brigade_id
	request.battalion_type = p_battalion_type
	request.count = 1
	request.cause = p_cause
	request.source_location = p_source
	return request
