class_name ForceTransitions
extends RefCounted

## THE mutation authority for the force aggregate (plan 0044). It is the only production writer for
## Brigade runtime fields, the GameData.brigades_by_hex placement projection, and who is ABOARD a
## sealift cohort (`SealiftCohort.bn_ids`). The hulls in that same cohort, and which leg it is on,
## belong to `SealiftTransitions` (plan 0045) — the two authorities share the object and never reach
## across, so an operation that moves troops AND hulls is two calls in one coordinator.
##
## Reserve and mainland-pool entries are still dictionary-shaped; callers pass typed requests so the
## operation vocabulary is closed before the physical storage moves.
##
## One consequence of the split is worth stating so nobody re-derives it: this file CREATES cohorts, which
## means a cohort's hull fields get their first value on a path that runs through here. It does that
## through `SealiftCohort.sent(...)`, passing the hull plan as an argument — the fields themselves are
## written inside `SealiftCohort`, which the manifest registers as the construction writer for them. A
## fresh cohort is unpublished until it is appended; from that moment on its hulls are the fleet
## authority's alone.
##
## This file validates the pre-state, applies the requested delta, checks the placement index, and
## returns typed receipts for operations that summaries/narratives may later consume. It does not
## roll dice, choose targets, or read autoload singletons; coordinators pass the GameDataStore whose
## force state they are mutating.


# ── Placement ───────────────────────────────────────────────────────────────────────────────────

static func place_brigade(data_store: GameDataStore, request: ForcePlacementRequest) -> ForcePlacementReceipt:
	var receipt := ForcePlacementReceipt.new()
	receipt.brigade_id = request.brigade_id
	receipt.new_hex = request.destination_hex
	receipt.destination = ForceLocation.label(request.destination)
	receipt.phase = request.phase
	var brigade := _brigade_or_error(data_store, request.brigade_id, "place")
	if brigade == null:
		return receipt
	if request.destination == ForceLocation.Kind.ASHORE and request.destination_hex.is_empty():
		push_error("ForceTransitions: ashore placement for %s has no hex" % request.brigade_id)
		return receipt
	if not request.destination_hex.is_empty() and not data_store.hex_lookup.has(request.destination_hex):
		push_error("ForceTransitions: placement for %s names unknown hex %s" % [
			request.brigade_id, request.destination_hex])
		return receipt
	receipt.old_hex = brigade.hex_id
	_apply_hex(data_store, brigade, request.destination_hex)
	if request.has_entry_bearing:
		brigade.entry_bearing = request.entry_bearing
	_check_index(data_store, brigade.id)
	return receipt


static func remove_brigade_from_map(data_store: GameDataStore, brigade_id: String) -> ForcePlacementReceipt:
	return place_brigade(data_store, ForcePlacementRequest.off_map(brigade_id, "remove"))


# ── Casualties ──────────────────────────────────────────────────────────────────────────────────

static func apply_battalion_casualties(
		data_store: GameDataStore, request: ForceCasualtyRequest) -> ForceCasualtyReceipt:
	var receipt := ForceCasualtyReceipt.new()
	receipt.brigade_id = request.brigade_id
	receipt.battalion_type = request.battalion_type
	receipt.requested = request.count
	receipt.cause = ForceCasualtyCause.label(request.cause)
	receipt.source_location = ForceLocation.label(request.source_location)
	if request.count <= 0:
		push_error("ForceTransitions: casualty count for %s/%s must be positive" % [
			request.brigade_id, request.battalion_type])
		return receipt
	var brigade := _brigade_or_error(data_store, request.brigade_id, "casualty")
	if brigade == null:
		return receipt
	var available := _battalion_count(brigade, request.battalion_type)
	if available < request.count:
		push_error("ForceTransitions: %s casualty requested %d %s but roster has %d" % [
			request.brigade_id, request.count, request.battalion_type, available])
		return receipt
	_apply_roster_loss(brigade, request.battalion_type, request.count)
	receipt.applied = request.count
	if brigade.get_battalion_count() == 0:
		receipt.destroyed_brigade = true
		receipt.removed_from_hex = brigade.hex_id
		brigade.destroyed = true
		_apply_hex(data_store, brigade, "")
	_check_index(data_store, brigade.id)
	return receipt


# ── Brigade activity / organization ────────────────────────────────────────────────────────────

