extends Node
class_name GameStateType

const MoveOrderResource = preload("res://scripts/model/MoveOrder.gd")
const CommitOrderResource = preload("res://scripts/model/CommitOrder.gd")
const FEBA_RETREAT_THRESHOLD_KM := 10.0

# IJFS (D4) data-source paths live on IjfsStateBuilder (their only consumer).

# D3/D4 data paths + phase knobs live on their resolvers (AntishipResolver, IjfsResolver,
# AntishipSystemsBuilder, IjfsStateBuilder) — each const sits with its only consumer.

enum Phase { PLANNING, RESOLUTION, END }

var turn_number: int = 1
var phase: Phase = Phase.PLANNING
var turn_length_days: int = 1
var orders: Dictionary = {}  # Brigade.Team -> Array[MoveOrder]
var commitments: Dictionary = {}  # Brigade.Team -> Array[CommitOrder]
var ship_reserve: Array = []  # OffloadCalculator-ready: [{brigade_id, locked_beach, beach_hex, offset_bearing, bns:[{id,type}]}]
var fleet: Dictionary = {}  # ship name (String) -> ShipState
# Cross-turn sealift state (plan 0004): mainland follow-on pool, in-transit cohorts, ship
# return/reload pipeline, escort SAM magazine. Built at scenario load, advanced by SealiftResolver
# each turn before the crossing. Null only before the first reset_to_scenario.
var sealift_state: SealiftState = null
var infrastructure_state: InfrastructureState = null
var jlsf_orders: Array[String] = []  # port/airbridge ids with a pending explicit deploy_jlsf order
var pending_lost_at_sea: int = 0
var supply_state: SupplyState
var last_contested_hexes: Array[String] = []
var last_combat_summaries: Array[CombatSummary] = []
# IJFS daily state persists across turns (carry_to_next_day advances it each turn).
var ijfs_state: IjfsDailyState = null
var _ijfs_day: int = 0
var last_ijfs_summary: Dictionary = {}
var last_ijfs_writeback: IjfsWriteback = null
# D3 anti-ship Green firing systems (AntishipSystem rows aggregated by (to_number, type_id)). Persist
# across turns so launcher destruction/suppression carries forward; lazily built on first use.
var antiship_systems: Array = []
# Container-level view of the same arsenal (one entry per platform-group bin) — IJFS target source.
var antiship_containers: Array = []
# Fractional BN-equiv owed from ship losses, carried across turns (ShipLoadingModel.resolve_bn_losses).
var lost_at_sea_accumulator: float = 0.0
var last_antiship_summary: AntishipSummary = null
var last_offload_summary: Dictionary = {}
# The sealift phase's committed sailing fleet this turn (ship_type -> hull count): cohort carriers +
# ready escort screen. Consumed by resolve_antiship_turn as the crossing fleet (plan 0004).
var last_sealift_sent_by_type: Dictionary = {}
var last_frontline_summary: FrontlineSummary = null
var last_cleanup_summary: CleanupSummary = null
# Victory state, set in the end-of-turn cleanup census (VictoryConditions). winner: ""/"red"/"green".
var game_over: bool = false
var winner: String = ""
var _china_has_landed: bool = false  # latch for the "after_first_landing" loss-check arm


func _ready() -> void:
	reset_to_scenario()


func reset_to_scenario() -> void:
	# Restore brigade state (composition, hex_id, destroyed) from source data, since combat mutates
	# Brigade resources in place and the old values carry across play-throughs. Hex ownership/FEBA
	# mutate the same way — without this, run 2 of an in-process replay starts on run 1's map.
	GameData.load_brigades()
	GameData.reset_hex_states()
	# Reload the CURRENT scenario (a process-level --scenario/HEXCOMBAT_SCENARIO selection must
	# survive resets); before any load_all it falls back to the default.
	GameData.load_scenario(GameData.scenario_path if not GameData.scenario_path.is_empty() else GameData.DEFAULT_SCENARIO_PATH)

	turn_number = 1
	phase = Phase.PLANNING
	turn_length_days = GameData.turn_length_days
	if turn_length_days == 0:
		push_warning("GameData.turn_length_days is 0; falling back to 1 day")
		turn_length_days = 1
	orders = {
		Brigade.Team.RED: [],
		Brigade.Team.GREEN: []
	}
	commitments = {
		Brigade.Team.RED: [],
		Brigade.Team.GREEN: []
	}
	_rebuild_ship_reserve()
	_rebuild_sealift_state()
	_rebuild_fleet()
	_rebuild_supply_state()
	_rebuild_infrastructure_state()
	# IJFS state is lazy-loaded on the first resolve_ijfs_turn (it pulls ~500KB of pairings + many
	# Resource objects; eager-loading it in every booted process — validators, smoke, tests — bloated
	# shutdown and triggered the Godot 4.7 teardown crash). Reset the handle; resolve_ijfs_turn builds
	# it fresh per scenario.
	ijfs_state = null
	_ijfs_day = 0
	pending_lost_at_sea = 0
	last_contested_hexes.clear()
	last_combat_summaries.clear()
	last_ijfs_summary = {}
	last_ijfs_writeback = null
	# Anti-ship systems are lazily (re)built on first use (resolve_ijfs_turn / resolve_antiship_turn),
	# matching the IJFS state's lazy-load pattern; clearing here forces a fresh build per scenario.
	antiship_systems = []
	antiship_containers = []
	lost_at_sea_accumulator = 0.0
	last_antiship_summary = null
	last_sealift_sent_by_type = {}
	last_frontline_summary = null
	last_cleanup_summary = null
	game_over = false
	winner = ""
	_china_has_landed = false
	EventBus.phase_changed.emit(phase)


