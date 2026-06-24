extends Node
class_name GameStateType

const MoveOrderResource = preload("res://scripts/model/MoveOrder.gd")
const CommitOrderResource = preload("res://scripts/model/CommitOrder.gd")
const FEBA_RETREAT_THRESHOLD_KM := 10.0

enum Phase { PLANNING, RESOLUTION, END }

var turn_number: int = 1
var phase: Phase = Phase.PLANNING
var turn_length_days: int = 1
var orders: Dictionary = {}  # Brigade.Team -> Array[MoveOrder]
var commitments: Dictionary = {}  # Brigade.Team -> Array[CommitOrder]
var last_contested_hexes: Array[String] = []
var last_combat_summaries: Array = []


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
	last_contested_hexes.clear()
	last_combat_summaries.clear()
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
