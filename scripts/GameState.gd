extends Node
class_name GameStateType

const MoveOrderResource = preload("res://scripts/model/MoveOrder.gd")

enum Phase { PLANNING, RESOLUTION, END }

var turn_number: int = 1
var phase: Phase = Phase.PLANNING
var turn_length_days: int = 1
var orders: Dictionary = {}  # Brigade.Team -> Array[MoveOrder]
var last_contested_hexes: Array[String] = []


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
	last_contested_hexes.clear()
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

	var order: MoveOrder = MoveOrderResource.new()
	order.brigade_id = brigade_id
	order.target_hex = target_hex
	order.mode = mode
	orders[team].append(order)


func resolve_turn() -> void:
	if phase != Phase.PLANNING:
		push_error("Cannot resolve turn outside PLANNING phase")
		return

	phase = Phase.RESOLUTION
	EventBus.phase_changed.emit(phase)

	_apply_move_orders(Brigade.Team.RED)
	_apply_move_orders(Brigade.Team.GREEN)
	last_contested_hexes = _find_contested_hexes()

	phase = Phase.END
	EventBus.phase_changed.emit(phase)
	EventBus.turn_resolved.emit(turn_number)


func begin_next_turn() -> void:
	if phase != Phase.END:
		push_error("Cannot begin next turn outside END phase")
		return

	for brigade in GameData.brigades.values():
		var typed_brigade: Brigade = brigade
		typed_brigade.moved_this_turn = false
		typed_brigade.fought_this_turn = false
	orders[Brigade.Team.RED].clear()
	orders[Brigade.Team.GREEN].clear()
	turn_number += 1
	phase = Phase.PLANNING
	EventBus.phase_changed.emit(phase)


func orders_for(team: Brigade.Team) -> Array:
	return orders[team]


func _apply_move_orders(team: Brigade.Team) -> void:
	for order in orders[team]:
		var move_order: MoveOrder = order
		var brigade: Brigade = GameData.get_brigade(move_order.brigade_id)
		GameData.set_brigade_hex(move_order.brigade_id, move_order.target_hex)
		brigade.moved_this_turn = true


func _find_contested_hexes() -> Array[String]:
	var contested: Array[String] = []
	for hex_id in GameData.hex_lookup.keys():
		var has_red := false
		var has_green := false
		for brigade_id in GameData.get_brigades_in_hex(String(hex_id)):
			var brigade: Brigade = GameData.get_brigade(String(brigade_id))
			match brigade.team:
				Brigade.Team.RED:
					has_red = true
				Brigade.Team.GREEN:
					has_green = true
			if has_red and has_green:
				contested.append(String(hex_id))
				break
	return contested


func _team_to_string(team: Brigade.Team) -> String:
	match team:
		Brigade.Team.GREEN:
			return "Green"
		_:
			return "Red"
