class_name OffloadResolver
extends RefCounted

## Pure resolver for the D1 amphibious offload phase (refactor_audit item 10, Phase C): runs the
## OffloadCalculator day, removes landed BNs from their reserve entries (in place), and reports
## which brigades make their first landing. Consumes NO dice (deterministic capacity ordering).
## No autoload/engine access — GameState's wrapper applies the landings via
## GameData.set_brigade_hex, reassigns ship_reserve, recomputes ownership, threads
## pending_lost_at_sea, and owns the EventBus.offload_resolved emit.


static func empty_manifest() -> Dictionary:
	return {
		"bns_sent": 0,
		"bns_landed": 0,
		"bns_waiting": 0,
		"lost_at_sea": 0,
		"manifest_landed": [],
		"manifest_deferred": [],
		"landed_brigade_ids": []
	}


static func priority_order(ship_reserve: Array) -> Array[String]:
	var order: Array[String] = []
	for reserve_entry_value in ship_reserve:
		var reserve_entry: Dictionary = reserve_entry_value
		order.append(String(reserve_entry["brigade_id"]))
	return order


## beaches: GameData.beaches (beach_id -> BeachDef). brigades: brigade_id -> Brigade (read-only
## here — landing application is the caller's job; the hex_id check decides FIRST landing).
## Plan 0006 (all defaulted; omitting them = pre-0006 beaches-only flat-cost behavior):
##   infra_nodes: Red-usable ports/airbridges from InfrastructureResolver.red_offload_nodes
##                ({id, kind, to_number, rate_tons, hex_id}).
##   cost_config: OffloadCostModel config ({} = flat TONS_PER_BN).
##   beach_to_to: beach_id -> TO (GameData.beach_to_to), for same-TO infra routing.
##   owner_by_hex: hex_id -> owner string; needed only to land JLSF cargo (see below).
## Beach occupancy (the valve) is derived here from `brigades`: non-destroyed RED brigades
## sitting on an active beach's hex count against that beach's BeachDef.depth.
## JLSF pseudo-entries (JlsfCargo.is_jlsf_entry) never enter the throughput math or the brigade
## landing path: one waits offshore until its target node's hex (its beach_hex) is Red-held,
## then delivers whole — reported in "jlsf_arrivals" [{port_id, bn_ids}] and dropped from the
## remaining reserve.
## Returns {"manifest": Dictionary (incl. landed_brigade_ids), "remaining_ship_reserve": Array,
## "landings": [{brigade_id, beach_hex, offset_bearing}, …], "jlsf_arrivals": Array}. A brigade
## whose FIRST landed BN came ashore through an infra node lands at the node's hex instead of
## the entry's beach_hex. Mutates each reserve entry's "bns" in place (landed BNs removed),
## matching the pre-extraction behavior.
static func resolve(
	turn_number: int,
	ship_reserve: Array,
	beaches: Dictionary,
	brigades: Dictionary,
	infra_nodes: Array = [],
	cost_config: Dictionary = {},
	beach_to_to: Dictionary = {},
	owner_by_hex: Dictionary = {},
) -> Dictionary:
	var jlsf_entries: Array = []
	var troop_reserve: Array = []
	for reserve_entry_value in ship_reserve:
		var reserve_entry: Dictionary = reserve_entry_value
		if JlsfCargo.is_jlsf_entry(reserve_entry):
			jlsf_entries.append(reserve_entry)
		else:
			troop_reserve.append(reserve_entry)

	var active_beach_ids := _active_beach_ids(troop_reserve)
	var valve := _occupancy_valve_inputs(active_beach_ids, beaches, brigades)
	var beach_capacity := OffloadCalculator.beach_capacity_bns(active_beach_ids, beaches)
	var manifest := OffloadCalculator.resolve_offload_day(
		turn_number, beach_capacity, troop_reserve, priority_order(troop_reserve),
		infra_nodes, cost_config, valve["occupancy"], valve["depth"], beach_to_to)

	var applied := _apply_manifest_to_reserve(manifest, troop_reserve, brigades, infra_nodes)
	var remaining_ship_reserve: Array = applied["remaining_ship_reserve"]

	# JLSF delivery: a pseudo-entry lands whole (no throughput cost) the moment its target node's
	# hex is Red-held; otherwise it stays offshore in the reserve, hulls committed.
	var jlsf_arrivals: Array = []
	for jlsf_entry_value in jlsf_entries:
		var jlsf_entry: Dictionary = jlsf_entry_value
		if String(owner_by_hex.get(String(jlsf_entry.get("beach_hex", "")), "")) == "red":
			var bn_ids: Array = []
			for bn_value in jlsf_entry.get("bns", []):
				bn_ids.append(String((bn_value as Dictionary).get("id", "")))
			jlsf_arrivals.append({"port_id": String(jlsf_entry.get("port_id", "")), "bn_ids": bn_ids})
		else:
			remaining_ship_reserve.append(jlsf_entry)

	manifest["landed_brigade_ids"] = applied["landed_brigade_ids"]
	return {
		"manifest": manifest,
		"remaining_ship_reserve": remaining_ship_reserve,
		"landings": applied["landings"],
		"jlsf_arrivals": jlsf_arrivals,
	}


