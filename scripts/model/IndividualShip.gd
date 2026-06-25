extends Resource
class_name IndividualShip

const DAMAGE_STATUSES := ["undamaged", "damaged", "sunk"]
const OPERATIONAL_STATES := ["ready", "sent", "offloading", "returning"]

@export var ship_id: String = ""
@export var ship_class: String = ""
@export var damage_status: String = "undamaged"
@export var operational_state: String = "ready"
@export var flotilla_id: int = -1
@export var hq10_current: int = 0
@export var hq10_max: int = 0
@export var hhq9_current: int = 0
@export var hhq9_max: int = 0
@export var assigned_route_type: String = ""
@export var assigned_route_id: String = ""
# Repair, embark, multi-turn-offload, and return-destination fields are deferred to D3.


func validate() -> bool:
	if damage_status not in DAMAGE_STATUSES:
		push_error("invalid damage_status %s for %s" % [damage_status, ship_id])
		return false
	if operational_state not in OPERATIONAL_STATES:
		push_error("invalid operational_state %s for %s" % [operational_state, ship_id])
		return false
	var ammo_values := {
		"hq10_current": hq10_current,
		"hq10_max": hq10_max,
		"hhq9_current": hhq9_current,
		"hhq9_max": hhq9_max,
	}
	for field_name in ammo_values.keys():
		if int(ammo_values[field_name]) < 0:
			push_error("negative %s for %s" % [String(field_name), ship_id])
			return false
	if hq10_current > hq10_max:
		push_error("hq10_current exceeds max for %s" % ship_id)
		return false
	if hhq9_current > hhq9_max:
		push_error("hhq9_current exceeds max for %s" % ship_id)
		return false
	return true


func is_sunk() -> bool:
	return damage_status == "sunk"
