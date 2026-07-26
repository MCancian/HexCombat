class_name TurnConductor
extends RefCounted

## Static turn orchestration for HexCombat's WeGo resolution (plan 0014 P3). Every public method
## takes `state: GameStateData` as its first argument, mutates it in place, and returns the same
## typed value the pre-refactor GameState method returned. Reading the GameData content autoload
## (map/OOB/scenario content) is allowed — it is the universal read-only content source, not
## runtime state — but this class NEVER takes the GameState autoload singleton as a parameter,
## which is what makes it unit-testable against a GameStateData built from scratch. GameState.gd's
## resolve_* methods are now one-line delegating wrappers to these.
##
## Plan 0038: the "force arrives" phases (sealift, offload, ROC mobilization, air insertion) live in
## `ReinforcementPhases` and the roster-shrinking seam in `RosterMutations`. `resolve_turn` below
## still holds the full ordered call list — the modules own the HOW of a phase, never the WHEN.

const FEBA_RETREAT_THRESHOLD_KM := 10.0



static func resolve_turn(state: GameStateData, dice: Dice = null) -> void:
	if state.phase != GameStateData.Phase.PLANNING:
		push_error("Cannot resolve turn outside PLANNING phase")
		return

	if dice == null:
		dice = SeededDice.new(state.turn_number)

	state.phase = GameStateData.Phase.RESOLUTION
	EventBus.phase_changed.emit(state.phase)
	# Sea phase ordering (D3-D): IJFS (Red joint fires) suppresses/destroys Green anti-ship systems
	# first; then Green anti-ship + mines attrit the Red crossing (removing BNs from the reserve);
	# then offload lands only the survivors. Each draws from its own INDEPENDENT substream (never the
	# combat dice), so the ground-combat golden invariant stays byte-stable.
	FiresPhases.resolve_ijfs_turn(state, dice)
	# D4-H (2d): IJFS maneuver kills reduce the ground OOB before combat. Deterministic (reads the
	# writeback the warmup just produced; no dice), so the combat golden stays reproducible.
	FiresPhases.apply_ijfs_maneuver_casualties(state)
	# Sealift (plan 0004): tick the ship return/reload pipeline and embark this turn's wave (first
	# echelon adopted, follow-on echelons loaded onto ready amphibious lift) BEFORE the crossing, so
	# the anti-ship phase attrits exactly the hulls that sail. Dice-free -> combat golden unaffected.
	ReinforcementPhases.resolve_sealift_turn(state)
	FiresPhases.resolve_antiship_turn(state, dice)
	state.last_offload_summary = ReinforcementPhases.resolve_offload_turn(state, dice)
	# ROC mobilization (plan 0029 Tier A2): Green's reinforcement step sits at the same seam as
	# Red's (offload) and before movement, so arrivals are on the map for this turn's combat but only
	# take orders next planning phase. Dice-free -> the golden stream is untouched.
	state.last_mobilization_summary = ReinforcementPhases.resolve_mobilization_turn(state)
	# Air insertion (plan 0032): Red's OTHER reinforcement path sits at the same seam as its sea
	# one and Green's mobilization, and — critically — AFTER the IJFS phase, because the attrition
	# a drop takes is read off the air-defence picture those fires just produced. Landing before
	# movement means a drop onto Green ground is contested and fought in the SAME turn, which is
	# how an opposed insertion is paid for. Its own dice substream; no orders => no draws.
	state.last_air_insertion_summary = ReinforcementPhases.resolve_air_insertion_turn(state, dice)

	# disable_phases (plan 0012): a scenario/override can skip the ground WeGo phases wholesale so
	# calibration sweeps run standard games while isolating the sea/IJFS phases. Buffered orders
	# simply never execute; skipping consumes no dice, so an empty list is byte-identical.
	var skip_movement := GameData.disabled_phases.has("movement")
	var skip_ground_combat := GameData.disabled_phases.has("ground_combat")
	if not skip_movement:
		apply_move_orders(state, Brigade.Team.RED)
		apply_move_orders(state, Brigade.Team.GREEN)
	if skip_ground_combat:
		state.last_contested_hexes.clear()
	else:
		state.last_contested_hexes = find_contested_hexes()
	# Supply corridors are fixed for the whole combat loop (ownership is only recomputed after it),
	# so the air-landing isolation flood runs once here rather than once per contested hex.
	state.isolated_air_landed_brigades = ReinforcementPhases.isolated_air_landed_brigades(state)
	# Who is actually ashore is likewise fixed for the combat loop: every arrival phase (offload,
	# mobilization, air insertion) has already run this turn and the pools do not change again until
	# next turn's sealift. Computing it ONCE means two hexes cannot disagree about who is present
	# (plan 0037).
	state.refresh_not_ashore_by_type()
	var combat_summaries: Array[CombatSummary] = []
	# Per-hex combat substream (plan 0010): each contested hex draws from its OWN dice stream derived
	# from the root turn seed, so a design tweak that changes the roll count in one hex's fight never
	# scrambles the dice of an unrelated hex. Turn-scoped salt matches the ijfs/antiship pattern so an
	# injected constant-seed dice still varies per turn.
	for hex_id in state.last_contested_hexes:
		var summary := resolve_combat_at(state, hex_id, dice.derive("combat:%d:%s" % [state.turn_number, hex_id]))
		if summary != null:
			combat_summaries.append(summary)
	if not skip_ground_combat:
		apply_feba_retreats(state)
	GameData.recompute_hex_ownership()
	for summary in combat_summaries:
		summary.owner_after = String(GameData.hex_states[summary.hex_id].owner)
	state.last_combat_summaries = combat_summaries.duplicate()
	resolve_supply_turn(state)
	resolve_cleanup_phase(state)

	# Debug-only invariant (refactor item 4): at the settled end of a turn the brigade↔hex indexes
	# must be consistent. Gated on OS.is_debug_build() so the validator is never called in release;
	# in debug/test/headless runs it fails loud on any silent index desync. End-of-turn only (a settled
	# boundary) — NOT the per-mutator hot path, which can hold benign transient desync mid-resolution.
	if OS.is_debug_build():
		var index_violations := GameData.validate_runtime_indexes()
		assert(index_violations.is_empty(), "runtime index desync at end of resolve_turn: %s" % "; ".join(index_violations))
		var roster_violations := RosterMutations.pending_pool_roster_violations(state)
		assert(roster_violations.is_empty(), "roster/pool desync at end of resolve_turn: %s" % "; ".join(roster_violations))

	state.phase = GameStateData.Phase.END
	EventBus.phase_changed.emit(state.phase)
	EventBus.combat_resolved.emit(combat_summaries)
	EventBus.turn_resolved.emit(state.turn_number)


