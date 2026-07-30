extends Resource
class_name InfrastructureState

## Cross-turn offload-infrastructure status (plan 0006). Owned by GameState, built by
## InfrastructureStateBuilder at scenario load, advanced by InfrastructureResolver during the
## offload phase. Port of TIV infrastructure_status (infrastructure_manager.py) adapted to
## in-memory per-turn recompute.

## Per-node lifecycle: infra_id (String) -> InfrastructureNodeState. The per-node fields and their
## meanings live on that class; this container owns only the mapping.
@export var nodes: Dictionary = {}

const STATUS_TAIWANESE := "taiwanese"
const STATUS_SEIZED := "seized"
const STATUS_DEGRADED := "degraded"
const STATUS_OPERATIONAL := "operational"
const JLSF_NONE := "none"
const JLSF_QUEUED := "queued"
const JLSF_ENROUTE := "enroute"
const JLSF_ARRIVED := "arrived"


## Deep copy in the pre-0047 dictionary shape: {"nodes": {id: {status, repair_turns_remaining, jlsf}}},
## same key names and order. Typing the node must not be visible here.
func to_dict() -> Dictionary:
	var node_dicts: Dictionary = {}
	for id in nodes.keys():
		var node: InfrastructureNodeState = nodes[id]
		node_dicts[id] = node.to_dict()
	return {"nodes": node_dicts}


## Fail-loud structural invariants: every node has a legal status, a legal jlsf, and
## repair_turns_remaining >= 0. Returns false + push_error on the first violation.
func validate() -> bool:
	var valid_statuses := [STATUS_TAIWANESE, STATUS_SEIZED, STATUS_DEGRADED, STATUS_OPERATIONAL]
	var valid_jlsf := [JLSF_NONE, JLSF_QUEUED, JLSF_ENROUTE, JLSF_ARRIVED]

	for id in nodes.keys():
		# Checked before casting, deliberately: `nodes` is an untyped Dictionary, so a caller CAN put
		# a stray value in it, and this method's whole contract is to return false + push_error rather
		# than to die. A bare cast would crash before delivering the diagnostic it promises.
		var node_val: Variant = nodes[id]
		if not (node_val is InfrastructureNodeState):
			push_error("InfrastructureState: node %s is not an InfrastructureNodeState" % id)
			return false
		var node: InfrastructureNodeState = node_val

		if not node.node_status in valid_statuses:
			push_error("InfrastructureState: node %s has illegal status %s" % [id, node.node_status])
			return false

		if not node.jlsf in valid_jlsf:
			push_error("InfrastructureState: node %s has illegal jlsf %s" % [id, node.jlsf])
			return false

		if node.repair_turns_remaining < 0:
			push_error("InfrastructureState: node %s has negative repair_turns_remaining %s" % [
				id, node.repair_turns_remaining])
			return false

	return true
