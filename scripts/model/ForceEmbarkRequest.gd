class_name ForceEmbarkRequest
extends Resource

## Closed transition vocabulary for troop rows. Cargo specs share the physical transaction but are
## identified explicitly and never interpreted as force locations.
@export var source: ForceLocation.Kind = ForceLocation.Kind.MAINLAND
@export var destination: ForceLocation.Kind = ForceLocation.Kind.AT_SEA
@export var brigade_specs: Array = []
@export var batch_bn_ids: Array[String] = []
@export var batch_hulls_by_type: Dictionary = {}


static func batch(
		p_brigade_specs: Array, p_batch_bn_ids: Array,
		p_hulls: Dictionary) -> ForceEmbarkRequest:
	var request := ForceEmbarkRequest.new()
	request.brigade_specs = p_brigade_specs.duplicate(true)
	for id_value in p_batch_bn_ids:
		request.batch_bn_ids.append(String(id_value))
	request.batch_hulls_by_type = p_hulls.duplicate(true)
	return request
