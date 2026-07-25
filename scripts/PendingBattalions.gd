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


## brigade_id -> number of its battalions not ashore, summed across every supplied pool. A brigade
## split across pools (embarking in echelons, so part at sea and part on the mainland) sums.
static func by_brigade(pools: Array) -> Dictionary:
	var not_ashore: Dictionary = {}
	for pool_value in pools:
		for entry_value in pool_value as Array:
			var entry: Dictionary = entry_value
			var brigade_id := String(entry["brigade_id"])
			not_ashore[brigade_id] = int(not_ashore.get(brigade_id, 0)) + (entry["bns"] as Array).size()
	return not_ashore


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