static func apply_activity(brigade: Brigade, request: ForceActivityRequest) -> void:
	if brigade == null:
		push_error("ForceTransitions: activity request has null brigade")
		return
	match request.operation:
		ForceActivityRequest.Operation.MOVE_TACTICAL:
			brigade.moved_this_turn = true
			brigade.organization = clampf(
				brigade.organization - Brigade.TACTICAL_MOVE_ORG_COST, 0.0, Brigade.MAX_ORGANIZATION)
		ForceActivityRequest.Operation.MOVE_ADMIN:
			brigade.moved_this_turn = true
			brigade.moved_admin_this_turn = true
			brigade.organization = clampf(
				brigade.organization - Brigade.ADMIN_MOVE_ORG_COST, 0.0, Brigade.MAX_ORGANIZATION)
		ForceActivityRequest.Operation.FOUGHT:
			brigade.fought_this_turn = true
		ForceActivityRequest.Operation.LATCH_PRIOR_FROM_CURRENT:
			brigade.moved_last_turn = brigade.moved_this_turn or brigade.moved_admin_this_turn
			brigade.fought_last_turn = brigade.fought_this_turn
		ForceActivityRequest.Operation.RESET_TURN_FLAGS:
			brigade.moved_this_turn = false
			brigade.moved_admin_this_turn = false
			brigade.fought_this_turn = false


# ── Air insertion (plan 0032) ────────────────────────────────────────────────────────────────────

## Apply a resolver-computed air insertion outcome: drain the pool of the BNs that flew,
## apply casualties to roster, update landed membership, and place first-landing brigades
## on the map. All-or-nothing: any validation failure refuses the entire request and
## changes nothing on the force side. Caps erosion and history append are companion updates
## performed by the caller (ReinforcementPhases) after this succeeds.
static func apply_air_insertion_outcome(
		data_store: GameDataStore,
		air_state: AirInsertionState,
		request: ForceAirInsertionRequest) -> ForceAirInsertionReceipt:
	var preflight_error := ForceValidationHelper.preflight_air_insertion(data_store, air_state, request)
	if preflight_error != null:
		return ForceAirInsertionReceipt.refused(preflight_error.error)
	return _commit_air_insertion(data_store, air_state, request)



static func _commit_air_insertion(data_store: GameDataStore, air_state: AirInsertionState, request: ForceAirInsertionRequest) -> ForceAirInsertionReceipt:
	if request.landings.is_empty():
		return ForceAirInsertionReceipt.succeeded()
	var pool_removed := 0
	var total_landed := 0
	var total_lost := 0
	var casualty_receipts: Array[ForceCasualtyReceipt] = []
	var placement_receipts: Array[ForcePlacementReceipt] = []
	var placed: Array[String] = []

	for landing_value in request.landings:
		var landing: Dictionary = landing_value
		var brigade_id := String(landing["brigade_id"])
		var hex_id := String(landing["hex_id"])
		var first_landing := bool(landing.get("first_landing", false))
		var landed_bns: Array = landing.get("landed_bns", [])
		var lost_bns: Array = landing.get("lost_bns", [])

		_remove_pool_bns(air_state, brigade_id, landed_bns, lost_bns)
		if landed_bns.size() + lost_bns.size() > 0:
			pool_removed += 1

		for bn_value in lost_bns:
			var bn: Dictionary = bn_value
			var casualty := ForceCasualtyRequest.one(
				brigade_id, String(bn["type"]),
				ForceCasualtyCause.Kind.AIR_INSERTION,
				ForceLocation.Kind.AWAITING_AIR_INSERTION)
			var receipt := apply_battalion_casualties(data_store, casualty)
			casualty_receipts.append(receipt)

		if first_landing:
			air_state.landed.append(brigade_id)
			var place_receipt := place_brigade(
				data_store, ForcePlacementRequest.ashore(brigade_id, hex_id, "air_insertion"))
			placement_receipts.append(place_receipt)
			if not place_receipt.new_hex.is_empty():
				placed.append(brigade_id)

		total_landed += landed_bns.size()
		total_lost += lost_bns.size()

	_drop_empty_air_pool_entries(air_state)

	var receipt := ForceAirInsertionReceipt.succeeded()
	receipt.pool_entries_drained = pool_removed
	receipt.battalions_landed = total_landed
	receipt.battalions_lost = total_lost
	receipt.casualty_receipts = casualty_receipts
	receipt.placement_receipts = placement_receipts
	receipt.placed_brigades = placed
	return receipt


# ── Mobilization release (plan 0029) ─────────────────────────────────────────────────────────────

## Release brigades from mobilization onto the map. Each arrival's brigade is moved from pending
## to released, and the brigade is placed on its arrival hex via place_brigade. All-or-nothing:
## preflights the entire batch before any mutation.
static func release_mobilized_brigades(
		data_store: GameDataStore,
		mob_state: MobilizationState,
		request: ForceMobilizationRequest) -> ForceMobilizationReceipt:
	if mob_state == null:
		return ForceMobilizationReceipt.refused("ForceTransitions: release_mobilized has null mob_state")
	if request.arrivals.is_empty():
		return ForceMobilizationReceipt.ok(0, 0, [], [], request.deferred)

	var preflight_error := ForceMobilizationValidation.preflight(data_store, mob_state, request)
	if preflight_error != null:
		return ForceMobilizationReceipt.refused(preflight_error.error)
	return _commit_mobilization(data_store, mob_state, request)


