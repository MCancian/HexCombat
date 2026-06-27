class_name ShipLoadingModel
extends RefCounted

## D3-D BN <-> ship mapping. Bridges HexCombat's BN-carrying ship_reserve to the anti-ship
## crossing model (which targets a per-ship-type "sent" fleet) and back.
##
## Source oracle: TaiwanInvasionViewer src/services/manifest_allocator.py
##   - forward  (BNs -> ships):  capacity/eligibility concepts from _AllocationRun._assign_ships,
##                               but the hull-count derivation is HexCombat's (see build_sent_snapshots).
##   - backward (ship loss -> BN loss): _AllocationRun._apply_casualties (lost-capacity sampling)
##
## Two deliberate HexCombat simplifications (consistent with OffloadCalculator's abstraction level,
## logged as in-spirit divergences in PLAN.md):
##   1. Every BN is 1.0 BN-equiv. TIV weights each BN by configurator.get_unit_transport_weight();
##      HexCombat's offload models no per-type transport weight, so all BNs weigh 1.0 BN-equiv and
##      all capacities are read in BN-equiv (data/ships.json carrying_capacity_bn_equiv) -- no tons.
##   2. The amphibious-vs-cargo ship-eligibility split is dropped. TIV's _ship_can_carry_battalion
##      gates amphibious BNs to amphibious ship categories; OffloadCalculator already ignores ship
##      eligibility, so any carrying ship (capacity > 0) may carry any BN here.
##
## Pure RefCounted lib -- no Node/GameState/ShipState coupling. Forward packing is deterministic;
## only the backward BN selection draws from the injected Dice.


## Forward: derive the "sent" crossing fleet from the BNs still at sea.
##
## HexCombat-specific minimum-lift derivation. TIV (_assign_ships) starts from a live sailing set of
## ships already in transit and assigns BNs to fill them; HexCombat has no ship-cycle, so we instead
## derive the smallest fleet that lifts the at-sea BNs: fill the highest-capacity carrier types first
## (capacity_bn_equiv desc, ties by ship_type), consuming ceil(remaining_bn / capacity) hulls per
## type, clamped to the ready count. The capacity/eligibility concepts follow TIV; the hull-count
## derivation is ours. The escort + decoy screen always sails on top.
##
## Args:
##   bn_count: int                  -- number of BNs still at sea (each 1.0 BN-equiv).
##   carriers: Array of Dictionary  -- {ship_type:String, capacity:float, ready:int}; capacity > 0.
##   screen:   Array of Dictionary  -- {ship_type:String, ready:int}; escorts + decoys (capacity 0)
##                                     that sail with the wave as defensive screen / missile soak.
##
## Returns Dictionary:
##   "snapshots":    Array of {ship_type, surviving_sent} -- crossing-ready (carriers + screen,
##                   only types with surviving_sent > 0).
##   "sent_by_type": Dictionary {ship_type -> int}
##   "bn_equiv_assigned": Dictionary {ship_type -> float}  -- BN-equiv carried per carrier type.
##   "unliftable_bn": int -- BNs that exceeded total carrier capacity (fleet can't lift them).
static func build_sent_snapshots(bn_count: int, carriers: Array, screen: Array) -> Dictionary:
	# Highest-capacity carriers first (ties by ship_type) -> deterministic minimum lift.
	var sorted_carriers: Array = []
	for c in carriers:
		var cap := float(c["capacity"])
		var ready := int(c["ready"])
		if cap <= 0.0 or ready <= 0:
			continue
		sorted_carriers.append({"ship_type": String(c["ship_type"]), "capacity": cap, "ready": ready})
	sorted_carriers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a["capacity"]), float(b["capacity"])):
			return float(a["capacity"]) > float(b["capacity"])
		return String(a["ship_type"]) < String(b["ship_type"]))

	var sent_by_type: Dictionary = {}
	var bn_equiv_assigned: Dictionary = {}
	var snapshots: Array = []
	var remaining := float(maxi(0, bn_count))

	for c in sorted_carriers:
		if remaining <= 1e-9:
			break
		var cap := float(c["capacity"])
		var ready := int(c["ready"])
		var ship_type := String(c["ship_type"])
		var sent := mini(ready, int(ceil(remaining / cap)))
		if sent <= 0:
			continue
		var carried := minf(remaining, float(sent) * cap)
		remaining -= carried
		sent_by_type[ship_type] = sent
		bn_equiv_assigned[ship_type] = carried
		snapshots.append({"ship_type": ship_type, "surviving_sent": sent})

	var unliftable := int(ceil(remaining - 1e-9)) if remaining > 1e-9 else 0

	# Escort + decoy screen: every surviving ship of these types sails with the wave.
	for s in screen:
		var ready := int(s["ready"])
		if ready <= 0:
			continue
		var ship_type := String(s["ship_type"])
		sent_by_type[ship_type] = int(sent_by_type.get(ship_type, 0)) + ready
		snapshots.append({"ship_type": ship_type, "surviving_sent": ready})

	return {
		"snapshots": snapshots,
		"sent_by_type": sent_by_type,
		"bn_equiv_assigned": bn_equiv_assigned,
		"unliftable_bn": unliftable,
	}


