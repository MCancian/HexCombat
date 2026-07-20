extends Node
class_name GameStateType

const MoveOrderResource = preload("res://scripts/model/MoveOrder.gd")
const CommitOrderResource = preload("res://scripts/model/CommitOrder.gd")
const FEBA_RETREAT_THRESHOLD_KM := 10.0

# IJFS (D4) data-source paths live on IjfsStateBuilder (their only consumer).

# D3/D4 data paths + phase knobs live on their resolvers (AntishipResolver, IjfsResolver,
# AntishipSystemsBuilder, IjfsStateBuilder) — each const sits with its only consumer.

# Re-exposed so external `GameStateType.Phase.*` / `GameState.Phase.*` references (tests, tools)
# keep resolving unchanged (plan 0014 P1) — the enum's home moved to GameStateData.
const Phase = GameStateData.Phase

# Mutable runtime state lives in this single value object (plan 0014 P1, folded 0016) — see
# scripts/model/GameStateData.gd. GameState (this autoload) forwards the fields external callers
# read/write via the typed properties below, so `GameState.turn_number` etc. keep working
# unchanged. Internal code in this file always goes through `data.<field>` explicitly — the
# properties below exist ONLY for the autoload's public surface (GameController, tests,
# tools/validate_*.gd). Declared `var name: Type: get/set` (not a generic _get/_set override)
# because a generic override can't distinguish a legitimately-null field (e.g.
# last_antiship_summary before the first antiship phase) from "property does not exist".
var data := GameStateData.new()

var turn_number: int:
	get: return data.turn_number
	set(value): data.turn_number = value
var phase: Phase:
	get: return data.phase
	set(value): data.phase = value
var turn_length_days: int:
	get: return data.turn_length_days
	set(value): data.turn_length_days = value
var orders: Dictionary:
	get: return data.orders
	set(value): data.orders = value
var commitments: Dictionary:
	get: return data.commitments
	set(value): data.commitments = value
var ship_reserve: Array:
	get: return data.ship_reserve
	set(value): data.ship_reserve = value
var fleet: Dictionary:
	get: return data.fleet
	set(value): data.fleet = value
var sealift_state: SealiftState:
	get: return data.sealift_state
	set(value): data.sealift_state = value
var infrastructure_state: InfrastructureState:
	get: return data.infrastructure_state
	set(value): data.infrastructure_state = value
var jlsf_orders: Array[String]:
	get: return data.jlsf_orders
	set(value): data.jlsf_orders = value
var pending_lost_at_sea: int:
	get: return data.pending_lost_at_sea
	set(value): data.pending_lost_at_sea = value
var supply_state: SupplyState:
	get: return data.supply_state
	set(value): data.supply_state = value
var last_contested_hexes: Array[String]:
	get: return data.last_contested_hexes
	set(value): data.last_contested_hexes = value
var last_combat_summaries: Array[CombatSummary]:
	get: return data.last_combat_summaries
	set(value): data.last_combat_summaries = value
var ijfs_state: IjfsDailyState:
	get: return data.ijfs_state
	set(value): data.ijfs_state = value
var _ijfs_day: int:
	get: return data._ijfs_day
	set(value): data._ijfs_day = value
var last_ijfs_summary: Dictionary:
	get: return data.last_ijfs_summary
	set(value): data.last_ijfs_summary = value
var last_ijfs_writeback: IjfsWriteback:
	get: return data.last_ijfs_writeback
	set(value): data.last_ijfs_writeback = value
var antiship_systems: Array:
	get: return data.antiship_systems
	set(value): data.antiship_systems = value
var antiship_containers: Array:
	get: return data.antiship_containers
	set(value): data.antiship_containers = value
var lost_at_sea_accumulator: float:
	get: return data.lost_at_sea_accumulator
	set(value): data.lost_at_sea_accumulator = value
