extends Node
class_name GameStateType

const MoveOrderResource = preload("res://scripts/model/MoveOrder.gd")
const CommitOrderResource = preload("res://scripts/model/CommitOrder.gd")
const ShipStateResource = preload("res://scripts/model/ShipState.gd")
const SupplyStateResource = preload("res://scripts/model/SupplyState.gd")
const FEBA_RETREAT_THRESHOLD_KM := 10.0

# IJFS (D4) data sources — Red joint/air-missile fires phase.
const IJFS_TARGETS_PATH := "res://data/ijfs/targets_master.json"
const IJFS_MUNITIONS_PATH := "res://data/ijfs/red_munitions.json"
const IJFS_PAIRINGS_PATH := "res://data/ijfs/munition_target_pairings.json"
const IJFS_SCENARIO_PATH := "res://data/ijfs/ijfs_scenario.json"
const IJFS_AIR_CLASSES_PATH := "res://data/ijfs/air_classes.json"
const IJFS_OOB_PATH := "res://data/ijfs/red_air_oob.json"
const IJFS_SAM_CAPS_PATH := "res://data/ijfs/sam_capabilities.json"

# D3 anti-ship / mine-warfare data (Green coastal anti-ship fires vs the Red crossing).
const ANTISHIP_TYPES_PATH := "res://data/antiship/antiship_systems_consolidated.json"
const ANTISHIP_GROUPING_PATH := "res://data/antiship/antiship_grouping_spec.json"
const ANTISHIP_CATALOG_PATH := "res://data/antiship/antiship_combat_catalog.json"
const ANTISHIP_CROSSING_PATH := "res://data/antiship/antiship_crossing_config.json"
const ANTISHIP_MINEFIELDS_PATH := "res://data/antiship/minefields.json"
# Default share of each surviving Green launcher group that fires at the crossing each turn. 100 =
# fire-all (maximally lethal: the whole coastal arsenal engages every wave). Lethality balance knob —
# scenario-configurable firing/detection percentages are a follow-up (see PLAN.md D3-D).
const DEFAULT_ANTISHIP_FIRE_PCT := 100.0
# When a TO's C2 node (type 99) is suppressed by the IJFS, the TO loses over-the-horizon targeting
# for its anti-ship systems (esp. mobile shoot-and-scoot coastal launchers that can't be IJFS-targeted
# directly). Suppressed-C2 TOs fire at this fraction of their surviving capacity. There is NO C2
# destruction mechanic — suppression already models the staff being knocked out (user decision, D3-D).
const C2_SUPPRESSED_FIRE_MULTIPLIER := 0.70
const PRE_INVASION_IJFS_DAYS := 4
# Number of IJFS daily cycles run on the FIRST IJFS of the game (the pre-invasion air campaign:
# several days attriting anti-ship platforms + a final suppression day). Later turns run one cycle.

enum Phase { PLANNING, RESOLUTION, END }

var turn_number: int = 1
var phase: Phase = Phase.PLANNING
var turn_length_days: int = 1
var orders: Dictionary = {}  # Brigade.Team -> Array[MoveOrder]
var commitments: Dictionary = {}  # Brigade.Team -> Array[CommitOrder]
var ship_reserve: Array = []  # OffloadCalculator-ready: [{brigade_id, locked_beach, beach_hex, offset_bearing, bns:[{id,type}]}]
var fleet: Dictionary = {}  # ship name (String) -> ShipState
var pending_lost_at_sea: int = 0
var supply_state: SupplyState
var last_contested_hexes: Array[String] = []
var last_combat_summaries: Array = []
# IJFS daily state persists across turns (carry_to_next_day advances it each turn).
var ijfs_state: IjfsDailyState = null
var _ijfs_day: int = 0
var last_ijfs_summary: Dictionary = {}
var last_ijfs_writeback: Dictionary = {}
# D3 anti-ship Green firing systems (AntishipSystem rows aggregated by (to_number, type_id)). Persist
# across turns so launcher destruction/suppression carries forward; lazily built on first use.
var antiship_systems: Array = []
# Container-level view of the same arsenal (one entry per platform-group bin) — IJFS target source.
var antiship_containers: Array = []
# Fractional BN-equiv owed from ship losses, carried across turns (ShipLoadingModel.resolve_bn_losses).
var lost_at_sea_accumulator: float = 0.0
var last_antiship_summary: Dictionary = {}


