class_name ForceValidationHelper
extends RefCounted

## Read-only preflight for ForceTransitions. It returns one typed refusal and never mutates live
## state. The authority converts that refusal into the operation-specific receipt before writing.


static func preflight_embark(
		sealift_state: SealiftState, ship_reserve: Array,
		request: ForceEmbarkRequest) -> ForceValidationResult:
	if sealift_state == null:
		return _refused("ForceTransitions: apply_embark has null sealift_state")
	if request.source != ForceLocation.Kind.MAINLAND \
			or request.destination != ForceLocation.Kind.AT_SEA:
		return _refused("ForceTransitions: embark must be mainland -> at sea")
	if request.brigade_specs.is_empty() or request.batch_bn_ids.is_empty():
		return _refused("ForceTransitions: empty embark request")
	if request.batch_hulls_by_type.is_empty():
		return _refused("ForceTransitions: embark request has no carrier hulls")
	var batch_ids: Variant = _unique_ids(request.batch_bn_ids, "embark batch")
	if batch_ids is ForceValidationResult:
		return batch_ids
	var source_error := _validate_embark_sources(sealift_state, request, batch_ids)
	if source_error != null:
		return source_error
	return _validate_embark_destinations(sealift_state, ship_reserve, request, batch_ids)


static func _validate_embark_sources(
		sealift_state: SealiftState, request: ForceEmbarkRequest,
		batch_ids: Dictionary) -> ForceValidationResult:
	var claimed: Dictionary = {}
	for spec_value in request.brigade_specs:
		var spec: Dictionary = spec_value
		var brigade_id := String(spec.get("brigade_id", ""))
		var spec_ids: Array = spec.get("bn_ids", [])
		if brigade_id.is_empty() or spec_ids.is_empty():
			return _refused("ForceTransitions: embark spec has empty brigade_id or bn_ids")
		var source_rows := _rows_for_brigade(sealift_state.mainland_pool, brigade_id)
		for id_value in spec_ids:
			var bn_id := String(id_value)
			if claimed.has(bn_id):
				return _refused("ForceTransitions: embark BN id %s claimed twice" % bn_id)
			if not batch_ids.has(bn_id) or int(source_rows.get(bn_id, 0)) != 1:
				return _refused(
					"ForceTransitions: embark BN id %s is not unique in mainland pool for %s" % [
						bn_id, brigade_id])
			claimed[bn_id] = true
	if claimed.size() != batch_ids.size():
		return _refused("ForceTransitions: embark batch and brigade specs differ")
	return null


static func _validate_embark_destinations(
		sealift_state: SealiftState, ship_reserve: Array,
		_request: ForceEmbarkRequest, batch_ids: Dictionary) -> ForceValidationResult:
	for bn_id in batch_ids:
		if _transport_id_count(ship_reserve, sealift_state, String(bn_id)) != 0:
			return _refused(
				"ForceTransitions: embark destination id %s already exists in transit" % bn_id)
	return null


static func preflight_air_insertion(
		data_store: GameDataStore, air_state: AirInsertionState,
		request: ForceAirInsertionRequest) -> ForceValidationResult:
	if air_state == null:
		return _refused("ForceTransitions: air insertion has null state")
	if request.landings.is_empty():
		return null
	var seen: Dictionary = {}
	var losses: Dictionary = {}
	for landing_value in request.landings:
		var landing: Dictionary = landing_value
		var brigade_id := String(landing.get("brigade_id", ""))
		if seen.has(brigade_id):
			return _refused("ForceTransitions: duplicate air insertion brigade %s" % brigade_id)
		seen[brigade_id] = true
		var error := _validate_air_landing(data_store, air_state, landing, losses)
		if error != null:
			return error
	return _validate_roster_losses(data_store, losses, "air insertion")