static func resolve_supply_turn(state: GameStateData) -> Dictionary:
	assert(state.supply_state != null, "resolve_supply_turn requires supply_state")
	var units := active_red_battalion_units(state)
	var moved_ids: Array[String] = []
	var engaged_ids: Array[String] = []
	for brigade_value in GameData.brigades.values():
		var brigade: Brigade = brigade_value
		if brigade.team != Brigade.Team.RED or brigade.destroyed or brigade.hex_id.is_empty():
			continue
		if brigade.moved_this_turn:
			moved_ids.append(brigade.id)
		if brigade.fought_this_turn:
			engaged_ids.append(brigade.id)

	var summary := SupplyResolver.resolve(state.supply_state, units, moved_ids, engaged_ids, state.turn_number)
	EventBus.supply_updated.emit(summary)
	return summary


# --- D5-C Cleanup phase — end-of-turn per-system flag reset ------------------------------------

static func resolve_cleanup_phase(state: GameStateData) -> Dictionary:
	GameData.recompute_hex_ownership()
	# Pure work (flag reset, victory census + verdict, activity latch) lives in CleanupResolver;
	# consumes no dice, so the golden RNG stream is unaffected.
	var outcome := CleanupResolver.resolve(
		state.antiship_systems, GameData.brigades, state.pending_battalion_pools(),
		GameData.victory_config, state.turn_number, state._china_has_landed)
	state._china_has_landed = bool(outcome["china_has_landed"])
	state.last_cleanup_summary = outcome["summary"]
	state.game_over = state.last_cleanup_summary.game_over
	state.winner = state.last_cleanup_summary.winner
	EventBus.cleanup_resolved.emit(state.last_cleanup_summary.to_dict())
	return state.last_cleanup_summary.to_dict()