var last_antiship_summary: AntishipSummary:
	get: return data.last_antiship_summary
	set(value): data.last_antiship_summary = value
var last_offload_summary: Dictionary:
	get: return data.last_offload_summary
	set(value): data.last_offload_summary = value
var last_sealift_sent_by_type: Dictionary:
	get: return data.last_sealift_sent_by_type
	set(value): data.last_sealift_sent_by_type = value
var last_frontline_summary: FrontlineSummary:
	get: return data.last_frontline_summary
	set(value): data.last_frontline_summary = value
var last_cleanup_summary: CleanupSummary:
	get: return data.last_cleanup_summary
	set(value): data.last_cleanup_summary = value
var game_over: bool:
	get: return data.game_over
	set(value): data.game_over = value
var winner: String:
	get: return data.winner
	set(value): data.winner = value


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

	data.turn_number = 1
	data.phase = Phase.PLANNING
	data.turn_length_days = GameData.turn_length_days
	if data.turn_length_days == 0:
		push_warning("GameData.turn_length_days is 0; falling back to 1 day")
		data.turn_length_days = 1
	data.orders = {
		Brigade.Team.RED: [],
		Brigade.Team.GREEN: []
	}
	data.commitments = {
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
	data.ijfs_state = null
	data._ijfs_day = 0
	data.pending_lost_at_sea = 0
	data.last_contested_hexes.clear()
	data.last_combat_summaries.clear()
	data.last_ijfs_summary = {}
	data.last_ijfs_writeback = null
	# Anti-ship systems are lazily (re)built on first use (resolve_ijfs_turn / resolve_antiship_turn),
	# matching the IJFS state's lazy-load pattern; clearing here forces a fresh build per scenario.
	data.antiship_systems = []
	data.antiship_containers = []
	data._antiship_built = false
	data.lost_at_sea_accumulator = 0.0
	data.last_antiship_summary = null
	data.last_sealift_sent_by_type = {}
	data.last_frontline_summary = null
	data.last_cleanup_summary = null
	data.game_over = false
	data.winner = ""
	data._china_has_landed = false
	EventBus.phase_changed.emit(data.phase)


func add_move_order(team: Brigade.Team, brigade_id: String, target_hex: String, mode: String) -> void:
	if data.phase != Phase.PLANNING:
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

	for pending_order in data.orders[team]:
		var typed_pending_order: MoveOrder = pending_order
		if typed_pending_order.brigade_id == brigade_id:
			push_error("Brigade already has a pending move order this turn: %s" % brigade_id)
			return
	for pending_commitment in data.commitments[team]:
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
	data.orders[team].append(order)


func resolve_turn(dice: Dice = null) -> void:
	if data.phase != Phase.PLANNING:
		push_error("Cannot resolve turn outside PLANNING phase")
		return

	if dice == null:
		dice = SeededDice.new(data.turn_number)

	data.phase = Phase.RESOLUTION
	EventBus.phase_changed.emit(data.phase)
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
	data.last_offload_summary = resolve_offload_turn(dice)

	# disable_phases (plan 0012): a scenario/override can skip the ground WeGo phases wholesale so
	# calibration sweeps run standard games while isolating the sea/IJFS phases. Buffered orders
	# simply never execute; skipping consumes no dice, so an empty list is byte-identical.
	var skip_movement := GameData.disabled_phases.has("movement")
	var skip_ground_combat := GameData.disabled_phases.has("ground_combat")
	if not skip_movement:
		_apply_move_orders(Brigade.Team.RED)
		_apply_move_orders(Brigade.Team.GREEN)
	if skip_ground_combat:
		data.last_contested_hexes.clear()
	else:
		data.last_contested_hexes = _find_contested_hexes()
	var combat_summaries: Array[CombatSummary] = []
	# Per-hex combat substream (plan 0010): each contested hex draws from its OWN dice stream derived
	# from the root turn seed, so a design tweak that changes the roll count in one hex's fight never
	# scrambles the dice of an unrelated hex. Turn-scoped salt matches the ijfs/antiship pattern so an
	# injected constant-seed dice still varies per turn.
	for hex_id in data.last_contested_hexes:
		var summary := _resolve_combat_at(hex_id, dice.derive("combat:%d:%s" % [data.turn_number, hex_id]))
		if summary != null:
			combat_summaries.append(summary)
	if not skip_ground_combat:
		_apply_feba_retreats()
	GameData.recompute_hex_ownership()
	for summary in combat_summaries:
		summary.owner_after = String(GameData.hex_states[summary.hex_id].owner)
	data.last_combat_summaries = combat_summaries.duplicate()
	resolve_supply_turn()
	resolve_cleanup_phase()

	# Debug-only invariant (refactor item 4): at the settled end of a turn the brigade↔hex indexes
	# must be consistent. Gated on OS.is_debug_build() so the validator is never called in release;
	# in debug/test/headless runs it fails loud on any silent index desync. End-of-turn only (a settled
	# boundary) — NOT the per-mutator hot path, which can hold benign transient desync mid-resolution.
	if OS.is_debug_build():
		var index_violations := GameData.validate_runtime_indexes()
		assert(index_violations.is_empty(), "runtime index desync at end of resolve_turn: %s" % "; ".join(index_violations))

	data.phase = Phase.END
	EventBus.phase_changed.emit(data.phase)
	EventBus.combat_resolved.emit(combat_summaries)
	EventBus.turn_resolved.emit(data.turn_number)


func add_commit_order(team: Brigade.Team, brigade_id: String, target_hex: String) -> void:
	if data.phase != Phase.PLANNING:
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

	for pending_order in data.orders[team]:
		var typed_pending_order: MoveOrder = pending_order
		if typed_pending_order.brigade_id == brigade_id:
			push_error("Brigade already has a pending move order this turn: %s" % brigade_id)
			return
	for pending_commitment in data.commitments[team]:
		var typed_pending_commitment: CommitOrder = pending_commitment
		if typed_pending_commitment.brigade_id == brigade_id:
			push_error("Brigade already has a pending commit order this turn: %s" % brigade_id)
			return

	var order: CommitOrder = CommitOrderResource.new()
	order.brigade_id = brigade_id
	order.target_hex = target_hex
	data.commitments[team].append(order)


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
	if data.phase != Phase.END:
		push_error("Cannot begin next turn outside END phase")
		return

	for brigade in GameData.brigades.values():
		var typed_brigade: Brigade = brigade
		typed_brigade.moved_this_turn = false
		typed_brigade.moved_admin_this_turn = false
		typed_brigade.fought_this_turn = false
	data.orders[Brigade.Team.RED].clear()
	data.orders[Brigade.Team.GREEN].clear()
	data.commitments[Brigade.Team.RED].clear()
	data.commitments[Brigade.Team.GREEN].clear()
	data.turn_number += 1
	data.phase = Phase.PLANNING
	EventBus.phase_changed.emit(data.phase)


func orders_for(team: Brigade.Team) -> Array:
	return data.orders[team]


func commitments_for(team: Brigade.Team) -> Array:
	return data.commitments[team]


func ship_reserve_priority_order() -> Array[String]:
	return OffloadResolver.priority_order(data.ship_reserve)


func resolve_offload_turn(dice: Dice) -> Dictionary:
	assert(dice != null, "resolve_offload_turn requires a Dice instance")
	# Infrastructure lifecycle ticks every offload phase (plan 0006), even with an empty reserve:
	# ground combat can seize a port hex long after the last beach landing. Ownership here is last
	# turn's post-combat state — the producer->consumer edge is combat ownership -> next offload.
	var infra_nodes: Array = []
	if data.infrastructure_state != null:
		var owner_by_hex := _owner_by_hex()
		InfrastructureResolver.tick(data.infrastructure_state, GameData.infrastructure, owner_by_hex)
		infra_nodes = InfrastructureResolver.red_offload_nodes(data.infrastructure_state, GameData.infrastructure, owner_by_hex)

	if data.ship_reserve.is_empty():
		var empty_manifest := _empty_offload_manifest()
		empty_manifest["lost_at_sea"] = data.pending_lost_at_sea
		# D3-F applies lost_at_sea to the reserve; D0-C only threads the value.
		data.pending_lost_at_sea = 0
		EventBus.offload_resolved.emit(empty_manifest)
		return empty_manifest

	var cost_config: Dictionary = GameData.offload_weights if GameData.use_offload_weight_matrix else {}
	var outcome := OffloadResolver.resolve(
		data.turn_number, data.ship_reserve, GameData.beaches, GameData.brigades,
		infra_nodes, cost_config, GameData.beach_to_to, _owner_by_hex())
	for landing_value in outcome["landings"]:
		var landing: Dictionary = landing_value
		var brigade_id := String(landing["brigade_id"])
		GameData.set_brigade_hex(brigade_id, String(landing["beach_hex"]))
		GameData.get_brigade(brigade_id).entry_bearing = float(landing["offset_bearing"])
	data.ship_reserve = outcome["remaining_ship_reserve"]
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
		if data.infrastructure_state != null and data.infrastructure_state.nodes.has(port_id):
			data.infrastructure_state.nodes[port_id]["jlsf"] = InfrastructureState.JLSF_ARRIVED
		for bn_id_value in arrival["bn_ids"]:
			landed_ids.append(String(bn_id_value))
	if data.sealift_state != null:
		SealiftResolver.drain_bn_ids(data.sealift_state, landed_ids, GameData.amphibious_return_time_turns)
		_project_sealift_onto_fleet()
	_reconcile_lost_jlsf()

	manifest["lost_at_sea"] = data.pending_lost_at_sea
	# D3-F applies lost_at_sea to the reserve; D0-C only threads the value.
	data.pending_lost_at_sea = 0
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
	data.infrastructure_state = GameStateBuilder.build_infrastructure_state(GameData.infrastructure)
	data.jlsf_orders.clear()


## A JLSF deployment lost whole at sea (its pseudo-BNs all drowned in the crossing) leaves no
## pool or reserve trace; reset its node marker so a new deployment can be ordered/auto-queued.
func _reconcile_lost_jlsf() -> void:
	if data.infrastructure_state == null:
		return
	for id_value in data.infrastructure_state.nodes.keys():
		var node: Dictionary = data.infrastructure_state.nodes[id_value]
		var marker := String(node["jlsf"])
		if marker != InfrastructureState.JLSF_QUEUED and marker != InfrastructureState.JLSF_ENROUTE:
			continue
		var brigade_id := JlsfCargo.brigade_id_for(String(id_value))
		if not _reserve_or_pool_has(brigade_id):
			node["jlsf"] = InfrastructureState.JLSF_NONE


func _reserve_or_pool_has(brigade_id: String) -> bool:
	for entry_value in data.ship_reserve:
		if String((entry_value as Dictionary).get("brigade_id", "")) == brigade_id:
			return true
	if data.sealift_state != null:
		for entry_value in data.sealift_state.mainland_pool:
			if String((entry_value as Dictionary).get("brigade_id", "")) == brigade_id:
				return true
	return false


func resolve_supply_turn() -> Dictionary:
	assert(data.supply_state != null, "resolve_supply_turn requires supply_state")
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

	var summary := SupplyResolver.resolve(data.supply_state, units, moved_ids, engaged_ids, data.turn_number)
	EventBus.supply_updated.emit(summary)
	return summary


# --- IJFS (D4) — Red joint/air-missile fires daily phase ----------------------------------------

func resolve_ijfs_turn(dice: Dice) -> Dictionary:
	assert(dice != null, "resolve_ijfs_turn requires a Dice instance")
	if data.ijfs_state == null:
		_rebuild_ijfs_state()
	var outcome := IjfsResolver.resolve(data.ijfs_state, GameData.brigades, data.turn_number, data._ijfs_day, dice)
	data._ijfs_day = data.turn_number
	var ledgers: Dictionary = outcome["ledgers"]
	data.last_ijfs_summary = ledgers["summary"]
	data.last_ijfs_writeback = outcome["writeback"]
	EventBus.ijfs_resolved.emit(data.last_ijfs_summary)
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
	if data._antiship_built:
		return
	var built := GameStateBuilder.build_antiship_systems()
	data.antiship_systems = built["systems"]
	data.antiship_containers = built["containers"]
	data._antiship_built = true


func _rebuild_ijfs_state() -> void:
	# Anti-ship systems must exist first (their containers seed the per-(TO,type) IJFS targets).
	_ensure_antiship_systems()
	data.ijfs_state = GameStateBuilder.build_ijfs_state(data.antiship_containers, GameData.brigades)
	data._ijfs_day = 0


func _update_maneuver_posture() -> void:
	IjfsResolver.update_maneuver_posture(data.ijfs_state, GameData.brigades)


func _sync_maneuver_targets_to_oob() -> void:
	IjfsResolver.sync_maneuver_targets_to_oob(data.ijfs_state, GameData.brigades)


func _apply_ijfs_maneuver_casualties() -> void:
	var casualties: Array = data.last_ijfs_writeback.maneuver_casualties if data.last_ijfs_writeback != null else []
	IjfsResolver.apply_maneuver_casualties(casualties, GameData.brigades)


## D3-D: Green coastal anti-ship fires + mine warfare against the Red amphibious crossing. Threads the
## firing plan (D3-B2) -> crossing (D3-B3) -> mines (D3-C); ship losses convert to BNs lost at sea
## (ShipLoadingModel) and feed register_ship_losses (the D0-C seam offload consumes). Runs after IJFS
## (Green systems suppressed/destroyed first) and before offload (only survivors land). Draws from an
## INDEPENDENT substream so the ground-combat golden invariant stays byte-stable.
func resolve_antiship_turn(dice: Dice) -> Dictionary:
	_ensure_antiship_systems()
	data.last_antiship_summary = null

	# Independent substream (same isolation pattern as resolve_ijfs_turn). SeededDice.derive is a
	# pure hash of (seed, label) — it consumes no parent-stream state, so deriving before the
	# resolver's no-wave check cannot shift the base combat stream.
	var as_dice: Dice
	if dice is SeededDice:
		as_dice = dice.derive("antiship:%d" % data.turn_number)
	else:
		as_dice = SeededDice.new(hash("antiship:%d" % data.turn_number))

	# Theaters reads the GameData autoload internally, so the TO maps are materialized here and
	# passed into the pure resolver as plain data.
	var to_adjacency: Dictionary = {}
	for to_num in GameData.active_tos:
		to_adjacency[to_num] = Theaters.adjacent_tos(to_num)

	# Only the BNs sailing this turn (the sealift "sent" cohorts) cross and take attrition; offloading
	# BNs are safe ashore. Slice that crossing wave out of the full reserve (plan 0004 D3).
	var crossing_reserve := _crossing_reserve_from_sent_cohorts()
	# Captured pre-resolve: drain/flip below mutate the cohorts before the summary is stored.
	var wave_bns: int = SealiftResolver.sent_cohort_bn_ids(data.sealift_state).size()

	var outcome := AntishipResolver.resolve(
		data.turn_number, crossing_reserve, data.antiship_systems, data.last_ijfs_writeback,
		data.last_sealift_sent_by_type, GameData.ship_defs, GameData.beach_to_to, GameData.active_tos, to_adjacency,
		data.lost_at_sea_accumulator, data.sealift_state.escort_sam, as_dice)
	if outcome["summary"] == null:
		# Nothing crossed this turn: no fires, no state to apply (pending_lost_at_sea keeps its value).
		return {}

	data.lost_at_sea_accumulator = float(outcome["accumulator"])
	# Apply hull losses to the sealift cohorts (carriers) + the fleet, then drop drowned BNs from the
	# reserve AND their cohorts, and flip the surviving crossers to offloading (plan 0004 D3).
	_apply_crossing_hull_losses(outcome["destroyed_by_type"])
	var lost_ids: Array = outcome["lost_ids"]
	data.ship_reserve = AntishipResolver.remaining_reserve_after_losses(data.ship_reserve, lost_ids)
	SealiftResolver.drain_bn_ids(data.sealift_state, lost_ids, GameData.amphibious_return_time_turns)
	SealiftResolver.flip_sent_to_offloading(data.sealift_state)
	# Deplete the escort SAM magazines by what fired, and divert any type that dropped to/below its
	# reload threshold (plan 0004 D5). No-op when the magazine is unmodelled (escort_sam empty).
	SealiftResolver.apply_escort_consumption(
		data.sealift_state, outcome["escort_sam_consumed"], GameData.escort_reload_time_turns)
	_project_sealift_onto_fleet()
	register_ship_losses(int(outcome["bn_equiv_lost"]))
	data.last_antiship_summary = outcome["summary"]
	data.last_antiship_summary.wave_bns = wave_bns
	EventBus.antiship_resolved.emit(data.last_antiship_summary.to_dict())
	return data.last_antiship_summary.to_dict()


## The subset of ship_reserve whose BNs are bound to a "sent" cohort (crossing this turn), with each
## kept entry trimmed to just those BNs. Empty when nothing sails.
func _crossing_reserve_from_sent_cohorts() -> Array:
	var sailing := SealiftResolver.sent_cohort_bn_ids(data.sealift_state)
	if sailing.is_empty():
		return []
	var crossing: Array = []
	for entry_value in data.ship_reserve:
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
		var state: ShipState = data.fleet.get(ship_type, null)
		if state == null:
			continue
		# Carriers (capacity > 0) lose hulls out of their cohorts; escorts out of the ready screen.
		var ship_def: ShipDef = GameData.ship_defs_by_name.get(ship_type, null)
		var applied: int
		if ship_def != null and ship_def.is_carrier():
			applied = SealiftResolver.remove_carrier_hulls(data.sealift_state, ship_type, requested)
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
		data.antiship_systems, GameData.brigades, data.ship_reserve, GameData.victory_config,
		data.turn_number, data._china_has_landed)
	data._china_has_landed = bool(outcome["china_has_landed"])
	data.last_cleanup_summary = outcome["summary"]
	data.game_over = data.last_cleanup_summary.game_over
	data.winner = data.last_cleanup_summary.winner
	EventBus.cleanup_resolved.emit(data.last_cleanup_summary.to_dict())
	return data.last_cleanup_summary.to_dict()