func add_move_order(team: Brigade.Team, brigade_id: String, target_hex: String, mode: String) -> void:
	if phase != Phase.PLANNING:
		push_error("Cannot add move order outside PLANNING phase")
		return

	var brigade: Brigade = GameData.get_brigade(brigade_id)
	if brigade == null:
		push_error("Move order references unknown brigade_id: %s" % brigade_id)
		return
	if brigade.team != team:
		push_error("Move order team mismatch for %s: order=%s brigade=%s" % [brigade_id, _team_to_string(team), _team_to_string(brigade.team)])
		return
	if target_hex not in GameData.hex_lookup:
		push_error("Move order references unknown target_hex: %s" % target_hex)
		return
	if mode != Movement.MODE_TACTICAL and mode != Movement.MODE_ADMINISTRATIVE:
		push_error("Unknown movement mode: %s" % mode)
		return

	for pending_order in orders[team]:
		var typed_pending_order: MoveOrder = pending_order
		if typed_pending_order.brigade_id == brigade_id:
			push_error("Brigade already has a pending move order this turn: %s" % brigade_id)
			return
	for pending_commitment in commitments[team]:
		var typed_pending_commitment: CommitOrder = pending_commitment
		if typed_pending_commitment.brigade_id == brigade_id:
			push_error("Brigade already has a pending commit order this turn: %s" % brigade_id)
			return

	var allowance := Movement.move_allowance(brigade, mode)
	var reachable := GameData.find_reachable(brigade.hex_id, allowance)
	if target_hex not in reachable:
		push_error("Move order target %s beyond %s allowance for %s" % [target_hex, mode, brigade_id])
		return

	var order: MoveOrder = MoveOrderResource.new()
	order.brigade_id = brigade_id
	order.target_hex = target_hex
	order.mode = mode
	orders[team].append(order)


func resolve_turn(dice: Dice = null) -> void:
	if phase != Phase.PLANNING:
		push_error("Cannot resolve turn outside PLANNING phase")
		return

	if dice == null:
		dice = SeededDice.new(turn_number)

	phase = Phase.RESOLUTION
	EventBus.phase_changed.emit(phase)
	# Sea phase ordering (D3-D): IJFS (Red joint fires) suppresses/destroys Green anti-ship systems
	# first; then Green anti-ship + mines attrit the Red crossing (removing BNs from the reserve);
	# then offload lands only the survivors. Each draws from its own INDEPENDENT substream (never the
	# combat dice), so the ground-combat golden invariant stays byte-stable.
	resolve_ijfs_turn(dice)
	# D4-H (2d): IJFS maneuver kills reduce the ground OOB before combat. Deterministic (reads the
	# writeback the warmup just produced; no dice), so the combat golden stays reproducible.
	_apply_ijfs_maneuver_casualties()
	# Sealift (plan 0004): tick the ship return/reload pipeline and embark this turn's wave (first
	# echelon adopted, follow-on echelons loaded onto ready amphibious lift) BEFORE the crossing, so
	# the anti-ship phase attrits exactly the hulls that sail. Dice-free -> combat golden unaffected.
	resolve_sealift_turn()
	resolve_antiship_turn(dice)
	last_offload_summary = resolve_offload_turn(dice)

	# disable_phases (plan 0012): a scenario/override can skip the ground WeGo phases wholesale so
	# calibration sweeps run standard games while isolating the sea/IJFS phases. Buffered orders
	# simply never execute; skipping consumes no dice, so an empty list is byte-identical.
	var skip_movement := GameData.disabled_phases.has("movement")
	var skip_ground_combat := GameData.disabled_phases.has("ground_combat")
	if not skip_movement:
		_apply_move_orders(Brigade.Team.RED)
		_apply_move_orders(Brigade.Team.GREEN)
	if skip_ground_combat:
		last_contested_hexes.clear()
	else:
		last_contested_hexes = _find_contested_hexes()
	var combat_summaries: Array[CombatSummary] = []
	# Per-hex combat substream (plan 0010): each contested hex draws from its OWN dice stream derived
	# from the root turn seed, so a design tweak that changes the roll count in one hex's fight never
	# scrambles the dice of an unrelated hex. Turn-scoped salt matches the ijfs/antiship pattern so an
	# injected constant-seed dice still varies per turn.
	for hex_id in last_contested_hexes:
		var summary := _resolve_combat_at(hex_id, dice.derive("combat:%d:%s" % [turn_number, hex_id]))
		if summary != null:
			combat_summaries.append(summary)
	if not skip_ground_combat:
		_apply_feba_retreats()
	GameData.recompute_hex_ownership()
	for summary in combat_summaries:
		summary.owner_after = String(GameData.hex_states[summary.hex_id].owner)
	last_combat_summaries = combat_summaries.duplicate()
	resolve_supply_turn()
	resolve_cleanup_phase()

	# Debug-only invariant (refactor item 4): at the settled end of a turn the brigade↔hex indexes
	# must be consistent. Gated on OS.is_debug_build() so the validator is never called in release;
	# in debug/test/headless runs it fails loud on any silent index desync. End-of-turn only (a settled
	# boundary) — NOT the per-mutator hot path, which can hold benign transient desync mid-resolution.
	if OS.is_debug_build():
		var index_violations := GameData.validate_runtime_indexes()
		assert(index_violations.is_empty(), "runtime index desync at end of resolve_turn: %s" % "; ".join(index_violations))

	phase = Phase.END
	EventBus.phase_changed.emit(phase)
	EventBus.combat_resolved.emit(combat_summaries)
	EventBus.turn_resolved.emit(turn_number)


