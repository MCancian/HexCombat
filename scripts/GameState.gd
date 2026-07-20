extends Node
class_name GameStateType

## Runtime-state autoload — now a thin shell (plan 0014): the mutable state itself lives in
## `data: GameStateData` (scripts/model/GameStateData.gd), the scenario-load builders in
## `GameStateBuilder`, turn orchestration in `TurnConductor`, and order legality in
## `OrderValidator` (all scripts/resolvers/, all static, all taking `GameStateData` — never this
## autoload — as their first argument). What remains here: the typed forwarding properties that
## keep the pre-refactor `GameState.<field>` API byte-stable for external callers, a handful of
## one-line delegating wrappers kept because GdUnit tests call them directly on the autoload, and
## `reset_to_scenario`/`begin_next_turn`/`play_turn` (the autoload's own lifecycle, not turn logic).

# IJFS (D4) data-source paths live on IjfsStateBuilder (their only consumer).

# D3/D4 data paths + phase knobs live on their resolvers (AntishipResolver, IjfsResolver,
# AntishipSystemsBuilder, IjfsStateBuilder) — each const sits with its only consumer.

# Re-exposed so external `GameStateType.Phase.*` / `GameState.Phase.*` references (tests, tools)
# keep resolving unchanged (plan 0014 P1) — the enum's home moved to GameStateData.
const Phase = GameStateData.Phase
# Re-exposed for the same reason (plan 0014 P3) — the constant's home moved to TurnConductor,
# its only real consumer.
const FEBA_RETREAT_THRESHOLD_KM = TurnConductor.FEBA_RETREAT_THRESHOLD_KM

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


func add_move_order(team: Brigade.Team, brigade_id: String, target_hex: String, mode: String) -> OrderResult:
	return OrderValidator.add_move_order(data, team, brigade_id, target_hex, mode)


## Full WeGo turn resolution — delegates to TurnConductor (plan 0014 P3); see that class's header
## and inline comments for the phase-order/RNG-substream rationale.
func resolve_turn(dice: Dice = null) -> void:
	TurnConductor.resolve_turn(data, dice)


func add_commit_order(team: Brigade.Team, brigade_id: String, target_hex: String) -> OrderResult:
	return OrderValidator.add_commit_order(data, team, brigade_id, target_hex)


func eligible_commit_brigades(team: Brigade.Team, target_hex: String) -> Array:
	return OrderValidator.eligible_commit_brigades(data, team, target_hex)


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
	return TurnConductor.resolve_offload_turn(data, dice)


func _rebuild_infrastructure_state() -> void:
	data.infrastructure_state = GameStateBuilder.build_infrastructure_state(GameData.infrastructure)
	data.jlsf_orders.clear()


func resolve_supply_turn() -> Dictionary:
	return TurnConductor.resolve_supply_turn(data)


# --- IJFS (D4) — Red joint/air-missile fires daily phase ----------------------------------------

func resolve_ijfs_turn(dice: Dice) -> Dictionary:
	return TurnConductor.resolve_ijfs_turn(data, dice)


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


## Test-called surface (tests/ijfs/*) — pure logic lives in TurnConductor.
func _rebuild_ijfs_state() -> void:
	TurnConductor.rebuild_ijfs_state(data)


## Test-called surface (tests/ijfs/ijfs_maneuver_posture_test.gd) — pure logic lives in TurnConductor.
func _update_maneuver_posture() -> void:
	TurnConductor.update_maneuver_posture(data)


## Test-called surface (tests/ijfs/ijfs_maneuver_sync_test.gd) — pure logic lives in TurnConductor.
func _sync_maneuver_targets_to_oob() -> void:
	TurnConductor.sync_maneuver_targets_to_oob(data)


## Test-called surface (tests/ijfs/ijfs_maneuver_consume_test.gd) — pure logic lives in TurnConductor.
func _apply_ijfs_maneuver_casualties() -> void:
	TurnConductor.apply_ijfs_maneuver_casualties(data)


func resolve_antiship_turn(dice: Dice) -> Dictionary:
	return TurnConductor.resolve_antiship_turn(data, dice)


## Test-called surface (tests/mine_neutralization_override_test.gd) — pure logic lives in
## AntishipResolver; no GameStateData involved (unaffected by plan 0014 P3).
func _mine_ship_meta(transit_config: Dictionary) -> Dictionary:
	return AntishipResolver.mine_ship_meta(GameData.ship_defs, transit_config)


# --- D5-C Cleanup phase — end-of-turn per-system flag reset ------------------------------------

func resolve_cleanup_phase() -> Dictionary:
	return TurnConductor.resolve_cleanup_phase(data)


## Test-called surface (tests/victory_present_census_test.gd) — pure logic lives in TurnConductor.
func _taiwan_battalion_census() -> Dictionary:
	return TurnConductor.taiwan_battalion_census(data)


# --- D5-A Frontline phase — redistribute Red brigades along a drawn polyline -------------------

func resolve_frontline_phase(polyline_coords: Array) -> Dictionary:
	return TurnConductor.resolve_frontline_phase(data, polyline_coords)


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
	TurnConductor.resolve_sealift_turn(data)


func _rebuild_supply_state() -> void:
	data.supply_state = GameStateBuilder.build_supply_state(float(GameData.red_dos_start))


func _rebuild_fleet() -> void:
	data.fleet = GameStateBuilder.build_fleet(GameData.ship_defs)


## Delegating wrapper (test-called surface: tests/supply_combat_effectiveness_test.gd) — pure
## logic lives in TurnConductor / CombatResolver.
func _inject_supply_effectiveness(units: Array, team: int) -> void:
	TurnConductor.inject_supply_effectiveness(data, units, team)


## Delegating wrapper (test-called surface: tests/composition_test.gd) — pure logic lives in
## TurnConductor.
func _combat_contributors_for(team: Brigade.Team, hex_id: String) -> Array:
	return TurnConductor.combat_contributors_for(data, team, hex_id)


# Delegating wrapper (test-called surface) — pure logic lives in CombatResolver.
func _brigade_ids(brigades: Array) -> Array[String]:
	return CombatResolver.brigade_ids(brigades)


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