static func taiwan_battalion_census(state: GameStateData) -> Dictionary:
	return CleanupResolver.census(
		GameData.brigades, state.pending_battalion_pools(), GameData.victory_config)


# --- D5-A Frontline phase — redistribute Red brigades along a drawn polyline -------------------

static func frontline_hex_centers() -> Array:
	var centers: Array = []
	for hex_value in GameData.hexes:
		var hex: Hex = hex_value
		centers.append({"id": hex.id, "lat": hex.center.x, "lon": hex.center.y})
	return centers


static func resolve_frontline_phase(state: GameStateData, polyline_coords: Array) -> Dictionary:
	# Only the drawing side's brigades reshuffle along the line — RED here (the amphibious attacker),
	# mirroring TIV front_line_service's single-side filter. Intentional asymmetry, not a bug; if Green
	# ever draws front lines, pass its brigades instead.
	var candidate_brigades: Array = []
	for brigade_value in GameData.brigades.values():
		var brigade: Brigade = brigade_value
		if brigade.team == Brigade.Team.RED and not brigade.destroyed:
			candidate_brigades.append(brigade)

	state.last_frontline_summary = FrontlineResolver.resolve(polyline_coords, frontline_hex_centers(), candidate_brigades)
	for brigade_id in state.last_frontline_summary.moves.keys():
		GameData.set_brigade_hex(String(brigade_id), String(state.last_frontline_summary.moves[brigade_id]))
	EventBus.frontline_resolved.emit(state.last_frontline_summary.to_dict())
	return state.last_frontline_summary.to_dict()


## Red battalions drawing Taiwan-theater supply. Only battalions ASHORE eat (plan 0037, USER call
## 2026-07-25): one still at sea, on the mainland, or waiting to fly is not being supplied across the
## strait by this pool. Same not-ashore definition combat uses, so a brigade's fighting strength and
## its ration bill always describe the same battalions.
static func active_red_battalion_units(state: GameStateData) -> Array:
	var units: Array = []
	# A FRESH recompute, not the combat loop's cached map: the supply phase runs after combat, and a
	# future phase order could drain a pool in between. Pools are unchanged today, so this is the same
	# value line 70 computed — but the bill must not depend on that staying true.
	var not_ashore := state.refresh_not_ashore_by_type()
	for brigade_value in GameData.brigades.values():
		var brigade: Brigade = brigade_value
		if brigade.team != Brigade.Team.RED or brigade.destroyed or brigade.hex_id.is_empty():
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


static func apply_move_orders(state: GameStateData, team: Brigade.Team) -> void:
	for order in state.orders[team]:
		var move_order: MoveOrder = order
		var brigade: Brigade = GameData.get_brigade(move_order.brigade_id)
		GameData.set_brigade_hex(move_order.brigade_id, move_order.target_hex)
		brigade.moved_this_turn = true
		if move_order.mode == Movement.MODE_ADMINISTRATIVE:
			brigade.adjust_organization(-Brigade.ADMIN_MOVE_ORG_COST)
			brigade.moved_admin_this_turn = true
		else:
			brigade.adjust_organization(-Brigade.TACTICAL_MOVE_ORG_COST)


static func find_contested_hexes() -> Array[String]:
	var contested: Array[String] = []
	for hex_id in GameData.hex_lookup.keys():
		var has_red := false
		var has_green := false
		for brigade_id in GameData.get_brigades_in_hex(String(hex_id)):
			var brigade: Brigade = GameData.get_brigade(String(brigade_id))
			if brigade == null or brigade.destroyed:
				continue
			match brigade.team:
				Brigade.Team.RED:
					has_red = true
				Brigade.Team.GREEN:
					has_green = true
			if has_red and has_green:
				contested.append(String(hex_id))
				break
	return contested


