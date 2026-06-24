extends Node
class_name GameController

@onready var hex_map: HexMap = $HexMap
@onready var debug_label: Label = $UI/DebugLabel
@onready var move_mode_option: OptionButton = $UI/MovementControls/MoveModeOption
@onready var end_turn_button: Button = $UI/MovementControls/EndTurnButton
@onready var turn_status_label: Label = $UI/MovementControls/TurnStatusLabel
@onready var composition_panel: CompositionPanel = $UI/CompositionPanel

var selected_hex: String = ""
var selected_brigade: String = ""
var current_move_mode: String = Movement.MODE_TACTICAL
var current_reachable: Array = []
var _last_combat_summary_text: String = ""


func _ready() -> void:
	hex_map.hex_clicked.connect(_on_hex_clicked)
	move_mode_option.clear()
	move_mode_option.add_item("Tactical")
	move_mode_option.add_item("Administrative")
	move_mode_option.item_selected.connect(_on_move_mode_option_selected)
	end_turn_button.pressed.connect(end_turn)
	EventBus.combat_resolved.connect(_on_combat_resolved)
	composition_panel.commit_requested.connect(commit_brigade)
	_update_turn_status()
	debug_label.text = "HexCombat | Loaded %d hexes, %d brigades. Click a hex to select." % [GameData.hex_lookup.size(), GameData.brigades.size()]


func _on_hex_clicked(hex_id: String) -> void:
	if selected_brigade != "" and hex_id in current_reachable:
		var selected: Brigade = GameData.get_brigade(selected_brigade)
		assert(selected != null, "Selected brigade not found: %s" % selected_brigade)
		if hex_id != selected.hex_id:
			var order_count_before := GameState.orders_for(selected.team).size()
			GameState.add_move_order(selected.team, selected_brigade, hex_id, current_move_mode)
			if GameState.orders_for(selected.team).size() == order_count_before + 1:
				EventBus.move_order_issued.emit(selected_brigade, hex_id, current_move_mode)
				debug_label.text = "Order: %s -> %s (%s)" % [selected.name, hex_id, current_move_mode]
				current_reachable = []
				EventBus.reachable_hexes_changed.emit(current_reachable)
			return

	selected_hex = hex_id
	selected_brigade = ""
	EventBus.hex_selected.emit(hex_id)
	_emit_commit_options(hex_id)

	var brigade_ids: Array = GameData.get_brigades_in_hex(hex_id)
	if not brigade_ids.is_empty():
		selected_brigade = String(brigade_ids[0])
		EventBus.brigade_selected.emit(selected_brigade)

	if selected_brigade != "":
		_update_reachable()
	else:
		current_reachable = []
		EventBus.reachable_hexes_changed.emit(current_reachable)

	debug_label.text = "Selected hex: %s" % hex_id
	print_debug("Clicked hex: %s" % hex_id)


func _update_reachable() -> void:
	if selected_brigade == "":
		current_reachable = []
		EventBus.reachable_hexes_changed.emit(current_reachable)
		return

	var brigade: Brigade = GameData.get_brigade(selected_brigade)
	assert(brigade != null, "Selected brigade not found: %s" % selected_brigade)
	current_reachable = GameData.find_reachable(brigade.hex_id, Movement.move_allowance(brigade, current_move_mode))
	EventBus.reachable_hexes_changed.emit(current_reachable)


func set_move_mode(mode: String) -> void:
	current_move_mode = mode
	EventBus.move_mode_changed.emit(mode)
	_update_turn_status()
	_update_reachable()


func commit_brigade(team: Brigade.Team, brigade_id: String, target_hex: String) -> void:
	var brigade: Brigade = GameData.get_brigade(brigade_id)
	assert(brigade != null, "Commit requested for unknown brigade: %s" % brigade_id)
	var commitment_count_before := GameState.commitments_for(team).size()
	GameState.add_commit_order(team, brigade_id, target_hex)
	if GameState.commitments_for(team).size() == commitment_count_before + 1:
		EventBus.brigade_committed.emit(brigade_id, target_hex)
		_emit_commit_options(target_hex)
		debug_label.text = "Commit: %s -> %s" % [brigade.name, target_hex]


func end_turn() -> void:
	GameState.resolve_turn()
	GameState.begin_next_turn()
	hex_map.render_brigade_markers()
	selected_brigade = ""
	current_reachable = []
	EventBus.reachable_hexes_changed.emit(current_reachable)
	EventBus.turn_advanced.emit(GameState.turn_number)
	_update_turn_status()
	if _last_combat_summary_text == "":
		debug_label.text = "Turn %d — Planning. Select a brigade." % GameState.turn_number


func _on_combat_resolved(summaries: Array) -> void:
	var attacker_losses := 0
	var defender_losses := 0
	for summary_value in summaries:
		var summary: Dictionary = summary_value
		attacker_losses += int(summary["attacker_losses"])
		defender_losses += int(summary["defender_losses"])
	_last_combat_summary_text = "Turn %d resolved: %d combat(s), R lost %d / G lost %d" % [GameState.turn_number, summaries.size(), attacker_losses, defender_losses]
	debug_label.text = _last_combat_summary_text


func _on_move_mode_option_selected(index: int) -> void:
	match index:
		0:
			set_move_mode(Movement.MODE_TACTICAL)
		1:
			set_move_mode(Movement.MODE_ADMINISTRATIVE)
		_:
			push_error("Unknown movement mode option index: %d" % index)


func _emit_commit_options(target_hex: String) -> void:
	var options: Array = []
	for team in [Brigade.Team.RED, Brigade.Team.GREEN]:
		for brigade_id_value in GameState.eligible_commit_brigades(team, target_hex):
			var brigade_id := String(brigade_id_value)
			var brigade: Brigade = GameData.get_brigade(brigade_id)
			assert(brigade != null, "Eligible commit brigade not found: %s" % brigade_id)
			options.append({
				"brigade_id": brigade_id,
				"team": team,
				"team_string": _team_to_string(team),
				"name": brigade.name
			})
	EventBus.commit_options_changed.emit(target_hex, options)


func _team_to_string(team: Brigade.Team) -> String:
	match team:
		Brigade.Team.GREEN:
			return "Green"
		_:
			return "Red"


func _update_turn_status() -> void:
	turn_status_label.text = "Turn %d | Mode: %s" % [GameState.turn_number, current_move_mode.capitalize()]