static func _commit_mobilization(
		data_store: GameDataStore, mob_state: MobilizationState,
		request: ForceMobilizationRequest) -> ForceMobilizationReceipt:
	var arrivals_by_id: Dictionary = {}
	for arrival_value in request.arrivals:
		var arrival: Dictionary = arrival_value
		arrivals_by_id[String(arrival["brigade_id"])] = arrival
	var total_battalions := 0
	var placements: Array[ForcePlacementReceipt] = []
	var placed: Array[String] = []
	var still_pending: Array = []
	for entry_value in mob_state.pending:
		var entry: Dictionary = entry_value
		var brigade_id := String(entry["brigade_id"])
		if not arrivals_by_id.has(brigade_id):
			still_pending.append(entry)
			continue
		var arrival: Dictionary = arrivals_by_id[brigade_id]
		var receipt := place_brigade(data_store, ForcePlacementRequest.ashore(
			brigade_id, String(arrival["hex_id"]), "mobilization"))
		placements.append(receipt)
		placed.append(brigade_id)
		total_battalions += int(arrival["battalions"])
		mob_state.released.append({
			"brigade_id": brigade_id,
			"hex_id": String(arrival["hex_id"]),
			"turn": request.turn_number,
			"displaced": bool(arrival.get("displaced", false)),
		})
	mob_state.pending = still_pending
	return ForceMobilizationReceipt.ok(
		request.arrivals.size(), total_battalions, placements, placed, request.deferred)


# ── Sea transport: embark (plan 0004 / 0044) ─────────────────────────────────────────────────────

## Atomically drain one embark batch from mainland_pool, merge its exact rows into ship_reserve,
## and bind every id to one sent cohort. Troop rosters do not change. JLSF specs may share the
## physical batch but remain explicitly marked cargo and never enter the ForceLocation vocabulary.
static func apply_embark(
		sealift_state: SealiftState, request: ForceEmbarkRequest,
		ship_reserve: Array) -> Array[ForceEmbarkReceipt]:
	var preflight_error := ForceValidationHelper.preflight_embark(
		sealift_state, ship_reserve, request)
	if preflight_error != null:
		return [ForceEmbarkReceipt.refused(preflight_error.error)]
	return _commit_embark(sealift_state, ship_reserve, request)



static func _commit_embark(
		sealift_state: SealiftState, ship_reserve: Array,
		request: ForceEmbarkRequest) -> Array[ForceEmbarkReceipt]:
	var receipts: Array[ForceEmbarkReceipt] = []
	for spec_value in request.brigade_specs:
		var spec: Dictionary = spec_value
		var brigade_id := String(spec.get("brigade_id", ""))
		var spec_bn_ids: Array = spec.get("bn_ids", [])
		var spec_ids_set: Dictionary = {}
		for bn_id_value in spec_bn_ids:
			spec_ids_set[String(bn_id_value)] = true

		for pool_entry_value in sealift_state.mainland_pool:
			var pool_entry: Dictionary = pool_entry_value
			if String(pool_entry.get("brigade_id", "")) != brigade_id:
				continue
			var kept: Array = []
			var moved: Array = []
			for bn_value in pool_entry.get("bns", []):
				var bn: Dictionary = bn_value
				if spec_ids_set.has(String(bn.get("id", ""))):
					_stamp_ship_category(bn, request.ship_categories)
					moved.append(bn)
				else:
					kept.append(bn)
			pool_entry["bns"] = kept
			if not moved.is_empty():
				var reserve_entry: Dictionary = spec.duplicate(true)
				reserve_entry.erase("bn_ids")
				reserve_entry["bns"] = moved
				_merge_reserve_entry(ship_reserve, reserve_entry)
				receipts.append(ForceEmbarkReceipt.ok(brigade_id, spec_bn_ids))

	var remaining_pool: Array = []
	for pool_entry_value in sealift_state.mainland_pool:
		var pe: Dictionary = pool_entry_value
		if not (pe.get("bns", []) as Array).is_empty():
			remaining_pool.append(pe)
	sealift_state.mainland_pool = remaining_pool

	sealift_state.cohorts.append(
		SealiftCohort.sent(request.batch_hulls_by_type, request.batch_bn_ids))
	if receipts.is_empty():
		receipts.append(ForceEmbarkReceipt.refused("ForceTransitions: no BNs embarked"))
	return receipts


# ── Sea transport: crossing loss (plan 0044) ──────────────────────────────────────────────────────

