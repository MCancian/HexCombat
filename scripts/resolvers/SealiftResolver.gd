class_name SealiftResolver
extends RefCounted

## Pure resolver for the cross-turn sealift phase (plan 0004): runs at the top of each turn,
## BEFORE the anti-ship crossing. Three deterministic steps, no dice:
##
##   1. tick   — advance the return/reload pipeline; hulls whose timer hits 0 rejoin the ready pool.
##   2. adopt  — any at-sea BN in ship_reserve not yet bound to a cohort (the programmed first
##               echelon on turn 1, or a straggler) is wrapped in a "sent" cohort using the same
##               minimum-lift derivation the crossing used before (ShipLoadingModel.build_sent_snapshots
##               over the FULL carrier set), so the default scenario's sent fleet is unchanged.
##   3. embark — remaining ready AMPHIBIOUS capacity loads follow-on BNs from the mainland pool
##               (departed brigades finished first, then new brigades), binding them in a new cohort.
##
## Escorts (capacity 0) screen the wave and, unless they divert to reload their SAM magazine, stay in
## the ready pool (same-turn round trip). Only carrier hulls (capacity > 0) enter cohorts and go busy.
## Amphibious-lift eligibility is classified by ShipDef.is_amphibious_lift() / is_carrier() / sails().
##
## Mutates the passed SealiftState in place (sanctioned Resource mutation, like IjfsResolver);
## ship_reserve merging + ShipState bin projection stay in GameState's wrapper. Returns the deltas
## the wrapper needs.


## state: SealiftState (mutated in place). ship_reserve: current active reserve (at-sea BNs).
## ready_by_type: {ship_type -> ready hull count} (from fleet ShipState.ready). ship_defs:
## {ship_type -> ShipDef}.
##
## Returns {
##   "sent_by_type":            {ship_type -> int}  -- the sailing fleet for the crossing (all cohort
##                                                      carrier hulls this turn + all ready escorts),
##   "carriers_sent_by_type":   {ship_type -> int}  -- carrier hulls that entered cohorts (left ready),
##   "returned_by_type":        {ship_type -> int}  -- hulls the pipeline released to ready this turn,
##   "embarked_reserve_entries": Array              -- new/updated ship_reserve entries to merge,
## }.
static func resolve(
	state: SealiftState,
	ship_reserve: Array,
	ready_by_type: Dictionary,
	ship_defs: Dictionary,
) -> Dictionary:
	# --- step 1: tick the return/reload pipelines -----------------------------------------------
	var returned_by_type := _tick_return_pipeline(state)
	_tick_escort_reload(state)

	# Local ready pool = current ready + hulls the pipeline just released (available to sail today).
	var ready: Dictionary = {}
	for t in ready_by_type.keys():
		ready[String(t)] = int(ready_by_type[t])
	for t in returned_by_type.keys():
		ready[String(t)] = int(ready.get(String(t), 0)) + int(returned_by_type[t])

	var carriers_sent_by_type: Dictionary = {}

	# --- step 2: adopt orphan at-sea BNs into a "sent" cohort -----------------------------------
	var bound_ids := _bound_bn_ids(state)
	var orphan_bns: Array = []
	for entry in ship_reserve:
		for bn in entry.get("bns", []):
			if not bound_ids.has(String(bn.get("id", ""))):
				orphan_bns.append(bn)
	if not orphan_bns.is_empty():
		# Full carrier set + escort screen, matching the pre-0004 build_sent_fleet, so the default
		# scenario's minimum-lift derivation is identical.
		var full := _gather_carriers_and_screen(ready, ship_defs, false)
		# Passing screen=[] means build_sent_snapshots' sent_by_type is carriers only, so it is the
		# adopted cohort's hull set directly (no escort filtering needed).
		var snap := ShipLoadingModel.build_sent_snapshots(orphan_bns.size(), full["carriers"], [])
		var adopted_hulls: Dictionary = snap["sent_by_type"]
		# Stamp each adopted BN with the category of the carrier type that lifts it (plan 0006: the
		# offload cost matrix needs the ship category a BN crossed on). build_sent_snapshots fills
		# carrier types in deterministic order and bn_equiv_assigned preserves that insertion order,
		# so walking its cumulative BN-equiv against the orphan pool reproduces the assignment.
		_stamp_ship_categories(orphan_bns, snap["bn_equiv_assigned"], ship_defs)
		if not adopted_hulls.is_empty():
			state.cohorts.append({
				"hulls_by_type": adopted_hulls,
				"bn_ids": _bn_ids(orphan_bns),
				"state": SealiftState.STATE_SENT,
			})
			_consume(ready, adopted_hulls)
			_accumulate(carriers_sent_by_type, adopted_hulls)

	# --- step 3: embark follow-on BNs onto remaining ready AMPHIBIOUS capacity -------------------
	var embarked_reserve_entries := _embark_followon(state, ship_reserve, ready, ship_defs, carriers_sent_by_type)

	# --- assemble the sailing fleet for the crossing --------------------------------------------
	var sent_by_type: Dictionary = carriers_sent_by_type.duplicate(true)
	# Escort + decoy screen: every ready escort sails (capacity 0) and stays ready; SAM-magazine
	# depletion + reload is applied separately via apply_escort_consumption. Mirror the screen selection.
	var screen: Array = _gather_carriers_and_screen(ready, ship_defs, false)["screen"]
	for s in screen:
		var st := String(s["ship_type"])
		sent_by_type[st] = int(sent_by_type.get(st, 0)) + int(s["ready"])

	# Freed-hull return timing is applied in the offload drain (drain_bn_ids / _free_cohort_hulls),
	# where the scenario's amphibious_return_time is threaded in directly; nothing to do here.

	return {
		"sent_by_type": sent_by_type,
		"carriers_sent_by_type": carriers_sent_by_type,
		"returned_by_type": returned_by_type,
		"embarked_reserve_entries": embarked_reserve_entries,
	}


