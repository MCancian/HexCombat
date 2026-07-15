extends Resource
class_name InfrastructureState

## Cross-turn offload-infrastructure status (plan 0006). Owned by GameState, built by
## InfrastructureStateBuilder at scenario load, advanced by InfrastructureResolver during the
## offload phase. Port of TIV infrastructure_status (infrastructure_manager.py) adapted to
## in-memory per-turn recompute.

## Per-node lifecycle: infra_id (String) -> {status: String, repair_turns_remaining: int,
## jlsf: String}. status: taiwanese (Green-run, never usable by Red) -> seized (hex Red-owned;
## 0 throughput) -> degraded -> operational (JLSF-repaired). jlsf: none | queued (order accepted,
## awaiting lift) | enroute (riding a sealift cohort) | arrived (at the port; drives repair).
@export var nodes: Dictionary = {}

const STATUS_TAIWANESE := "taiwanese"
const STATUS_SEIZED := "seized"
const STATUS_DEGRADED := "degraded"
const STATUS_OPERATIONAL := "operational"
const JLSF_NONE := "none"
const JLSF_QUEUED := "queued"
const JLSF_ENROUTE := "enroute"
const JLSF_ARRIVED := "arrived"


func to_dict() -> Dictionary:
	return {"nodes": nodes.duplicate(true)}


## Fail-loud structural invariants: every node value has a legal status, a legal jlsf, and
## repair_turns_remaining >= 0. Returns false + push_error on the first violation.
func validate() -> bool:
	var valid_statuses := [STATUS_TAIWANESE, STATUS_SEIZED, STATUS_DEGRADED, STATUS_OPERATIONAL]
	var valid_jlsf := [JLSF_NONE, JLSF_QUEUED, JLSF_ENROUTE, JLSF_ARRIVED]

	for id in nodes.keys():
		var node_val: Variant = nodes[id]
		var node: Dictionary = node_val

		var status: String = String(node.get("status", ""))
		if not status in valid_statuses:
			push_error("InfrastructureState: node %s has illegal status %s" % [id, status])
			return false

		var jlsf: String = String(node.get("jlsf", ""))
		if not jlsf in valid_jlsf:
			push_error("InfrastructureState: node %s has illegal jlsf %s" % [id, jlsf])
			return false

		var repair: int = int(node.get("repair_turns_remaining", -1))
		if repair < 0:
			push_error("InfrastructureState: node %s has negative repair_turns_remaining %s" % [id, repair])
			return false

	return true