func _ready() -> void:
	reset_to_scenario()


func reset_to_scenario() -> void:
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
	_rebuild_fleet()
	_rebuild_supply_state()
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
	last_ijfs_writeback = {}
	# Anti-ship systems are lazily (re)built on first use (resolve_ijfs_turn / resolve_antiship_turn),
	# matching the IJFS state's lazy-load pattern; clearing here forces a fresh build per scenario.
	antiship_systems = []
	antiship_containers = []
	lost_at_sea_accumulator = 0.0
	last_antiship_summary = {}
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
	resolve_antiship_turn(dice)
	resolve_offload_turn(dice)

	_apply_move_orders(Brigade.Team.RED)
	_apply_move_orders(Brigade.Team.GREEN)
	last_contested_hexes = _find_contested_hexes()
	var combat_summaries: Array = []
	for hex_id in last_contested_hexes:
		var summary := _resolve_combat_at(hex_id, dice)
		if not summary.is_empty():
			combat_summaries.append(summary)
	_apply_feba_retreats()
	GameData.recompute_hex_ownership()
	for summary in combat_summaries:
		var typed_summary: Dictionary = summary
		typed_summary["owner_after"] = String(GameData.hex_states[String(typed_summary["hex_id"])]["owner"])
	last_combat_summaries = combat_summaries.duplicate(true)
	resolve_supply_turn()

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
	var priority_order: Array[String] = []
	for reserve_entry_value in ship_reserve:
		var reserve_entry: Dictionary = reserve_entry_value
		priority_order.append(String(reserve_entry["brigade_id"]))
	return priority_order


func resolve_offload_turn(dice: Dice) -> Dictionary:
	assert(dice != null, "resolve_offload_turn requires a Dice instance")
	if ship_reserve.is_empty():
		var empty_manifest := _empty_offload_manifest()
		empty_manifest["lost_at_sea"] = pending_lost_at_sea
		# D3-F applies lost_at_sea to the reserve; D0-C only threads the value.
		pending_lost_at_sea = 0
		EventBus.offload_resolved.emit(empty_manifest)
		return empty_manifest

	var active_beach_ids: Array[int] = []
	for reserve_entry_value in ship_reserve:
		var reserve_entry: Dictionary = reserve_entry_value
		var locked_beach := int(reserve_entry["locked_beach"])
		if locked_beach <= 0:
			push_error("Ship reserve entry has no locked_beach: %s" % String(reserve_entry["brigade_id"]))
			continue
		if locked_beach not in active_beach_ids:
			active_beach_ids.append(locked_beach)

	var beach_capacity := OffloadCalculator.beach_capacity_bns(active_beach_ids, GameData.beaches)
	var priority_order := ship_reserve_priority_order()
	var manifest := OffloadCalculator.resolve_offload_day(turn_number, beach_capacity, ship_reserve, priority_order)

	var landed_bn_ids_by_brigade: Dictionary = {}
	for landed_value in manifest["manifest_landed"]:
		var landed: Dictionary = landed_value
		var brigade_id := String(landed["brigade_id"])
		var bn_id := String(landed["bn_id"])
		if brigade_id not in landed_bn_ids_by_brigade:
			landed_bn_ids_by_brigade[brigade_id] = {}
		landed_bn_ids_by_brigade[brigade_id][bn_id] = true

	var landed_brigade_ids: Array[String] = []
	var remaining_ship_reserve: Array = []
	for reserve_entry_value in ship_reserve:
		var reserve_entry: Dictionary = reserve_entry_value
		var brigade_id := String(reserve_entry["brigade_id"])
		if brigade_id in landed_bn_ids_by_brigade:
			var landed_bn_ids: Dictionary = landed_bn_ids_by_brigade[brigade_id]
			var remaining_bns: Array = []
			for bn_value in reserve_entry["bns"]:
				var bn: Dictionary = bn_value
				if String(bn["id"]) not in landed_bn_ids:
					remaining_bns.append(bn)
			reserve_entry["bns"] = remaining_bns

			var brigade: Brigade = GameData.get_brigade(brigade_id)
			if brigade == null:
				push_error("Offload manifest references unknown brigade_id: %s" % brigade_id)
			elif brigade.hex_id.is_empty():
				GameData.set_brigade_hex(brigade_id, String(reserve_entry["beach_hex"]))
				brigade.entry_bearing = float(reserve_entry["offset_bearing"])
				landed_brigade_ids.append(brigade_id)

		if (reserve_entry["bns"] as Array).is_empty():
			continue
		remaining_ship_reserve.append(reserve_entry)

	ship_reserve = remaining_ship_reserve
	GameData.recompute_hex_ownership()
	manifest["landed_brigade_ids"] = landed_brigade_ids
	manifest["lost_at_sea"] = pending_lost_at_sea
	# D3-F applies lost_at_sea to the reserve; D0-C only threads the value.
	pending_lost_at_sea = 0
	EventBus.offload_resolved.emit(manifest)
	return manifest


