class_name SealiftHullLossReceipt
extends Resource

## What one checked hull-loss application actually did (plan 0045). The crossing calculator reports
## how many hulls of each type it killed; the sealift authority decides which BUCKET each type loses
## them from and how many of them the bucket can actually give up. Those are different numbers, so
## both are recorded: `requested_by_type` is what the calculator asked for and `applied_by_type` is
## what the fleet booked.
##
## Why they can differ, and why that is not an error: a crossing can legitimately report more kills of
## a carrier type than the sent cohorts hold (the firing model works from the sailing snapshot, and
## mines/attrition are resolved independently), so the application is CAPPED at what is present. The
## cap is recorded rather than silently absorbed — `capped_types` names every type where it bit, which
## is what a phase summary or a reconciliation check reads.

## The bucket a type's losses came out of. Carriers are busy inside "sent" cohorts; escorts screen the
## wave out of the ready pool and are never bound to a cohort.
const SOURCE_SENT_COHORTS := "sent_cohorts"
const SOURCE_READY_SCREEN := "ready_screen"

const CAUSE_CROSSING := "crossing"

@export var cause: String = CAUSE_CROSSING
@export var requested_by_type: Dictionary = {}   # ship_type (String) -> hulls requested (int)
@export var applied_by_type: Dictionary = {}     # ship_type (String) -> hulls actually destroyed (int)
@export var source_by_type: Dictionary = {}      # ship_type (String) -> SOURCE_* (String)
@export var capped_types: Array[String] = []     # types where applied < requested


static func for_cause(p_cause: String) -> SealiftHullLossReceipt:
	var receipt := SealiftHullLossReceipt.new()
	receipt.cause = p_cause
	return receipt


## Record one type's outcome. Called once per requested type by the authority, in the order the
## request was iterated, so the receipt's key order mirrors the request's.
func record(ship_type: String, requested: int, applied: int, source: String) -> void:
	requested_by_type[ship_type] = requested
	applied_by_type[ship_type] = applied
	source_by_type[ship_type] = source
	if applied < requested:
		capped_types.append(ship_type)


func total_applied() -> int:
	var total := 0
	for count in applied_by_type.values():
		total += int(count)
	return total


func was_capped() -> bool:
	return not capped_types.is_empty()
