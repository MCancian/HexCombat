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
		for instance_value in PendingBattalions.instances(brigade):
			var instance: Dictionary = instance_value
			var battalion_type := String(instance["type"])
			var type_slug := battalion_type.to_lower().replace(" ", "_")
			bns.append({
				"id": "%s-%s-%d" % [brigade_id, type_slug, int(instance["index"])],
				"type": battalion_type
			})

		reserve.append({
			"brigade_id": brigade_id,
			"locked_beach": int(reserve_entry["locked_beach"]),
			"beach_hex": String(reserve_entry["beach_hex"]),
			"offset_bearing": float(reserve_entry["offset_bearing"]),
			"bns": bns
		})
	return reserve