## Decrement every pipeline slot; slots at 0 release their hulls to ready. Returns {ship_type -> int}
## released this turn. Mutates state.return_pipeline in place.
static func _tick_return_pipeline(state: SealiftState) -> Dictionary:
	var returned: Dictionary = {}
	for ship_type in state.return_pipeline.keys():
		var kept: Array = []
		for slot_value in (state.return_pipeline[ship_type] as Array):
			var slot: Dictionary = slot_value
			var remaining := int(slot["turns_remaining"]) - 1
			if remaining <= 0:
				returned[String(ship_type)] = int(returned.get(String(ship_type), 0)) + int(slot["count"])
			else:
				slot["turns_remaining"] = remaining
				kept.append(slot)
		state.return_pipeline[ship_type] = kept
	# Drop emptied type buckets to keep to_dict() minimal.
	for ship_type in returned.keys():
		if (state.return_pipeline.get(ship_type, []) as Array).is_empty():
			state.return_pipeline.erase(ship_type)
	return returned


## Build the ordered follow-on BN pool (departed brigades first, then new brigades in pool order),
## pack it onto ready AMPHIBIOUS carriers, and record the loaded BNs in a new "sent" cohort. Drains
## loaded BNs from state.mainland_pool; returns the ship_reserve entries to merge. Mutates state +
## ready + carriers_sent_by_type in place.
static func _embark_followon(
	state: SealiftState, ship_reserve: Array, ready: Dictionary, ship_defs: Dictionary,
	carriers_sent_by_type: Dictionary,
) -> Array:
	if state.mainland_pool.is_empty():
		return []

	var departed := {}
	for entry in ship_reserve:
		departed[String(entry.get("brigade_id", ""))] = true

	# Priority: pool entries whose brigade already has an active reserve entry come first (finish
	# departed brigades), then the rest in scenario order. Stable within each group.
	var ordered_entries: Array = []
	for entry in state.mainland_pool:
		if departed.has(String(entry.get("brigade_id", ""))):
			ordered_entries.append(entry)
	for entry in state.mainland_pool:
		if not departed.has(String(entry.get("brigade_id", ""))):
			ordered_entries.append(entry)

	# Flatten to an ordered BN pool, remembering each BN's home entry so loaded ones can be drained.
	var pool_bns: Array = []
	var entry_by_bn_id: Dictionary = {}
	for entry in ordered_entries:
		for bn in entry.get("bns", []):
			pool_bns.append(bn)
			entry_by_bn_id[String(bn.get("id", ""))] = entry

	var amph_carriers: Array = _gather_carriers_and_screen(ready, ship_defs, true)["carriers"]
	var packed := ShipLoadingModel.pack_bns_into_hulls(pool_bns, amph_carriers)
	var loaded_bns: Array = packed["loaded_bns"]
	if loaded_bns.is_empty():
		return []

	var hulls_used: Dictionary = packed["hulls_used_by_type"]
	state.cohorts.append({
		"hulls_by_type": hulls_used.duplicate(true),
		"bn_ids": _bn_ids(loaded_bns),
		"state": SealiftState.STATE_SENT,
	})
	_consume(ready, hulls_used)
	_accumulate(carriers_sent_by_type, hulls_used)

	# Drain loaded BNs from their mainland_pool entries; build the reserve entries to merge.
	var loaded_ids: Dictionary = {}
	for bn in loaded_bns:
		loaded_ids[String(bn.get("id", ""))] = true
	var embarked_by_brigade: Dictionary = {}
	for entry in state.mainland_pool:
		var kept: Array = []
		var moved: Array = []
		for bn in entry.get("bns", []):
			if loaded_ids.has(String(bn.get("id", ""))):
				moved.append(bn)
			else:
				kept.append(bn)
		entry["bns"] = kept
		if not moved.is_empty():
			embarked_by_brigade[String(entry["brigade_id"])] = {
				"brigade_id": String(entry["brigade_id"]),
				"locked_beach": int(entry["locked_beach"]),
				"beach_hex": String(entry["beach_hex"]),
				"offset_bearing": float(entry["offset_bearing"]),
				"bns": moved,
			}
	# Fully-drained pool entries drop out.
	var remaining_pool: Array = []
	for entry in state.mainland_pool:
		if not (entry.get("bns", []) as Array).is_empty():
			remaining_pool.append(entry)
	state.mainland_pool = remaining_pool

	return embarked_by_brigade.values()


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


