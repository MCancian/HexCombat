extends Resource
class_name ShipState

@export var ship_type: String = ""
@export var fleet_total: int = 0
@export var fleet_surviving_total: int = 0
@export var ready: int = 0
@export var sent_original: int = 0
@export var surviving_sent: int = 0
@export var offloading: int = 0
@export var returning: int = 0
@export var destroyed: int = 0


func validate() -> bool:
	var values: Array[int] = [
		fleet_total,
		fleet_surviving_total,
		ready,
		sent_original,
		surviving_sent,
		offloading,
		returning,
		destroyed,
	]
	for value in values:
		if value < 0:
			push_error("ship_state negative value for %s" % ship_type)
			return false
	if ready + surviving_sent + offloading + returning + destroyed != fleet_total:
		push_error("ship_state total invariant failed for %s" % ship_type)
		return false
	if ready + surviving_sent + offloading + returning != fleet_surviving_total:
		push_error("ship_state surviving invariant failed for %s" % ship_type)
		return false
	if fleet_surviving_total > fleet_total:
		push_error("ship_state surviving exceeds total for %s" % ship_type)
		return false
	if sent_original < surviving_sent:
		push_error("ship_state sent_original invariant failed for %s" % ship_type)
		return false
	return true
