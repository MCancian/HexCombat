class_name SupplyBill
extends RefCounted

## Who eats today, and how much (plan 0049). Pure: it reads the content store's roster, decides which
## Red battalions draw Taiwan-theater supply and which brigades were active, and returns the
## consumption row `DosConsumption` computes. It applies NOTHING — `SupplyTransitions` alone moves the
## balance and appends the ledger row.
##
## This is the gathering `TurnClosure.resolve_supply_turn` did inline before the supply aggregate got
## an authority. It moved here rather than into the authority because an authority may not read a
## content autoload, and it takes `not_ashore` as an ARGUMENT rather than calling
## `state.refresh_not_ashore_by_type()` itself: that method assigns a cache that outlives the call,
## which is exactly what a calculator may not do. The coordinator refreshes and passes the result in.


## units: DosConsumption battalion records ({brigade_id, type, brigade_type} per BN instance).
## not_ashore: brigade_id -> {battalion_type: count}, freshly recomputed by the caller.
## Returns the consumption summary Dictionary (the public/JSON contract for this phase).
static func for_turn(store: GameDataStore, not_ashore: Dictionary, turn_number: int) -> Dictionary:
	var moved_ids: Array[String] = []
	var engaged_ids: Array[String] = []
	for brigade_value in store.brigades.values():
		var brigade: Brigade = brigade_value
		if not _draws_theater_supply(brigade):
			continue
		if brigade.moved_this_turn:
			moved_ids.append(brigade.id)
		if brigade.fought_this_turn:
			engaged_ids.append(brigade.id)
	return DosConsumption.calculate_consumption(
		active_red_battalion_units(store, not_ashore), moved_ids, engaged_ids, turn_number)


## Red battalions drawing Taiwan-theater supply. Only battalions ASHORE eat (plan 0037, USER call
## 2026-07-25): one still at sea, on the mainland, or waiting to fly is not being supplied across the
## strait by this pool. Same not-ashore definition combat uses, so a brigade's fighting strength and
## its ration bill always describe the same battalions.
static func active_red_battalion_units(store: GameDataStore, not_ashore: Dictionary) -> Array:
	var units: Array = []
	for brigade_value in store.brigades.values():
		var brigade: Brigade = brigade_value
		if not _draws_theater_supply(brigade):
			continue
		var brigade_not_ashore: Dictionary = not_ashore.get(brigade.id, {})
		for battalion_value in brigade.composition:
			var battalion: Battalion = battalion_value
			for _qty_index in range(Brigade.landed_qty(battalion, brigade_not_ashore)):
				units.append({
					"brigade_id": brigade.id,
					"type": battalion.type,
					"brigade_type": brigade.nato_type,
				})
	return units


## One definition, used by both loops above, so the ration bill and the activity flags can never
## describe different brigades: Red, alive, and actually on the island.
static func _draws_theater_supply(brigade: Brigade) -> bool:
	return brigade.team == Brigade.Team.RED and not brigade.destroyed and not brigade.hex_id.is_empty()