func add_commit_order(team: Brigade.Team, brigade_id: String, target_hex: String) -> void:
	if phase != Phase.PLANNING:
		push_error("Cannot add commit order outside PLANNING phase")
		return

	var brigade: Brigade = GameData.get_brigade(brigade_id)
	if brigade == null:
		push_error("Commit order references unknown brigade_id: %s" % brigade_id)
		return
	if brigade.team != team:
		push_error("Commit order team mismatch for %s: order=%s brigade=%s" % [brigade_id, _team_to_string(team), _team_to_string(brigade.team)])
		return
	if brigade.destroyed:
		push_error("Destroyed brigade cannot commit: %s" % brigade_id)
		return
	if brigade.moved_admin_this_turn:
		push_error("Administrative-moved brigade cannot commit: %s" % brigade_id)
		return
	if target_hex not in GameData.hex_lookup:
		push_error("Commit order references unknown target_hex: %s" % target_hex)
		return
	if brigade.hex_id == target_hex:
		push_error("Commit order brigade is already in target hex: %s" % brigade_id)
		return
	if brigade.hex_id not in GameData.get_neighbors(target_hex):
		push_error("Commit order brigade %s is not adjacent to target_hex: %s" % [brigade_id, target_hex])
		return

	for pending_order in orders[team]:
		var typed_pending_order: MoveOrder = pending_order
		if typed_pending_order.brigade_id == brigade_id:
			push_error("Brigade already has a pending move order this turn: %s" % brigade_id)
			return
	for pending_commitment in commitments[team]:
		var typed_pending_commitment: CommitOrder = pending_commitment
		if typed_pending_commitment.brigade_id == brigade_id:
			push_error("Brigade already has a pending commit order this turn: %s" % brigade_id)
			return

	var order: CommitOrder = CommitOrderResource.new()
	order.brigade_id = brigade_id
	order.target_hex = target_hex
	commitments[team].append(order)


func eligible_commit_brigades(team: Brigade.Team, target_hex: String) -> Array:
	if target_hex not in GameData.hex_lookup:
		push_error("Commit eligibility requested for unknown target_hex: %s" % target_hex)
		return []

	var eligible: Array = []
	for brigade_value in GameData.brigades.values():
		var brigade: Brigade = brigade_value
		if brigade.team != team or brigade.destroyed or brigade.moved_admin_this_turn:
			continue
		if brigade.hex_id == target_hex:
			continue
		if brigade.hex_id not in GameData.get_neighbors(target_hex):
			continue
		if _brigade_has_pending_order(team, brigade.id):
			continue
		eligible.append(brigade.id)
	return eligible


func begin_next_turn() -> void:
	if phase != Phase.END:
		push_error("Cannot begin next turn outside END phase")
		return

	for brigade in GameData.brigades.values():
		var typed_brigade: Brigade = brigade
		typed_brigade.moved_this_turn = false
		typed_brigade.moved_admin_this_turn = false
		typed_brigade.fought_this_turn = false
	orders[Brigade.Team.RED].clear()
	orders[Brigade.Team.GREEN].clear()
	commitments[Brigade.Team.RED].clear()
	commitments[Brigade.Team.GREEN].clear()
	turn_number += 1
	phase = Phase.PLANNING
	EventBus.phase_changed.emit(phase)


func orders_for(team: Brigade.Team) -> Array:
	return orders[team]


func commitments_for(team: Brigade.Team) -> Array:
	return commitments[team]


func ship_reserve_priority_order() -> Array[String]:
	return OffloadResolver.priority_order(ship_reserve)


func resolve_offload_turn(dice: Dice) -> Dictionary:
	assert(dice != null, "resolve_offload_turn requires a Dice instance")
	# Infrastructure lifecycle ticks every offload phase (plan 0006), even with an empty reserve:
	# ground combat can seize a port hex long after the last beach landing. Ownership here is last
	# turn's post-combat state — the producer->consumer edge is combat ownership -> next offload.
	var infra_nodes: Array = []
	if infrastructure_state != null:
		var owner_by_hex := _owner_by_hex()
		InfrastructureResolver.tick(infrastructure_state, GameData.infrastructure, owner_by_hex)
		infra_nodes = InfrastructureResolver.red_offload_nodes(infrastructure_state, GameData.infrastructure, owner_by_hex)

	if ship_reserve.is_empty():
		var empty_manifest := _empty_offload_manifest()
		empty_manifest["lost_at_sea"] = pending_lost_at_sea
		# D3-F applies lost_at_sea to the reserve; D0-C only threads the value.
		pending_lost_at_sea = 0
		EventBus.offload_resolved.emit(empty_manifest)
		return empty_manifest

	var cost_config: Dictionary = GameData.offload_weights if GameData.use_offload_weight_matrix else {}
	var outcome := OffloadResolver.resolve(
		turn_number, ship_reserve, GameData.beaches, GameData.brigades,
		infra_nodes, cost_config, GameData.beach_to_to, _owner_by_hex())
	for landing_value in outcome["landings"]:
		var landing: Dictionary = landing_value
		var brigade_id := String(landing["brigade_id"])
		GameData.set_brigade_hex(brigade_id, String(landing["beach_hex"]))
		GameData.get_brigade(brigade_id).entry_bearing = float(landing["offset_bearing"])
	ship_reserve = outcome["remaining_ship_reserve"]
	GameData.recompute_hex_ownership()

	var manifest: Dictionary = outcome["manifest"]
	# Drain the landed BNs from their offloading cohorts; a fully-offloaded cohort frees its hulls
	# into the return/reload pipeline (or straight back to ready when return time is 0) — plan 0004 D4.
	var landed_ids: Array = []
	for landed_value in manifest["manifest_landed"]:
		landed_ids.append(String((landed_value as Dictionary)["bn_id"]))
	# JLSF deliveries (plan 0006): the detachment is ashore at its node — start the repair clock
	# and free its hulls like any landed cargo.
	for arrival_value in outcome.get("jlsf_arrivals", []):
		var arrival: Dictionary = arrival_value
		var port_id := String(arrival["port_id"])
		if infrastructure_state != null and infrastructure_state.nodes.has(port_id):
			infrastructure_state.nodes[port_id]["jlsf"] = InfrastructureState.JLSF_ARRIVED
		for bn_id_value in arrival["bn_ids"]:
			landed_ids.append(String(bn_id_value))
	if sealift_state != null:
		SealiftResolver.drain_bn_ids(sealift_state, landed_ids, GameData.amphibious_return_time_turns)
		_project_sealift_onto_fleet()
	_reconcile_lost_jlsf()

	manifest["lost_at_sea"] = pending_lost_at_sea
	# D3-F applies lost_at_sea to the reserve; D0-C only threads the value.
	pending_lost_at_sea = 0
	EventBus.offload_resolved.emit(manifest)
	return manifest


