extends Node
class_name GameStateType

## Runtime-state autoload — now a thin shell (plan 0014): the mutable state itself lives in
## `data: GameStateData` (scripts/model/GameStateData.gd), the scenario-load builders in
## `GameStateBuilder`, turn orchestration in `TurnConductor` — with the arrival phases (sealift,
## offload, mobilization, air insertion) in `ReinforcementPhases`, the fires phases (IJFS, anti-ship)
## in `FiresPhases` and the end-of-turn accounting (supply, cleanup) in `TurnClosure`, plan 0038 —
## and order legality in `OrderValidator` (all static, all taking
## `GameStateData` — never this
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

# Read-only façade: turn and phase are written only by TurnLifecycleTransitions (plan 0049), which
# offers the three legal edges and no destination setter. These two setters were the widest hole in
# the gate — seventeen tools/validate_*.gd lines wrote GameState.turn_number, and the scan could not
# see any of them because the receiver resolves to GameStateType rather than GameStateData.
var turn_number: int:
	get: return data.turn_number
var phase: Phase:
	get: return data.phase
var turn_length_days: int:
	get: return data.turn_length_days
	set(value): data.turn_length_days = value
# Read-only façade: the four order queues are written only by OrderTransitions (plan 0049). A
# forwarding SETTER is a public door the mutation gate cannot see — the receiver resolves to
# GameStateType, not GameStateData — so the setters are gone rather than merely unused.
var orders: Dictionary:
	get: return data.orders
var commitments: Dictionary:
	get: return data.commitments
# Read-only façade: force transport storage is initialized and mutated only by ForceTransitions.
var ship_reserve: Array:
	get: return data.ship_reserve
# Read-only façade: the fleet is built by FleetBuilder and thereafter written only by
# SealiftTransitions (plan 0045). Scenario reset goes through _rebuild_fleet, not an assignment here.
var fleet: Dictionary:
	get: return data.fleet
# Read-only façade: the sealift state is built by SealiftStateBuilder and thereafter written only by
# SealiftTransitions (plan 0050). Scenario reset goes through _rebuild_sealift_state, not an
# assignment here — the setter had zero callers and was a public door around the authority, because
# the receiver of `GameState.sealift_state = x` resolves to GameStateType and the scan cannot see it.
var sealift_state: SealiftState:
	get: return data.sealift_state
# Read-only façade: the infrastructure map is built by InfrastructureStateBuilder and thereafter
# written only by InfrastructureTransitions (plan 0047). Scenario reset goes through
# _rebuild_infrastructure_state, not an assignment here.
var infrastructure_state: InfrastructureState:
	get: return data.infrastructure_state
var jlsf_orders: Array[String]:
	get: return data.jlsf_orders
# Read-only façade: the crossing's BN-equivalent ledger is written only by SealiftTransitions
# (plan 0050) — booked by the anti-ship phase, consumed and cleared by the offload phase.
var pending_lost_at_sea: int:
	get: return data.pending_lost_at_sea
# Read-only façade: the DOS pool is built by SupplyStateBuilder and thereafter written only by
# SupplyTransitions (plan 0049). Scenario reset goes through _rebuild_supply_state, not an assignment
# here — a setter would be a public door around the authority, which is how the fifteen validator
# writes to `GameState.turn_number` escaped the gate for so long.
var supply_state: SupplyState:
	get: return data.supply_state
var last_contested_hexes: Array[String]:
	get: return data.last_contested_hexes
	set(value): data.last_contested_hexes = value
var last_combat_summaries: Array[CombatSummary]:
	get: return data.last_combat_summaries
	set(value): data.last_combat_summaries = value
# Read-only: the IJFS state is built, replaced and dropped only by its mutation authority (plan
# 0046), reached through FiresPhases. A setter here would be a public door around it — and neither
# had a single caller.
var ijfs_state: IjfsDailyState:
	get: return data.ijfs_state
var _ijfs_day: int:
	get: return data._ijfs_day
var last_ijfs_summary: Dictionary:
	get: return data.last_ijfs_summary
	set(value): data.last_ijfs_summary = value
var last_ijfs_writeback: IjfsWriteback:
	get: return data.last_ijfs_writeback
	set(value): data.last_ijfs_writeback = value