func _empty_offload_manifest() -> Dictionary:
	return {
		"bns_sent": 0,
		"bns_landed": 0,
		"bns_waiting": 0,
		"lost_at_sea": 0,
		"manifest_landed": [],
		"manifest_deferred": [],
		"landed_brigade_ids": []
	}


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

	var summary := DosConsumption.calculate_consumption(units, moved_ids, engaged_ids, turn_number)
	var pool_before := supply_state.current_dos_tons
	var consumed := float(summary["red_dos_consumed_tons"])
	supply_state.current_dos_tons = maxf(0.0, pool_before - consumed)
	summary["applied"] = true
	summary["pool_before"] = pool_before
	summary["pool_after"] = supply_state.current_dos_tons
	# Combat-effectiveness modifier from supply exhaustion is deferred to D4 IJFS.
	supply_state.day_history.append(summary)
	EventBus.supply_updated.emit(summary)
	return summary


# --- IJFS (D4) — Red joint/air-missile fires daily phase ----------------------------------------

func resolve_ijfs_turn(dice: Dice) -> Dictionary:
	assert(dice != null, "resolve_ijfs_turn requires a Dice instance")
	if ijfs_state == null:
		_rebuild_ijfs_state()
	# Continuity: after the first IJFS day, carry destroyed/known/inventory/attrition forward and
	# clear per-day suppression flags (mirrors the TIV loader reload reset).
	# On the FIRST IJFS of the game, run the multi-day pre-invasion air campaign so anti-ship
	# platforms are attrited cumulatively before the turn-1 crossing; later turns run one cycle.
	var cycles := PRE_INVASION_IJFS_DAYS if _ijfs_day == 0 else 1
	var ledgers: Dictionary = {}
	for i in range(cycles):
		# carry_to_next_day persists destroyed/known/inventory and clears per-day suppression flags
		# (so only the final pre-invasion day's suppression survives; destruction accumulates).
		if _ijfs_day > 0 or i > 0:
			IjfsEngine.carry_to_next_day(ijfs_state)
		# Independent IJFS substream per cycle — NEVER consume the combat dice. SeededDice.derive()
		# yields a fresh stream (so SeededDice combat is reproducible AND isolated); ScriptedDice
		# .derive() returns self (shared queue), so for scripted combat we seed an independent
		# SeededDice off the turn+cycle instead.
		var ijfs_dice: Dice
		if dice is SeededDice:
			ijfs_dice = dice.derive("ijfs:%d:%d" % [turn_number, i])
		else:
			ijfs_dice = SeededDice.new(hash("ijfs:%d:%d" % [turn_number, i]))
		ledgers = IjfsEngine.run_daily(ijfs_state, ijfs_dice, turn_number + i)
	# The whole pre-invasion campaign resolves as THIS turn's IJFS (validators expect day==turn).
	_ijfs_day = turn_number
	last_ijfs_summary = ledgers["summary"]
	last_ijfs_writeback = _compute_ijfs_writeback(ledgers)
	EventBus.ijfs_resolved.emit(last_ijfs_summary)
	return ledgers


## Lazily build the persistent anti-ship Green firing systems (aggregated by (to_number, type_id)).
## Shared by resolve_ijfs_turn (IJFS targeting) and resolve_antiship_turn (firing).
func _ensure_antiship_systems() -> void:
	if not antiship_systems.is_empty():
		return
	var types := AntishipLoaders.load_system_types(ANTISHIP_TYPES_PATH)
	antiship_systems = AntishipLoaders.load_systems(ANTISHIP_GROUPING_PATH, types)
	antiship_containers = AntishipLoaders.load_containers(ANTISHIP_GROUPING_PATH, types)


