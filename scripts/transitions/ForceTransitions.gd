class_name ForceTransitions
extends RefCounted

## THE mutation authority for the force aggregate (plan 0044). It is the only production writer for
## Brigade runtime fields and the GameData.brigades_by_hex placement projection. Legacy transport
## storage is still dictionary-shaped during this migration; callers pass typed requests so the
## operation vocabulary is closed before the physical storage moves.
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


## Validate drowned force BN ids against both live storage views, then shrink the roster once per id.
## Reserve/cohort removal still happens in the phase coordinator during this migration, but this
## method is the one place that maps ids to roster deltas and catches one-sided omissions before the
## roster changes. JLSF pseudo-BNs are cargo and deliberately ignored here.
static func apply_crossing_casualties(
		data_store: GameDataStore, request: ForceCrossingCasualtyRequest) -> Array[ForceCasualtyReceipt]:
	var receipts: Array[ForceCasualtyReceipt] = []
	var lost := _force_lost_id_set(request.lost_ids, request.ship_reserve)
	if lost.is_empty():
		return receipts
	var reserve_rows := _reserve_rows_by_lost_id(request.ship_reserve, lost)
	if reserve_rows.size() != lost.size():
		return receipts
	if not _sent_cohorts_contain_once(request.sealift_state, lost):
		return receipts
	for bn_id in lost.keys():
		var row: Dictionary = reserve_rows[bn_id]
		var casualty := ForceCasualtyRequest.one(
			String(row["brigade_id"]), String(row["type"]),
			ForceCasualtyCause.Kind.CROSSING, ForceLocation.Kind.AT_SEA)
		receipts.append(apply_battalion_casualties(data_store, casualty))
	return receipts


# ── Brigade activity / organization ────────────────────────────────────────────────────────────

static func apply_activity(brigade: Brigade, request: ForceActivityRequest) -> void:
	if brigade == null:
		push_error("ForceTransitions: activity request has null brigade")
		return
	match request.operation:
		ForceActivityRequest.Operation.MOVE_TACTICAL:
			brigade.moved_this_turn = true
			brigade.adjust_organization(-Brigade.TACTICAL_MOVE_ORG_COST)
		ForceActivityRequest.Operation.MOVE_ADMIN:
			brigade.moved_this_turn = true
			brigade.moved_admin_this_turn = true
			brigade.adjust_organization(-Brigade.ADMIN_MOVE_ORG_COST)
		ForceActivityRequest.Operation.FOUGHT:
			brigade.fought_this_turn = true
		ForceActivityRequest.Operation.LATCH_PRIOR_FROM_CURRENT:
			brigade.moved_last_turn = brigade.moved_this_turn or brigade.moved_admin_this_turn
			brigade.fought_last_turn = brigade.fought_this_turn
		ForceActivityRequest.Operation.RESET_TURN_FLAGS:
			brigade.moved_this_turn = false
			brigade.moved_admin_this_turn = false
			brigade.fought_this_turn = false


# ── Read-only backstop ──────────────────────────────────────────────────────────────────────────

static func validate_force_state(data_store: GameDataStore) -> Array[String]:
	return data_store.validate_runtime_indexes()


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
		if lost.has(id):
			push_error("ForceTransitions: crossing casualty id %s appears twice in lost_ids" % id)
			return {}
		lost[id] = true
	return lost


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


static func _sent_cohorts_contain_once(sealift_state: SealiftState, lost: Dictionary) -> bool:
	if sealift_state == null:
		push_error("ForceTransitions: crossing casualty validation requires sealift_state")
		return false
	var counts: Dictionary = {}
	for cohort_value in sealift_state.cohorts:
		var cohort: Dictionary = cohort_value
		if String(cohort["state"]) != SealiftState.STATE_SENT:
			continue
		for id_value in cohort["bn_ids"]:
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