func _taiwan_battalion_census() -> Dictionary:
	return CleanupResolver.census(GameData.brigades, data.ship_reserve, GameData.victory_config)


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

	data.last_frontline_summary = FrontlineResolver.resolve(polyline_coords, _frontline_hex_centers(), candidate_brigades)
	for brigade_id in data.last_frontline_summary.moves.keys():
		GameData.set_brigade_hex(String(brigade_id), String(data.last_frontline_summary.moves[brigade_id]))
	EventBus.frontline_resolved.emit(data.last_frontline_summary.to_dict())
	return data.last_frontline_summary.to_dict()


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
	data.ship_reserve = GameStateBuilder.build_ship_reserve(GameData.red_ship_reserve, GameData.brigades)


func _rebuild_sealift_state() -> void:
	data.sealift_state = GameStateBuilder.build_sealift_state(
		GameData.red_followon_reserve, GameData.red_ship_reserve, GameData.brigades,
		GameData.auto_seed_followon_pool, GameData.escort_reload_time_turns)


## Sealift phase (plan 0004): advance the ship return pipeline and embark this turn's crossing wave.
## Dice-free and pure (SealiftResolver); this wrapper merges the newly-embarked BNs into the reserve,
## records the sailing fleet for the crossing, and reprojects the fleet ShipState bins from the
## advanced sealift state.
func resolve_sealift_turn() -> void:
	if data.sealift_state == null:
		return
	var ready_by_type: Dictionary = {}
	for ship_type in data.fleet.keys():
		ready_by_type[String(ship_type)] = int((data.fleet[ship_type] as ShipState).ready)

	_consume_jlsf_orders()
	var outcome := SealiftResolver.resolve(
		data.sealift_state, data.ship_reserve, ready_by_type, GameData.ship_defs)

	for entry_value in outcome["embarked_reserve_entries"]:
		var entry: Dictionary = entry_value
		# A JLSF deployment that got hulls this turn is now enroute (plan 0006).
		if JlsfCargo.is_jlsf_entry(entry) and data.infrastructure_state != null:
			var port_id := String(entry.get("port_id", ""))
			if data.infrastructure_state.nodes.has(port_id):
				data.infrastructure_state.nodes[port_id]["jlsf"] = InfrastructureState.JLSF_ENROUTE
		_merge_reserve_entry(entry)
	data.last_sealift_sent_by_type = outcome["sent_by_type"]
	_project_sealift_onto_fleet()


