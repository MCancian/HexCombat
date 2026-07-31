class_name AirInsertionResolver
extends RefCounted

## Pure calculator for the air insertion phase (plan 0032) — the PLA's non-amphibious path onto
## Taiwan. Each turn it flies the ordered brigades' battalions out of AirInsertionState.pool, up to
## a per-lift-class budget, rolls each battalion against the air-defence environment, and reports
## which ones came down alive and where.
##
## Purity boundary: this computes the outcome (summary + landings) but writes NOTHING — not
## AirInsertionState, not GameData force fields, nothing that outlives the call. It lives under
## scripts/calc/ for exactly that reason (plan 0048). `ReinforcementPhases` hands what it returns to
## the two authorities that share the model: `ForceTransitions` for who moved,
## `AirInsertionTransitions` for what the lift cost. `caps_after` here is REPORT-ONLY — the authority
## derives the applied budget from the drop rows rather than copying it.
##
## Dice: ONE derived substream per turn (`air_insertion:<turn>`), consumed only when a packet
## actually flies. No orders => no derive, no draws => the golden stream is untouched.

const REASON_UNKNOWN_HEX := "unknown_or_impassable_hex"


## Fraction of an inserting packet the air defences destroy.
##
##   airborne     = max_attrition_at_full_ad x effective_ad_health
##   air_assault  = the same, PLUS manpads_max_attrition x MANPADS threat fraction
##
## Linear in AD health by USER call (2026-07-24). Rotary-wing lift carries the second term because
## the MANPADS layer is deliberately outside the AD-health metric yet engages helicopters; reusing
## IjfsManpads.threat_fraction keeps the saturation curve in one place.
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
## on that chain OR merely touches it, so a formation fighting at the tip of a corridor is supplied.
## Pure: map access arrives as Callables; no autoload is touched.
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
			continue
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


## Extract the air-defence picture `resolve` wants from an IJFS phase summary. This is the sole home
## for which IJFS fields the air path reads, so turn resolution and observation cannot drift.
static func threat_from_ijfs_summary(ijfs_summary: Dictionary) -> Dictionary:
	var ad_health: Dictionary = ijfs_summary.get("taiwan_ad_health_after", {})
	var manpads: Dictionary = ijfs_summary.get("manpads", {})
	var ready_by_to: Dictionary = manpads.get("ready_systems_by_to", {})
	return {
		"ad_health": float(ad_health.get("effective_ad_health", 0.0)),
		"manpads_ready_systems": int(ready_by_to.get("total", 0)),
	}


## Resolve this turn's air insertions. Orders spend the shared per-class budget in issue order;
## threat is this turn's post-IJFS air-defence picture; hex_can_receive admits placed/passable drop
## zones, including enemy-held ground. Returns the report plus exact landed/lost manifests and a
## typed force request. Does NOT mutate `state`.
static func resolve(
	state: AirInsertionState,
	orders: Array,
	turn_number: int,
	threat: Dictionary,
	config: Dictionary,
	hex_can_receive: Callable,
	dice: Dice,
) -> Dictionary:
	var summary := AirInsertionSummary.new()
	var landings: Array = []
	if state == null:
		return {"summary": summary, "landings": landings}

	summary.caps_before = state.caps.duplicate()
	summary.caps_after = state.caps.duplicate()
	if orders.is_empty():
		_projected_finish(summary, state, {})
		return {"summary": summary, "landings": landings}

	if turn_number < state.first_turn:
		for order_value in orders:
			summary.rejected.append({
				"brigade_id": String((order_value as Dictionary)["brigade_id"]),
				"reason": AirInsertionSummary.REASON_BEFORE_FIRST_TURN,
			})
		_projected_finish(summary, state, {})
		return {"summary": summary, "landings": landings}

	var plan := AirInsertionResolutionPlan.new()
	plan.state = state
	plan.orders = orders
	plan.turn_number = turn_number
	plan.threat = threat
	plan.config = config
	plan.hex_can_receive = hex_can_receive
	plan.dice = dice
	plan.summary = summary
	plan.landings = landings
	plan.budget = state.caps.duplicate()
	plan.caps_after = state.caps.duplicate()
	_resolve_orders(plan)
	summary.caps_after = plan.caps_after.duplicate()
	_projected_finish(summary, state, plan.pool_sent)
	return {
		"summary": summary,
		"landings": landings,
		"force_request": ForceAirInsertionRequest.from_landings(turn_number, landings),
	}


