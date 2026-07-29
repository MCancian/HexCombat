class_name ForceEmbarkReceipt
extends Resource

@export var success: bool = false
@export var error: String = ""
@export var brigade_id: String = ""
@export var bn_ids_embarked: Array[String] = []


static func ok(p_brigade_id: String, p_bn_ids: Array) -> ForceEmbarkReceipt:
	var r := ForceEmbarkReceipt.new()
	r.success = true
	r.brigade_id = p_brigade_id
	for id in p_bn_ids:
		r.bn_ids_embarked.append(String(id))
	return r


static func refused(msg: String) -> ForceEmbarkReceipt:
	var r := ForceEmbarkReceipt.new()
	r.error = msg
	push_error(msg)
	return r
