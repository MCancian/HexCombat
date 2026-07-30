class_name SealiftResolver
extends RefCounted

## Pure planner for the cross-turn sealift phase (plan 0004): runs at the top of each turn, BEFORE the
## anti-ship crossing. Two deterministic steps, no dice:
##
##   1. adopt  — any at-sea BN in ship_reserve not yet bound to a cohort (the programmed first
##               echelon on turn 1, or a straggler) is wrapped in a "sent" cohort using the same
##               minimum-lift derivation the crossing used before (ShipLoadingModel.build_sent_snapshots
##               over the FULL carrier set), so the default scenario's sent fleet is unchanged.
##   2. embark — remaining ready AMPHIBIOUS capacity loads follow-on BNs from the mainland pool
##               (departed brigades finished first, then new brigades), binding them in a new cohort.
##
## The return/reload pipelines are ticked by the coordinator through SealiftTransitions BEFORE this
## runs, and the hulls they released arrive here as `returned_by_type` — they are available to sail the
## same turn they arrive back, so they join the local ready pool the packer works against.
##
## Escorts (capacity 0) screen the wave and, unless they diverted to reload their SAM magazine, stay in
## the ready pool (same-turn round trip). Only carrier hulls (capacity > 0) enter cohorts and go busy.
## Amphibious-lift eligibility is classified by ShipDef.is_amphibious_lift() / is_carrier() / sails().
##
## It lives in `scripts/calc/` rather than `scripts/resolvers/` for one reason and one reason only: that
## directory's claim is that it holds no file which writes campaign state, and this one qualifies as of
## plan 0045. `AntishipResolver` still sits under `resolvers/` because it still rewrites the caller's
## reserve entries in place — same rule, opposite answer.
##
## Writes NO campaign state — not the sealift queues, not the cohorts, and not the battalion rows it
## plans over. Everything it decides comes back as a plan: cohort binding and mainland/reserve membership
## for ForceTransitions to apply, hull totals for SealiftTransitions, and the per-battalion carrier
## CATEGORY (plan 0006) as a {bn_id -> category} map rather than a stamp written into the reserve row.
## That last one used to be written here in place, which quietly made this planner a second writer of
## force-owned storage and could leave a category behind from an embark the authority then refused.


## state: SealiftState (READ for cohort/pool membership; never written here). ship_reserve: current
## active reserve (at-sea BNs). ready_by_type: {ship_type -> ready hull count} (from fleet
## ShipState.ready, before this turn's pipeline release). returned_by_type: {ship_type -> int} the
## pipeline released this turn. ship_defs: {ship_type -> ShipDef}.
##
## Returns {
##   "sent_by_type":            {ship_type -> int}  -- the sailing fleet for the crossing (all cohort
##                                                      carrier hulls this turn + all ready escorts),
##   "carriers_sent_by_type":   {ship_type -> int}  -- carrier hulls that entered cohorts (left ready),
##   "returned_by_type":        {ship_type -> int}  -- passed through, so the phase summary and tests
##                                                      read one outcome rather than two,
##   "embarked_reserve_entries": Array              -- new/updated ship_reserve entries to merge,
## }.
static func resolve(
	state: SealiftState,
	ship_reserve: Array,
	ready_by_type: Dictionary,
	returned_by_type: Dictionary,
	ship_defs: Dictionary,
) -> Dictionary:
	# Local ready pool = current ready + hulls the pipeline just released (available to sail today).
	var ready: Dictionary = {}
	for t in ready_by_type.keys():
		ready[String(t)] = int(ready_by_type[t])
	for t in returned_by_type.keys():
		ready[String(t)] = int(ready.get(String(t), 0)) + int(returned_by_type[t])

	var carriers_sent_by_type: Dictionary = {}

	# --- step 1: adopt orphan at-sea BNs into a "sent" cohort -----------------------------------
	var adopt_plan := _plan_orphan_adoption(
		state, ship_reserve, ready, ship_defs, carriers_sent_by_type)

	# --- step 2: embark follow-on BNs onto remaining ready AMPHIBIOUS capacity -------------------
	var embark_result := _embark_followon(state, ship_reserve, ready, ship_defs, carriers_sent_by_type)

	# --- assemble the sailing fleet for the crossing --------------------------------------------
	var sent_by_type: Dictionary = carriers_sent_by_type.duplicate(true)
	var screen: Array = _gather_carriers_and_screen(ready, ship_defs, false)["screen"]
	for s in screen:
		var st := String(s["ship_type"])
		sent_by_type[st] = int(sent_by_type.get(st, 0)) + int(s["ready"])

	var embark_request: ForceEmbarkRequest = null
	if not (embark_result["brigade_specs"] as Array).is_empty():
		embark_request = ForceEmbarkRequest.batch(
			embark_result["brigade_specs"], embark_result["batch_bn_ids"],
			embark_result["batch_hulls"], embark_result["ship_categories"])
	return {
		"sent_by_type": sent_by_type,
		"carriers_sent_by_type": carriers_sent_by_type,
		"returned_by_type": returned_by_type,
		"embarked_reserve_entries": embark_result["embarked_reserve_entries"],
		"embark_request": embark_request,
		"adopt_plan": adopt_plan,
	}


