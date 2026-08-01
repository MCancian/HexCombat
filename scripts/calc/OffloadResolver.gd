class_name OffloadResolver
extends RefCounted

## Pure resolver for the D1 amphibious offload phase: runs the OffloadCalculator day and reports
## exact troop/cargo landing plans without changing reserve or cohort membership. Consumes NO dice.
## ReinforcementPhases passes the typed request to ForceTransitions, then owns infrastructure,
## ownership, pending_lost_at_sea, fleet projection, and the EventBus emit.
##
## CAVEAT, and it is the reason this file is named in plan 0058. "Without changing reserve or cohort
## MEMBERSHIP" is accurate and is not the whole story: this file appends the caller's live
## `ship_reserve` entries into `troop_reserve` (:63) and hands them to `OffloadCalculator` (:68),
## which writes `offload_progress_tons` into their BN dicts. So campaign state IS changed on this
## call path, transitively, through a helper. That makes this file a live instance of the blind spot
## `tools/validate_authority_call_placement.gd` documents — it sees direct authority calls, so this
## reads as clean and `scripts/calc/`'s claim is not actually true here today. Plan 0058 hoists the
## write into `ForceTransitions.apply_offload`; do not treat a green placement run as proof that this
## path applies nothing.


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
## Returns the legacy manifest/projections plus a typed force_request. A brigade whose FIRST landed
## BN came ashore through an infra node lands at the node's hex instead of the entry's beach_hex.
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

	var plan := _plan_landings(manifest, troop_reserve, brigades, infra_nodes)

	var jlsf_arrivals: Array = []
	var pass_through_reserve: Array = []
	for jlsf_entry_value in jlsf_entries:
		var jlsf_entry: Dictionary = jlsf_entry_value
		if String(owner_by_hex.get(String(jlsf_entry.get("beach_hex", "")), "")) == HexOwner.RED:
			var bn_ids: Array = []
			for bn_value in jlsf_entry.get("bns", []):
				bn_ids.append(String((bn_value as Dictionary).get("id", "")))
			jlsf_arrivals.append({"port_id": String(jlsf_entry.get("port_id", "")), "bn_ids": bn_ids})
		else:
			pass_through_reserve.append(jlsf_entry)

	manifest["landed_brigade_ids"] = plan["landed_brigade_ids"]
	var all_remaining: Array = plan["remaining_entries"].duplicate()
	all_remaining.append_array(pass_through_reserve)
	return {
		"manifest": manifest,
		"remaining_ship_reserve": all_remaining,
		"landings": plan["landings"],
		"jlsf_arrivals": jlsf_arrivals,
		"landed_bn_ids_by_brigade": plan["landed_bn_ids_by_brigade"],
		"troop_landing_plan": plan["landing_plan"],
		"force_request": ForceOffloadRequest.from_resolution(plan["landing_plan"], jlsf_arrivals),
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


## Compute the landing plan (which BN ids land per brigade) without mutating reserve entries.
## Returns {"landed_brigade_ids": Array[String], "landings": placement dicts,
## "remaining_entries": entries still holding BNs, "landed_bn_ids_by_brigade": {brigade_id: {bn_id: true}},
## "landing_plan": [{brigade_id, bn_ids, hex_id, offset_bearing}]}.
static func _plan_landings(
		manifest: Dictionary, troop_reserve: Array,
		brigades: Dictionary, infra_nodes: Array) -> Dictionary:
	var maps := _landing_maps(manifest, infra_nodes)
	var brigade_ids: Array[String] = []
	var landings: Array = []
	var remaining: Array = []
	var plans: Array = []
	for entry_value in troop_reserve:
		var entry: Dictionary = entry_value
		var brigade_id := String(entry["brigade_id"])
		if not maps["ids"].has(brigade_id):
			remaining.append(entry.duplicate(true))
			continue
		var result := _plan_reserve_entry(
			entry, maps["ids"][brigade_id], String(maps["hexes"].get(brigade_id, "")), brigades)
		plans.append(result["plan"])
		if result["first_landing"]:
			brigade_ids.append(brigade_id)
			landings.append(result["landing"])
		if result["remaining"] != null:
			remaining.append(result["remaining"])
	return {
		"landed_brigade_ids": brigade_ids,
		"landings": landings,
		"remaining_entries": remaining,
		"landed_bn_ids_by_brigade": maps["ids"],
		"landing_plan": plans,
	}


static func _landing_maps(manifest: Dictionary, infra_nodes: Array) -> Dictionary:
	var node_hexes: Dictionary = {}
	for node_value in infra_nodes:
		var node: Dictionary = node_value
		node_hexes[String(node.get("id", ""))] = String(node.get("hex_id", ""))
	var ids: Dictionary = {}
	var hexes: Dictionary = {}
	for landed_value in manifest["manifest_landed"]:
		var landed: Dictionary = landed_value
		var brigade_id := String(landed["brigade_id"])
		if not ids.has(brigade_id):
			ids[brigade_id] = {}
			hexes[brigade_id] = String(node_hexes.get(String(landed.get("node_id", "")), ""))
		ids[brigade_id][String(landed["bn_id"])] = true
	return {"ids": ids, "hexes": hexes}


static func _plan_reserve_entry(
		entry_value: Dictionary, landed_ids: Dictionary,
		preferred_hex: String, brigades: Dictionary) -> Dictionary:
	var entry := entry_value.duplicate(true)
	var landed: Array = []
	var kept: Array = []
	for bn_value in entry["bns"]:
		var bn: Dictionary = bn_value
		if landed_ids.has(String(bn["id"])):
			landed.append(String(bn["id"]))
		else:
			kept.append(bn)
	var brigade_id := String(entry["brigade_id"])
	var brigade: Brigade = brigades.get(brigade_id)
	var first := brigade != null and brigade.hex_id.is_empty()
	var hex_id := preferred_hex if not preferred_hex.is_empty() else String(entry["beach_hex"])
	var offset := float(entry["offset_bearing"])
	var remaining = null
	if not kept.is_empty():
		entry["bns"] = kept
		remaining = entry
	return {
		"first_landing": first,
		"landing": {"brigade_id": brigade_id, "beach_hex": hex_id, "offset_bearing": offset},
		"remaining": remaining,
		"plan": {
			"brigade_id": brigade_id, "bn_ids": landed,
			"hex_id": hex_id if first else "", "offset_bearing": offset,
		},
	}