func _rebuild_ijfs_state() -> void:
	_ensure_antiship_systems()
	ijfs_state = IjfsDailyState.new()
	# D3-D (1-A): anti-ship targets are generated per-(TO,type) from antiship_systems (carrying that
	# pair in metadata) and replace the static "Anti-Ship Systems" rows, so IJFS strikes write back by
	# (TO, type) for the D3 firing-plan join.
	ijfs_state.targets = IjfsLoaders.load_targets_with_antiship(IJFS_TARGETS_PATH, antiship_containers, 1)
	ijfs_state.munitions = IjfsLoaders.load_munitions(IJFS_MUNITIONS_PATH)
	ijfs_state.pairings = IjfsLoaders.load_pairings(IJFS_PAIRINGS_PATH)
	ijfs_state.scenario = IjfsLoaders.load_scenario(IJFS_SCENARIO_PATH)
	ijfs_state.air_classes = IjfsLoaders.load_air_classes(IJFS_AIR_CLASSES_PATH)
	ijfs_state.squadron_force = IjfsLoaders.expand_oob_to_squadrons(IjfsLoaders.load_oob(IJFS_OOB_PATH))
	IjfsLoaders.enrich_sam_scores(ijfs_state.targets, IjfsLoaders.load_sam_capabilities(IJFS_SAM_CAPS_PATH))
	_ijfs_day = 0


## Aggregates the IJFS ledgers into the writeback seam D3 (anti-ship) and future ground-casualty
## linkage consume. D3-D (1-A) closed the anti-ship side: targets are generated per-(TO,type) from
## antiship_systems, so anti-ship writeback is keyed by encode_key("<to>:<type>"). Maneuver casualties
## still depend on per-battalion target metadata (see PLAN.md Open Question, D4-H maneuver linkage).
func _compute_ijfs_writeback(ledgers: Dictionary) -> Dictionary:
	var strike_log: Array = ledgers["strike_log"]
	var engagement_log: Array = ledgers["engagement_log"]

	var antiship_destroyed_by_type: Dictionary = {}
	var antiship_suppressed_by_type: Dictionary = {}
	var maneuver_casualties: Array = []

	# Anti-ship attrition is read from the CUMULATIVE target state (target.destroyed persists across
	# days; target.suppressed reflects the latest day) so the multi-day pre-invasion campaign feeds
	# the firing plan. Keyed by encode_key("<to>:<type>"); a struck container removes its whole bin.
	# INVARIANT: antiship_destroyed_by_type is a running TOTAL (all days so far), NOT a per-turn delta
	# — resolve_antiship_turn relies on this to decrement from original_quantity idempotently.
	# (Reads ijfs_state directly, not `ledgers`, because cumulative state spans multiple run_daily days.)
	for target_value in ijfs_state.targets:
		var target: IjfsTarget = target_value
		if String(target.category) != "Anti-Ship Systems":
			continue
		var asm: Dictionary = target.metadata
		if not (asm.has("to_number") and asm.has("type_id")):
			continue
		var rep := int(asm.get("systems_represented", 1))
		var ask := AntishipCalculator.encode_key(int(asm["to_number"]), int(asm["type_id"]))
		if target.destroyed:
			antiship_destroyed_by_type[ask] = int(antiship_destroyed_by_type.get(ask, 0)) + rep
		elif target.suppressed:
			antiship_suppressed_by_type[ask] = int(antiship_suppressed_by_type.get(ask, 0)) + rep

	for entry in strike_log:
		if not entry.get("attack_executed"):
			continue
		var category := String(entry.get("category", ""))
		if category == "Maneuver Units" and entry.get("destroyed"):
			# Faithful port of ijfs_maneuver_writeback_service.compute_maneuver_writeback.
			var metadata: Dictionary = entry.get("metadata", {})
			var unit_id: Variant = metadata.get("battalion_id", metadata.get("unit_id", null))
			if unit_id == null or String(unit_id) == "":
				continue
			maneuver_casualties.append({
				"battalion_id": unit_id,
				"brigade_id": metadata.get("brigade_id", null),
				"to": metadata.get("to_number", null),
				"unit_type": metadata.get("unit_type", null),
				"subcategory": entry.get("subcategory", null),
			})

	var sam_destroyed := 0
	var sam_suppressed := 0
	for entry in engagement_log:
		if entry.get("destroyed"):
			sam_destroyed += 1
		if entry.get("suppressed"):
			sam_suppressed += 1

	return {
		"antiship_destroyed_by_type": antiship_destroyed_by_type,
		"antiship_suppressed_by_type": antiship_suppressed_by_type,
		"maneuver_casualties": maneuver_casualties,
		"sam_destroyed": sam_destroyed,
		"sam_suppressed": sam_suppressed,
	}


