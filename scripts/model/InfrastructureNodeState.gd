extends Resource
class_name InfrastructureNodeState

## One port/airbridge's runtime lifecycle, keyed by infra_id in InfrastructureState.nodes (plan 0047).
##
## WHY THIS IS A RESOURCE AND NOT THE DICTIONARY IT USED TO BE. The mutation-authority gate resolves
## the RECEIVER's type before judging a write, so a value inside an untyped Dictionary is invisible to
## it — `node["status"] = ...` names no type at all. As three nested dictionaries this state could not
## be protected however carefully the manifest was written. Typing it is the precondition for
## enforcement, not tidiness. (Plan 0045 learned the same thing on SealiftCohort.)
##
## The field is `node_status`, not `status`: a protected field NAME is claimed repo-wide, and the
## manifest's own _schema_rules ask for distinctive names. The SERIALIZED key stays "status".
##
## All three fields are protected state of the `infrastructure` aggregate; the writer list lives in
## tools/mutation_authority_manifest.json and is not copied here.

## taiwanese (Green-run, never usable by Red) -> seized (hex Red-owned; 0 throughput) -> degraded ->
## operational (JLSF-repaired). Status never regresses on recapture; contribution is gated by current
## ownership at read time in InfrastructureResolver.red_offload_nodes.
@export var node_status: String = InfrastructureState.STATUS_TAIWANESE

## Ticks left in the current repair stage. 0 means "no stage armed", not "done".
@export var repair_turns_remaining: int = 0

## none | queued (order accepted, awaiting lift) | enroute (riding a sealift cohort) | arrived (at the
## port; drives repair).
@export var jlsf: String = InfrastructureState.JLSF_NONE


## Key names and ORDER are the pre-0047 dictionary's, exactly. Nothing reads this today, but plan
## 0031 is expected to serialize node state and the shape is free to keep.
func to_dict() -> Dictionary:
	return {
		"status": node_status,
		"repair_turns_remaining": repair_turns_remaining,
		"jlsf": jlsf,
	}