## Remove lost troop BN ids from ship_reserve and from sent/offloading cohort bn_ids,
## in addition to the existing roster-loss application. JLSF cargo IDs are ignored.
## Preflight: all checks from the existing apply_crossing_casualties plus reserve/cohort removal
## are validated before any mutation.
static func apply_crossing_loss(
		data_store: GameDataStore, sealift_state: SealiftState,
		ship_reserve: Array,
		request: ForceCrossingCasualtyRequest) -> ForceCrossingCasualtyResult:
	if request.source != ForceLocation.Kind.AT_SEA \
			or request.destination != ForceLocation.Kind.DEAD:
		return ForceCrossingCasualtyResult.refused(
			"ForceTransitions: crossing loss must be at sea -> dead")
	var duplicate_id := _duplicate_id(request.lost_ids)
	if not duplicate_id.is_empty():
		return ForceCrossingCasualtyResult.refused(
			"ForceTransitions: crossing loss id %s appears twice in lost_ids" % duplicate_id)
	var all_lost: Variant = _unique_id_set(request.lost_ids)
	if all_lost == null:
		return ForceCrossingCasualtyResult.refused(
			"ForceTransitions: crossing loss contains an empty id")
	if all_lost.is_empty():
		return ForceCrossingCasualtyResult.ok([])
	for bn_id in all_lost:
		var reserve_count := _reserve_id_count(ship_reserve, String(bn_id))
		if reserve_count == 0:
			return ForceCrossingCasualtyResult.refused(
				"ForceTransitions: crossing casualty id %s is missing from reserve" % bn_id)
		if reserve_count != 1:
			return ForceCrossingCasualtyResult.refused(
				"ForceTransitions: crossing casualty id %s appears in reserve twice" % bn_id)
	if not _sent_cohorts_contain_once(sealift_state, all_lost):
		return ForceCrossingCasualtyResult.refused(
			"ForceTransitions: crossing loss cohort validation failed")
	var force_lost := _force_lost_id_set(request.lost_ids, ship_reserve)
	var reserve_rows := _reserve_rows_by_lost_id(ship_reserve, force_lost)
	if reserve_rows.size() != force_lost.size() \
			or not _rosters_cover_rows(data_store, reserve_rows):
		return ForceCrossingCasualtyResult.refused(
			"ForceTransitions: crossing loss roster validation failed")
	var receipts := _apply_crossing_roster_losses(data_store, force_lost, reserve_rows)
	_remove_from_reserve_ids(ship_reserve, all_lost)
	_remove_from_cohort_ids(sealift_state, all_lost.keys())
	return ForceCrossingCasualtyResult.ok(receipts)


static func _apply_crossing_roster_losses(
		data_store: GameDataStore, force_lost: Dictionary,
		reserve_rows: Dictionary) -> Array[ForceCasualtyReceipt]:
	var receipts: Array[ForceCasualtyReceipt] = []
	for bn_id in force_lost:
		var row: Dictionary = reserve_rows[bn_id]
		receipts.append(apply_battalion_casualties(
			data_store, ForceCasualtyRequest.one(
				String(row["brigade_id"]), String(row["type"]),
				ForceCasualtyCause.Kind.CROSSING, ForceLocation.Kind.AT_SEA)))
	return receipts


# ── Sea transport: sent cohort creation (plan 0044) ───────────────────────────────

## Create a sent cohort binding BN ids to hulls, with no mainland_pool or reserve change.
## Used for the "adopt" step where BNs already in reserve get bound to a crossing cohort.
## `ship_categories` ({bn_id -> carrier category}, from the planner) is applied to the reserve rows only
## after the preflight passes, so a refused adoption leaves the reserve exactly as it was.
static func apply_sent_cohort(
		sealift_state: SealiftState, bn_ids: Array, hulls_by_type: Dictionary,
		ship_reserve: Array, ship_categories: Dictionary) -> ForceEmbarkReceipt:
	if sealift_state == null:
		return ForceEmbarkReceipt.refused("ForceTransitions: apply_sent_cohort has null sealift_state")
	if bn_ids.is_empty():
		return ForceEmbarkReceipt.refused("ForceTransitions: apply_sent_cohort has empty bn_ids")
	var existing_ids: Dictionary = {}
	for bn_id_value in bn_ids:
		var bn_id := String(bn_id_value)
		if _reserve_id_count(ship_reserve, bn_id) != 1:
			return ForceEmbarkReceipt.refused(
				"ForceTransitions: adopt BN id %s is not unique in ship_reserve" % bn_id)
	for cohort in sealift_state.cohorts:
		for bid in cohort.bn_ids:
			if existing_ids.has(bid):
				return ForceEmbarkReceipt.refused(
					"ForceTransitions: duplicate BN id %s across cohorts" % bid)
			existing_ids[bid] = true
	for bn_id in bn_ids:
		if existing_ids.has(bn_id):
			return ForceEmbarkReceipt.refused(
				"ForceTransitions: adopt BN id %s already in a cohort" % bn_id)
	sealift_state.cohorts.append(SealiftCohort.sent(hulls_by_type, bn_ids))
	for entry_value in ship_reserve:
		for bn_value in (entry_value as Dictionary).get("bns", []):
			_stamp_ship_category(bn_value, ship_categories)
	return ForceEmbarkReceipt.ok("", bn_ids)


# ── Sea transport: offload (plan 0044) ───────────────────────────────────────────────────────────

