class_name SealiftCohort
extends Resource

## One in-transit ship group: the exact hulls loaded in one embark bound to the exact battalions they
## carry (plan 0004). Binding them makes hull-freeing unambiguous — when the last battalion of a cohort
## is ashore or drowned, THOSE hulls are free, and no accounting is needed to work out which.
##
## It is deliberately a typed Resource rather than the dictionary it was until plan 0045, because a
## cohort is the one object the two transport authorities SHARE, and they split it by field:
##
##   `bn_ids`      — who is aboard. The FORCE aggregate owns it (ForceTransitions), which is what binds
##                   a battalion's existence, its roster and its landing to one writer.
##   `hulls_by_type`,
##   `cohort_state` — what floats and which leg it is on. The SEALIFT/FLEET aggregate owns them
##                   (SealiftTransitions), which is what keeps the fleet projection honest.
##
## As a dictionary that split could not be enforced: the mutation-authority gate resolves the receiver's
## TYPE, and an untyped `cohort["hulls_by_type"][t] = n` names no type at all (it is the aliased-container
## blind spot the validator's own header documents). Typed, both halves are checked at the write site.
##
## `cohort_state` is spelled out rather than called `state`: the gate protects field NAMES, and `state`
## is used all over this codebase for something else entirely, so protecting that name would turn every
## unrelated `x.state = …` into a suspect write.

## {ship_type (String) -> hull count (int)}. Only CARRIER hulls appear: escorts screen the wave from the
## ready pool and are never bound to a cohort.
@export var hulls_by_type: Dictionary = {}

## The battalions aboard, by id. Drained as they land (offload) or drown (crossing loss); when it is
## empty the cohort has done its job and the force authority drops it.
@export var bn_ids: Array[String] = []

## SealiftState.STATE_SENT while it crosses, STATE_OFFLOADING once it is ashore-bound. The constants stay
## on SealiftState: they name states of the lift as a whole and predate this Resource.
@export var cohort_state: String = SealiftState.STATE_SENT


## A cohort that is crossing THIS turn. `hulls` and `ids` are copied, so the caller's plan cannot keep
## mutating a live cohort through an alias it still holds.
static func sent(hulls: Dictionary, ids: Array) -> SealiftCohort:
	return _build(hulls, ids, SealiftState.STATE_SENT)


## A cohort that is already ashore-bound. Used by the unopposed-offload façade, which skips the crossing
## entirely and therefore has to start where the crossing would have left it.
static func offloading(hulls: Dictionary, ids: Array) -> SealiftCohort:
	return _build(hulls, ids, SealiftState.STATE_OFFLOADING)


static func _build(hulls: Dictionary, ids: Array, initial_state: String) -> SealiftCohort:
	var cohort := SealiftCohort.new()
	cohort.hulls_by_type = hulls.duplicate(true)
	cohort.bn_ids = ids_as_strings(ids)
	cohort.cohort_state = initial_state
	return cohort


## Convert any array of ids into the typed array `bn_ids` requires. Callers building a replacement id
## list (a drain, a filter) go through this rather than assigning an untyped Array, which GDScript
## refuses at runtime.
static func ids_as_strings(ids: Array) -> Array[String]:
	var typed: Array[String] = []
	for id_value in ids:
		typed.append(String(id_value))
	return typed


func is_sent() -> bool:
	return cohort_state == SealiftState.STATE_SENT


func is_empty() -> bool:
	return bn_ids.is_empty()


## Total hulls aboard, all types — the "is this cohort still holding shipping" question.
func hull_count() -> int:
	var total := 0
	for count in hulls_by_type.values():
		total += int(count)
	return total


func to_dict() -> Dictionary:
	return {
		"hulls_by_type": hulls_by_type.duplicate(true),
		"bn_ids": bn_ids.duplicate(),
		"cohort_state": cohort_state,
	}
