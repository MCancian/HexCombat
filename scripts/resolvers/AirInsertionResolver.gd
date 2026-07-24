class_name AirInsertionResolver
extends RefCounted

## Pure resolver for the air insertion phase (plan 0032) — the PLA's non-amphibious path onto
## Taiwan. Each turn it flies the ordered brigades' battalions out of AirInsertionState.pool, up to
## a per-lift-class budget, rolls each battalion against the air-defence environment, and reports
## which ones came down alive and where.
##
## Purity boundary: this drains the pool, erodes the caps and reports what should arrive where; the
## CALLER (TurnConductor.resolve_air_insertion_turn) owns the GameData mutation — set_brigade_hex
## for the landings, apply_casualty for the losses — and the IJFS target bookkeeping, exactly as
## OffloadResolver and MobilizationResolver leave application to their wrappers. Live map knowledge
## enters through the `hex_can_receive` Callable so no autoload is touched here.
##
## Dice: ONE derived substream per turn (`air_insertion:<turn>`), consumed only when a packet
## actually flies. No orders => no derive, no draws => the golden stream is untouched.

const REASON_UNKNOWN_HEX := "unknown_or_impassable_hex"


## Fraction of an inserting packet the air defences destroy.
##
##   airborne     = max_attrition_at_full_ad x effective_ad_health
##   air_assault  = the same, PLUS manpads_max_attrition x MANPADS threat fraction
##
## Linear in AD health by USER call (2026-07-24): an intact system destroys 75%, and the ~0.24
## effective_ad_health that survives the 3-day pre-invasion warmup therefore costs a typical drop
## ~18%. Rotary-wing lift carries the second term because the MANPADS layer is deliberately outside
## the AD-health metric yet is exactly what engages helicopters — reusing IjfsManpads.threat_fraction
## keeps the saturation curve in one place.
static func attrition_rate(
	lift_class: String, ad_health: float, manpads_ready_systems: int, config: Dictionary
) -> float:
	var rate := float(config["max_attrition_at_full_ad"]) * clampf(ad_health, 0.0, 1.0)
	if lift_class == LiftClass.AIR_ASSAULT:
		rate += float(config["manpads_max_attrition"]) * IjfsManpads.threat_fraction(manpads_ready_systems)
	return clampf(rate, 0.0, 1.0)


## Which air-landed brigades are fighting on their own (plan 0032, USER call 2026-07-24: dropped
## battalions are out of supply until connected to the beach). Returns brigade_id -> true.
##
## Connected means a chain of Red-held hexes runs from the brigade back to a lodgement — a held
## landing beach or a Red-usable port/airbridge. A brigade counts as connected when its own hex is
## on that chain OR merely touches it, so a formation fighting at the tip of a corridor is supplied
## while one dropped in the deep rear is not; the corridor has to actually reach it.
##
## Pure: the map arrives as Callables, so nothing here touches an autoload.
##   is_red_hex:   Callable(hex_id) -> bool
##   neighbors_of: Callable(hex_id) -> Array
static func isolated_brigades(
	landed_brigade_ids: Array,
	brigade_hexes: Dictionary,
	source_hexes: Array,
	is_red_hex: Callable,
	neighbors_of: Callable,
) -> Dictionary:
	var isolated: Dictionary = {}
	if landed_brigade_ids.is_empty():
		return isolated

	# Flood the Red-held corridor outward from every lodgement.
	var connected: Dictionary = {}
	var frontier: Array[String] = []
	for source_value in source_hexes:
		var source_hex := String(source_value)
		if connected.has(source_hex) or not bool(is_red_hex.call(source_hex)):
			continue
		connected[source_hex] = true
		frontier.append(source_hex)
	while not frontier.is_empty():
		var hex_id: String = frontier.pop_back()
		for neighbor_value in neighbors_of.call(hex_id):
			var neighbor := String(neighbor_value)
			if connected.has(neighbor) or not bool(is_red_hex.call(neighbor)):
				continue
			connected[neighbor] = true
			frontier.append(neighbor)

	for brigade_id_value in landed_brigade_ids:
		var brigade_id := String(brigade_id_value)
		var hex_id := String(brigade_hexes.get(brigade_id, ""))
		if hex_id.is_empty():
			continue  # not on the map (destroyed, or nothing landed yet) — nothing to supply
		if connected.has(hex_id):
			continue
		var touching := false
		for neighbor_value in neighbors_of.call(hex_id):
			if connected.has(String(neighbor_value)):
				touching = true
				break
		if not touching:
			isolated[brigade_id] = true
	return isolated


## Extract the air-defence picture `resolve` wants from an IJFS phase summary. The sole home for
## which IJFS fields the air path reads, so the turn conductor and the LLM observation cannot drift
## apart on it — and pure, so callers that must not touch autoloads can use it too.
static func threat_from_ijfs_summary(ijfs_summary: Dictionary) -> Dictionary:
	var ad_health: Dictionary = ijfs_summary.get("taiwan_ad_health_after", {})
	var manpads: Dictionary = ijfs_summary.get("manpads", {})
	var ready_by_to: Dictionary = manpads.get("ready_systems_by_to", {})
	return {
		"ad_health": float(ad_health.get("effective_ad_health", 0.0)),
		"manpads_ready_systems": int(ready_by_to.get("total", 0)),
	}