static func _plan_orphan_adoption(
		state: SealiftState, ship_reserve: Array, ready: Dictionary,
		ship_defs: Dictionary, carriers_sent_by_type: Dictionary) -> Dictionary:
	var bound_ids := _bound_bn_ids(state)
	var orphan_bns: Array = []
	for entry in ship_reserve:
		for bn in entry.get("bns", []):
			if not bound_ids.has(String(bn.get("id", ""))):
				orphan_bns.append(bn)
	if orphan_bns.is_empty():
		return {}
	var carriers: Array = _gather_carriers_and_screen(ready, ship_defs, false)["carriers"]
	var snapshot := ShipLoadingModel.build_sent_snapshots(orphan_bns.size(), carriers, [])
	var adopted_hulls: Dictionary = snapshot["sent_by_type"]
	if adopted_hulls.is_empty():
		return {}
	_consume(ready, adopted_hulls)
	_accumulate(carriers_sent_by_type, adopted_hulls)
	return {
		"bn_ids": _bn_ids(orphan_bns),
		"hulls_by_type": adopted_hulls,
		"ship_categories": _ship_category_stamps(
			orphan_bns, snapshot["bn_equiv_assigned"], ship_defs),
	}


## Build the ordered follow-on BN pool (departed brigades first, then new brigades in pool order),
## pack it onto ready AMPHIBIOUS carriers, and plan the loaded BNs for a new "sent" cohort. Does
## NOT mutate state.mainland_pool or state.cohorts — the caller owns applying force mutations
## through ForceTransitions.
## Returns {embarked_reserve_entries: Array, brigade_specs: Array, batch_bn_ids: Array,
## batch_hulls: Dictionary, ship_categories: Dictionary}.
## Mutates ready + carriers_sent_by_type in place (companion hull tracking).
static func _embark_followon(
	state: SealiftState, ship_reserve: Array, ready: Dictionary, ship_defs: Dictionary,
	carriers_sent_by_type: Dictionary,
) -> Dictionary:
	var empty := {
		"embarked_reserve_entries": [], "brigade_specs": [], "batch_bn_ids": [], "batch_hulls": {},
		"ship_categories": {},
	}
	if state.mainland_pool.is_empty():
		return empty

	var ordered_entries := _ordered_mainland_entries(state.mainland_pool, ship_reserve)
	var pool_bns: Array = []
	for entry in ordered_entries:
		pool_bns.append_array(entry.get("bns", []))
	var carriers: Array = _gather_carriers_and_screen(ready, ship_defs, true)["carriers"]
	var packed := ShipLoadingModel.pack_bns_into_hulls(pool_bns, carriers)
	var loaded_bns: Array = packed["loaded_bns"]
	if loaded_bns.is_empty():
		return empty
	var hulls_used: Dictionary = packed["hulls_used_by_type"]
	_consume(ready, hulls_used)
	_accumulate(carriers_sent_by_type, hulls_used)
	var plan := _build_embark_plan(ordered_entries, loaded_bns, hulls_used)
	plan["ship_categories"] = packed["loaded_categories"]
	return plan


static func _ordered_mainland_entries(mainland_pool: Array, ship_reserve: Array) -> Array:
	var departed: Dictionary = {}
	for entry in ship_reserve:
		departed[String(entry.get("brigade_id", ""))] = true
	var ordered: Array = []
	for entry in mainland_pool:
		if departed.has(String(entry.get("brigade_id", ""))):
			ordered.append(entry)
	for entry in mainland_pool:
		if not departed.has(String(entry.get("brigade_id", ""))):
			ordered.append(entry)
	return ordered


