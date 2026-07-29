class_name FiresPhases
extends RefCounted

## The fires phases of the WeGo turn (plan 0038 step 2): Red's IJFS joint/air-missile fires and
## Green's coastal anti-ship + mine defence of the crossing. They are one group because they share
## the anti-ship firing systems — IJFS suppresses and destroys the very launchers the anti-ship
## phase then fires — and because both draw from their OWN dice substream, which is what keeps the
## ground-combat golden invariant byte-stable.
##
## `TurnConductor` keeps the ORDERING (the when); this module only owns the how. Same contract as
## every other resolver: static, first argument `state: GameStateData` mutated in place, reads the
## GameData content autoload but never the GameState autoload singleton. The crossing's roster
## casualties go through `ForceTransitions`, and the fleet reprojection through
## `ReinforcementPhases.project_sealift_onto_fleet` — the sealift state is that module's to own.


static func resolve_ijfs_turn(state: GameStateData, dice: Dice) -> Dictionary:
	assert(dice != null, "resolve_ijfs_turn requires a Dice instance")
	if state.ijfs_state == null:
		rebuild_ijfs_state(state)
	var outcome := IjfsResolver.resolve(state.ijfs_state, GameData.brigades, state.turn_number, state._ijfs_day, dice)
	state._ijfs_day = state.turn_number
	var ledgers: Dictionary = outcome["ledgers"]
	state.last_ijfs_summary = ledgers["summary"]
	state.last_ijfs_writeback = outcome["writeback"]
	EventBus.ijfs_resolved.emit(state.last_ijfs_summary)
	return ledgers


## Scenario reset of the Green anti-ship arsenal, for GameState's reset_to_scenario. Thin pass-through
## to the establishment's authority, in the same style as rebuild_ijfs_state below — GameState reaches
## the fires phases' state through this module, never around it.
static func reset_antiship_establishment(state: GameStateData) -> void:
	AntishipTransitions.reset_establishment(state)


static func rebuild_ijfs_state(state: GameStateData) -> void:
	# Anti-ship systems must exist first (their containers seed the per-(TO,type) IJFS targets).
	AntishipTransitions.ensure_establishment(state)
	state.ijfs_state = GameStateBuilder.build_ijfs_state(
		state.antiship_containers, GameData.brigades, GameData.mobilization_holdback)
	state._ijfs_day = 0


static func update_maneuver_posture(state: GameStateData) -> void:
	IjfsResolver.update_maneuver_posture(state.ijfs_state, GameData.brigades)


static func sync_maneuver_targets_to_oob(state: GameStateData) -> void:
	IjfsResolver.sync_maneuver_targets_to_oob(state.ijfs_state, GameData.brigades)


static func apply_ijfs_maneuver_casualties(state: GameStateData) -> void:
	var casualties: Array = state.last_ijfs_writeback.maneuver_casualties if state.last_ijfs_writeback != null else []
	for casualty_value in casualties:
		var casualty: Dictionary = casualty_value
		ForceTransitions.apply_battalion_casualties(
			GameData, ForceTransitions.ijfs_casualty_request(casualty))