static func _resolve_orders(plan: AirInsertionResolutionPlan) -> void:
	for order_value in plan.orders:
		_resolve_order(plan, order_value as Dictionary)


static func _resolve_order(plan: AirInsertionResolutionPlan, order: Dictionary) -> void:
	var brigade_id := String(order["brigade_id"])
	var target_hex := String(order["target_hex"])
	var entry := plan.state.entry_for(brigade_id)
	if entry.is_empty():
		_reject(plan.summary, brigade_id, AirInsertionSummary.REASON_POOL_EMPTY)
		return
	if not bool(plan.hex_can_receive.call(target_hex)):
		_reject(plan.summary, brigade_id, REASON_UNKNOWN_HEX)
		return
	var lift_class := String(entry["lift_class"])
	var remaining := int(plan.budget.get(lift_class, 0))
	if remaining <= 0:
		_reject(plan.summary, brigade_id, AirInsertionSummary.REASON_CAP_EXHAUSTED)
		return
	var manifest: Array = entry["bns"]
	var sent := mini(remaining, manifest.size())
	var rate := attrition_rate(
		lift_class, float(plan.threat.get("ad_health", 0.0)),
		int(plan.threat.get("manpads_ready_systems", 0)), plan.config)
	if plan.substream == null:
		plan.substream = plan.dice.derive("air_insertion:%d" % plan.turn_number)
	var packet := _roll_packet(manifest, sent, rate, plan.substream)
	var lost: Array = packet["lost"]
	packet["brigade_id"] = brigade_id
	packet["target_hex"] = target_hex
	packet["lift_class"] = lift_class
	packet["rate"] = rate
	plan.budget[lift_class] = remaining - sent
	plan.caps_after[lift_class] = maxi(0, int(plan.caps_after[lift_class]) - lost.size())
	plan.pool_sent[brigade_id] = sent
	_append_drop(plan, packet)


static func _roll_packet(manifest: Array, sent: int, rate: float, dice: Dice) -> Dictionary:
	var landed: Array = []
	var lost: Array = []
	for index in range(sent):
		var battalion: Dictionary = manifest[index]
		if dice.randf() < rate:
			lost.append(battalion.duplicate())
		else:
			landed.append(battalion.duplicate())
	return {"landed": landed, "lost": lost}


static func _append_drop(plan: AirInsertionResolutionPlan, packet: Dictionary) -> void:
	var brigade_id := String(packet["brigade_id"])
	var target_hex := String(packet["target_hex"])
	var lift_class := String(packet["lift_class"])
	var rate := float(packet["rate"])
	var landed: Array = packet["landed"]
	var lost: Array = packet["lost"]
	var first := not landed.is_empty() and not plan.state.landed.has(brigade_id)
	plan.summary.drops.append({
		"brigade_id": brigade_id, "lift_class": lift_class, "hex_id": target_hex,
		"sent": landed.size() + lost.size(), "landed": landed.size(), "lost": lost.size(),
		"attrition_rate": rate, "first_landing": first,
	})
	plan.landings.append({
		"brigade_id": brigade_id, "hex_id": target_hex, "first_landing": first,
		"landed_bns": landed, "lost_bns": lost,
	})
	plan.summary.battalions_landed += landed.size()
	plan.summary.battalions_lost += lost.size()
	plan.summary.attrition_by_class[lift_class] = rate


static func _reject(summary: AirInsertionSummary, brigade_id: String, reason: String) -> void:
	summary.rejected.append({"brigade_id": brigade_id, "reason": reason})


## Compute projected pending counts without mutating state.
static func _projected_finish(summary: AirInsertionSummary, state: AirInsertionState, pool_sent: Dictionary) -> void:
	var projected_pool_size := 0
	var non_empty_count := 0
	for entry_value in state.pool:
		var entry: Dictionary = entry_value
		var entry_size := (entry["bns"] as Array).size()
		var brigade_id := String(entry["brigade_id"])
		var sent := int(pool_sent.get(brigade_id, 0))
		var remaining := entry_size - sent
		if remaining > 0:
			non_empty_count += 1
		projected_pool_size += remaining
	summary.pending_brigades = non_empty_count
	summary.pending_battalions = projected_pool_size