## Remove landed BN ids from ship_reserve entries and from offloading cohort bn_ids,
## then apply first-landing placement for brigades whose FIRST battalion comes ashore.
## No roster change — every battalion is already counted in its brigade's composition.
## Preflights every landed BN id exists in ship_reserve before any mutation.
static func apply_offload(
		data_store: GameDataStore, ship_reserve: Array,
		sealift_state: SealiftState,
		request: ForceOffloadRequest) -> ForceOffloadReceipt:
	var preflight_error := ForceValidationHelper.preflight_offload(
		data_store, request, ship_reserve, sealift_state)
	if preflight_error != null:
		return ForceOffloadReceipt.refused(preflight_error.error)
	var troop_ids := _offload_troop_ids(request)
	var all_ids := troop_ids.duplicate()
	for arrival_value in request.cargo_arrivals:
		for id_value in (arrival_value as Dictionary).get("bn_ids", []):
			all_ids[String(id_value)] = true
	var placement_result := _apply_first_offload_placements(data_store, request)
	_remove_from_reserve_ids(ship_reserve, all_ids)
	_remove_from_cohort_ids(sealift_state, all_ids.keys())
	return ForceOffloadReceipt.ok(
		placement_result["brigade_ids"], placement_result["landings"],
		_typed_string_array(troop_ids.keys()), placement_result["receipts"])


static func _offload_troop_ids(request: ForceOffloadRequest) -> Dictionary:
	var ids: Dictionary = {}
	for landing_value in request.landings:
		for id_value in (landing_value as Dictionary).get("bn_ids", []):
			ids[String(id_value)] = true
	return ids


static func _apply_first_offload_placements(
		data_store: GameDataStore, request: ForceOffloadRequest) -> Dictionary:
	var brigade_ids: Array[String] = []
	var landings: Array = []
	var receipts: Array[ForcePlacementReceipt] = []
	for landing_value in request.landings:
		var landing: Dictionary = landing_value
		var brigade: Brigade = data_store.get_brigade(String(landing["brigade_id"]))
		if not brigade.hex_id.is_empty():
			continue
		var receipt := place_brigade(data_store, ForcePlacementRequest.ashore(
			brigade.id, String(landing["hex_id"]), "offload"))
		receipts.append(receipt)
		brigade_ids.append(brigade.id)
		landings.append({
			"brigade_id": brigade.id,
			"beach_hex": String(landing["hex_id"]),
			"offset_bearing": float(landing.get("offset_bearing", 0.0)),
		})
	return {"brigade_ids": brigade_ids, "landings": landings, "receipts": receipts}


# ── JLSF queueing (plan 0044) ────────────────────────────────────────────────────────────────────

## Queue JLSF cargo pseudo-entries into the MAINLAND POOL (force aggregate field). JLSF entries
## have cargo='jlsf' and port_id; they are NOT troop and must not enter ForceLocation methods
## (apply_offload/free_emptied_cohorts skip them automatically by checking is_jlsf_entry).
static func apply_queue_jlsf(sealift_state: SealiftState, entries: Array) -> void:
	for entry in entries:
		sealift_state.mainland_pool.push_front(entry)


# ── Cohort lifecycle (plan 0044) ──────────────────────────────────────────────────────────────────

## Drop the cohorts whose bn_ids have been drained (by apply_offload or apply_crossing_loss) — nobody
## is aboard, so the binding this authority owns has served its purpose. The hulls that were carrying
## them are reported, one batch per freed cohort, and go no further here: where a freed hull goes next
## (straight back to ready, or through the return pipeline) is the sealift authority's call, so the
## caller hands this plan to `SealiftTransitions.release_hulls`. That split is why this function no
## longer takes the scenario's return time — the force aggregate has no business knowing it.
static func free_emptied_cohorts(sealift_state: SealiftState) -> SealiftHullReleasePlan:
	if sealift_state == null:
		return SealiftHullReleasePlan.new()
	var batches: Array = []
	var kept: Array[SealiftCohort] = []
	for cohort in sealift_state.cohorts:
		if cohort.is_empty():
			batches.append(cohort.hulls_by_type)
		else:
			kept.append(cohort)
	sealift_state.cohorts = kept
	return SealiftHullReleasePlan.of(batches)


# ── Construction and read-only backstops ────────────────────────────────────────────────────────

static func initialize_ship_reserve(state: GameStateData, reserve: Array) -> void:
	state.ship_reserve = reserve


static func reset_placement_index(data_store: GameDataStore) -> void:
	data_store.brigades_by_hex.clear()


static func ground_combat_casualty_request(casualty: Dictionary) -> ForceCasualtyRequest:
	return ForceCasualtyRequest.one(
		String(casualty["brigade_id"]), String(casualty["type"]),
		ForceCasualtyCause.Kind.GROUND_COMBAT, ForceLocation.Kind.ASHORE)