static func _validate_air_landing(
		data_store: GameDataStore, air_state: AirInsertionState,
		landing: Dictionary, losses: Dictionary) -> ForceValidationResult:
	var brigade_id := String(landing.get("brigade_id", ""))
	var landed_bns: Array = landing.get("landed_bns", [])
	var lost_bns: Array = landing.get("lost_bns", [])
	if _pool_entry_count(air_state.pool, brigade_id) != 1:
		return _refused("ForceTransitions: air insertion needs one pool entry for %s" % brigade_id)
	if not _air_pool_prefix_matches(air_state.pool, brigade_id, landed_bns, lost_bns):
		return _refused("ForceTransitions: air insertion pool prefix failed for %s" % brigade_id)
	var brigade: Brigade = data_store.get_brigade(brigade_id)
	if brigade == null or brigade.destroyed:
		return _refused("ForceTransitions: air insertion has unavailable brigade %s" % brigade_id)
	var first := bool(landing.get("first_landing", false))
	var expected_first := not landed_bns.is_empty() and not air_state.landed.has(brigade_id)
	if first != expected_first:
		return _refused("ForceTransitions: air insertion first_landing mismatch for %s" % brigade_id)
	var target_hex := String(landing.get("hex_id", ""))
	if first and (not brigade.hex_id.is_empty() or not data_store.hex_lookup.has(target_hex)):
		return _refused("ForceTransitions: invalid first air landing for %s" % brigade_id)
	if air_state.landed.has(brigade_id) and brigade.hex_id != target_hex:
		return _refused("ForceTransitions: air insertion follow-up hex mismatch for %s" % brigade_id)
	for bn_value in lost_bns:
		var key := "%s|%s" % [brigade_id, String((bn_value as Dictionary).get("type", ""))]
		losses[key] = int(losses.get(key, 0)) + 1
	return null


static func preflight_offload(
		data_store: GameDataStore, request: ForceOffloadRequest,
		ship_reserve: Array, sealift_state: SealiftState) -> ForceValidationResult:
	if sealift_state == null:
		return _refused("ForceTransitions: apply_offload has null sealift_state")
	if request.source != ForceLocation.Kind.OFFLOADING \
			or request.destination != ForceLocation.Kind.ASHORE:
		return _refused("ForceTransitions: offload must be offloading -> ashore")
	var requested_ids: Dictionary = {}
	for landing_value in request.landings:
		var error := _validate_troop_offload(
			data_store, landing_value as Dictionary, ship_reserve, sealift_state, requested_ids)
		if error != null:
			return error
	for arrival_value in request.cargo_arrivals:
		var error := _validate_cargo_offload(
			arrival_value as Dictionary, ship_reserve, sealift_state, requested_ids)
		if error != null:
			return error
	return null


static func _validate_troop_offload(
		data_store: GameDataStore, landing: Dictionary, ship_reserve: Array,
		sealift_state: SealiftState, requested_ids: Dictionary) -> ForceValidationResult:
	var brigade_id := String(landing.get("brigade_id", ""))
	var bn_ids: Array = landing.get("bn_ids", [])
	if brigade_id.is_empty() or bn_ids.is_empty():
		return _refused("ForceTransitions: offload landing has empty brigade_id or bn_ids")
	var brigade: Brigade = data_store.get_brigade(brigade_id)
	if brigade == null or brigade.destroyed:
		return _refused("ForceTransitions: offload has unavailable brigade %s" % brigade_id)
	var landing_hex := String(landing.get("hex_id", ""))
	if brigade.hex_id.is_empty() and not data_store.hex_lookup.has(landing_hex):
		return _refused("ForceTransitions: offload has invalid first-landing hex for %s" % brigade_id)
	for id_value in bn_ids:
		var bn_id := String(id_value)
		var error := _validate_offload_id(
			bn_id, brigade_id, ship_reserve, sealift_state, requested_ids)
		if error != null:
			return error
		var battalion_type := _reserve_bn_type(ship_reserve, brigade_id, bn_id)
		if not _brigade_has_type(brigade, battalion_type):
			return _refused(
				"ForceTransitions: offload BN id %s type %s is absent from roster" % [
					bn_id, battalion_type])
	return null


static func _validate_cargo_offload(
		arrival: Dictionary, ship_reserve: Array, sealift_state: SealiftState,
		requested_ids: Dictionary) -> ForceValidationResult:
	var brigade_id := JlsfCargo.brigade_id_for(String(arrival.get("port_id", "")))
	for id_value in (arrival.get("bn_ids", []) as Array):
		var error := _validate_offload_id(
			String(id_value), brigade_id, ship_reserve, sealift_state, requested_ids)
		if error != null:
			return error
	return null


static func _validate_offload_id(
		bn_id: String, brigade_id: String, ship_reserve: Array,
		sealift_state: SealiftState, requested_ids: Dictionary) -> ForceValidationResult:
	var cargo := brigade_id.begins_with(JlsfCargo.BRIGADE_ID_PREFIX)
	if requested_ids.has(bn_id):
		return _refused("ForceTransitions: duplicate offload BN id %s" % bn_id)
	requested_ids[bn_id] = true
	var reserve_matches := 0
	for entry_value in ship_reserve:
		var entry: Dictionary = entry_value
		if String(entry.get("brigade_id", "")) != brigade_id:
			continue
		if JlsfCargo.is_jlsf_entry(entry) != cargo:
			continue
		for bn_value in entry.get("bns", []):
			if String((bn_value as Dictionary).get("id", "")) == bn_id:
				reserve_matches += 1
	if reserve_matches != 1 or _cohort_id_count(sealift_state, bn_id, SealiftState.STATE_OFFLOADING) != 1:
		return _refused("ForceTransitions: offload BN id %s is not unique at source" % bn_id)
	return null


