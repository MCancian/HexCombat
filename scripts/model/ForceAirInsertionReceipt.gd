class_name ForceAirInsertionReceipt
extends Resource

## Which pool entries were drained (how many brigade entries removed from pool).
@export var pool_entries_drained: int = 0

## How many battalions landed (sum of all landing.landed_bns size).
@export var battalions_landed: int = 0

## How many battalions lost (sum of all landing.lost_bns size).
@export var battalions_lost: int = 0

## Casualty receipts for each lost BN.
@export var casualty_receipts: Array[ForceCasualtyReceipt] = []

## Placement receipts for each first landing.
@export var placement_receipts: Array[ForcePlacementReceipt] = []

## Brigade ids placed on map this turn.
@export var placed_brigades: Array[String] = []

## Whether the operation succeeded.
@export var success: bool = false

## Error message if the request was refused.
@export var error: String = ""


static func succeeded() -> ForceAirInsertionReceipt:
	var receipt := ForceAirInsertionReceipt.new()
	receipt.success = true
	return receipt


static func refused(msg: String) -> ForceAirInsertionReceipt:
	var r := ForceAirInsertionReceipt.new()
	r.error = msg
	push_error(msg)
	return r