## Consume the deploy_jlsf order buffer through the JlsfCargo queueing policy (plan 0006). New
## pseudo-entries go to the FRONT of the mainland pool (logistics open the port gate before more
## troops help); JlsfCargo.queue_deployments owns ordering + marker flips.
func _consume_jlsf_orders() -> void:
	if data.infrastructure_state == null or data.sealift_state == null:
		data.jlsf_orders.clear()
		return
	var entries := JlsfCargo.queue_deployments(
		data.jlsf_orders, data.infrastructure_state, GameData.infrastructure, GameData.beaches,
		GameData.beach_to_to, GameData.auto_jlsf, GameData.jlsf_lift_bn_equiv)
	data.jlsf_orders.clear()
	for entry in entries:
		data.sealift_state.mainland_pool.push_front(entry)


## Merge a newly-embarked reserve entry into ship_reserve: append its BNs to the brigade's existing
## entry (a follow-on brigade already partway across) or add a new entry.
func _merge_reserve_entry(entry_value) -> void:
	var entry: Dictionary = entry_value
	var brigade_id := String(entry["brigade_id"])
	for existing_value in data.ship_reserve:
		var existing: Dictionary = existing_value
		if String(existing["brigade_id"]) == brigade_id:
			(existing["bns"] as Array).append_array(entry["bns"])
			return
	data.ship_reserve.append(entry)