## --- escort SAM magazine -------------------------------------------------------------------------

## Deplete each escort type's SAM magazine by what it fired this crossing, then divert any type that
## dropped to/below its reload threshold into a reload (escort_reload) for reload_time turns. No-op
## when the magazine is unmodelled (escort_sam empty) or reload_time <= 0. Mutates state in place.
static func apply_escort_consumption(state: SealiftState, consumed: Dictionary, reload_time: int) -> void:
	for ship_type in consumed.keys():
		var st := String(ship_type)
		if state.escort_sam.has(st):
			state.escort_sam[st] = maxi(0, int(state.escort_sam[st]) - int(consumed[ship_type]))
	if reload_time <= 0:
		return
	for ship_type in state.escort_sam.keys():
		var st := String(ship_type)
		if state.escort_reload.has(st):
			continue
		if int(state.escort_sam[st]) <= int(state.escort_sam_threshold.get(st, 0)):
			state.escort_reload[st] = reload_time


## Advance escort reloads; a type whose timer hits 0 refills to its loadout max and rejoins the
## screen. Mutates state.escort_reload + state.escort_sam in place.
static func _tick_escort_reload(state: SealiftState) -> void:
	var done: Array = []
	for ship_type in state.escort_reload.keys():
		var remaining := int(state.escort_reload[ship_type]) - 1
		if remaining <= 0:
			state.escort_sam[String(ship_type)] = int(state.escort_sam_max.get(String(ship_type), int(state.escort_sam.get(String(ship_type), 0))))
			done.append(ship_type)
		else:
			state.escort_reload[ship_type] = remaining
	for ship_type in done:
		state.escort_reload.erase(ship_type)


## --- post-crossing / offload cohort maintenance --------------------------------------------------

## BN ids currently bound to a "sent" cohort (crossing THIS turn) — the wrapper uses these to slice
## the crossing_reserve out of the full ship_reserve so only sailing BNs are attrited.
static func sent_cohort_bn_ids(state: SealiftState) -> Dictionary:
	var ids: Dictionary = {}
	for cohort in state.cohorts:
		if String(cohort.get("state", "")) != SealiftState.STATE_SENT:
			continue
		for id in cohort.get("bn_ids", []):
			ids[String(id)] = true
	return ids