# Read-only: the arsenal is built and replaced only by its mutation authority (plan 0043), reached
# through FiresPhases.reset_antiship_establishment. A setter here would be a public door around it.
var antiship_systems: Array:
	get: return data.antiship_systems
var antiship_containers: Array:
	get: return data.antiship_containers
# Read-only façade: the other half of that ledger — the fractional BN remainder carried to the next
# crossing. Same authority, same reason (plan 0050).
var lost_at_sea_accumulator: float:
	get: return data.lost_at_sea_accumulator
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
## Read-only: the schedule is replaced by _rebuild_mobilization_state, not by an assignment here
## (plan 0048 — the force authority owns this handle along with the model's fields).
var mobilization_state: MobilizationState:
	get: return data.mobilization_state
var last_mobilization_summary: MobilizationSummary:
	get: return data.last_mobilization_summary
	set(value): data.last_mobilization_summary = value
## Read-only: the pool and lift budgets are replaced by _rebuild_air_insertion_state, not by an
## assignment here (plan 0048 — AirInsertionTransitions owns this handle).
var air_insertion_state: AirInsertionState:
	get: return data.air_insertion_state
var last_air_insertion_summary: AirInsertionSummary:
	get: return data.last_air_insertion_summary
	set(value): data.last_air_insertion_summary = value
var air_insert_orders: Array:
	get: return data.air_insert_orders
# Read-only façade: the victory latches are applied together from one cleanup receipt.
var game_over: bool:
	get: return data.game_over
var winner: String:
	get: return data.winner


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

	TurnLifecycleTransitions.reset_to_turn_one(data)
	data.turn_length_days = GameData.turn_length_days
	if data.turn_length_days == 0:
		push_warning("GameData.turn_length_days is 0; falling back to 1 day")
		data.turn_length_days = 1
	OrderTransitions.reset_buffers(data)
	_rebuild_ship_reserve()
	_rebuild_sealift_state()
	_rebuild_fleet()
	_rebuild_supply_state()
	_rebuild_infrastructure_state()
	# IJFS state is lazy-loaded on the first resolve_ijfs_turn (it pulls ~500KB of pairings + many
	# Resource objects; eager-loading it in every booted process — validators, smoke, tests — bloated
	# shutdown and triggered the Godot 4.7 teardown crash). Reset the handle; resolve_ijfs_turn builds
	# it fresh per scenario.
	FiresPhases.reset_ijfs_state(data)
	data.last_contested_hexes.clear()
	data.last_combat_summaries.clear()
	data.last_ijfs_summary = {}
	data.last_ijfs_writeback = null
	data.last_ijfs_air_oob = {}
	# Anti-ship systems are lazily (re)built on first use (resolve_ijfs_turn / resolve_antiship_turn),
	# matching the IJFS state's lazy-load pattern; clearing here forces a fresh build per scenario.
	FiresPhases.reset_antiship_establishment(data)
	# The crossing ledger (pending_lost_at_sea / lost_at_sea_accumulator) is cleared by
	# _rebuild_sealift_state above: installing a fresh campaign sealift and clearing what the last
	# scenario's crossing drowned is one transition, owned by SealiftTransitions (plan 0050).
	data.last_antiship_summary = null
	data.last_sealift_sent_by_type = {}
	data.last_frontline_summary = null
	data.last_cleanup_summary = null
	_rebuild_mobilization_state()
	data.last_mobilization_summary = null
	_rebuild_air_insertion_state()
	data.last_air_insertion_summary = null
	EventBus.phase_changed.emit(data.phase)


func add_move_order(team: Brigade.Team, brigade_id: String, target_hex: String, mode: String) -> OrderResult:
	return OrderTransitions.add_move_order(
		data, GameData, team, OrderTransitions.move_order(brigade_id, target_hex, mode))


func add_air_insert_order(team: Brigade.Team, brigade_id: String, target_hex: String) -> OrderResult:
	return OrderTransitions.add_air_insert_order(data, GameData, team, brigade_id, target_hex)


## Public entry for the JLSF deployment order (plan 0049). It previously had none: the LLM boundary
## reached the buffer through the private `_apply_order`, which validated nothing.
func add_jlsf_order(team: Brigade.Team, port_id: String) -> OrderResult:
	return OrderTransitions.add_jlsf_order(data, GameData, team, port_id)


