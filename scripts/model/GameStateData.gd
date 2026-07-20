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
