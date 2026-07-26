class_name RosterMutations
extends RefCounted

## The roster-shrinking seam (plan 0038). Every path that KILLS a battalion — ground combat,
## drowning in the crossing, being shot down on the way in — goes through `apply_casualty` here, so
## a dead battalion stops existing everywhere (census, combat strength, offload) rather than only in
## the pool it happened to be sitting in. Two bug families have lived on this seam (the ghost-landing
## census bug, and its mirror image the roster/pool desync), which is why the tripwire that guards it
## lives beside it.
##
## Static and GameData-only: no GameStateData is needed except by the tripwire, and no phase module
## owns it — combat (TurnConductor), the crossing (FiresPhases) and air insertion
## (ReinforcementPhases) all call in. Extracting it is what keeps those modules a DAG rather than a
## reference cycle. Consumes no dice, so the golden RNG stream is unaffected.


static func apply_casualty(casualty: Dictionary) -> void:
	var brigade_id := String(casualty["brigade_id"])
	var casualty_type := String(casualty["type"])
	var brigade: Brigade = GameData.get_brigade(brigade_id)
	if brigade == null:
		push_error("Combat casualty references unknown brigade_id: %s" % brigade_id)
		return

	for index in range(brigade.composition.size()):
		var battalion: Battalion = brigade.composition[index]
		if battalion.type != casualty_type:
			continue
		battalion.qty -= 1
		if battalion.qty <= 0:
			brigade.composition.remove_at(index)
		if brigade.get_battalion_count() == 0:
			brigade.destroyed = true
			GameData.remove_brigade_from_map(brigade_id)
		return

	push_error("Combat casualty references missing battalion type '%s' in brigade %s" % [casualty_type, brigade_id])


## Delete drowned crossing BNs from their brigade rosters so a dead battalion stops existing
## everywhere (census, combat strength, offload) — not just in ship_reserve. Maps each drowned id
## back to (brigade_id, battalion type) via the PRE-removal reserve entries, then applies one
## roster casualty per drowned BN through the shared apply_casualty (consumes no dice → golden RNG
## stream unaffected). See the call site in FiresPhases.resolve_antiship_turn for why the
## ghost-landing mattered.
static func apply_crossing_casualties(ship_reserve: Array, lost_ids: Array) -> void:
	if lost_ids.is_empty():
		return
	var lost: Dictionary = {}
	for id in lost_ids:
		lost[String(id)] = true
	for entry_value in ship_reserve:
		var entry: Dictionary = entry_value
		var brigade_id := String(entry.get("brigade_id", ""))
		for bn_value in entry.get("bns", []):
			var bn: Dictionary = bn_value
			if lost.has(String(bn.get("id", ""))):
				apply_casualty({"brigade_id": brigade_id, "type": String(bn.get("type", ""))})


## Tripwire for the mirror image of the ghost-landing bug (plan 0037): a brigade's roster must never
## hold FEWER battalions of a type than its off-map pools claim are waiting. If it does, something
## killed a battalion that was not ashore — apply_casualty shrinks `composition` by type and never
## touches the pools, so the pool entry would survive as a claim on a roster slot that no longer
## exists, and the census would silently under-count for the rest of the game.
##
## Checked at the END of resolve_turn, not inside apply_casualty, because the invariant is
## transiently false BY DESIGN mid-turn: apply_crossing_casualties deletes drowned battalions from
## their rosters while they are still listed in ship_reserve (it maps ids via the pre-removal
## entries), and the reserve is pruned immediately afterwards. End-of-turn is the settled boundary,
## the same reasoning as the runtime-index assert beside it.
static func pending_pool_roster_violations(state: GameStateData) -> Array[String]:
	var violations: Array[String] = []
	var not_ashore := state.refresh_not_ashore_by_type()
	for brigade_id_value in not_ashore:
		var brigade_id := String(brigade_id_value)
		var brigade: Brigade = GameData.get_brigade(brigade_id)
		if brigade == null:
			continue  # JLSF pseudo-entries carry a cargo brigade_id with no OOB brigade behind it
		var qty_by_type: Dictionary = {}
		for battalion_value in brigade.composition:
			var battalion: Battalion = battalion_value
			qty_by_type[battalion.type] = int(qty_by_type.get(battalion.type, 0)) + battalion.qty
		var brigade_not_ashore: Dictionary = not_ashore[brigade_id]
		for battalion_type in brigade_not_ashore:
			var pending := int(brigade_not_ashore[battalion_type])
			var roster := int(qty_by_type.get(battalion_type, 0))
			if roster < pending:
				violations.append("%s/%s: roster %d < pending %d" % [
					brigade_id, battalion_type, roster, pending])
	return violations