## Reproject the fleet ShipState bins from the sealift state (the single source of truth for where
## hulls are): surviving_sent/offloading from cohorts, returning from the pipeline, ready as the
## remainder of the surviving fleet. Keeps ShipState.validate()'s invariants honest (plan 0004).
func _project_sealift_onto_fleet() -> void:
	var sent: Dictionary = {}
	var offloading: Dictionary = {}
	var returning: Dictionary = {}
	for cohort_value in data.sealift_state.cohorts:
		var cohort: Dictionary = cohort_value
		var bucket: Dictionary = sent if String(cohort["state"]) == SealiftState.STATE_SENT else offloading
		for ship_type in (cohort["hulls_by_type"] as Dictionary).keys():
			bucket[String(ship_type)] = int(bucket.get(String(ship_type), 0)) + int(cohort["hulls_by_type"][ship_type])
	for ship_type in data.sealift_state.return_pipeline.keys():
		for slot_value in (data.sealift_state.return_pipeline[ship_type] as Array):
			returning[String(ship_type)] = int(returning.get(String(ship_type), 0)) + int((slot_value as Dictionary)["count"])
	# Escort types reloading SAMs are away from the screen: all their surviving hulls are busy
	# (returning) until reload completes (plan 0004 D5).
	for ship_type in data.sealift_state.escort_reload.keys():
		var reloading_state: ShipState = data.fleet.get(String(ship_type), null)
		if reloading_state != null:
			returning[String(ship_type)] = int(returning.get(String(ship_type), 0)) + reloading_state.fleet_surviving_total

	for ship_type in data.fleet.keys():
		var state: ShipState = data.fleet[ship_type]
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
	data.supply_state = GameStateBuilder.build_supply_state(float(GameData.red_dos_start))