# Defender combat modifier for hex_id: terrain.defender_modifier (1.0 if the hex has no terrain
# classification) times a situational multiplier, currently always 1.0. The `* 1.0` is a
# deliberate seam — a future situational modifier (e.g. a first-landing beach-assault penalty on
# the defender, see BACKLOG) multiplies in here without touching CombatResolver or GameData.
static func defender_combat_modifier(hex_id: String) -> float:
	var terrain := GameData.get_terrain(hex_id)
	var terrain_modifier: float = terrain.defender_modifier if terrain != null else 1.0
	return terrain_modifier * 1.0


# Delegating wrapper (test-called surface) — pure logic lives in CombatResolver.
static func inject_supply_effectiveness(state: GameStateData, units: Array, team: int) -> void:
	var pool: float = state.supply_state.current_dos_tons if state.supply_state != null else 1.0
	CombatResolver.inject_supply_effectiveness(units, team, pool, GameData.red_out_of_supply_effectiveness)


# Thin wrapper: gathers contributors (board/commitment state), delegates the dice-consuming combat
# core to CombatResolver.resolve_at, then applies the result — casualties, FEBA accumulation,
# fought flags — and stamps owner_after. Application stays here because combat at one hex mutates
# state the next hex's contributor gathering reads (ported interleaving semantics).
static func resolve_combat_at(state: GameStateData, hex_id: String, dice: Dice) -> CombatSummary:
	var attacker_brigades := combat_contributors_for(state, Brigade.Team.RED, hex_id)
	var defender_brigades := combat_contributors_for(state, Brigade.Team.GREEN, hex_id)
	var pool: float = state.supply_state.current_dos_tons if state.supply_state != null else 1.0
	# Terrain resolves at hex_id (the defended/contested hex), not the attacker's origin — the
	# defender_modifier models fortification/cover of the ground being held, which belongs to the
	# hex under attack regardless of which side started there.
	var rules := CombatRules.new()
	rules.feba_base_km = GameData.feba_base_km
	rules.red_supply_pool = pool
	rules.red_out_of_supply_effectiveness = GameData.red_out_of_supply_effectiveness
	rules.isolated_red_brigade_ids = state.isolated_air_landed_brigades
	rules.not_ashore_by_type = state.not_ashore_by_type
	rules.unscreened_support_strength = GameData.unscreened_support_strength
	rules.maneuver_casualty_weight = GameData.maneuver_casualty_weight
	rules.support_casualty_weight = GameData.support_casualty_weight
	rules.defender_terrain_modifier = defender_combat_modifier(hex_id)
	rules.support_multipliers = GameData.support_multipliers
	rules.combat_base_loss_rate = GameData.combat_base_loss_rate
	rules.combat_attacker_ratio_slope = GameData.combat_attacker_ratio_slope
	rules.combat_defender_ratio_slope = GameData.combat_defender_ratio_slope
	rules.combat_loss_roll_midpoint = GameData.combat_loss_roll_midpoint
	rules.combat_loss_roll_scale = GameData.combat_loss_roll_scale
	rules.combat_min_loss_rate = GameData.combat_min_loss_rate
	rules.combat_max_attacker_loss_rate = GameData.combat_max_attacker_loss_rate
	rules.combat_max_defender_loss_rate = GameData.combat_max_defender_loss_rate
	rules.feba_balance_gain = GameData.feba_balance_gain
	rules.feba_balance_clamp = GameData.feba_balance_clamp
	rules.feba_roll_factor_min = GameData.feba_roll_factor_min
	rules.feba_roll_factor_span = GameData.feba_roll_factor_span
	rules.combat_min_effective_strength = GameData.combat_min_effective_strength
	rules.combat_attacker_advantage_ratio = GameData.combat_attacker_advantage_ratio
	rules.combat_defender_advantage_ratio = GameData.combat_defender_advantage_ratio
	rules.default_combat_strength = GameData.default_combat_strength

	var outcome := CombatResolver.resolve_at(
		hex_id,
		attacker_brigades,
		defender_brigades,
		dice,
		rules
	)
	if outcome["summary"] == null:
		return null

	var result: CombatResult = outcome["result"]
	for casualty in result.attacker_casualties:
		RosterMutations.apply_casualty(casualty)
	for casualty in result.defender_casualties:
		RosterMutations.apply_casualty(casualty)

	GameData.hex_states[hex_id].feba_km = GameData.hex_states[hex_id].feba_km + result.feba_movement_km
	for brigade_value in attacker_brigades + defender_brigades:
		var fought_brigade: Brigade = brigade_value
		fought_brigade.fought_this_turn = true

	var summary: CombatSummary = outcome["summary"]
	summary.owner_after = String(GameData.hex_states[hex_id].owner)
	return summary