static func ijfs_casualty_request(casualty: Dictionary) -> ForceCasualtyRequest:
	return ForceCasualtyRequest.one(
		String(casualty["brigade_id"]), String(casualty["unit_type"]),
		ForceCasualtyCause.Kind.IJFS_MANEUVER, ForceLocation.Kind.ASHORE)


static func crossing_casualty_request(
		lost_ids: Array, ship_reserve: Array,
		sealift_state: SealiftState) -> ForceCrossingCasualtyRequest:
	return ForceCrossingCasualtyRequest.from_crossing(lost_ids, ship_reserve, sealift_state)


static func validate_force_state(data_store: GameDataStore) -> Array[String]:
	return data_store.validate_runtime_indexes()


static func pending_pool_roster_violations(
		data_store: GameDataStore, state: GameStateData) -> Array[String]:
	var violations: Array[String] = []
	var not_ashore := state.refresh_not_ashore_by_type()
	for brigade_id_value in not_ashore:
		var brigade_id := String(brigade_id_value)
		var brigade: Brigade = data_store.get_brigade(brigade_id)
		if brigade == null:
			continue
		var qty_by_type: Dictionary = {}
		for battalion_value in brigade.composition:
			var battalion: Battalion = battalion_value
			qty_by_type[battalion.type] = int(qty_by_type.get(battalion.type, 0)) + battalion.qty
		for battalion_type in (not_ashore[brigade_id] as Dictionary):
			var pending := int(not_ashore[brigade_id][battalion_type])
			var roster := int(qty_by_type.get(battalion_type, 0))
			if roster < pending:
				violations.append("%s/%s: roster %d < pending %d" % [
					brigade_id, battalion_type, roster, pending])
	return violations


# ── Helpers ─────────────────────────────────────────────────────────────────────────────────────

static func _brigade_or_error(data_store: GameDataStore, brigade_id: String, action: String) -> Brigade:
	var brigade: Brigade = data_store.get_brigade(brigade_id)
	if brigade == null:
		push_error("ForceTransitions: %s references unknown brigade_id: %s" % [action, brigade_id])
	return brigade


static func _apply_hex(data_store: GameDataStore, brigade: Brigade, hex_id: String) -> void:
	var old_hex := brigade.hex_id
	if old_hex != "" and data_store.brigades_by_hex.has(old_hex):
		data_store.brigades_by_hex[old_hex] = (data_store.brigades_by_hex[old_hex] as Array).filter(
			func(id: String) -> bool: return id != brigade.id)
	brigade.hex_id = hex_id
	if hex_id.is_empty():
		return
	if not data_store.brigades_by_hex.has(hex_id):
		data_store.brigades_by_hex[hex_id] = []
	if brigade.id not in data_store.brigades_by_hex[hex_id]:
		(data_store.brigades_by_hex[hex_id] as Array).append(brigade.id)


static func _check_index(data_store: GameDataStore, brigade_id: String) -> void:
	if not OS.is_debug_build():
		return
	var violations := data_store.validate_runtime_indexes()
	for violation in violations:
		if String(violation).find(brigade_id) >= 0:
			push_error("ForceTransitions: placement index invariant failed: %s" % String(violation))


static func _battalion_count(brigade: Brigade, battalion_type: String) -> int:
	var total := 0
	for battalion_value in brigade.composition:
		var battalion: Battalion = battalion_value
		if battalion.type == battalion_type:
			total += battalion.qty
	return total


static func _apply_roster_loss(brigade: Brigade, battalion_type: String, count: int) -> void:
	var remaining := count
	for index in range(brigade.composition.size() - 1, -1, -1):
		var battalion: Battalion = brigade.composition[index]
		if battalion.type != battalion_type:
			continue
		var take := mini(battalion.qty, remaining)
		battalion.qty -= take
		remaining -= take
		if battalion.qty <= 0:
			brigade.composition.remove_at(index)
		if remaining <= 0:
			return


static func _force_lost_id_set(lost_ids: Array, ship_reserve: Array) -> Dictionary:
	var cargo_ids := _cargo_bn_ids(ship_reserve)
	var lost: Dictionary = {}
	for id_value in lost_ids:
		var id := String(id_value)
		if cargo_ids.has(id):
			continue
		lost[id] = true
	return lost


static func _duplicate_force_lost_id(lost_ids: Array, ship_reserve: Array) -> String:
	var cargo_ids := _cargo_bn_ids(ship_reserve)
	var seen: Dictionary = {}
	for id_value in lost_ids:
		var id := String(id_value)
		if cargo_ids.has(id):
			continue
		if seen.has(id):
			return id
		seen[id] = true
	return ""


static func _cargo_bn_ids(ship_reserve: Array) -> Dictionary:
	var ids: Dictionary = {}
	for entry_value in ship_reserve:
		var entry: Dictionary = entry_value
		if not JlsfCargo.is_jlsf_entry(entry):
			continue
		for bn_value in entry["bns"]:
			ids[String((bn_value as Dictionary)["id"])] = true
	return ids


