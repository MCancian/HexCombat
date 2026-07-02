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
## Returns {"manifest": Dictionary (incl. landed_brigade_ids), "remaining_ship_reserve": Array,
## "landings": [{brigade_id, beach_hex, offset_bearing}, …]}. Mutates each reserve entry's "bns"
## in place (landed BNs removed), matching the pre-extraction behavior.
static func resolve(turn_number: int, ship_reserve: Array, beaches: Dictionary, brigades: Dictionary) -> Dictionary:
	var active_beach_ids: Array[int] = []
	for reserve_entry_value in ship_reserve:
		var reserve_entry: Dictionary = reserve_entry_value
		var locked_beach := int(reserve_entry["locked_beach"])
		if locked_beach <= 0:
			push_error("Ship reserve entry has no locked_beach: %s" % String(reserve_entry["brigade_id"]))
			continue
		if locked_beach not in active_beach_ids:
			active_beach_ids.append(locked_beach)

	var beach_capacity := OffloadCalculator.beach_capacity_bns(active_beach_ids, beaches)
	var manifest := OffloadCalculator.resolve_offload_day(turn_number, beach_capacity, ship_reserve, priority_order(ship_reserve))

	var landed_bn_ids_by_brigade: Dictionary = {}
	for landed_value in manifest["manifest_landed"]:
		var landed: Dictionary = landed_value
		var brigade_id := String(landed["brigade_id"])
		var bn_id := String(landed["bn_id"])
		if brigade_id not in landed_bn_ids_by_brigade:
			landed_bn_ids_by_brigade[brigade_id] = {}
		landed_bn_ids_by_brigade[brigade_id][bn_id] = true

	var landed_brigade_ids: Array[String] = []
	var landings: Array = []
	var remaining_ship_reserve: Array = []
	for reserve_entry_value in ship_reserve:
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
				landings.append({
					"brigade_id": brigade_id,
					"beach_hex": String(reserve_entry["beach_hex"]),
					"offset_bearing": float(reserve_entry["offset_bearing"]),
				})
				landed_brigade_ids.append(brigade_id)

		if (reserve_entry["bns"] as Array).is_empty():
			continue
		remaining_ship_reserve.append(reserve_entry)

	manifest["landed_brigade_ids"] = landed_brigade_ids
	return {
		"manifest": manifest,
		"remaining_ship_reserve": remaining_ship_reserve,
		"landings": landings,
	}