func register_ship_losses(bn_equiv_lost: int) -> void:
	data.pending_lost_at_sea = maxi(0, bn_equiv_lost)


func _rebuild_fleet() -> void:
	data.fleet = GameStateBuilder.build_fleet(GameData.ship_defs)


func _apply_move_orders(team: Brigade.Team) -> void:
	for order in data.orders[team]:
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
	var pool: float = data.supply_state.current_dos_tons if data.supply_state != null else 1.0
	CombatResolver.inject_supply_effectiveness(units, team, pool, GameData.red_out_of_supply_effectiveness)


# Thin wrapper: gathers contributors (board/commitment state), delegates the dice-consuming combat
# core to CombatResolver.resolve_at, then applies the result — casualties, FEBA accumulation,
# fought flags — and stamps owner_after. Application stays here because combat at one hex mutates
# state the next hex's contributor gathering reads (ported interleaving semantics).
func _resolve_combat_at(hex_id: String, dice: Dice) -> CombatSummary:
	var attacker_brigades := _combat_contributors_for(Brigade.Team.RED, hex_id)
	var defender_brigades := _combat_contributors_for(Brigade.Team.GREEN, hex_id)
	var pool: float = data.supply_state.current_dos_tons if data.supply_state != null else 1.0
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

	for commitment_value in data.commitments[team]:
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
	for pending_order in data.orders[team]:
		var typed_pending_order: MoveOrder = pending_order
		if typed_pending_order.brigade_id == brigade_id:
			return true
	for pending_commitment in data.commitments[team]:
		var typed_pending_commitment: CommitOrder = pending_commitment
		if typed_pending_commitment.brigade_id == brigade_id:
			return true
	return false