## Backward: convert crossing ship losses into BNs lost at sea.
##
## Mirrors TIV _apply_casualties: lost_capacity = sum(destroyed[type] * capacity[type]); a fractional
## accumulator carries across turns; bn_count_lost = floor(lost_capacity + accumulator). TIV samples
## the lost BNs weighted by transport weight -- here every BN is 1.0 BN-equiv, so the weighted draw
## reduces to a uniform shuffle of the at-sea pool (dice.shuffle_indices), taking the first N.
##
## Args:
##   destroyed_by_ship_type: Dictionary {ship_type -> int}   -- from AntishipCrossing.
##   capacity_by_type:       Dictionary {ship_type -> float} -- carrying_capacity_bn_equiv (0 = escort).
##   bns_at_sea: Array of Dictionary {id, type, ...}          -- the at-sea BN pool to draw from.
##   accumulator: float                                       -- fractional BN-equiv carried in.
##   dice: Dice                                               -- injected RNG for the BN draw.
##
## Returns Dictionary:
##   "bns_lost":    Array -- the drawn BN dicts (caller removes them from the reserve).
##   "lost_ids":    Array[String] -- their ids, for convenience.
##   "bn_equiv_lost": int   -- number of BNs sunk (== bns_lost.size()).
##   "capacity_lost": float -- raw lost BN-equiv this turn (before accumulator floor).
##   "accumulator":  float  -- fractional remainder to carry into the next turn.
static func resolve_bn_losses(
	destroyed_by_ship_type: Dictionary,
	capacity_by_type: Dictionary,
	bns_at_sea: Array,
	accumulator: float,
	dice: Dice,
) -> Dictionary:
	var capacity_lost := 0.0
	for ship_type in destroyed_by_ship_type.keys():
		var destroyed := int(destroyed_by_ship_type[ship_type])
		if destroyed <= 0:
			continue
		var cap := float(capacity_by_type.get(ship_type, 0.0))
		capacity_lost += float(destroyed) * cap

	var available := capacity_lost + accumulator
	var bn_count_lost := int(floor(available))
	var new_accumulator := available - float(bn_count_lost)

	var n := bns_at_sea.size()
	bn_count_lost = mini(bn_count_lost, n)
	# Carry any capacity we could not realize (pool exhausted) back into the accumulator so it is
	# not silently dropped -- a sunk ship whose cargo already landed still owes its tonnage.
	if bn_count_lost < int(floor(available)):
		new_accumulator += float(int(floor(available)) - bn_count_lost)

	var bns_lost: Array = []
	var lost_ids: Array[String] = []
	if bn_count_lost > 0 and n > 0:
		var order: Array = dice.shuffle_indices(n)
		for i in range(bn_count_lost):
			var bn: Dictionary = bns_at_sea[int(order[i])]
			bns_lost.append(bn)
			lost_ids.append(String(bn.get("id", "")))

	return {
		"bns_lost": bns_lost,
		"lost_ids": lost_ids,
		"bn_equiv_lost": bns_lost.size(),
		"capacity_lost": capacity_lost,
		"accumulator": new_accumulator,
	}
