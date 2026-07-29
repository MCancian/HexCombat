class_name ForceMobilizationValidation
extends RefCounted

## Read-only all-or-nothing preflight for a mobilization release batch.

static func preflight(
		data_store: GameDataStore, state: MobilizationState,
		request: ForceMobilizationRequest) -> ForceValidationResult:
	if state == null:
		return ForceValidationResult.refused("ForceTransitions: mobilization has null state")
	var pending_count: Dictionary = {}
	var pending_by_id: Dictionary = {}
	for entry_value in state.pending:
		var entry: Dictionary = entry_value
		var brigade_id := String(entry.get("brigade_id", ""))
		pending_count[brigade_id] = int(pending_count.get(brigade_id, 0)) + 1
		pending_by_id[brigade_id] = entry
	var seen: Dictionary = {}
	for arrival_value in request.arrivals:
		var arrival: Dictionary = arrival_value
		var brigade_id := String(arrival.get("brigade_id", ""))
		if seen.has(brigade_id):
			return ForceValidationResult.refused(
				"ForceTransitions: duplicate mobilization arrival %s" % brigade_id)
		seen[brigade_id] = true
		var error := _validate_arrival(
			data_store, request.turn_number, arrival,
			int(pending_count.get(brigade_id, 0)), pending_by_id.get(brigade_id, {}))
		if error != null:
			return error
	return null


static func _validate_arrival(
		data_store: GameDataStore, turn_number: int, arrival: Dictionary,
		pending_count: int, pending_entry: Dictionary) -> ForceValidationResult:
	var brigade_id := String(arrival.get("brigade_id", ""))
	if pending_count != 1:
		return ForceValidationResult.refused(
			"ForceTransitions: mobilization %s has %d pending entries" % [brigade_id, pending_count])
	if int(pending_entry.get("release_turn", 0)) > turn_number:
		return ForceValidationResult.refused(
			"ForceTransitions: mobilization %s is not due" % brigade_id)
	var brigade: Brigade = data_store.get_brigade(brigade_id)
	if brigade == null or brigade.destroyed or not brigade.hex_id.is_empty():
		return ForceValidationResult.refused(
			"ForceTransitions: mobilization brigade %s is unavailable" % brigade_id)
	if int(arrival.get("battalions", 0)) != brigade.get_battalion_count():
		return ForceValidationResult.refused(
			"ForceTransitions: mobilization battalion count mismatch for %s" % brigade_id)
	var hex_id := String(arrival.get("hex_id", ""))
	if not data_store.hex_lookup.has(hex_id):
		return ForceValidationResult.refused(
			"ForceTransitions: mobilization destination is invalid for %s" % brigade_id)
	return null