## Brigades of `team` that actually fight at `hex_id`.
##
## A brigade with NO battalions ashore is excluded (plan 0037). It is not merely a contributor worth
## zero: CombatCalculator floors a zero-strength side to combat_min_effective_strength, so leaving it
## in would have it fight — and inflict real casualties — with its whole composition still at sea.
## It keeps its hex_id and still holds ground for ownership; it just brings nobody to the battle.
static func combat_contributors_for(state: GameStateData, team: Brigade.Team, hex_id: String) -> Array:
	var contributors: Array = []
	var seen := {}
	var not_ashore := state.not_ashore_by_type
	for brigade_id_value in GameData.get_brigades_in_hex(hex_id):
		var brigade: Brigade = GameData.get_brigade(String(brigade_id_value))
		if brigade == null or brigade.destroyed or brigade.moved_admin_this_turn or brigade.team != team:
			continue
		if brigade.landed_battalion_count(not_ashore.get(brigade.id, {})) <= 0:
			continue
		contributors.append(brigade)
		seen[brigade.id] = true

	for commitment_value in state.commitments[team]:
		var commitment: CommitOrder = commitment_value
		if commitment.target_hex != hex_id:
			continue
		var brigade: Brigade = GameData.get_brigade(commitment.brigade_id)
		if brigade == null or brigade.destroyed or brigade.moved_admin_this_turn or brigade.team != team:
			continue
		if brigade.id in seen:
			continue
		if brigade.landed_battalion_count(not_ashore.get(brigade.id, {})) <= 0:
			continue
		contributors.append(brigade)
		seen[brigade.id] = true
	return contributors


static func apply_feba_retreats(state: GameStateData) -> void:
	for hex_id in state.last_contested_hexes:
		var feba: float = GameData.hex_states[hex_id].feba_km
		if absf(feba) < FEBA_RETREAT_THRESHOLD_KM:
			continue

		var retreating_team := Brigade.Team.RED
		if feba > 0.0:
			retreating_team = Brigade.Team.GREEN

		var retreaters: Array[Brigade] = []
		for brigade_id_value in GameData.get_brigades_in_hex(hex_id):
			var brigade: Brigade = GameData.get_brigade(String(brigade_id_value))
			if brigade != null and not brigade.destroyed and brigade.team == retreating_team:
				retreaters.append(brigade)
		if retreaters.is_empty():
			continue

		var target := find_retreat_hex(hex_id, retreating_team)
		if target == "":
			continue

		for brigade in retreaters:
			GameData.set_brigade_hex(brigade.id, target)
		GameData.hex_states[hex_id].feba_km = 0.0


static func find_retreat_hex(from_hex: String, team: Brigade.Team) -> String:
	var friendly_owner := HexOwner.RED
	var enemy_team := Brigade.Team.GREEN
	if team == Brigade.Team.GREEN:
		friendly_owner = HexOwner.GREEN
		enemy_team = Brigade.Team.RED

	for neighbor_id_value in GameData.get_neighbors(from_hex):
		var neighbor_id := String(neighbor_id_value)
		var neighbor_terrain := GameData.get_terrain(neighbor_id)
		if neighbor_terrain != null and neighbor_terrain.impassable:
			continue

		var has_enemy := false
		for brigade_id_value in GameData.get_brigades_in_hex(neighbor_id):
			var brigade: Brigade = GameData.get_brigade(String(brigade_id_value))
			if brigade != null and not brigade.destroyed and brigade.team == enemy_team:
				has_enemy = true
				break
		if has_enemy:
			continue

		var owner := String(GameData.hex_states[neighbor_id].owner)
		if owner == friendly_owner or owner == HexOwner.NONE:
			return neighbor_id
	return ""