## D3-D: Green coastal anti-ship fires + mine warfare against the Red amphibious crossing. Threads the
## firing plan (D3-B2) -> crossing (D3-B3) -> mines (D3-C); ship losses convert to BNs lost at sea
## (ShipLoadingModel) and feed register_ship_losses (the D0-C seam offload consumes). Runs after IJFS
## (Green systems suppressed/destroyed first) and before offload (only survivors land). Draws from an
## INDEPENDENT substream so the ground-combat golden invariant stays byte-stable.
static func resolve_antiship_turn(state: GameStateData, dice: Dice) -> Dictionary:
	AntishipTransitions.ensure_establishment(state)
	state.last_antiship_summary = null
	# The IJFS has already fired this turn; book its cumulative kills and this cycle's suppression
	# onto the establishment BEFORE the firing plan reads it. Only the authority writes those rows —
	# the resolver below reads the result and reports what its own attrition destroyed (plan 0043).
	AntishipTransitions.apply_ijfs_effects(state.antiship_systems, state.last_ijfs_writeback)

	# Independent substream (same isolation pattern as resolve_ijfs_turn). SeededDice.derive is a
	# pure hash of (seed, label) — it consumes no parent-stream state, so deriving before the
	# resolver's no-wave check cannot shift the base combat stream.
	var as_dice: Dice
	if dice is SeededDice:
		as_dice = dice.derive("antiship:%d" % state.turn_number)
	else:
		as_dice = SeededDice.new(hash("antiship:%d" % state.turn_number))

	# Only the BNs sailing this turn (the sealift "sent" cohorts) cross and take attrition; offloading
	# BNs are safe ashore. Slice that crossing wave out of the full reserve (plan 0004 D3).
	var crossing_reserve := crossing_reserve_from_sent_cohorts(state)
	# Captured pre-resolve: drain/flip below mutate the cohorts before the summary is stored.
	var wave_bns: int = SealiftResolver.sent_cohort_bn_ids(state.sealift_state).size()

	var context := AntishipResolutionContext.new()
	context.crossing_reserve = crossing_reserve
	context.antiship_systems = state.antiship_systems
	context.sent_by_type = state.last_sealift_sent_by_type
	context.ship_defs = GameData.ship_defs
	context.beach_to_to = GameData.beach_to_to
	context.active_tos = GameData.active_tos
	context.to_adjacency = GameData.to_adjacency
	context.lost_at_sea_accumulator = state.lost_at_sea_accumulator
	context.escort_sam = state.sealift_state.escort_sam
	var outcome := AntishipResolver.resolve(state.turn_number, context, as_dice)
	if outcome["summary"] == null:
		# Nothing crossed this turn: no fires, no state to apply (pending_lost_at_sea keeps its value).
		return {}

	var lost_ids: Array = outcome["lost_ids"]
	# Drowned crossers are dead: the force authority removes them from reserve + cohorts AND their
	# brigade rosters in one preflighted all-or-nothing transaction. If the preflight fails, nothing
	# changes — no ghost-landing mirror bug.
	var crossing_casualties := ForceTransitions.apply_crossing_loss(
		GameData, state.sealift_state, state.ship_reserve,
		ForceTransitions.crossing_casualty_request(
			lost_ids, state.ship_reserve, state.sealift_state))
	if not crossing_casualties.success:
		return {}

	# Book what the crossing's launch attrition destroyed. The resolver only reported it.
	AntishipTransitions.apply_launch_attrition(state, outcome["launch_outcomes"])
	state.lost_at_sea_accumulator = float(outcome["accumulator"])
	# Apply hull losses to the sealift cohorts (carriers) + the fleet; free hulls from cohorts whose
	# BNs all drowned; flip survivors to offloading.
	apply_crossing_hull_losses(state, outcome["destroyed_by_type"])
	ForceTransitions.free_emptied_cohorts(state.sealift_state, GameData.amphibious_return_time_turns)
	ForceTransitions.apply_sent_to_offloading(state.sealift_state)
	# Deplete the escort SAM magazines by what fired, and divert any type that dropped to/below its
	# reload threshold (plan 0004 D5). No-op when the magazine is unmodelled (escort_sam empty).
	SealiftResolver.apply_escort_consumption(
		state.sealift_state, outcome["escort_sam_consumed"], GameData.escort_reload_time_turns)
	ReinforcementPhases.project_sealift_onto_fleet(state)
	register_ship_losses(state, int(outcome["bn_equiv_lost"]))
	state.last_antiship_summary = outcome["summary"]
	state.last_antiship_summary.wave_bns = wave_bns
	EventBus.antiship_resolved.emit(state.last_antiship_summary.to_dict())
	return state.last_antiship_summary.to_dict()


## The subset of ship_reserve whose BNs are bound to a "sent" cohort (crossing this turn), with each
## kept entry trimmed to just those BNs. Empty when nothing sails.
static func crossing_reserve_from_sent_cohorts(state: GameStateData) -> Array:
	var sailing := SealiftResolver.sent_cohort_bn_ids(state.sealift_state)
	if sailing.is_empty():
		return []
	var crossing: Array = []
	for entry_value in state.ship_reserve:
		var entry: Dictionary = entry_value
		var bns: Array = []
		for bn in entry.get("bns", []):
			if sailing.has(String((bn as Dictionary).get("id", ""))):
				bns.append(bn)
		if bns.is_empty():
			continue
		var trimmed: Dictionary = entry.duplicate(true)
		trimmed["bns"] = bns
		crossing.append(trimmed)
	return crossing


## Apply crossing/mine hull losses: carrier losses come out of the "sent" cohorts, escort/screen
## losses out of the ready pool — both booked as destroyed on the fleet. The ShipState bins are then
## reprojected from the sealift state by the caller (plan 0004 D3).
static func apply_crossing_hull_losses(state: GameStateData, destroyed_by_type: Dictionary) -> void:
	for ship_type_value in destroyed_by_type.keys():
		var ship_type := String(ship_type_value)
		var requested := int(destroyed_by_type[ship_type_value])
		if requested <= 0:
			continue
		var ship_state: ShipState = state.fleet.get(ship_type, null)
		if ship_state == null:
			continue
		# Carriers (capacity > 0) lose hulls out of their cohorts; escorts out of the ready screen.
		var ship_def: ShipDef = GameData.ship_defs_by_name.get(ship_type, null)
		var applied: int
		if ship_def != null and ship_def.is_carrier():
			applied = SealiftResolver.remove_carrier_hulls(state.sealift_state, ship_type, requested)
		else:
			applied = mini(requested, ship_state.fleet_surviving_total)
		ship_state.destroyed += applied
		ship_state.fleet_surviving_total -= applied


static func register_ship_losses(state: GameStateData, bn_equiv_lost: int) -> void:
	state.pending_lost_at_sea = maxi(0, bn_equiv_lost)