static func _build_embark_plan(
		ordered_entries: Array, loaded_bns: Array, hulls_used: Dictionary) -> Dictionary:
	var loaded: Dictionary = {}
	for bn in loaded_bns:
		loaded[String(bn.get("id", ""))] = true
	var specs: Array = []
	var reserve_entries: Array = []
	var batch_ids: Array = []
	for entry in ordered_entries:
		var moved: Array = []
		for bn in entry.get("bns", []):
			if loaded.has(String(bn.get("id", ""))):
				moved.append(bn)
		if moved.is_empty():
			continue
		var moved_ids := _bn_ids(moved)
		var spec: Dictionary = {
			"brigade_id": String(entry["brigade_id"]),
			"bn_ids": moved_ids,
			"locked_beach": int(entry["locked_beach"]),
			"beach_hex": String(entry["beach_hex"]),
			"offset_bearing": float(entry["offset_bearing"]),
		}
		if entry.has("cargo"):
			spec["cargo"] = entry["cargo"]
		if entry.has("port_id"):
			spec["port_id"] = entry["port_id"]
		var reserve_entry := spec.duplicate(true)
		reserve_entry.erase("bn_ids")
		reserve_entry["bns"] = moved
		specs.append(spec)
		reserve_entries.append(reserve_entry)
		batch_ids.append_array(moved_ids)
	return {
		"embarked_reserve_entries": reserve_entries,
		"brigade_specs": specs,
		"batch_bn_ids": batch_ids,
		"batch_hulls": hulls_used,
	}


## Carrier / screen split from the ready pool. amphibious_only gates carriers to amphibious lift (the
## follow-on lift rule); when false, every carrier qualifies (matches the pre-0004 build_sent_fleet,
## preserving the default scenario). Classification lives on ShipDef (sails / is_carrier /
## is_amphibious_lift). Returns {"carriers": [{ship_type, capacity, ready}], "screen": [{ship_type, ready}]}.
static func _gather_carriers_and_screen(ready: Dictionary, ship_defs: Dictionary, amphibious_only: bool) -> Dictionary:
	var carriers: Array = []
	var screen: Array = []
	for ship_def_value in ship_defs.values():
		var ship_def: ShipDef = ship_def_value
		if not ship_def.sails():
			continue
		var n := int(ready.get(ship_def.name, 0))
		if n <= 0:
			continue
		if ship_def.is_carrier():
			if amphibious_only and not ship_def.is_amphibious_lift():
				continue
			carriers.append({"ship_type": ship_def.name, "capacity": ship_def.carrying_capacity_bn_equiv, "ready": n, "category": ship_def.category})
		else:
			screen.append({"ship_type": ship_def.name, "ready": n})
	return {"carriers": carriers, "screen": screen}


## Which carrier category lifts each bn, in pool order: walk bn_equiv_assigned ({ship_type -> BN-equiv
## carried}, insertion order = build_sent_snapshots' deterministic fill order) and assign each type's
## cumulative floor of BNs from the front of the pool. BNs beyond the lifted total (unliftable) get no
## entry at all, so applying the map leaves whatever category they already carried untouched.
static func _ship_category_stamps(
		bns: Array, bn_equiv_assigned: Dictionary, ship_defs: Dictionary) -> Dictionary:
	# ship_defs is keyed by numeric id (GameData.ship_defs); index by type name for the lookup.
	var category_by_type: Dictionary = {}
	for ship_def_value in ship_defs.values():
		var ship_def: ShipDef = ship_def_value
		category_by_type[ship_def.name] = ship_def.category
	var stamps: Dictionary = {}
	var idx := 0
	var cumulative := 0.0
	for ship_type in bn_equiv_assigned.keys():
		cumulative += float(bn_equiv_assigned[ship_type])
		var upto := mini(int(floor(cumulative + 1e-9)), bns.size())
		var category := String(category_by_type.get(String(ship_type), ""))
		while idx < upto:
			stamps[String((bns[idx] as Dictionary).get("id", ""))] = category
			idx += 1
	return stamps


static func _bound_bn_ids(state: SealiftState) -> Dictionary:
	var ids: Dictionary = {}
	for cohort in state.cohorts:
		for bn_id in cohort.bn_ids:
			ids[bn_id] = true
	return ids


static func _bn_ids(bns: Array) -> Array:
	var ids: Array = []
	for bn in bns:
		ids.append(String(bn.get("id", "")))
	return ids


static func _consume(ready: Dictionary, hulls_by_type: Dictionary) -> void:
	for ship_type in hulls_by_type.keys():
		ready[String(ship_type)] = maxi(0, int(ready.get(String(ship_type), 0)) - int(hulls_by_type[ship_type]))


static func _accumulate(target: Dictionary, hulls_by_type: Dictionary) -> void:
	for ship_type in hulls_by_type.keys():
		target[String(ship_type)] = int(target.get(String(ship_type), 0)) + int(hulls_by_type[ship_type])
