class_name ForceOffloadRequest
extends Resource

@export var source: ForceLocation.Kind = ForceLocation.Kind.OFFLOADING
@export var destination: ForceLocation.Kind = ForceLocation.Kind.ASHORE
@export var landings: Array = []
## JLSF rows delivered in the same physical offload transaction. They are cargo, not force, and do
## not acquire a ForceLocation; the authority only removes their ids from shared transport storage.
@export var cargo_arrivals: Array = []


static func from_landings(p_landings: Array) -> ForceOffloadRequest:
	return from_resolution(p_landings, [])


static func from_resolution(p_landings: Array, p_cargo_arrivals: Array) -> ForceOffloadRequest:
	var request := ForceOffloadRequest.new()
	request.landings = p_landings.duplicate(true)
	request.cargo_arrivals = p_cargo_arrivals.duplicate(true)
	return request
