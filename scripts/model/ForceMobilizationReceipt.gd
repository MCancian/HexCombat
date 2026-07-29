class_name ForceMobilizationReceipt
extends Resource

## Number of brigades that arrived this turn.
@export var arrived: int = 0

## Battalions that arrived this turn.
@export var battalions_arrived: int = 0

## Placement receipts for each arrival.
@export var placement_receipts: Array[ForcePlacementReceipt] = []

## Brigade ids placed on map this turn.
@export var placed_brigades: Array[String] = []

## Brigade ids that were deferred.
@export var deferred: Array[String] = []

## Whether the operation succeeded.
@export var success: bool = false

## Error message if the request was refused.
@export var error: String = ""


static func ok(
	p_arrived: int,
	p_battalions: int,
	p_placements: Array[ForcePlacementReceipt],
	p_placed: Array[String],
	p_deferred: Array[String],
) -> ForceMobilizationReceipt:
	var r := ForceMobilizationReceipt.new()
	r.success = true
	r.arrived = p_arrived
	r.battalions_arrived = p_battalions
	r.placement_receipts = p_placements
	r.placed_brigades = p_placed
	r.deferred = p_deferred
	return r


static func refused(msg: String) -> ForceMobilizationReceipt:
	var r := ForceMobilizationReceipt.new()
	r.error = msg
	push_error(msg)
	return r
