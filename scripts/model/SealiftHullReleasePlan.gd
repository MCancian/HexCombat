class_name SealiftHullReleasePlan
extends Resource

## The hulls that fell out of the cohorts drained this turn (plan 0045) — the hand-off from the FORCE
## authority, which decides that a cohort has no battalions left aboard and drops it, to the SEALIFT
## authority, which decides where those hulls go next (straight back to ready, or through the return
## pipeline for `amphibious_return_time_turns`).
##
## The batches are kept SEPARATE, one per freed cohort in cohort order, rather than summed into a
## single per-type total. That is deliberate: the return pipeline holds discrete slots, and one slot per
## (freed cohort, ship type) is the shape it has always had. Summing first would merge two cohorts'
## hulls into one slot — the same hulls returning on the same turn, but a different pipeline, and the
## moment return times ever differ per cohort it would be wrong as well as different.

## Per freed cohort: {ship_type (String) -> hull count (int)}, in the order the cohorts were freed and
## with each cohort's own hull key order preserved.
@export var batches: Array = []


static func of(p_batches: Array) -> SealiftHullReleasePlan:
	var plan := SealiftHullReleasePlan.new()
	for batch_value in p_batches:
		plan.batches.append((batch_value as Dictionary).duplicate(true))
	return plan


func is_empty() -> bool:
	return batches.is_empty()


## Every released hull summed per type — the reporting/assertion view. Never used to build the
## pipeline; see the note above on why the batches stay separate.
func total_by_type() -> Dictionary:
	var totals: Dictionary = {}
	for batch_value in batches:
		var batch: Dictionary = batch_value
		for ship_type in batch.keys():
			totals[String(ship_type)] = int(totals.get(String(ship_type), 0)) + int(batch[ship_type])
	return totals