func _apply_feba_retreats() -> void:
	for hex_id in data.last_contested_hexes:
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
	if data.phase != Phase.PLANNING:
		push_error("play_turn requires PLANNING phase")
		return null

	for raw_order in red_orders:
		_apply_order(raw_order, Brigade.Team.RED)
	for raw_order in green_orders:
		_apply_order(raw_order, Brigade.Team.GREEN)

	resolve_turn(dice)

	var result := TurnResult.new()
	result.turn_number = data.turn_number
	result.contested_hexes = data.last_contested_hexes.duplicate()
	result.combat_summaries = data.last_combat_summaries.duplicate()
	result.ijfs_summary = data.last_ijfs_summary.duplicate(true)
	result.ijfs_writeback = data.last_ijfs_writeback.to_dict() if data.last_ijfs_writeback != null else {}
	result.antiship_summary = data.last_antiship_summary.to_dict() if data.last_antiship_summary != null else {}
	result.offload_summary = data.last_offload_summary.duplicate(true)
	result.frontline_summary = data.last_frontline_summary.to_dict() if data.last_frontline_summary != null else {}
	result.cleanup_summary = data.last_cleanup_summary.to_dict() if data.last_cleanup_summary != null else {}
	result.events = TurnEventLog.build(self)
	result.game_over = data.game_over
	result.winner = data.winner
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
				data.jlsf_orders.append(String(order.get("port_id", "")))
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