## Distinct locked beaches across the troop reserve (fail-loud on a missing locked_beach).
static func _active_beach_ids(troop_reserve: Array) -> Array[int]:
	var active_beach_ids: Array[int] = []
	for reserve_entry_value in troop_reserve:
		var reserve_entry: Dictionary = reserve_entry_value
		var locked_beach := int(reserve_entry["locked_beach"])
		if locked_beach <= 0:
			push_error("Ship reserve entry has no locked_beach: %s" % String(reserve_entry["brigade_id"]))
			continue
		if locked_beach not in active_beach_ids:
			active_beach_ids.append(locked_beach)
	return active_beach_ids


## Occupancy valve inputs (plan 0006): landed RED brigades per active beach hex vs its depth.
## Returns {"occupancy": beach_id -> count, "depth": beach_id -> BeachDef.depth}.
static func _occupancy_valve_inputs(active_beach_ids: Array[int], beaches: Dictionary, brigades: Dictionary) -> Dictionary:
	var beach_occupancy: Dictionary = {}
	var beach_depth: Dictionary = {}
	for beach_id in active_beach_ids:
		var beach: BeachDef = beaches.get(beach_id, null)
		if beach == null:
			continue
		beach_depth[beach_id] = beach.depth
		var count := 0
		for brigade_value in brigades.values():
			var brigade: Brigade = brigade_value
			if brigade.team == Brigade.Team.RED and not brigade.destroyed and brigade.hex_id == beach.hex_id:
				count += 1
		beach_occupancy[beach_id] = count
	return {"occupancy": beach_occupancy, "depth": beach_depth}


## Remove landed BNs from their reserve entries (in place), report first landings, and keep the
## still-populated entries. A brigade whose FIRST landed BN came ashore through an infra node
## lands at the node's hex instead of the entry's beach_hex.
## Returns {"landed_brigade_ids": Array[String], "landings": placement dicts,
## "remaining_ship_reserve": entries that still hold BNs}.
static func _apply_manifest_to_reserve(manifest: Dictionary, troop_reserve: Array, brigades: Dictionary, infra_nodes: Array) -> Dictionary:
	var node_hex_by_id: Dictionary = {}
	for node_value in infra_nodes:
		var node: Dictionary = node_value
		node_hex_by_id[String(node.get("id", ""))] = String(node.get("hex_id", ""))

	var landed_bn_ids_by_brigade: Dictionary = {}
	var first_landing_hex_by_brigade: Dictionary = {}  # brigade_id -> node hex ("" = beach entry hex)
	for landed_value in manifest["manifest_landed"]:
		var landed: Dictionary = landed_value
		var brigade_id := String(landed["brigade_id"])
		var bn_id := String(landed["bn_id"])
		if brigade_id not in landed_bn_ids_by_brigade:
			landed_bn_ids_by_brigade[brigade_id] = {}
			# First landed BN this turn decides where a first-landing brigade comes ashore: the
			# infra node's hex when it landed through a port/airbridge, else the entry's beach_hex.
			first_landing_hex_by_brigade[brigade_id] = String(node_hex_by_id.get(String(landed.get("node_id", "")), ""))
		landed_bn_ids_by_brigade[brigade_id][bn_id] = true

	var landed_brigade_ids: Array[String] = []
	var landings: Array = []
	var remaining_ship_reserve: Array = []
	for reserve_entry_value in troop_reserve:
		var reserve_entry: Dictionary = reserve_entry_value
		var brigade_id := String(reserve_entry["brigade_id"])
		if brigade_id in landed_bn_ids_by_brigade:
			var landed_bn_ids: Dictionary = landed_bn_ids_by_brigade[brigade_id]
			var remaining_bns: Array = []
			for bn_value in reserve_entry["bns"]:
				var bn: Dictionary = bn_value
				if String(bn["id"]) not in landed_bn_ids:
					remaining_bns.append(bn)
			reserve_entry["bns"] = remaining_bns

			var brigade: Brigade = brigades.get(brigade_id)
			if brigade == null:
				push_error("Offload manifest references unknown brigade_id: %s" % brigade_id)
			elif brigade.hex_id.is_empty():
				var node_hex := String(first_landing_hex_by_brigade.get(brigade_id, ""))
				landings.append({
					"brigade_id": brigade_id,
					"beach_hex": node_hex if not node_hex.is_empty() else String(reserve_entry["beach_hex"]),
					"offset_bearing": float(reserve_entry["offset_bearing"]),
				})
				landed_brigade_ids.append(brigade_id)

		if (reserve_entry["bns"] as Array).is_empty():
			continue
		remaining_ship_reserve.append(reserve_entry)

	return {
		"landed_brigade_ids": landed_brigade_ids,
		"landings": landings,
		"remaining_ship_reserve": remaining_ship_reserve,
	}