## Remove up to `count` carrier hulls of `ship_type` from this turn's "sent" cohorts (crossing
## losses), in cohort order. Returns the number actually removed (<= count, capped by hulls present).
static func remove_carrier_hulls(state: SealiftState, ship_type: String, count: int) -> int:
	var removed := 0
	for cohort in state.cohorts:
		if removed >= count:
			break
		if String(cohort.get("state", "")) != SealiftState.STATE_SENT:
			continue
		var hulls: Dictionary = cohort["hulls_by_type"]
		var have := int(hulls.get(ship_type, 0))
		if have <= 0:
			continue
		var take := mini(have, count - removed)
		hulls[ship_type] = have - take
		removed += take
	return removed


## After the crossing, every surviving "sent" cohort is now ashore-bound: flip it to "offloading".
static func flip_sent_to_offloading(state: SealiftState) -> void:
	for cohort in state.cohorts:
		if String(cohort.get("state", "")) == SealiftState.STATE_SENT:
			cohort["state"] = SealiftState.STATE_OFFLOADING


## Drop the given BN ids (landed or drowned) from every cohort; a cohort whose BNs all drain frees
## its surviving hulls into the return pipeline (or straight to ready when return_time <= 0). Mutates
## state.cohorts + state.return_pipeline in place.
static func drain_bn_ids(state: SealiftState, bn_ids: Array, amphibious_return_time: int) -> void:
	if bn_ids.is_empty():
		return
	var drop: Dictionary = {}
	for id in bn_ids:
		drop[String(id)] = true
	var kept_cohorts: Array = []
	for cohort in state.cohorts:
		var remaining_ids: Array = []
		for id in cohort.get("bn_ids", []):
			if not drop.has(String(id)):
				remaining_ids.append(String(id))
		cohort["bn_ids"] = remaining_ids
		if remaining_ids.is_empty():
			_free_cohort_hulls(state, cohort["hulls_by_type"], amphibious_return_time)
		else:
			kept_cohorts.append(cohort)
	state.cohorts = kept_cohorts


## Freed hulls with a positive return time enter the pipeline; with return_time <= 0 they simply
## leave the cohort and become ready again via the ShipState projection (same-turn round trip).
static func _free_cohort_hulls(state: SealiftState, hulls_by_type: Dictionary, amphibious_return_time: int) -> void:
	if amphibious_return_time <= 0:
		return
	for ship_type in hulls_by_type.keys():
		var count := int(hulls_by_type[ship_type])
		if count <= 0:
			continue
		if not state.return_pipeline.has(String(ship_type)):
			state.return_pipeline[String(ship_type)] = []
		(state.return_pipeline[String(ship_type)] as Array).append({
			"count": count,
			"turns_remaining": amphibious_return_time,
		})


## Stamp bns (in pool order) with the carrier category lifting them: walk bn_equiv_assigned
## ({ship_type -> BN-equiv carried}, insertion order = build_sent_snapshots' deterministic fill
## order) and assign each type's cumulative floor of BNs from the front of the pool. BNs beyond
## the lifted total (unliftable) keep any existing stamp.
static func _stamp_ship_categories(bns: Array, bn_equiv_assigned: Dictionary, ship_defs: Dictionary) -> void:
	# ship_defs is keyed by numeric id (GameData.ship_defs); index by type name for the lookup.
	var category_by_type: Dictionary = {}
	for ship_def_value in ship_defs.values():
		var ship_def: ShipDef = ship_def_value
		category_by_type[ship_def.name] = ship_def.category
	var idx := 0
	var cumulative := 0.0
	for ship_type in bn_equiv_assigned.keys():
		cumulative += float(bn_equiv_assigned[ship_type])
		var upto := mini(int(floor(cumulative + 1e-9)), bns.size())
		var category := String(category_by_type.get(String(ship_type), ""))
		while idx < upto:
			(bns[idx] as Dictionary)["ship_category"] = category
			idx += 1


static func _bound_bn_ids(state: SealiftState) -> Dictionary:
	var ids: Dictionary = {}
	for cohort in state.cohorts:
		for id in cohort.get("bn_ids", []):
			ids[String(id)] = true
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
