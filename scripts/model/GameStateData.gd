extends RefCounted
class_name GameStateData

## Plain mutable runtime-state value object (plan 0014 P1, folded 0016): every field GameState used
## to carry directly now lives here. No engine/scene concerns, no autoload access, no logic — this
## is data only. GameState (autoload) owns a single `data := GameStateData.new()` and forwards the
## small set of fields/methods external callers read; TurnConductor/OrderValidator/GameStateBuilder
## (scripts/resolvers/) take an instance of this class as their first argument and mutate it
## in place. Building a GameStateData from scratch (no autoload) is what makes those resolvers
## unit-testable in isolation.

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
# ROC mobilization phase-in (plan 0029 Tier A2): Green brigades still forming plus their release
# schedule. Built at scenario load, drained by MobilizationResolver each turn between offload and
# movement. Empty pending list (the default) => the phase is a no-op.
var mobilization_state: MobilizationState = null
var last_mobilization_summary: MobilizationSummary = null
# PLAAF air insertion (plan 0032): the pool of Red battalions waiting to fly, the per-turn lift
# budgets, and this turn's drops. Built at scenario load, drained by AirInsertionResolver each turn
# at the same seam as the other reinforcement phases. Empty pool (the default) => the phase is a
# no-op that consumes no dice.
var air_insertion_state: AirInsertionState = null
var last_air_insertion_summary: AirInsertionSummary = null
# Pending air_insert orders for this planning phase: [{brigade_id, target_hex}] in issue order,
# which is also the order the shared per-class lift budget is spent in. Red-only.
var air_insert_orders: Array = []
# Air-landed brigades with no Red corridor back to a lodgement, brigade_id -> true. Recomputed ONCE
# per turn immediately before the combat loop (ownership is fixed for its duration) and read by
# every contested hex, rather than re-flooding the map per hex. Empty whenever nothing has air-landed.
var isolated_air_landed_brigades: Dictionary = {}
# Battalions belonging to an on-map brigade that are NOT ashore (plan 0037),
# brigade_id -> {battalion_type: count}. Recomputed ONCE per turn immediately before the combat loop,
# from pending_battalion_pools(), and read by every contested hex — combat fields only the landed
# remainder, and a brigade with nothing ashore is not a contributor at all. Empty until the first
# resolve_turn, and empty whenever every brigade is fully landed.
var not_ashore_by_type: Dictionary = {}
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
var _antiship_built: bool = false
# The turn whose launch attrition has already been booked onto the arsenal (-1 = none yet). At most
# one crossing resolves per turn, so this is the crossing's identity: it is what lets the anti-ship
# mutation authority refuse to apply the same result twice and double-kill launchers (plan 0043).
var _antiship_launch_turn: int = -1
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


## Every pool of battalions that belong to a brigade but are NOT ashore on Taiwan, in the shared
## {brigade_id, …, bns: […]} entry shape (plan 0034). The victory census subtracts all of them from
## each brigade's composition, because a brigade counts as present the moment its FIRST battalion
## lands while the rest is still in a pool.
##
## ADD NEW OFF-MAP POOLS HERE — this list is the only enumeration of them. A pool missing from it is
## silently counted as ashore, which credits its side with battalions that do not exist: the
## ghost-landing failure family (2026-07-24, commit bff4a1c), and the reason `mainland_pool` is in
## this list — SealiftResolver drains it partially, so a brigade can be ashore with battalions still
## waiting for a hull on the mainland.
func pending_battalion_pools() -> Array:
	var pools: Array = [ship_reserve]
	if sealift_state != null:
		pools.append(sealift_state.mainland_pool)
	if air_insertion_state != null:
		pools.append(air_insertion_state.pool)
	return pools


## Recompute `not_ashore_by_type` from the pools as they stand right now, and return it (plan 0037).
## Callers that need the map at a phase boundary other than the combat loop's — the supply bill, the
## end-of-turn roster check — call this rather than reading the cached field, because a pool can have
## drained since it was last refreshed.
func refresh_not_ashore_by_type() -> Dictionary:
	not_ashore_by_type = PendingBattalions.by_brigade_and_type(pending_battalion_pools())
	return not_ashore_by_type