## Resolve this turn's air insertions.
##
## orders:  [{brigade_id: String, target_hex: String}] in issue order — the player's priority, and
##          the order the shared per-class budget is spent in.
## threat:  {"ad_health": float, "manpads_ready_systems": int} — this turn's POST-strike air-defence
##          picture, so suppressing Taiwan's SAMs before dropping visibly pays off.
## config:  AirInsertionStateBuilder.attrition_config output.
## hex_can_receive: Callable(hex_id: String) -> bool — placed and passable. Enemy-held and contested
##          hexes ARE legal drop zones (USER design call: land on any hex); the cost of dropping
##          onto the enemy is the ground combat that follows in the same turn, not a special rule.
##
## Mutates `state` (pool drained, caps eroded, history/landed appended) and returns the summary.
## The returned drops carry the battalion manifests the caller must apply: `landed_bns` to place,
## `lost_bns` to kill.
static func resolve(
	state: AirInsertionState,
	orders: Array,
	turn_number: int,
	threat: Dictionary,
	config: Dictionary,
	hex_can_receive: Callable,
	dice: Dice,
) -> AirInsertionSummary:
	var summary := AirInsertionSummary.new()
	if state == null:
		return summary

	summary.caps_before = state.caps.duplicate()
	summary.caps_after = state.caps.duplicate()
	if orders.is_empty():
		_finish(summary, state)
		return summary

	if turn_number < state.first_turn:
		for order_value in orders:
			summary.rejected.append({
				"brigade_id": String((order_value as Dictionary)["brigade_id"]),
				"reason": AirInsertionSummary.REASON_BEFORE_FIRST_TURN,
			})
		_finish(summary, state)
		return summary

	# Budget is per turn and shared across every order of a class; caps themselves are eroded
	# permanently by losses further down.
	var budget: Dictionary = state.caps.duplicate()
	var substream: Dice = null

	for order_value in orders:
		var order: Dictionary = order_value
		var brigade_id := String(order["brigade_id"])
		var target_hex := String(order["target_hex"])

		var entry := state.entry_for(brigade_id)
		if entry.is_empty():
			summary.rejected.append({"brigade_id": brigade_id, "reason": AirInsertionSummary.REASON_POOL_EMPTY})
			continue
		if not bool(hex_can_receive.call(target_hex)):
			summary.rejected.append({"brigade_id": brigade_id, "reason": REASON_UNKNOWN_HEX})
			continue

		var lift_class := String(entry["lift_class"])
		var remaining := int(budget.get(lift_class, 0))
		if remaining <= 0:
			summary.rejected.append({"brigade_id": brigade_id, "reason": AirInsertionSummary.REASON_CAP_EXHAUSTED})
			continue

		var manifest: Array = entry["bns"]
		var sent := mini(remaining, manifest.size())
		var rate := attrition_rate(
			lift_class, float(threat.get("ad_health", 0.0)),
			int(threat.get("manpads_ready_systems", 0)), config)
		if substream == null:
			substream = dice.derive("air_insertion:%d" % turn_number)

		var landed_bns: Array = []
		var lost_bns: Array = []
		for _packet_index in range(sent):
			var battalion: Dictionary = manifest.pop_front()
			if substream.randf() < rate:
				lost_bns.append(battalion)
			else:
				landed_bns.append(battalion)

		budget[lift_class] = remaining - sent
		# Every loss is an airframe as well as a battalion: the cap it flew under drops by one and
		# never recovers (USER call 2026-07-24).
		state.caps[lift_class] = maxi(0, int(state.caps[lift_class]) - lost_bns.size())

		var first_landing := not landed_bns.is_empty() and not state.landed.has(brigade_id)
		if first_landing:
			state.landed.append(brigade_id)

		summary.drops.append({
			"brigade_id": brigade_id,
			"lift_class": lift_class,
			"hex_id": target_hex,
			"sent": sent,
			"landed": landed_bns.size(),
			"lost": lost_bns.size(),
			"attrition_rate": rate,
			"first_landing": first_landing,
			"landed_bns": landed_bns,
			"lost_bns": lost_bns,
		})
		summary.battalions_landed += landed_bns.size()
		summary.battalions_lost += lost_bns.size()
		summary.attrition_by_class[lift_class] = rate
		state.history.append({
			"turn": turn_number,
			"brigade_id": brigade_id,
			"lift_class": lift_class,
			"hex_id": target_hex,
			"landed": landed_bns.size(),
			"lost": lost_bns.size(),
		})

	_drop_empty_entries(state)
	summary.caps_after = state.caps.duplicate()
	_finish(summary, state)
	return summary


static func _drop_empty_entries(state: AirInsertionState) -> void:
	var remaining: Array = []
	for entry_value in state.pool:
		var entry: Dictionary = entry_value
		if not (entry["bns"] as Array).is_empty():
			remaining.append(entry)
	state.pool = remaining


static func _finish(summary: AirInsertionSummary, state: AirInsertionState) -> void:
	summary.pending_brigades = state.pending_brigades()
	summary.pending_battalions = state.pending_battalions()
