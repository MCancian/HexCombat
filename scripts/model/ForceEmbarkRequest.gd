class_name ForceEmbarkRequest
extends Resource

## Closed transition vocabulary for troop rows. Cargo specs share the physical transaction but are
## identified explicitly and never interpreted as force locations.
@export var source: ForceLocation.Kind = ForceLocation.Kind.MAINLAND
@export var destination: ForceLocation.Kind = ForceLocation.Kind.AT_SEA
@export var brigade_specs: Array = []
@export var batch_bn_ids: Array[String] = []
@export var batch_hulls_by_type: Dictionary = {}

## {bn_id (String) -> carrier category (String)}: which class of hull is lifting each battalion in this
## batch. The offload cost matrix needs it (plan 0006 — heavy equipment comes off a civilian hull at a
## different rate than a military one), and it is carried in the REQUEST rather than stamped by the
## planner because the row it belongs on is force-owned: the authority applies it when it moves the
## battalion into the reserve, after the preflight, so a refused embark leaves no trace behind.
@export var ship_categories: Dictionary = {}


static func batch(
		p_brigade_specs: Array, p_batch_bn_ids: Array,
		p_hulls: Dictionary, p_ship_categories: Dictionary) -> ForceEmbarkRequest:
	var request := ForceEmbarkRequest.new()
	request.brigade_specs = p_brigade_specs.duplicate(true)
	for id_value in p_batch_bn_ids:
		request.batch_bn_ids.append(String(id_value))
	request.batch_hulls_by_type = p_hulls.duplicate(true)
	request.ship_categories = p_ship_categories.duplicate(true)
	return request