static func _unique_ids(ids: Array, label: String):
	var unique: Dictionary = {}
	for value in ids:
		var id := String(value)
		if id.is_empty() or unique.has(id):
			return _refused("ForceTransitions: duplicate or empty BN id in %s: %s" % [label, id])
		unique[id] = true
	return unique


static func _rows_for_brigade(entries: Array, brigade_id: String) -> Dictionary:
	var counts: Dictionary = {}
	for entry_value in entries:
		var entry: Dictionary = entry_value
		if String(entry.get("brigade_id", "")) != brigade_id:
			continue
		for bn_value in entry.get("bns", []):
			var id := String((bn_value as Dictionary).get("id", ""))
			counts[id] = int(counts.get(id, 0)) + 1
	return counts


static func _reserve_bn_type(ship_reserve: Array, brigade_id: String, bn_id: String) -> String:
	for entry_value in ship_reserve:
		var entry: Dictionary = entry_value
		if String(entry.get("brigade_id", "")) != brigade_id:
			continue
		for bn_value in entry.get("bns", []):
			var bn: Dictionary = bn_value
			if String(bn.get("id", "")) == bn_id:
				return String(bn.get("type", ""))
	return ""


static func _brigade_has_type(brigade: Brigade, battalion_type: String) -> bool:
	for battalion_value in brigade.composition:
		if String(battalion_value.type) == battalion_type and int(battalion_value.qty) > 0:
			return true
	return false


static func _transport_id_count(ship_reserve: Array, sealift_state: SealiftState, bn_id: String) -> int:
	var count := 0
	for entry_value in ship_reserve:
		for bn_value in (entry_value as Dictionary).get("bns", []):
			if String((bn_value as Dictionary).get("id", "")) == bn_id:
				count += 1
	for cohort_value in sealift_state.cohorts:
		for id_value in (cohort_value as Dictionary).get("bn_ids", []):
			if String(id_value) == bn_id:
				count += 1
	return count


static func _cohort_id_count(sealift_state: SealiftState, bn_id: String, state_label: String) -> int:
	var count := 0
	for cohort_value in sealift_state.cohorts:
		var cohort: Dictionary = cohort_value
		if String(cohort.get("state", "")) != state_label:
			continue
		for id_value in cohort.get("bn_ids", []):
			if String(id_value) == bn_id:
				count += 1
	return count


static func _pool_entry_count(pool: Array, brigade_id: String) -> int:
	var count := 0
	for entry_value in pool:
		if String((entry_value as Dictionary).get("brigade_id", "")) == brigade_id:
			count += 1
	return count


static func _air_pool_prefix_matches(
		pool: Array, brigade_id: String, landed: Array, lost: Array) -> bool:
	var requested: Dictionary = {}
	for bn_value in landed + lost:
		var bn: Dictionary = bn_value
		var id := String(bn.get("id", ""))
		if requested.has(id):
			return false
		requested[id] = String(bn.get("type", ""))
	for entry_value in pool:
		var entry: Dictionary = entry_value
		if String(entry.get("brigade_id", "")) != brigade_id:
			continue
		if requested.size() > (entry.get("bns", []) as Array).size():
			return false
		for index in range(requested.size()):
			var bn: Dictionary = entry["bns"][index]
			var id := String(bn.get("id", ""))
			if requested.get(id, "") != String(bn.get("type", "")):
				return false
		return true
	return false


static func _validate_roster_losses(
		data_store: GameDataStore, losses: Dictionary, label: String) -> ForceValidationResult:
	for key_value in losses:
		var key := String(key_value)
		var brigade: Brigade = data_store.get_brigade(key.get_slice("|", 0))
		var available := 0
		if brigade != null:
			for battalion_value in brigade.composition:
				if String(battalion_value.type) == key.get_slice("|", 1):
					available += int(battalion_value.qty)
		if brigade == null or available < int(losses[key]):
			return _refused("ForceTransitions: %s roster cannot cover %s" % [label, key])
	return null


static func _refused(message: String) -> ForceValidationResult:
	return ForceValidationResult.refused(message)
