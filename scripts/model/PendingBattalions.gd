class_name PendingBattalions
extends RefCounted

## The single home for "battalions that belong to an on-map brigade but are not on Taiwan yet"
## (plan 0034). Three subsystems park battalions off-map, all in the same `{brigade_id, …, bns: […]}`
## entry shape:
##
##   1. GameStateData.ship_reserve          — at sea, crossing or waiting to offload.
##   2. SealiftState.mainland_pool          — still on the mainland, waiting for a hull.
##   3. AirInsertionState.pool              — waiting to fly (plan 0032).
##
## The victory census MUST subtract every one of them from Brigade.get_battalion_count(), because a
## brigade counts as present the moment its FIRST battalion lands while the rest of its composition
## is still in a pool. A pool the census does not know about silently credits its side with
## battalions that are not there — the ghost-landing failure family (2026-07-24, commit bff4a1c).
##
## `GameStateData.pending_battalion_pools()` is the enforcement point — the ONLY place that
## enumerates the off-map pools, and it lives on the value object that owns all three fields. A new
## mechanic that parks battalions off-map is wired into the census by adding one line THERE, rather
## than by remembering to widen a census signature. Everything that needs "who is not ashore" goes
## pending_battalion_pools() -> by_brigade() and so cannot accidentally see a partial list.


## brigade_id -> {battalion_type: count} not ashore, across every supplied pool (plan 0037).
##
## The type breakdown is what combat needs: WHICH type is missing decides whether the absent
## battalion was a maneuver unit or a support one, and those are weighted differently in strength and
## in casualty selection. It is exact rather than apportioned because pool entries carry each
## battalion's `type`, inherited from `composition` when the pool was built — so a pool BN's type
## always names a real composition entry of the same brigade.
static func by_brigade_and_type(pools: Array) -> Dictionary:
	var not_ashore: Dictionary = {}
	for pool_value in pools:
		for entry_value in pool_value as Array:
			var entry: Dictionary = entry_value
			var brigade_id := String(entry["brigade_id"])
			var by_type: Dictionary = not_ashore.get(brigade_id, {})
			for bn_value in entry["bns"] as Array:
				var battalion_type := String((bn_value as Dictionary)["type"])
				by_type[battalion_type] = int(by_type.get(battalion_type, 0)) + 1
			not_ashore[brigade_id] = by_type
	return not_ashore


## brigade_id -> total battalions not ashore. Derived from by_brigade_and_type rather than counted
## separately, so the census and combat can never disagree about who is present.
static func by_brigade(pools: Array) -> Dictionary:
	var totals: Dictionary = {}
	var by_type := by_brigade_and_type(pools)
	for brigade_id in by_type:
		var total := 0
		for battalion_type in by_type[brigade_id]:
			total += int(by_type[brigade_id][battalion_type])
		totals[brigade_id] = total
	return totals


## One entry per battalion INSTANCE of a brigade, as {type, index} with a 1-based index running
## across the whole composition. The shared half of the two manifest builders: ShipReserveBuilder and
## AirInsertionStateBuilder each format their own id from this, because their id conventions differ
## and BN ids appear in game records and fixtures (renaming one would be a fixture-visible change for
## no behavioural gain).
static func instances(brigade: Brigade) -> Array:
	var out: Array = []
	var index := 0
	for battalion_value in brigade.composition:
		var battalion: Battalion = battalion_value
		for _qty_index in range(battalion.qty):
			index += 1
			out.append({"type": battalion.type, "index": index})
	return out