func _empty_offload_manifest() -> Dictionary:
	return OffloadResolver.empty_manifest()


func _owner_by_hex() -> Dictionary:
	var owners: Dictionary = {}
	for hex_id in GameData.hex_states.keys():
		owners[String(hex_id)] = String((GameData.hex_states[hex_id] as HexState).owner)
	return owners


func _rebuild_infrastructure_state() -> void:
	infrastructure_state = InfrastructureStateBuilder.build(GameData.infrastructure)
	jlsf_orders.clear()


## A JLSF deployment lost whole at sea (its pseudo-BNs all drowned in the crossing) leaves no
## pool or reserve trace; reset its node marker so a new deployment can be ordered/auto-queued.
func _reconcile_lost_jlsf() -> void:
	if infrastructure_state == null:
		return
	for id_value in infrastructure_state.nodes.keys():
		var node: Dictionary = infrastructure_state.nodes[id_value]
		var marker := String(node["jlsf"])
		if marker != InfrastructureState.JLSF_QUEUED and marker != InfrastructureState.JLSF_ENROUTE:
			continue
		var brigade_id := JlsfCargo.brigade_id_for(String(id_value))
		if not _reserve_or_pool_has(brigade_id):
			node["jlsf"] = InfrastructureState.JLSF_NONE


func _reserve_or_pool_has(brigade_id: String) -> bool:
	for entry_value in ship_reserve:
		if String((entry_value as Dictionary).get("brigade_id", "")) == brigade_id:
			return true
	if sealift_state != null:
		for entry_value in sealift_state.mainland_pool:
			if String((entry_value as Dictionary).get("brigade_id", "")) == brigade_id:
				return true
	return false


func resolve_supply_turn() -> Dictionary:
	assert(supply_state != null, "resolve_supply_turn requires supply_state")
	var units := _active_red_battalion_units()
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

	var summary := SupplyResolver.resolve(supply_state, units, moved_ids, engaged_ids, turn_number)
	EventBus.supply_updated.emit(summary)
	return summary


# --- IJFS (D4) — Red joint/air-missile fires daily phase ----------------------------------------

func resolve_ijfs_turn(dice: Dice) -> Dictionary:
	assert(dice != null, "resolve_ijfs_turn requires a Dice instance")
	if ijfs_state == null:
		_rebuild_ijfs_state()
	var outcome := IjfsResolver.resolve(ijfs_state, GameData.brigades, turn_number, _ijfs_day, dice)
	_ijfs_day = turn_number
	var ledgers: Dictionary = outcome["ledgers"]
	last_ijfs_summary = ledgers["summary"]
	last_ijfs_writeback = outcome["writeback"]
	EventBus.ijfs_resolved.emit(last_ijfs_summary)
	return ledgers


func _build_warmup_context(
	x_day: int, z_day: int, total_days: int,
	rules: Dictionary, exquisite_intel: Dictionary,
	attrition_profile: String,
	firing_capacity_config: Dictionary,
	release_rules: Array,
) -> Dictionary:
	return IjfsResolver.build_warmup_context(
		x_day, z_day, total_days, rules, exquisite_intel, attrition_profile,
		firing_capacity_config, release_rules)


## Lazily build the persistent anti-ship Green firing systems (aggregated by (to_number, type_id)).
## Shared by resolve_ijfs_turn (IJFS targeting) and resolve_antiship_turn (firing).
func _ensure_antiship_systems() -> void:
	if not antiship_systems.is_empty():
		return
	var built := AntishipSystemsBuilder.build()
	antiship_systems = built["systems"]
	antiship_containers = built["containers"]


func _rebuild_ijfs_state() -> void:
	# Anti-ship systems must exist first (their containers seed the per-(TO,type) IJFS targets).
	_ensure_antiship_systems()
	var green_brigades: Array = []
	for brigade_value in GameData.brigades.values():
		var brigade: Brigade = brigade_value
		if brigade.team == Brigade.Team.GREEN and not brigade.destroyed:
			green_brigades.append(brigade)
	ijfs_state = IjfsStateBuilder.build(antiship_containers, green_brigades)
	_ijfs_day = 0


