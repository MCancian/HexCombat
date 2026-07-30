extends Resource
class_name ShipState

## The checked per-ship-type view of the fleet: how many hulls of this type exist, how many are left,
## and which bucket each survivor is in. It is a PROJECTION — `SealiftState` is the truth about where a
## hull is, and `SealiftTransitions` (the fleet authority, plan 0045) is the only production writer of
## every field below. Nothing else may assign them, and nothing serializes this Resource, so the bins
## are a runtime contract rather than a fixture one.
##
## `sent_original` was removed in plan 0045: the projection assigned it `= surviving_sent` every turn,
## which made its `sent_original >= surviving_sent` invariant true by construction, and nothing read it.
## A real "how big was the wave before losses" fact belongs on the crossing summary, which is where the
## wave is actually known.

@export var ship_type: String = ""
@export var fleet_total: int = 0
@export var fleet_surviving_total: int = 0
@export var ready: int = 0
@export var surviving_sent: int = 0
@export var offloading: int = 0
@export var returning: int = 0
@export var destroyed: int = 0


func validate() -> bool:
	var values: Array[int] = [
		fleet_total,
		fleet_surviving_total,
		ready,
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
	return true