## Full WeGo turn resolution — delegates to TurnConductor (plan 0014 P3); see that class's header
## and inline comments for the phase-order/RNG-substream rationale.
func resolve_turn(dice: Dice = null) -> void:
	TurnConductor.resolve_turn(data, dice)


func add_commit_order(team: Brigade.Team, brigade_id: String, target_hex: String) -> OrderResult:
	return OrderTransitions.add_commit_order(
		data, GameData, team, OrderTransitions.commit_order(brigade_id, target_hex))


func eligible_commit_brigades(team: Brigade.Team, target_hex: String) -> Array:
	return OrderTransitions.eligible_commit_brigades(data, GameData, team, target_hex)


func begin_next_turn() -> void:
	if data.phase != Phase.END:
		push_error("Cannot begin next turn outside END phase")
		return

	for brigade in GameData.brigades.values():
		var typed_brigade: Brigade = brigade
		GameData.reset_brigade_turn_flags(typed_brigade)
	# The coordinator calls BOTH authorities; neither reaches into the other's fields.
	OrderTransitions.clear_turn_buffers(data)
	TurnLifecycleTransitions.begin_next_turn(data)
	EventBus.phase_changed.emit(data.phase)


func orders_for(team: Brigade.Team) -> Array:
	return data.orders[team]


func commitments_for(team: Brigade.Team) -> Array:
	return data.commitments[team]


func ship_reserve_priority_order() -> Array[String]:
	return ReinforcementPhases.ship_reserve_priority_order(data)


func resolve_offload_turn(dice: Dice) -> Dictionary:
	return ReinforcementPhases.resolve_unopposed_offload_turn(
		data, dice, GameStateBuilder.build_unopposed_offload_state(data.ship_reserve))


func _rebuild_infrastructure_state() -> void:
	ReinforcementPhases.rebuild_infrastructure(data, GameData.infrastructure)
	OrderTransitions.consume_jlsf_orders(data)


func resolve_supply_turn() -> Dictionary:
	return TurnClosure.resolve_supply_turn(data)


# --- IJFS (D4) — Red joint/air-missile fires daily phase ----------------------------------------

func resolve_ijfs_turn(dice: Dice) -> Dictionary:
	return FiresPhases.resolve_ijfs_turn(data, dice)


func resolve_antiship_turn(dice: Dice) -> Dictionary:
	return FiresPhases.resolve_antiship_turn(data, dice)


# --- D5-C Cleanup phase — end-of-turn per-system flag reset ------------------------------------

func resolve_cleanup_phase() -> Dictionary:
	return TurnClosure.resolve_cleanup_phase(data)


# --- D5-A Frontline phase — redistribute Red brigades along a drawn polyline -------------------

func resolve_frontline_phase(polyline_coords: Array) -> Dictionary:
	return FrontlinePhase.resolve_frontline_phase(data, polyline_coords)


## Green brigades held in mobilization by the scenario, plus their release schedule (plan 0029
## Tier A2). GameData.load_scenario already left them off-map; this only builds the schedule.
func _rebuild_mobilization_state() -> void:
	ReinforcementPhases.rebuild_mobilization_state(
		data, GameData.green_mobilization, GameData.mobilization_holdback)


## Test-called surface (tests/mobilization_*) — pure logic lives in
## ReinforcementPhases/MobilizationResolver.
func resolve_mobilization_turn() -> MobilizationSummary:
	return ReinforcementPhases.resolve_mobilization_turn(data)


## Red battalions waiting to fly plus the per-turn lift budgets (plan 0032). The PLAAF Airborne
## Corps is never placed by a scenario, so the pool is simply every unplaced air-lifted Red brigade.
func _rebuild_air_insertion_state() -> void:
	ReinforcementPhases.rebuild_air_insertion_state(
		data, GameData.red_air_insertion, GameData.brigades)


## Test-called surface (tests/air_insertion_*) — pure logic lives in
## ReinforcementPhases/AirInsertionResolver.
func resolve_air_insertion_turn(dice: Dice) -> AirInsertionSummary:
	return ReinforcementPhases.resolve_air_insertion_turn(data, dice)