func _update_maneuver_posture() -> void:
	IjfsResolver.update_maneuver_posture(ijfs_state, GameData.brigades)


func _sync_maneuver_targets_to_oob() -> void:
	IjfsResolver.sync_maneuver_targets_to_oob(ijfs_state, GameData.brigades)


func _apply_ijfs_maneuver_casualties() -> void:
	var casualties: Array = last_ijfs_writeback.maneuver_casualties if last_ijfs_writeback != null else []
	IjfsResolver.apply_maneuver_casualties(casualties, GameData.brigades)


## D3-D: Green coastal anti-ship fires + mine warfare against the Red amphibious crossing. Threads the
## firing plan (D3-B2) -> crossing (D3-B3) -> mines (D3-C); ship losses convert to BNs lost at sea
## (ShipLoadingModel) and feed register_ship_losses (the D0-C seam offload consumes). Runs after IJFS
## (Green systems suppressed/destroyed first) and before offload (only survivors land). Draws from an
## INDEPENDENT substream so the ground-combat golden invariant stays byte-stable.
func resolve_antiship_turn(dice: Dice) -> Dictionary:
	_ensure_antiship_systems()
	last_antiship_summary = null

	# Independent substream (same isolation pattern as resolve_ijfs_turn). SeededDice.derive is a
	# pure hash of (seed, label) — it consumes no parent-stream state, so deriving before the
	# resolver's no-wave check cannot shift the base combat stream.
	var as_dice: Dice
	if dice is SeededDice:
		as_dice = dice.derive("antiship:%d" % turn_number)
	else:
		as_dice = SeededDice.new(hash("antiship:%d" % turn_number))

	# Theaters reads the GameData autoload internally, so the TO maps are materialized here and
	# passed into the pure resolver as plain data.
	var to_adjacency: Dictionary = {}
	for to_num in GameData.active_tos:
		to_adjacency[to_num] = Theaters.adjacent_tos(to_num)

	# Only the BNs sailing this turn (the sealift "sent" cohorts) cross and take attrition; offloading
	# BNs are safe ashore. Slice that crossing wave out of the full reserve (plan 0004 D3).
	var crossing_reserve := _crossing_reserve_from_sent_cohorts()
	# Captured pre-resolve: drain/flip below mutate the cohorts before the summary is stored.
	var wave_bns: int = SealiftResolver.sent_cohort_bn_ids(sealift_state).size()

	var outcome := AntishipResolver.resolve(
		turn_number, crossing_reserve, antiship_systems, last_ijfs_writeback,
		last_sealift_sent_by_type, GameData.ship_defs, GameData.beach_to_to, GameData.active_tos, to_adjacency,
		lost_at_sea_accumulator, sealift_state.escort_sam, as_dice)
	if outcome["summary"] == null:
		# Nothing crossed this turn: no fires, no state to apply (pending_lost_at_sea keeps its value).
		return {}

	lost_at_sea_accumulator = float(outcome["accumulator"])
	# Apply hull losses to the sealift cohorts (carriers) + the fleet, then drop drowned BNs from the
	# reserve AND their cohorts, and flip the surviving crossers to offloading (plan 0004 D3).
	_apply_crossing_hull_losses(outcome["destroyed_by_type"])
	var lost_ids: Array = outcome["lost_ids"]
	ship_reserve = AntishipResolver.remaining_reserve_after_losses(ship_reserve, lost_ids)
	SealiftResolver.drain_bn_ids(sealift_state, lost_ids, GameData.amphibious_return_time_turns)
	SealiftResolver.flip_sent_to_offloading(sealift_state)
	# Deplete the escort SAM magazines by what fired, and divert any type that dropped to/below its
	# reload threshold (plan 0004 D5). No-op when the magazine is unmodelled (escort_sam empty).
	SealiftResolver.apply_escort_consumption(
		sealift_state, outcome["escort_sam_consumed"], GameData.escort_reload_time_turns)
	_project_sealift_onto_fleet()
	register_ship_losses(int(outcome["bn_equiv_lost"]))
	last_antiship_summary = outcome["summary"]
	last_antiship_summary.wave_bns = wave_bns
	EventBus.antiship_resolved.emit(last_antiship_summary.to_dict())
	return last_antiship_summary.to_dict()


## The subset of ship_reserve whose BNs are bound to a "sent" cohort (crossing this turn), with each
## kept entry trimmed to just those BNs. Empty when nothing sails.
func _crossing_reserve_from_sent_cohorts() -> Array:
	var sailing := SealiftResolver.sent_cohort_bn_ids(sealift_state)
	if sailing.is_empty():
		return []
	var crossing: Array = []
	for entry_value in ship_reserve:
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
func _apply_crossing_hull_losses(destroyed_by_type: Dictionary) -> void:
	for ship_type_value in destroyed_by_type.keys():
		var ship_type := String(ship_type_value)
		var requested := int(destroyed_by_type[ship_type_value])
		if requested <= 0:
			continue
		var state: ShipState = fleet.get(ship_type, null)
		if state == null:
			continue
		# Carriers (capacity > 0) lose hulls out of their cohorts; escorts out of the ready screen.
		var ship_def: ShipDef = GameData.ship_defs_by_name.get(ship_type, null)
		var applied: int
		if ship_def != null and ship_def.is_carrier():
			applied = SealiftResolver.remove_carrier_hulls(sealift_state, ship_type, requested)
		else:
			applied = mini(requested, state.fleet_surviving_total)
		state.destroyed += applied
		state.fleet_surviving_total -= applied