## D3-D: Green coastal anti-ship fires + mine warfare against the Red amphibious crossing. Threads the
## firing plan (D3-B2) -> crossing (D3-B3) -> mines (D3-C); ship losses convert to BNs lost at sea
## (ShipLoadingModel) and feed register_ship_losses (the D0-C seam offload consumes). Runs after IJFS
## (Green systems suppressed/destroyed first) and before offload (only survivors land). Draws from an
## INDEPENDENT substream so the ground-combat golden invariant stays byte-stable.
func resolve_antiship_turn(dice: Dice) -> Dictionary:
	_ensure_antiship_systems()
	last_antiship_summary = {}

	# The crossing wave = BNs still at sea. No wave -> no anti-ship phase.
	var bns_at_sea: Array = []
	var beach_set: Dictionary = {}
	for entry in ship_reserve:
		for bn in entry.get("bns", []):
			bns_at_sea.append(bn)
		beach_set[int(entry.get("locked_beach", 0))] = true
	if bns_at_sea.is_empty():
		return {}

	# Independent substream (same isolation pattern as resolve_ijfs_turn).
	var as_dice: Dice
	if dice is SeededDice:
		as_dice = dice.derive("antiship:%d" % turn_number)
	else:
		as_dice = SeededDice.new(hash("antiship:%d" % turn_number))

	var target_beaches: Array = []
	var target_tos: Array = []
	var to_seen: Dictionary = {}
	for beach_id in beach_set.keys():
		if int(beach_id) <= 0:
			continue
		target_beaches.append(int(beach_id))
		var to_num := Theaters.to_for_beach(int(beach_id))
		if not to_seen.has(to_num):
			to_seen[to_num] = true
			target_tos.append(to_num)
	target_beaches.sort()
	target_tos.sort()

	# Apply the IJFS writeback to the Green firing systems: destroyed launchers are permanently removed
	# from quantity; suppressed launchers sit out this turn (reduced firing %). Fire-all otherwise.
	var ijfs_destroyed: Dictionary = last_ijfs_writeback.get("antiship_destroyed_by_type", {})
	var ijfs_suppressed: Dictionary = last_ijfs_writeback.get("antiship_suppressed_by_type", {})
	# TOs whose C2 (type 99) the IJFS suppressed lose over-the-horizon targeting: every surviving
	# anti-ship system in that TO fires at C2_SUPPRESSED_FIRE_MULTIPLIER of capacity. Computed up front
	# because C2 itself is skipped (continue) in the firing loop below and never fires.
	var c2_suppressed_tos: Dictionary = {}
	for system_value in antiship_systems:
		var c2_system: AntishipSystem = system_value
		if c2_system.type_id != AntishipCalculator.SYSTEM_TYPE_C2:
			continue
		var c2_key := AntishipCalculator.encode_key(c2_system.to_number, c2_system.type_id)
		if int(ijfs_suppressed.get(c2_key, 0)) > 0:
			c2_suppressed_tos[c2_system.to_number] = true
	var firing_percentages: Dictionary = {}
	var target_locations: Array = []
	var loc_seen: Dictionary = {}
	for system_value in antiship_systems:
		var system: AntishipSystem = system_value
		var key := AntishipCalculator.encode_key(system.to_number, system.type_id)
		# `killed` is the CUMULATIVE total destroyed across all IJFS days (see _compute_ijfs_writeback),
		# so set quantity from original_quantity rather than subtracting — idempotent across turns.
		var killed := int(ijfs_destroyed.get(key, 0))
		system.quantity = maxi(0, system.original_quantity - killed)
		system.destroyed = killed
		if system.type_id == AntishipCalculator.SYSTEM_TYPE_C2:
			continue
		var avail := maxi(0, system.quantity)
		if avail <= 0:
			continue
		var suppressed := mini(avail, int(ijfs_suppressed.get(key, 0)))
		var fire_pct := DEFAULT_ANTISHIP_FIRE_PCT * float(avail - suppressed) / float(avail)
		# C2 suppression stacks on direct per-system suppression: the TO loses targeting for the rest.
		if c2_suppressed_tos.has(system.to_number):
			fire_pct *= C2_SUPPRESSED_FIRE_MULTIPLIER
		firing_percentages[key] = fire_pct
		if not loc_seen.has(system.to_number):
			loc_seen[system.to_number] = true
			target_locations.append(system.to_number)
	target_locations.sort()

	var crossing_config := AntishipLoaders.load_crossing_config(ANTISHIP_CROSSING_PATH)
	var combat_catalog := AntishipLoaders.load_combat_catalog(ANTISHIP_CATALOG_PATH)
	# Magazine gating is left null for this wiring: rebuilt-per-turn it would start full and never bind;
	# meaningful gating needs persistent cross-turn magazine state (logged follow-up, PLAN.md D3-D).
	var plan := AntishipCalculator.build_firing_plan(
		antiship_systems, {}, target_locations, firing_percentages, {}, null)
	var attrition := AntishipCalculator.resolve_launch_attrition(
		antiship_systems, plan["allocation_plan"], plan["destroyed_firing_plan"],
		crossing_config["launch_attrition"], as_dice)
	var systems_fired: Array = attrition["systems_fired"]

	# Sent fleet (D3-D BN<->ship mapping) + crossing (D3-B3).
	var sent := _build_sent_fleet(bns_at_sea.size())
	var to_adjacency: Dictionary = {}
	for to_num in GameData.active_tos:
		to_adjacency[to_num] = Theaters.adjacent_tos(to_num)
	var crossing := AntishipCrossing.resolve_crossing_damage(
		systems_fired, sent["snapshots"], combat_catalog, crossing_config,
		target_tos, as_dice, GameData.active_tos, to_adjacency)

	# Combine crossing + mine ship losses; mines run on the surviving crossing fleet pool.
	var destroyed_by_type: Dictionary = {}
	var crossing_destroyed: Dictionary = crossing["destroyed_by_ship_type"]
	var fleet_pool: Dictionary = (sent["sent_by_type"] as Dictionary).duplicate(true)
	for t in crossing_destroyed.keys():
		destroyed_by_type[t] = int(destroyed_by_type.get(t, 0)) + int(crossing_destroyed[t])
		fleet_pool[t] = maxi(0, int(fleet_pool.get(t, 0)) - int(crossing_destroyed[t]))
	var minefields := AntishipLoaders.load_minefields(ANTISHIP_MINEFIELDS_PATH)
	var sweepers := AntishipLoaders.available_minesweepers(ANTISHIP_MINEFIELDS_PATH)
	var mine_res := MineWarfareService.resolve_ship_losses(
		minefields, target_beaches, _distribute_minesweepers(sweepers, target_beaches), fleet_pool, as_dice)
	for beach_res in mine_res:
		for t in (beach_res["ship_loss_counts"] as Dictionary).keys():
			destroyed_by_type[t] = int(destroyed_by_type.get(t, 0)) + int(beach_res["ship_loss_counts"][t])

	# Ship losses -> BNs lost at sea (carry the fractional accumulator across turns).
	var losses := ShipLoadingModel.resolve_bn_losses(
		destroyed_by_type, _ship_capacity_by_type(), bns_at_sea, lost_at_sea_accumulator, as_dice)
	lost_at_sea_accumulator = float(losses["accumulator"])
	_remove_bns_from_reserve(losses["lost_ids"])
	register_ship_losses(int(losses["bn_equiv_lost"]))
	_apply_ship_losses_to_fleet(destroyed_by_type)

	last_antiship_summary = {
		"resolved_turn": turn_number,
		"sent_by_type": sent["sent_by_type"],
		"unliftable_bn": int(sent["unliftable_bn"]),
		"systems_fired_count": _sum_systems_fired(systems_fired),
		"destroyed_by_ship_type": destroyed_by_type,
		"crossing_casualties": crossing["casualty_totals"],
		"bns_lost_at_sea": int(losses["bn_equiv_lost"]),
		"target_beaches": target_beaches,
		"target_tos": target_tos,
		"mine_status": _mine_status_summary(mine_res),
	}
	EventBus.antiship_resolved.emit(last_antiship_summary)
	return last_antiship_summary


