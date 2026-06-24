extends PanelContainer
class_name CompositionPanel

signal commit_requested(team: Brigade.Team, brigade_id: String, target_hex: String)

@onready var list: VBoxContainer = $MarginContainer/VBoxContainer

var _target_hex: String = ""


func _ready() -> void:
	EventBus.commit_options_changed.connect(_on_commit_options_changed)
	EventBus.selection_cleared.connect(_show_empty)
	_show_empty()


func _on_commit_options_changed(target_hex: String, options: Array) -> void:
	_target_hex = target_hex
	_clear()
	var title := Label.new()
	title.text = "Commitments for %s" % target_hex
	list.add_child(title)

	if options.is_empty():
		var empty := Label.new()
		empty.text = "No eligible commitments"
		list.add_child(empty)
		return

	for option_value in options:
		var option: Dictionary = option_value
		var brigade_id := String(option["brigade_id"])
		var brigade: Brigade = GameData.get_brigade(brigade_id)
		assert(brigade != null, "Commit option references unknown brigade: %s" % brigade_id)
		var team: Brigade.Team = option["team"]
		var team_string := String(option["team_string"])
		var brigade_name := String(option["name"])
		var button := Button.new()
		button.text = "Commit %s (%s)" % [brigade_name, team_string]
		# Wrap long brigade names instead of forcing the panel past the viewport.
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.clip_text = true
		button.custom_minimum_size = Vector2.ZERO
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func() -> void:
			commit_requested.emit(team, brigade_id, _target_hex)
		)
		list.add_child(button)


func _show_empty() -> void:
	_clear()
	var title := Label.new()
	title.text = "Commitments"
	list.add_child(title)
	var empty := Label.new()
	empty.text = "No eligible commitments"
	list.add_child(empty)


func _clear() -> void:
	for child in list.get_children():
		child.queue_free()