func _mine_ship_meta(transit_config: Dictionary) -> Dictionary:
	return AntishipResolver.mine_ship_meta(GameData.ship_defs, transit_config)


# --- D5-C Cleanup phase — end-of-turn per-system flag reset ------------------------------------

func resolve_cleanup_phase() -> Dictionary:
	GameData.recompute_hex_ownership()
	# Pure work (flag reset, victory census + verdict, activity latch) lives in CleanupResolver;
	# consumes no dice, so the golden RNG stream is unaffected.
	var outcome := CleanupResolver.resolve(
		antiship_systems, GameData.brigades, ship_reserve, GameData.victory_config,
		turn_number, _china_has_landed)
	_china_has_landed = bool(outcome["china_has_landed"])
	last_cleanup_summary = outcome["summary"]
	game_over = last_cleanup_summary.game_over
	winner = last_cleanup_summary.winner
	EventBus.cleanup_resolved.emit(last_cleanup_summary.to_dict())
	return last_cleanup_summary.to_dict()


func _taiwan_battalion_census() -> Dictionary:
	return CleanupResolver.census(GameData.brigades, ship_reserve, GameData.victory_config)


# --- D5-A Frontline phase — redistribute Red brigades along a drawn polyline -------------------

func _frontline_hex_centers() -> Array:
	var centers: Array = []
	for hex_value in GameData.hexes:
		var hex: Hex = hex_value
		centers.append({"id": hex.id, "lat": hex.center.x, "lon": hex.center.y})
	return centers


func resolve_frontline_phase(polyline_coords: Array) -> Dictionary:
	# Only the drawing side's brigades reshuffle along the line — RED here (the amphibious attacker),
	# mirroring TIV front_line_service's single-side filter. Intentional asymmetry, not a bug; if Green
	# ever draws front lines, pass its brigades instead.
	var candidate_brigades: Array = []
	for brigade_value in GameData.brigades.values():
		var brigade: Brigade = brigade_value
		if brigade.team == Brigade.Team.RED and not brigade.destroyed:
			candidate_brigades.append(brigade)

	last_frontline_summary = FrontlineResolver.resolve(polyline_coords, _frontline_hex_centers(), candidate_brigades)
	for brigade_id in last_frontline_summary.moves.keys():
		GameData.set_brigade_hex(String(brigade_id), String(last_frontline_summary.moves[brigade_id]))
	EventBus.frontline_resolved.emit(last_frontline_summary.to_dict())
	return last_frontline_summary.to_dict()


func _active_red_battalion_units() -> Array:
	var units: Array = []
	for brigade_value in GameData.brigades.values():
		var brigade: Brigade = brigade_value
		if brigade.team != Brigade.Team.RED or brigade.destroyed or brigade.hex_id.is_empty():
			continue
		for battalion_value in brigade.composition:
			var battalion: Battalion = battalion_value
			for _qty_index in range(battalion.qty):
				units.append({
					"brigade_id": brigade.id,
					"type": battalion.type,
					"brigade_type": brigade.nato_type,
				})
	return units


func _rebuild_ship_reserve() -> void:
	ship_reserve = ShipReserveBuilder.build(GameData.red_ship_reserve, GameData.brigades)


func _rebuild_sealift_state() -> void:
	# Escort SAM magazine is seeded from the crossing config only when the scenario opts in via
	# escort_reload_time_turns > 0 (plan 0004 D5); otherwise it stays unmodelled (empty).
	var crossing_config := AntishipLoaders.load_crossing_config(AntishipResolver.CROSSING_PATH)
	var escort_interception: Dictionary = crossing_config.get("escort_interception", {})
	sealift_state = SealiftStateBuilder.build(
		GameData.red_followon_reserve, GameData.red_ship_reserve, GameData.brigades,
		GameData.auto_seed_followon_pool, escort_interception, GameData.escort_reload_time_turns > 0)


## Sealift phase (plan 0004): advance the ship return pipeline and embark this turn's crossing wave.
## Dice-free and pure (SealiftResolver); this wrapper merges the newly-embarked BNs into the reserve,
## records the sailing fleet for the crossing, and reprojects the fleet ShipState bins from the
## advanced sealift state.
func resolve_sealift_turn() -> void:
	if sealift_state == null:
		return
	var ready_by_type: Dictionary = {}
	for ship_type in fleet.keys():
		ready_by_type[String(ship_type)] = int((fleet[ship_type] as ShipState).ready)

	_consume_jlsf_orders()
	var outcome := SealiftResolver.resolve(
		sealift_state, ship_reserve, ready_by_type, GameData.ship_defs)

	for entry_value in outcome["embarked_reserve_entries"]:
		var entry: Dictionary = entry_value
		# A JLSF deployment that got hulls this turn is now enroute (plan 0006).
		if JlsfCargo.is_jlsf_entry(entry) and infrastructure_state != null:
			var port_id := String(entry.get("port_id", ""))
			if infrastructure_state.nodes.has(port_id):
				infrastructure_state.nodes[port_id]["jlsf"] = InfrastructureState.JLSF_ENROUTE
		_merge_reserve_entry(entry)
	last_sealift_sent_by_type = outcome["sent_by_type"]
	_project_sealift_onto_fleet()