## Build the sent crossing fleet inputs from the surviving fleet: carriers (capacity > 0, non-infra)
## and the escort + decoy screen (capacity 0). Infrastructure ships do not sail in the assault wave.
func _build_sent_fleet(bn_count: int) -> Dictionary:
	var carriers: Array = []
	var screen: Array = []
	for ship_def_value in GameData.ship_defs.values():
		var ship_def: ShipDef = ship_def_value
		if ship_def.infrastructure and not ship_def.is_decoy:
			continue
		var state: ShipState = fleet.get(ship_def.name, null)
		var ready := int(state.ready) if state != null else 0
		if ready <= 0:
			continue
		if ship_def.carrying_capacity_bn_equiv > 0.0:
			carriers.append({"ship_type": ship_def.name, "capacity": ship_def.carrying_capacity_bn_equiv, "ready": ready})
		else:
			screen.append({"ship_type": ship_def.name, "ready": ready})
	return ShipLoadingModel.build_sent_snapshots(bn_count, carriers, screen)


func _ship_capacity_by_type() -> Dictionary:
	var caps: Dictionary = {}
	for ship_def_value in GameData.ship_defs.values():
		var ship_def: ShipDef = ship_def_value
		caps[ship_def.name] = ship_def.carrying_capacity_bn_equiv
	return caps


