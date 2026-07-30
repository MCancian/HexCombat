class_name JlsfCargo
extends RefCounted

## Builds the pseudo mainland_pool entry for a JLSF deployment (plan 0006). The entry
## must satisfy the sealift/crossing plumbing contracts: a REAL locked_beach id
## (AntishipResolver derives crossing target beaches from it and push_errors on unknown
## ids), beach_hex = the target node's hex (where the detachment comes ashore), and
## unique BN ids (cohort binding + crossing attrition draw operate on BN id strings).

const BRIGADE_ID_PREFIX := "JLSF:"
const BN_TYPE := "JLSF Detachment"
const CARGO_KIND := "jlsf"


## True when the reserve/pool entry is a JLSF pseudo-entry, not a troop brigade.
static func is_jlsf_entry(entry: Dictionary) -> bool:
	return String(entry.get("cargo", "")) == CARGO_KIND


## brigade id for a port: "JLSF:<port_id>"
static func brigade_id_for(port_id: String) -> String:
	return BRIGADE_ID_PREFIX + port_id


## Build the pseudo pool entry.
##   node_def: InfrastructureDef of the target port/airbridge.
##   beaches: GameData.beaches (beach_id int -> BeachDef).
##   beach_to_to: beach_id int -> to_number int.
##   bn_count: lift cost in BN-equivalents (scenario knob jlsf_lift_bn_equiv, default 4).
## locked_beach = the LOWEST beach id in the node's TO (same-TO staging); when the TO
## has no beach, the lowest beach id overall (any real beach keeps the crossing
## targeting legal).
static func build_pool_entry(node_def: InfrastructureDef, beaches: Dictionary, beach_to_to: Dictionary, bn_count: int) -> Dictionary:
	var sorted_ids: Array = beaches.keys()
	sorted_ids.sort()

	var locked_beach: int = 0
	for id_value in sorted_ids:
		var bid: int = int(id_value)
		if int(beach_to_to.get(bid, -1)) == node_def.to_number:
			locked_beach = bid
			break
	if locked_beach == 0 and not sorted_ids.is_empty():
		locked_beach = int(sorted_ids[0])
	if locked_beach == 0:
		push_error("JlsfCargo: no beaches loaded")

	var bns: Array = []
	for i in range(1, bn_count + 1):
		bns.append({
			"id": "JLSF:%s:%d" % [node_def.id, i],
			"type": BN_TYPE,
		})

	return {
		"brigade_id": brigade_id_for(node_def.id),
		"cargo": "jlsf",
		"port_id": node_def.id,
		"locked_beach": locked_beach,
		"beach_hex": node_def.hex_id,
		"offset_bearing": 0.0,
		"bns": bns,
	}


## Queueing policy (extracted from GameState): turn explicit deploy_jlsf orders + the auto_jlsf
## policy into pool entries. A node accepts one deployment while its jlsf marker is "none".
## Deterministic: explicit orders in submission order, then auto policy in sorted node order.
## push_errors on unknown explicit ids. Returns the new pool entries in queue order — the caller
## push_fronts them in this order (logistics open the port gate before more troops help).
##
## The marker flip goes through `InfrastructureTransitions.queue_jlsf` AT THE POINT the loop used to
## assign it, and the loop stays sequential rather than becoming a snapshot planner. That is not
## laziness: whether an entry is emitted is decided by state the PREVIOUS iteration wrote, so two
## explicit orders for the same port produce exactly one entry because the second iteration observes
## the `queued` the first one set. A planner working from a pre-loop snapshot would emit two.
static func queue_deployments(
	explicit_orders: Array,
	infra_state: InfrastructureState,
	infra_defs: Dictionary,
	beaches: Dictionary,
	beach_to_to: Dictionary,
	auto_jlsf: bool,
	bn_count: int,
) -> Array:
	var to_queue: Array[String] = []
	for port_id in explicit_orders:
		if not infra_state.nodes.has(port_id):
			push_error("deploy_jlsf order references unknown infrastructure id: %s" % port_id)
			continue
		to_queue.append(String(port_id))
	if auto_jlsf:
		var ids: Array = infra_state.nodes.keys()
		ids.sort()
		for id_value in ids:
			var id := String(id_value)
			var node: InfrastructureNodeState = infra_state.nodes[id]
			if node.node_status == InfrastructureState.STATUS_SEIZED and id not in to_queue:
				to_queue.append(id)

	var entries: Array = []
	for port_id in to_queue:
		if not InfrastructureTransitions.queue_jlsf(infra_state, port_id):
			continue
		entries.append(build_pool_entry(infra_defs.get(port_id), beaches, beach_to_to, bn_count))
	return entries
