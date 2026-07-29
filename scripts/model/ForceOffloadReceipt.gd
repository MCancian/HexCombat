class_name ForceOffloadReceipt
extends Resource

@export var success: bool = false
@export var error: String = ""
@export var landed_brigade_ids: Array[String] = []
@export var landings: Array = []
@export var bn_ids_landed: Array[String] = []
@export var placement_receipts: Array[ForcePlacementReceipt] = []


static func ok(p_landed_brigade_ids: Array[String], p_landings: Array, p_bn_ids: Array[String], p_placements: Array[ForcePlacementReceipt]) -> ForceOffloadReceipt:
	var r := ForceOffloadReceipt.new()
	r.success = true
	r.landed_brigade_ids = p_landed_brigade_ids.duplicate()
	r.landings = p_landings.duplicate(true)
	r.bn_ids_landed = p_bn_ids.duplicate()
	r.placement_receipts = p_placements.duplicate()
	return r


static func refused(msg: String) -> ForceOffloadReceipt:
	var r := ForceOffloadReceipt.new()
	r.error = msg
	push_error(msg)
	return r
