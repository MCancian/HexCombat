class_name ShipReserveBuilder
extends RefCounted

## Pure builder for GameState.ship_reserve (refactor_audit item 10, Phase A): expands each
## scenario red_ship_reserve entry into an OffloadCalculator-ready record with one BN entry per
## battalion instance ({id: "<brigade>-<type_slug>-<n>", type}). No autoload access — the caller
## passes the scenario reserve entries and the brigade lookup in.


## red_ship_reserve: Array of scenario dicts {brigade_id, locked_beach, beach_hex, offset_bearing}.
## brigades: Dictionary of brigade_id (String) -> Brigade.
## Returns the ship_reserve Array; unknown brigade_ids push_error and are skipped (fail loud).
static func build(red_ship_reserve: Array, brigades: Dictionary) -> Array:
	var reserve: Array = []
	for reserve_entry_value in red_ship_reserve:
		var reserve_entry: Dictionary = reserve_entry_value
		var brigade_id := String(reserve_entry["brigade_id"])
		var brigade: Brigade = brigades.get(brigade_id)
		if brigade == null:
			push_error("Ship reserve references unknown brigade_id: %s" % brigade_id)
			continue

		var bns: Array = []
		var battalion_index := 1
		for battalion in brigade.composition:
			var typed_battalion: Battalion = battalion
			var type_slug := typed_battalion.type.to_lower().replace(" ", "_")
			for _qty_index in range(typed_battalion.qty):
				bns.append({
					"id": "%s-%s-%d" % [brigade_id, type_slug, battalion_index],
					"type": typed_battalion.type
				})
				battalion_index += 1

		reserve.append({
			"brigade_id": brigade_id,
			"locked_beach": int(reserve_entry["locked_beach"]),
			"beach_hex": String(reserve_entry["beach_hex"]),
			"offset_bearing": float(reserve_entry["offset_bearing"]),
			"bns": bns
		})
	return reserve
