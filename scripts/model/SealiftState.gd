extends Resource
class_name SealiftState

## Cross-turn sealift state for the sustained amphibious lift model (plan 0004). Owned by GameState,
## built by SealiftStateBuilder at scenario load, ticked + advanced by SealiftResolver each turn
## before the crossing. Holds the four persistent pieces the old one-shot ship_reserve lacked:
##
##   1. mainland_pool   — follow-on troops still ashore on the mainland, waiting to embark.
##   2. cohorts         — in-transit ship groups, each binding the specific hulls loaded in one
##                        embark to the specific BNs they carry (makes hull-freeing unambiguous).
##   3. return_pipeline — hulls cycling back to reload/repair before they are ready to sail again.
##   4. escort_sam      — per-escort-type SAM inventory, so escorts run low and divert to reload.
##
## to_dict() is the debug/inspection view of the whole lift in one dictionary. It has no production
## consumer today — no golden fixture, no observation payload and no loader reads it back — so it is
## NOT a byte contract, despite what this header claimed before plan 0045 checked. Its shape is pinned
## by a test so that stays true on purpose rather than by accident.
##
## Determinism: this Resource carries no RNG; it is advanced with deterministic ordering only.
## Ownership: `mainland_pool` and `cohorts` membership belong to the force aggregate (ForceTransitions);
## the return pipeline and escort magazines belong to the sealift/fleet aggregate (SealiftTransitions).
## The exact split lives in tools/mutation_authority_manifest.json, not here.

## Follow-on brigades not yet embarked. Same entry shape as GameState.ship_reserve —
## {brigade_id, locked_beach, beach_hex, offset_bearing, bns:[{id, type}]} — so embark simply drains
## BN dicts from these entries into the active reserve as ready amphibious capacity allows. A brigade
## appears in exactly ONE of {first echelon (seed reserve), mainland_pool}, so BN ids stay unique.
@export var mainland_pool: Array = []

## In-transit ship cohorts (see SealiftCohort). A cohort is created by one embark (the hulls loaded that
## turn + the BN ids they carry), flips sent -> offloading after the crossing, and is dropped once its
## bn_ids drain to empty — at which point its surviving hulls enter return_pipeline.
@export var cohorts: Array[SealiftCohort] = []

## Per-ship-type return/reload pipeline: ship_type (String) -> Array of
## {count: int, turns_remaining: int}. Freed amphibious hulls and reloading escorts land here; each
## turn SealiftResolver decrements turns_remaining and moves count back to ShipState.ready at 0.
@export var return_pipeline: Dictionary = {}

## Per-escort-type SAM magazine, CURRENT rounds: ship_type (String) -> count (int). Depleted by
## interception in the crossing (AntishipCrossing). EMPTY means the magazine is unmodelled (unlimited
## interception, pre-0004 behavior) — it is only seeded when a scenario opts in via
## escort_reload_time_turns > 0. An escort type at/below its threshold diverts to reload.
@export var escort_sam: Dictionary = {}
## Per-escort-type SAM loadout max (ship_type -> int): the value escort_sam is refilled to when the
## type finishes reloading. Empty when the magazine is unmodelled.
@export var escort_sam_max: Dictionary = {}
## Per-escort-type reload trigger (ship_type -> int): when escort_sam drops to/below this after a
## crossing, the type diverts to reload for escort_reload_time_turns. Empty when unmodelled.
@export var escort_sam_threshold: Dictionary = {}
## Escort types currently reloading (ship_type -> turns_remaining). While present, the type does not
## screen the crossing; when its timer hits 0, escort_sam is refilled to escort_sam_max and it
## returns to the screen. Advanced by SealiftResolver each turn.
@export var escort_reload: Dictionary = {}

const STATE_SENT := "sent"
const STATE_OFFLOADING := "offloading"


## BN ids currently bound to a "sent" cohort — the battalions crossing THIS turn. The crossing slices
## its wave out of the full ship_reserve with these, so only sailing BNs are attrited while battalions
## already offloading stay safe ashore (plan 0004 D3). Read-only: it answers a question about the
## cohorts, it does not touch them.
func sent_cohort_bn_ids() -> Dictionary:
	var ids: Dictionary = {}
	for cohort in cohorts:
		if not cohort.is_sent():
			continue
		for bn_id in cohort.bn_ids:
			ids[bn_id] = true
	return ids


func to_dict() -> Dictionary:
	var cohort_dicts: Array = []
	for cohort in cohorts:
		cohort_dicts.append(cohort.to_dict())
	return {
		"mainland_pool": mainland_pool.duplicate(true),
		"cohorts": cohort_dicts,
		"return_pipeline": return_pipeline.duplicate(true),
		"escort_sam": escort_sam.duplicate(true),
		"escort_sam_max": escort_sam_max.duplicate(true),
		"escort_sam_threshold": escort_sam_threshold.duplicate(true),
		"escort_reload": escort_reload.duplicate(true),
	}


## Fail-loud structural invariants (mirrors ShipState.validate's role): no negative counts anywhere,
## cohorts well-formed with a legal state. Returns false + push_error on the first violation.
func validate() -> bool:
	for entry_value in mainland_pool:
		var entry: Dictionary = entry_value
		if not entry.has("brigade_id") or not entry.has("bns"):
			push_error("SealiftState: malformed mainland_pool entry %s" % entry)
			return false

	for cohort in cohorts:
		if cohort.cohort_state != STATE_SENT and cohort.cohort_state != STATE_OFFLOADING:
			push_error("SealiftState: cohort has illegal state %s" % cohort.cohort_state)
			return false
		for count in cohort.hulls_by_type.values():
			if int(count) < 0:
				push_error("SealiftState: negative cohort hull count")
				return false

	for ship_type in return_pipeline.keys():
		for slot_value in (return_pipeline[ship_type] as Array):
			var slot: Dictionary = slot_value
			if int(slot.get("count", 0)) < 0 or int(slot.get("turns_remaining", 0)) < 0:
				push_error("SealiftState: negative return_pipeline slot for %s" % ship_type)
				return false

	for ship_type in escort_sam.keys():
		if int(escort_sam[ship_type]) < 0:
			push_error("SealiftState: negative escort_sam for %s" % ship_type)
			return false

	for ship_type in escort_reload.keys():
		if int(escort_reload[ship_type]) < 0:
			push_error("SealiftState: negative escort_reload for %s" % ship_type)
			return false

	return true