## Apply net ship losses (ready -> destroyed) to the fleet ShipStates, preserving the validate()
## invariants (the one-turn crossing send/return nets out to a straight ready->destroyed transfer).
func _apply_ship_losses_to_fleet(destroyed_by_type: Dictionary) -> void:
	for ship_type in destroyed_by_type.keys():
		var state: ShipState = fleet.get(String(ship_type), null)
		if state == null:
			continue
		var lost := mini(int(destroyed_by_type[ship_type]), state.ready)
		if lost <= 0:
			continue
		state.ready -= lost
		state.destroyed += lost
		state.fleet_surviving_total -= lost
		assert(state.validate(), "ShipState invariant broken applying anti-ship losses for %s" % ship_type)


func _remove_bns_from_reserve(lost_ids: Array) -> void:
	if lost_ids.is_empty():
		return
	var lost: Dictionary = {}
	for id in lost_ids:
		lost[String(id)] = true
	var kept: Array = []
	for entry in ship_reserve:
		var bns: Array = entry.get("bns", [])
		var surviving: Array = []
		for bn in bns:
			if not lost.has(String(bn.get("id", ""))):
				surviving.append(bn)
		if surviving.is_empty():
			continue
		entry["bns"] = surviving
		kept.append(entry)
	ship_reserve = kept


## Spread the available minesweepers round-robin across the target beaches (ascending beach_id).
func _distribute_minesweepers(available: int, target_beaches: Array) -> Dictionary:
	var assignments: Dictionary = {}
	if target_beaches.is_empty() or available <= 0:
		return assignments
	var sorted_beaches: Array = target_beaches.duplicate()
	sorted_beaches.sort()
	var i := 0
	while i < available:
		var beach_id := int(sorted_beaches[i % sorted_beaches.size()])
		assignments[beach_id] = int(assignments.get(beach_id, 0)) + 1
		i += 1
	return assignments


func _sum_systems_fired(systems_fired: Array) -> int:
	var total := 0
	for row in systems_fired:
		total += int(row.get("systems_fired", 0))
	return total


func _mine_status_summary(mine_res: Array) -> Array:
	var out: Array = []
	for beach_res in mine_res:
		out.append({
			"beach_id": int(beach_res.get("beach_id", 0)),
			"ships_destroyed": int(beach_res.get("ships_destroyed", 0)),
			"lane_cleared": bool(beach_res.get("lane_cleared", false)),
			"status_color": String(beach_res.get("status_color", "")),
		})
	return out


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
	ship_reserve.clear()
	for reserve_entry_value in GameData.red_ship_reserve:
		var reserve_entry: Dictionary = reserve_entry_value
		var brigade_id := String(reserve_entry["brigade_id"])
		var brigade: Brigade = GameData.get_brigade(brigade_id)
		if brigade == null:
			push_error("Ship reserve references unknown brigade_id: %s" % brigade_id)
			continue

		var bns: Array = []
		var battalion_index := 1
		for battalion in brigade.composition:
			var typed_battalion: Battalion = battalion
			var type_slug := typed_battalion.type.to_lower().replace(" ", "_")
			for _qty_index in range(typed_battalion.qty):
				bns.append({
					"id": "%s-%s-%d" % [brigade_id, type_slug, battalion_index],
					"type": typed_battalion.type
				})
				battalion_index += 1

		ship_reserve.append({
			"brigade_id": brigade_id,
			"locked_beach": int(reserve_entry["locked_beach"]),
			"beach_hex": String(reserve_entry["beach_hex"]),
			"offset_bearing": float(reserve_entry["offset_bearing"]),
			"bns": bns
		})


