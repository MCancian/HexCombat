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
	resolve_offload_turn(dice)
	# IJFS (Red joint fires) runs before maneuver/combat so its effects (suppressed anti-ship
	# systems for D3, future theater CAS/CRBM) precede ground combat. It draws from an INDEPENDENT
	# IJFS substream (never the combat dice), so the ground-combat golden invariant is byte-stable.
	resolve_ijfs_turn(dice)

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
	if _ijfs_day > 0:
		IjfsEngine.carry_to_next_day(ijfs_state)
	_ijfs_day = turn_number

	# Independent IJFS substream — NEVER consume the combat dice. SeededDice.derive() yields a fresh
	# stream (so SeededDice combat is reproducible AND isolated); ScriptedDice.derive() returns self
	# (shared queue), so for scripted combat we seed an independent SeededDice off the turn instead.
	var ijfs_dice: Dice
	if dice is SeededDice:
		ijfs_dice = dice.derive("ijfs:%d" % turn_number)
	else:
		ijfs_dice = SeededDice.new(hash("ijfs:%d" % turn_number))

	var ledgers := IjfsEngine.run_daily(ijfs_state, ijfs_dice, turn_number)
	last_ijfs_summary = ledgers["summary"]
	last_ijfs_writeback = _compute_ijfs_writeback(ledgers)
	EventBus.ijfs_resolved.emit(last_ijfs_summary)
	return ledgers


func _rebuild_ijfs_state() -> void:
	ijfs_state = IjfsDailyState.new()
	ijfs_state.targets = IjfsLoaders.load_targets(IJFS_TARGETS_PATH, 1)
	ijfs_state.munitions = IjfsLoaders.load_munitions(IJFS_MUNITIONS_PATH)
	ijfs_state.pairings = IjfsLoaders.load_pairings(IJFS_PAIRINGS_PATH)
	ijfs_state.scenario = IjfsLoaders.load_scenario(IJFS_SCENARIO_PATH)
	ijfs_state.air_classes = IjfsLoaders.load_air_classes(IJFS_AIR_CLASSES_PATH)
	ijfs_state.squadron_force = IjfsLoaders.expand_oob_to_squadrons(IjfsLoaders.load_oob(IJFS_OOB_PATH))
	IjfsLoaders.enrich_sam_scores(ijfs_state.targets, IjfsLoaders.load_sam_capabilities(IJFS_SAM_CAPS_PATH))
	_ijfs_day = 0


## Aggregates the IJFS ledgers into the writeback seam D3 (anti-ship) and future ground-casualty
## linkage consume. NOTE: HexCombat's target data carries no theater (TO) or battalion IDs, so
## anti-ship is keyed by Type (subcategory) and maneuver casualties stay empty until target data
## carries that metadata — see PLAN.md Open Question (D4-H writeback linkage).
func _compute_ijfs_writeback(ledgers: Dictionary) -> Dictionary:
	var strike_log: Array = ledgers["strike_log"]
	var engagement_log: Array = ledgers["engagement_log"]

	var antiship_destroyed_by_type: Dictionary = {}
	var antiship_suppressed_by_type: Dictionary = {}
	var maneuver_casualties: Array = []
	for entry in strike_log:
		if not entry.get("attack_executed"):
			continue
		var category := String(entry.get("category", ""))
		if category == "Anti-Ship Systems":
			var type_key := String(entry.get("subcategory", ""))
			if entry.get("destroyed"):
				antiship_destroyed_by_type[type_key] = int(antiship_destroyed_by_type.get(type_key, 0)) + 1
			if entry.get("suppressed"):
				antiship_suppressed_by_type[type_key] = int(antiship_suppressed_by_type.get(type_key, 0)) + 1
		elif category == "Maneuver Units" and entry.get("destroyed"):
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