static func _reserve_rows_by_lost_id(ship_reserve: Array, lost: Dictionary) -> Dictionary:
	var rows: Dictionary = {}
	for entry_value in ship_reserve:
		var entry: Dictionary = entry_value
		if JlsfCargo.is_jlsf_entry(entry):
			continue
		for bn_value in entry["bns"]:
			var bn: Dictionary = bn_value
			var bn_id := String(bn["id"])
			if not lost.has(bn_id):
				continue
			if rows.has(bn_id):
				push_error("ForceTransitions: crossing casualty id %s appears in reserve twice" % bn_id)
				return {}
			rows[bn_id] = {"brigade_id": String(entry["brigade_id"]), "type": String(bn["type"])}
	for bn_id in lost.keys():
		if not rows.has(bn_id):
			push_error("ForceTransitions: crossing casualty id %s is missing from reserve" % String(bn_id))
			return {}
	return rows


static func _rosters_cover_rows(data_store: GameDataStore, reserve_rows: Dictionary) -> bool:
	var needed_by_brigade_type: Dictionary = {}
	for row_value in reserve_rows.values():
		var row: Dictionary = row_value
		var key := "%s|%s" % [String(row["brigade_id"]), String(row["type"])]
		needed_by_brigade_type[key] = int(needed_by_brigade_type.get(key, 0)) + 1
	for key_value in needed_by_brigade_type.keys():
		var key := String(key_value)
		var brigade_id := key.get_slice("|", 0)
		var battalion_type := key.get_slice("|", 1)
		var brigade := _brigade_or_error(data_store, brigade_id, "crossing casualty")
		if brigade == null:
			return false
		var available := _battalion_count(brigade, battalion_type)
		var needed := int(needed_by_brigade_type[key])
		if available < needed:
			push_error("ForceTransitions: crossing casualties need %d %s from %s but roster has %d" % [
				needed, battalion_type, brigade_id, available])
			return false
	return true


## Validate that the sent BN ids (landed + lost) form the exact prefix of the pool entry.
## Each BN in the request must match the corresponding pool entry BN by id and type.
static func _validate_air_pool_prefix(air_state: AirInsertionState, brigade_id: String, landed: Array, lost: Array) -> bool:
	var pool_entry: Dictionary = {}
	for entry_value in air_state.pool:
		var entry: Dictionary = entry_value
		if String(entry["brigade_id"]) == brigade_id:
			pool_entry = entry
			break
	if pool_entry.is_empty():
		push_error("ForceTransitions: air pool has no entry for %s" % brigade_id)
		return false

	var pool_bns: Array = pool_entry["bns"]
	var sent := landed.size() + lost.size()
	if sent > pool_bns.size():
		push_error("ForceTransitions: air pool for %s has %d BNs but request sends %d" % [
			brigade_id, pool_bns.size(), sent])
		return false

	# Build lookup of request BN ids -> {id, type}
	var request_bns: Dictionary = {}
	for bn_value in landed:
		var bn: Dictionary = bn_value
		request_bns[String(bn["id"])] = bn
	for bn_value in lost:
		var bn: Dictionary = bn_value
		request_bns[String(bn["id"])] = bn

	# Verify the first sent BNs in pool match the request ids and types
	for index in range(sent):
		var pool_bn: Dictionary = pool_bns[index]
		var pool_id := String(pool_bn["id"])
		var pool_type := String(pool_bn["type"])
		if not request_bns.has(pool_id):
			push_error("ForceTransitions: air pool BN %s at position %d for %s missing from request" % [
				pool_id, index, brigade_id])
			return false
		var req_type := String((request_bns[pool_id] as Dictionary)["type"])
		if req_type != pool_type:
			push_error("ForceTransitions: air pool BN %s at position %d type mismatch: pool=%s request=%s" % [
				pool_id, index, pool_type, req_type])
			return false
		request_bns.erase(pool_id)

	if not request_bns.is_empty():
		push_error("ForceTransitions: air request for %s has extra BN ids not in pool prefix" % brigade_id)
		return false
	return true


## Pre-flight roster check: count needed losses per (brigade, type) and verify rosters can cover.
static func _pool_roster_refuses(data_store: GameDataStore, needed: Dictionary) -> bool:
	for key_value in needed.keys():
		var key := String(key_value)
		var brigade_id := key.get_slice("|", 0)
		var battalion_type := key.get_slice("|", 1)
		var count := int(needed[key])
		var brigade := _brigade_or_error(data_store, brigade_id, "air insertion")
		if brigade == null:
			return true
		var available := _battalion_count(brigade, battalion_type)
		if available < count:
			push_error("ForceTransitions: air insertion needs %d %s from %s but roster has %d" % [
				count, battalion_type, brigade_id, available])
			return true
	return false