func _rebuild_supply_state() -> void:
	supply_state = SupplyStateResource.new()
	supply_state.current_dos_tons = float(GameData.red_dos_start) * DosConsumption.TONS_PER_DOS
	supply_state.day_history = []


func register_ship_losses(bn_equiv_lost: int) -> void:
	pending_lost_at_sea = maxi(0, bn_equiv_lost)


func _rebuild_fleet() -> void:
	fleet.clear()
	for ship_def_value in GameData.ship_defs.values():
		var ship_def: ShipDef = ship_def_value
		var ship_state: ShipState = ShipStateResource.new()
		ship_state.ship_type = ship_def.name
		ship_state.fleet_total = ship_def.total_count
		ship_state.fleet_surviving_total = ship_def.total_count
		ship_state.ready = ship_def.total_count
		ship_state.sent_original = 0
		ship_state.surviving_sent = 0
		ship_state.offloading = 0
		ship_state.returning = 0
		ship_state.destroyed = 0
		assert(ship_state.validate(), "Invalid initial ShipState for %s" % ship_def.name)
		fleet[ship_def.name] = ship_state


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


func _resolve_combat_at(hex_id: String, dice: Dice) -> Dictionary:
	var attacker_brigades := _combat_contributors_for(Brigade.Team.RED, hex_id)
	var defender_brigades := _combat_contributors_for(Brigade.Team.GREEN, hex_id)

	if attacker_brigades.is_empty() or defender_brigades.is_empty():
		return {}

	var attacker_units := CombatForces.maneuver_units(attacker_brigades)
	var defender_units := CombatForces.maneuver_units(defender_brigades)
	var attacker_support := CombatForces.support_counts(attacker_brigades)
	var defender_support := CombatForces.support_counts(defender_brigades)
	var result := CombatCalculator.resolve_map_attack(
		dice,
		attacker_units,
		defender_units,
		attacker_support,
		defender_support,
		1.0,
		2.0
	)

	for casualty in result.attacker_casualties:
		_apply_casualty(casualty)
	for casualty in result.defender_casualties:
		_apply_casualty(casualty)

	GameData.hex_states[hex_id]["feba_km"] = float(GameData.hex_states[hex_id]["feba_km"]) + result.feba_movement_km
	for brigade_value in attacker_brigades + defender_brigades:
		var fought_brigade: Brigade = brigade_value
		fought_brigade.fought_this_turn = true

	return {
		"hex_id": hex_id,
		"attacker_losses": result.attacker_losses,
		"defender_losses": result.defender_losses,
		"feba_movement_km": result.feba_movement_km,
		"owner_after": String(GameData.hex_states[hex_id]["owner"]),
		"combat_detail": result.combat_detail,
		"attacker_brigade_ids": _brigade_ids(attacker_brigades),
		"defender_brigade_ids": _brigade_ids(defender_brigades)
	}


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


func _brigade_ids(brigades: Array) -> Array[String]:
	var ids: Array[String] = []
	for brigade_value in brigades:
		var brigade: Brigade = brigade_value
		ids.append(brigade.id)
	return ids


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
		var feba: float = float(GameData.hex_states[hex_id]["feba_km"])
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
		GameData.hex_states[hex_id]["feba_km"] = 0.0


func _find_retreat_hex(from_hex: String, team: Brigade.Team) -> String:
	var friendly_owner := HexOwner.RED
	var enemy_team := Brigade.Team.GREEN
	if team == Brigade.Team.GREEN:
		friendly_owner = HexOwner.GREEN
		enemy_team = Brigade.Team.RED

	for neighbor_id_value in GameData.get_neighbors(from_hex):
		var neighbor_id := String(neighbor_id_value)
		var has_enemy := false
		for brigade_id_value in GameData.get_brigades_in_hex(neighbor_id):
			var brigade: Brigade = GameData.get_brigade(String(brigade_id_value))
			if brigade != null and not brigade.destroyed and brigade.team == enemy_team:
				has_enemy = true
				break
		if has_enemy:
			continue

		var owner := String(GameData.hex_states[neighbor_id]["owner"])
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


func _team_to_string(team: Brigade.Team) -> String:
	match team:
		Brigade.Team.GREEN:
			return "Green"
		_:
			return "Red"