func _rebuild_ship_reserve() -> void:
	ReinforcementPhases.initialize_ship_reserve(
		data, GameStateBuilder.build_ship_reserve(GameData.red_ship_reserve, GameData.brigades))


## Also clears the crossing ledger — see SealiftTransitions.install_campaign_state for why the two
## are one transition. Reached through ReinforcementPhases rather than the authority directly, like
## every other phase state this autoload resets.
func _rebuild_sealift_state() -> void:
	ReinforcementPhases.install_sealift_state(data, GameStateBuilder.build_sealift_state(
		GameData.red_followon_reserve, GameData.red_ship_reserve, GameData.brigades,
		GameData.auto_seed_followon_pool, GameData.escort_reload_time_turns))


## Sealift phase (plan 0004): advance the ship return pipeline and embark this turn's crossing wave.
## Dice-free and pure (SealiftResolver); this wrapper merges the newly-embarked BNs into the reserve,
## records the sailing fleet for the crossing, and reprojects the fleet ShipState bins from the
## advanced sealift state.
func resolve_sealift_turn() -> void:
	ReinforcementPhases.resolve_sealift_turn(data)


func _rebuild_supply_state() -> void:
	TurnClosure.rebuild_supply_state(data, float(GameData.red_dos_start))


func _rebuild_fleet() -> void:
	ReinforcementPhases.rebuild_fleet(data, GameData.ship_defs)


## Play a full turn from a bulk-order spec: buffers every order, resolves, and
## returns a typed TurnResult. The caller remains in Phase.END and must call
## begin_next_turn() separately to advance.
func play_turn(red_orders: Array, green_orders: Array, dice: Dice = null) -> TurnResult:
	if data.phase != Phase.PLANNING:
		push_error("play_turn requires PLANNING phase")
		return null

	# A rejected bulk order is REPORTED, not swallowed. The pre-0049 dispatcher returned void, so a
	# malformed order vanished silently; now that every entry point returns an OrderResult, dropping it
	# on the floor here would be a new silent failure — an unknown JLSF port id used to be appended and
	# is now refused, and a research run must not record that as a clean turn (found in diff review).
	for raw_order in red_orders:
		_report_rejected_bulk_order(apply_bulk_order(raw_order, Brigade.Team.RED), raw_order)
	for raw_order in green_orders:
		_report_rejected_bulk_order(apply_bulk_order(raw_order, Brigade.Team.GREEN), raw_order)

	resolve_turn(dice)

	var result := TurnResult.new()
	result.turn_number = data.turn_number
	result.contested_hexes = data.last_contested_hexes.duplicate()
	result.combat_summaries = data.last_combat_summaries.duplicate()
	result.ijfs_summary = data.last_ijfs_summary.duplicate(true)
	result.ijfs_writeback = data.last_ijfs_writeback.to_dict() if data.last_ijfs_writeback != null else {}
	result.air_oob = data.last_ijfs_air_oob.duplicate(true)
	result.antiship_summary = data.last_antiship_summary.to_dict() if data.last_antiship_summary != null else {}
	result.offload_summary = data.last_offload_summary.duplicate(true)
	result.mobilization_summary = data.last_mobilization_summary.to_dict() if data.last_mobilization_summary != null else {}
	result.air_insertion_summary = data.last_air_insertion_summary.to_dict() if data.last_air_insertion_summary != null else {}
	result.frontline_summary = data.last_frontline_summary.to_dict() if data.last_frontline_summary != null else {}
	result.cleanup_summary = data.last_cleanup_summary.to_dict() if data.last_cleanup_summary != null else {}
	result.events = TurnEventLog.build(self)
	result.game_over = data.game_over
	result.winner = data.winner
	return result


func _report_rejected_bulk_order(result: OrderResult, raw_order: Dictionary) -> void:
	if result == null or result.ok:
		return
	push_error("play_turn dropped a rejected %s order: %s" % [
		String(raw_order.get("kind", "move")), result.message])


## Apply one order from a bulk spec. The dispatcher itself lives on OrderTransitions so the bulk path
## and the four public wrappers above cannot drift apart.
func apply_bulk_order(order: Dictionary, team: Brigade.Team) -> OrderResult:
	return OrderTransitions.apply_bulk_order(data, GameData, order, team)