## Remove specific BN ids from a pool entry, then remove the entry if empty.
static func _remove_pool_bns(air_state: AirInsertionState, brigade_id: String, landed: Array, lost: Array) -> void:
	var ids_to_remove: Dictionary = {}
	for bn_value in landed:
		ids_to_remove[String((bn_value as Dictionary)["id"])] = true
	for bn_value in lost:
		ids_to_remove[String((bn_value as Dictionary)["id"])] = true
	if ids_to_remove.is_empty():
		return
	for entry_value in air_state.pool:
		var entry: Dictionary = entry_value
		if String(entry["brigade_id"]) != brigade_id:
			continue
		var remaining: Array = []
		for bn_value in entry["bns"]:
			var bn: Dictionary = bn_value
			if not ids_to_remove.has(String(bn["id"])):
				remaining.append(bn)
		entry["bns"] = remaining
		return


## Remove empty pool entries (all their BNs have flown).
static func _remove_from_reserve_ids(ship_reserve: Array, lost: Dictionary) -> void:
	if lost.is_empty():
		return
	var kept: Array = []
	for entry_value in ship_reserve:
		var entry: Dictionary = entry_value
		var surviving: Array = []
		for bn_value in entry.get("bns", []):
			var bn: Dictionary = bn_value
			if not lost.has(String(bn.get("id", ""))):
				surviving.append(bn)
		if surviving.is_empty():
			continue
		entry["bns"] = surviving
		kept.append(entry)
	ship_reserve.clear()
	for entry_value in kept:
		ship_reserve.append(entry_value)


## Record which class of hull is lifting this battalion (plan 0006). The planner works it out and the
## authority writes it, because the row lives in force-owned transport storage — a battalion with no entry
## in the map is left exactly as it was, which is how an unliftable BN keeps the category of whatever
## lifted it last.
static func _stamp_ship_category(bn: Dictionary, ship_categories: Dictionary) -> void:
	var bn_id := String(bn.get("id", ""))
	if ship_categories.has(bn_id):
		bn["ship_category"] = String(ship_categories[bn_id])


static func _remove_from_cohort_ids(sealift_state: SealiftState, drop_ids: Array) -> void:
	if sealift_state == null or drop_ids.is_empty():
		return
	var drop: Dictionary = {}
	for id in drop_ids:
		drop[String(id)] = true
	for cohort in sealift_state.cohorts:
		var remaining: Array[String] = []
		for id_value in cohort.bn_ids:
			if not drop.has(String(id_value)):
				remaining.append(String(id_value))
		cohort.bn_ids = remaining


static func _drop_empty_air_pool_entries(air_state: AirInsertionState) -> void:
	var remaining: Array = []
	for entry_value in air_state.pool:
		var entry: Dictionary = entry_value
		if not (entry["bns"] as Array).is_empty():
			remaining.append(entry)
	air_state.pool = remaining


static func _merge_reserve_entry(ship_reserve: Array, entry: Dictionary) -> void:
	var brigade_id := String(entry.get("brigade_id", ""))
	for existing_value in ship_reserve:
		var existing: Dictionary = existing_value
		if String(existing.get("brigade_id", "")) == brigade_id:
			(existing["bns"] as Array).append_array(entry["bns"] as Array)
			return
	ship_reserve.append(entry.duplicate(true))


static func _reserve_id_count(ship_reserve: Array, bn_id: String) -> int:
	var count := 0
	for entry_value in ship_reserve:
		for bn_value in (entry_value as Dictionary).get("bns", []):
			if String((bn_value as Dictionary).get("id", "")) == bn_id:
				count += 1
	return count


static func _duplicate_id(ids: Array) -> String:
	var seen: Dictionary = {}
	for value in ids:
		var id := String(value)
		if seen.has(id):
			return id
		seen[id] = true
	return ""


static func _unique_id_set(ids: Array):
	var unique: Dictionary = {}
	for value in ids:
		var id := String(value)
		if id.is_empty() or unique.has(id):
			return null
		unique[id] = true
	return unique


static func _typed_string_array(values: Array) -> Array[String]:
	var strings: Array[String] = []
	for value in values:
		strings.append(String(value))
	return strings


static func _sent_cohorts_contain_once(sealift_state: SealiftState, lost: Dictionary) -> bool:
	if sealift_state == null:
		push_error("ForceTransitions: crossing casualty validation requires sealift_state")
		return false
	var counts: Dictionary = {}
	for cohort in sealift_state.cohorts:
		if not cohort.is_sent():
			continue
		for id_value in cohort.bn_ids:
			var id := String(id_value)
			if lost.has(id):
				counts[id] = int(counts.get(id, 0)) + 1
	for bn_id in lost.keys():
		var count := int(counts.get(bn_id, 0))
		if count != 1:
			push_error("ForceTransitions: crossing casualty id %s appears in sent cohorts %d times" % [
				String(bn_id), count])
			return false
	return true
