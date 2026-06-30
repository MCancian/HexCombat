extends PanelContainer
class_name InfoPanel

@onready var details_label: RichTextLabel = $MarginContainer/DetailsLabel

var selected_hex_id: String = ""
var selected_brigade_id: String = ""


func _ready() -> void:
	EventBus.hex_selected.connect(_on_hex_selected)
	EventBus.brigade_selected.connect(_on_brigade_selected)
	EventBus.selection_cleared.connect(_on_selection_cleared)
	_render_empty()


func _on_hex_selected(hex_id: String) -> void:
	selected_hex_id = hex_id
	selected_brigade_id = ""
	_render()


func _on_brigade_selected(brigade_id: String) -> void:
	selected_brigade_id = brigade_id
	_render()


func _on_selection_cleared() -> void:
	selected_hex_id = ""
	selected_brigade_id = ""
	_render_empty()


func _render_empty() -> void:
	details_label.text = "[b]Selection[/b]\nClick a hex to inspect it."


func _render() -> void:
	if selected_hex_id.is_empty():
		_render_empty()
		return

	var lines: Array[String] = []
	lines.append("[b]Hex[/b]")
	lines.append("ID: %s" % selected_hex_id)

	var state: HexState = GameData.hex_states.get(selected_hex_id, null)
	lines.append("Owner: %s" % (state.owner if state != null else "unknown"))
	lines.append("FEBA: %.1f km" % (state.feba_km if state != null else 0.0))
	lines.append("")
	lines.append("[b]Brigades in hex[/b]")

	var brigade_ids: Array = GameData.get_brigades_in_hex(selected_hex_id)
	if brigade_ids.is_empty():
		lines.append("None")
	else:
		for brigade_id in brigade_ids:
			var brigade: Brigade = GameData.get_brigade(String(brigade_id))
			if brigade == null:
				push_error("Hex '%s' references unknown brigade_id '%s'" % [selected_hex_id, String(brigade_id)])
				continue
			lines.append("- %s (%s)" % [brigade.name, _team_to_string(brigade.team)])

	if not selected_brigade_id.is_empty():
		lines.append("")
		_append_brigade_section(lines, selected_brigade_id)

	details_label.text = "\n".join(lines)


func _append_brigade_section(lines: Array[String], brigade_id: String) -> void:
	var brigade: Brigade = GameData.get_brigade(brigade_id)
	if brigade == null:
		push_error("InfoPanel asked to show unknown brigade_id: %s" % brigade_id)
		return

	lines.append("[b]Brigade[/b]")
	lines.append("ID: %s" % brigade.id)
	lines.append("Name: %s" % brigade.name)
	lines.append("Team: %s" % _team_to_string(brigade.team))
	lines.append("NATO type: %s" % brigade.nato_type)
	lines.append("Battalions: %d" % brigade.get_battalion_count())
	lines.append("Composition:")
	if brigade.composition.is_empty():
		lines.append("- None")
	else:
		for battalion in brigade.composition:
			lines.append("- %s x %d" % [battalion.type, battalion.qty])


func _team_to_string(team: Brigade.Team) -> String:
	match team:
		Brigade.Team.GREEN:
			return "Green"
		Brigade.Team.RED:
			return "Red"
		_:
			push_error("Unknown brigade team: %d" % team)
			return "Unknown"
