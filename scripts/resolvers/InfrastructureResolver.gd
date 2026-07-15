class_name InfrastructureResolver
extends RefCounted

## Pure resolver for infrastructure seizure + JLSF repair clock. Source oracle: TIV
## infrastructure_manager.py (refresh_status_from_hex = seizure; progress_status = JLSF repair
## clock). Differences: in-memory state, repair requires hex still Red-held (pauses otherwise),
## status never regresses on recapture (contribution gated by ownership at read time in
## red_offload_nodes). No dice, no autoload access.

## Advance seizure + repair one turn. owner_by_hex: hex_id -> owner string (HexOwner.* values,
## e.g. "red"). repair_turns_per_stage: ticks per repair stage (seized->degraded, degraded->
## operational); default 1 mirrors TIV (+1 turn per stage). Mutates state in place (contract);
## returns {"events": Array of {id, event}} with event in {"seized", "degraded", "operational"}.
static func tick(state: InfrastructureState, infra_defs: Dictionary, owner_by_hex: Dictionary, repair_turns_per_stage: int = 1) -> Dictionary:
	var events: Array = []
	var ids: Array = state.nodes.keys()
	ids.sort()
	for id in ids:
		var def_val: Variant = infra_defs.get(id)
		if def_val == null:
			push_error("InfrastructureResolver.tick: no def for node %s" % id)
			continue
		var def_data: InfrastructureDef = def_val
		var node_val: Variant = state.nodes[id]
		var node: Dictionary = node_val
		var is_red := String(owner_by_hex.get(def_data.hex_id, "")) == "red"

		# Seizure
		if node["status"] == InfrastructureState.STATUS_TAIWANESE and is_red:
			node["status"] = InfrastructureState.STATUS_SEIZED
			node["repair_turns_remaining"] = 0
			events.append({"id": id, "event": "seized"})

		# Repair
		if node["jlsf"] == InfrastructureState.JLSF_ARRIVED and is_red:
			var status: String = node["status"]
			if status == InfrastructureState.STATUS_SEIZED or status == InfrastructureState.STATUS_DEGRADED:
				var repair: int = node["repair_turns_remaining"]
				if repair == 0:
					node["repair_turns_remaining"] = repair_turns_per_stage
				node["repair_turns_remaining"] -= 1
				if node["repair_turns_remaining"] == 0:
					if node["status"] == InfrastructureState.STATUS_SEIZED:
						node["status"] = InfrastructureState.STATUS_DEGRADED
						events.append({"id": id, "event": "degraded"})
					elif node["status"] == InfrastructureState.STATUS_DEGRADED:
						node["status"] = InfrastructureState.STATUS_OPERATIONAL
						events.append({"id": id, "event": "operational"})

	return {"events": events}


## Red-usable offload nodes this turn: Red-held (owner "red") AND status degraded/operational.
## Returns Array (sorted by id) of {"id": String, "kind": String, "to_number": int,
## "rate_tons": float, "hex_id": String}. Rates: OffloadRates.OPERATIONAL_PORT / DEGRADED_PORT /
## OPERATIONAL_AIRBRIDGE / DEGRADED_AIRBRIDGE by (kind, status). hex_id lets the offload wrapper
## place a brigade whose first landed BN came ashore through the node at the node's hex.
static func red_offload_nodes(state: InfrastructureState, infra_defs: Dictionary, owner_by_hex: Dictionary) -> Array:
	var result: Array = []
	var ids: Array = state.nodes.keys()
	ids.sort()
	for id in ids:
		var def_val: Variant = infra_defs.get(id)
		if def_val == null:
			continue
		var def_data: InfrastructureDef = def_val
		var node_val: Variant = state.nodes[id]
		var node: Dictionary = node_val
		var status: String = String(node.get("status", ""))
		if status != InfrastructureState.STATUS_DEGRADED and status != InfrastructureState.STATUS_OPERATIONAL:
			continue
		var owner: String = String(owner_by_hex.get(def_data.hex_id, ""))
		if owner != "red":
			continue
		var rate: float = 0.0
		if def_data.kind == "port":
			if status == InfrastructureState.STATUS_OPERATIONAL:
				rate = OffloadRates.OPERATIONAL_PORT
			else:
				rate = OffloadRates.DEGRADED_PORT
		elif def_data.kind == "airbridge":
			if status == InfrastructureState.STATUS_OPERATIONAL:
				rate = OffloadRates.OPERATIONAL_AIRBRIDGE
			else:
				rate = OffloadRates.DEGRADED_AIRBRIDGE
		result.append({"id": id, "kind": def_data.kind, "to_number": def_data.to_number, "rate_tons": rate, "hex_id": def_data.hex_id})
	return result