## Consume the deploy_jlsf order buffer through the JlsfCargo queueing policy (plan 0006). New
## pseudo-entries go to the FRONT of the mainland pool (logistics open the port gate before more
## troops help); JlsfCargo.queue_deployments owns ordering + marker flips.
func _consume_jlsf_orders() -> void:
	if infrastructure_state == null or sealift_state == null:
		jlsf_orders.clear()
		return
	var entries := JlsfCargo.queue_deployments(
		jlsf_orders, infrastructure_state, GameData.infrastructure, GameData.beaches,
		GameData.beach_to_to, GameData.auto_jlsf, GameData.jlsf_lift_bn_equiv)
	jlsf_orders.clear()
	for entry in entries:
		sealift_state.mainland_pool.push_front(entry)


## Merge a newly-embarked reserve entry into ship_reserve: append its BNs to the brigade's existing
## entry (a follow-on brigade already partway across) or add a new entry.
func _merge_reserve_entry(entry_value) -> void:
	var entry: Dictionary = entry_value
	var brigade_id := String(entry["brigade_id"])
	for existing_value in ship_reserve:
		var existing: Dictionary = existing_value
		if String(existing["brigade_id"]) == brigade_id:
			(existing["bns"] as Array).append_array(entry["bns"])
			return
	ship_reserve.append(entry)


## Reproject the fleet ShipState bins from the sealift state (the single source of truth for where
## hulls are): surviving_sent/offloading from cohorts, returning from the pipeline, ready as the
## remainder of the surviving fleet. Keeps ShipState.validate()'s invariants honest (plan 0004).
func _project_sealift_onto_fleet() -> void:
	var sent: Dictionary = {}
	var offloading: Dictionary = {}
	var returning: Dictionary = {}
	for cohort_value in sealift_state.cohorts:
		var cohort: Dictionary = cohort_value
		var bucket: Dictionary = sent if String(cohort["state"]) == SealiftState.STATE_SENT else offloading
		for ship_type in (cohort["hulls_by_type"] as Dictionary).keys():
			bucket[String(ship_type)] = int(bucket.get(String(ship_type), 0)) + int(cohort["hulls_by_type"][ship_type])
	for ship_type in sealift_state.return_pipeline.keys():
		for slot_value in (sealift_state.return_pipeline[ship_type] as Array):
			returning[String(ship_type)] = int(returning.get(String(ship_type), 0)) + int((slot_value as Dictionary)["count"])
	# Escort types reloading SAMs are away from the screen: all their surviving hulls are busy
	# (returning) until reload completes (plan 0004 D5).
	for ship_type in sealift_state.escort_reload.keys():
		var reloading_state: ShipState = fleet.get(String(ship_type), null)
		if reloading_state != null:
			returning[String(ship_type)] = int(returning.get(String(ship_type), 0)) + reloading_state.fleet_surviving_total

	for ship_type in fleet.keys():
		var state: ShipState = fleet[ship_type]
		var ss := int(sent.get(String(ship_type), 0))
		var of := int(offloading.get(String(ship_type), 0))
		var rt := int(returning.get(String(ship_type), 0))
		state.surviving_sent = ss
		state.sent_original = ss
		state.offloading = of
		state.returning = rt
		state.ready = state.fleet_surviving_total - ss - of - rt
		assert(state.ready >= 0, "sealift projection: negative ready for %s (surviving=%d busy=%d)" % [ship_type, state.fleet_surviving_total, ss + of + rt])
		assert(state.validate(), "sealift projection broke ShipState invariant for %s" % ship_type)


func _rebuild_supply_state() -> void:
	supply_state = SupplyStateBuilder.build(float(GameData.red_dos_start))


func register_ship_losses(bn_equiv_lost: int) -> void:
	pending_lost_at_sea = maxi(0, bn_equiv_lost)


func _rebuild_fleet() -> void:
	fleet = FleetBuilder.build(GameData.ship_defs)


func _apply_move_orders(team: Brigade.Team) -> void:
	for order in orders[team]:
		var move_order: MoveOrder = order
		var brigade: Brigade = GameData.get_brigade(move_order.brigade_id)
		GameData.set_brigade_hex(move_order.brigade_id, move_order.target_hex)
		brigade.moved_this_turn = true
		if move_order.mode == Movement.MODE_ADMINISTRATIVE:
			brigade.adjust_organization(-Brigade.ADMIN_MOVE_ORG_COST)
			brigade.moved_admin_this_turn = true
		else:
			brigade.adjust_organization(-Brigade.TACTICAL_MOVE_ORG_COST)


func _find_contested_hexes() -> Array[String]:
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
func _defender_combat_modifier(hex_id: String) -> float:
	var terrain := GameData.get_terrain(hex_id)
	var terrain_modifier: float = terrain.defender_modifier if terrain != null else 1.0
	return terrain_modifier * 1.0


# Delegating wrapper (test-called surface) — pure logic lives in CombatResolver.
func _inject_supply_effectiveness(units: Array, team: int) -> void:
	var pool: float = supply_state.current_dos_tons if supply_state != null else 1.0
	CombatResolver.inject_supply_effectiveness(units, team, pool, GameData.red_out_of_supply_effectiveness)


