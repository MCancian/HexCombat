extends Control
class_name SymbolPreview

const OOB_PATHS := ["res://data/pla_ground_forces.json", "res://data/roc_ground_forces.json"]
const SYMBOL_SIZE := Vector2(64.0, 64.0)


func _ready() -> void:
	var counts := _count_oob_nato_types()
	var symbol_library := SymbolLibrary.new()

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)

	var rows := VBoxContainer.new()
	rows.name = "SymbolRows"
	rows.add_theme_constant_override("separation", 8)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)

	for nato_type in counts.keys():
		var row := HBoxContainer.new()
		row.name = "%s Row" % String(nato_type)
		row.add_theme_constant_override("separation", 12)
		rows.add_child(row)

		var texture_rect := TextureRect.new()
		texture_rect.name = "%s Symbol" % String(nato_type)
		texture_rect.custom_minimum_size = SYMBOL_SIZE
		texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		texture_rect.texture = symbol_library.texture_for_nato_type(String(nato_type))
		row.add_child(texture_rect)

		var label := Label.new()
		label.name = "%s Label" % String(nato_type)
		label.text = "%s — %d brigades" % [String(nato_type), int(counts[nato_type])]
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(label)


func _count_oob_nato_types() -> Dictionary:
	var counts: Dictionary = {}
	for path in OOB_PATHS:
		var data := _read_json(path)
		for brigade_data in data.get("brigades", []):
			var nato_type := String(brigade_data.get("nato_type", ""))
			if nato_type.is_empty():
				push_error("Brigade with missing nato_type in %s" % path)
				continue
			counts[nato_type] = int(counts.get(nato_type, 0)) + 1

	var sorted_counts: Dictionary = {}
	var nato_types := counts.keys()
	nato_types.sort()
	for nato_type in nato_types:
		sorted_counts[nato_type] = counts[nato_type]
	return sorted_counts


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not open %s" % path)
		return {}

	var parsed = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_error("%s did not parse to a Dictionary" % path)
		return {}
	return parsed