# Thin wrapper: gathers contributors (board/commitment state), delegates the dice-consuming combat
# core to CombatResolver.resolve_at, then applies the result — casualties, FEBA accumulation,
# fought flags — and stamps owner_after. Application stays here because combat at one hex mutates
# state the next hex's contributor gathering reads (ported interleaving semantics).
func _resolve_combat_at(hex_id: String, dice: Dice) -> CombatSummary:
	var attacker_brigades := _combat_contributors_for(Brigade.Team.RED, hex_id)
	var defender_brigades := _combat_contributors_for(Brigade.Team.GREEN, hex_id)
	var pool: float = supply_state.current_dos_tons if supply_state != null else 1.0
	# Terrain resolves at hex_id (the defended/contested hex), not the attacker's origin — the
	# defender_modifier models fortification/cover of the ground being held, which belongs to the
	# hex under attack regardless of which side started there.
	var rules := CombatRules.new()
	rules.feba_base_km = GameData.feba_base_km
	rules.red_supply_pool = pool
	rules.red_out_of_supply_effectiveness = GameData.red_out_of_supply_effectiveness
	rules.unscreened_support_strength = GameData.unscreened_support_strength
	rules.maneuver_casualty_weight = GameData.maneuver_casualty_weight
	rules.support_casualty_weight = GameData.support_casualty_weight
	rules.defender_terrain_modifier = _defender_combat_modifier(hex_id)

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
		_apply_casualty(casualty)
	for casualty in result.defender_casualties:
		_apply_casualty(casualty)

	GameData.hex_states[hex_id].feba_km = GameData.hex_states[hex_id].feba_km + result.feba_movement_km
	for brigade_value in attacker_brigades + defender_brigades:
		var fought_brigade: Brigade = brigade_value
		fought_brigade.fought_this_turn = true

	var summary: CombatSummary = outcome["summary"]
	summary.owner_after = String(GameData.hex_states[hex_id].owner)
	return summary


func _combat_contributors_for(team: Brigade.Team, hex_id: String) -> Array:
	var contributors: Array = []
	var seen := {}
	for brigade_id_value in GameData.get_brigades_in_hex(hex_id):
		var brigade: Brigade = GameData.get_brigade(String(brigade_id_value))
		if brigade == null or brigade.destroyed or brigade.moved_admin_this_turn or brigade.team != team:
			continue
		contributors.append(brigade)
		seen[brigade.id] = true

	for commitment_value in commitments[team]:
		var commitment: CommitOrder = commitment_value
		if commitment.target_hex != hex_id:
			continue
		var brigade: Brigade = GameData.get_brigade(commitment.brigade_id)
		if brigade == null or brigade.destroyed or brigade.moved_admin_this_turn or brigade.team != team:
			continue
		if brigade.id in seen:
			continue
		contributors.append(brigade)
		seen[brigade.id] = true
	return contributors


# Delegating wrapper (test-called surface) — pure logic lives in CombatResolver.
func _brigade_ids(brigades: Array) -> Array[String]:
	return CombatResolver.brigade_ids(brigades)


func _brigade_has_pending_order(team: Brigade.Team, brigade_id: String) -> bool:
	for pending_order in orders[team]:
		var typed_pending_order: MoveOrder = pending_order
		if typed_pending_order.brigade_id == brigade_id:
			return true
	for pending_commitment in commitments[team]:
		var typed_pending_commitment: CommitOrder = pending_commitment
		if typed_pending_commitment.brigade_id == brigade_id:
			return true
	return false


func _apply_feba_retreats() -> void:
	for hex_id in last_contested_hexes:
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

		var target := _find_retreat_hex(hex_id, retreating_team)
		if target == "":
			continue

		for brigade in retreaters:
			GameData.set_brigade_hex(brigade.id, target)
		GameData.hex_states[hex_id].feba_km = 0.0


func _find_retreat_hex(from_hex: String, team: Brigade.Team) -> String:
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


func _apply_casualty(casualty: Dictionary) -> void:
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


## Play a full turn from a bulk-order spec: buffers every order, resolves, and
## returns a typed TurnResult. The caller remains in Phase.END and must call
## begin_next_turn() separately to advance.
func play_turn(red_orders: Array, green_orders: Array, dice: Dice = null) -> TurnResult:
	if phase != Phase.PLANNING:
		push_error("play_turn requires PLANNING phase")
		return null

	for raw_order in red_orders:
		_apply_order(raw_order, Brigade.Team.RED)
	for raw_order in green_orders:
		_apply_order(raw_order, Brigade.Team.GREEN)

	resolve_turn(dice)

	var result := TurnResult.new()
	result.turn_number = turn_number
	result.contested_hexes = last_contested_hexes.duplicate()
	result.combat_summaries = last_combat_summaries.duplicate()
	result.ijfs_summary = last_ijfs_summary.duplicate(true)
	result.ijfs_writeback = last_ijfs_writeback.to_dict() if last_ijfs_writeback != null else {}
	result.antiship_summary = last_antiship_summary.to_dict() if last_antiship_summary != null else {}
	result.offload_summary = last_offload_summary.duplicate(true)
	result.frontline_summary = last_frontline_summary.to_dict() if last_frontline_summary != null else {}
	result.cleanup_summary = last_cleanup_summary.to_dict() if last_cleanup_summary != null else {}
	result.events = TurnEventLog.build(self)
	result.game_over = game_over
	result.winner = winner
	return result


func _apply_order(order: Dictionary, team: Brigade.Team) -> void:
	var kind := String(order.get("kind", "move"))
	match kind:
		"move":
			var mode := String(order.get("mode", Movement.MODE_TACTICAL))
			add_move_order(team, String(order["brigade_id"]), String(order["target_hex"]), mode)
		"commit":
			add_commit_order(team, String(order["brigade_id"]), String(order["target_hex"]))
		"deploy_jlsf":
			if team == Brigade.Team.RED:
				jlsf_orders.append(String(order.get("port_id", "")))
			else:
				push_error("deploy_jlsf is a Red order")
		_:
			push_error("Unknown order kind: %s" % kind)


func _team_to_string(team: Brigade.Team) -> String:
	match team:
		Brigade.Team.GREEN:
			return "Green"
		_:
			return "Red"
