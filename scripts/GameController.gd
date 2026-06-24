extends Node
class_name GameController

@onready var hex_map: HexMap = $HexMap
@onready var debug_label: Label = $UI/DebugLabel

var selected_hex: String = ""
var selected_brigade: String = ""


func _ready() -> void:
	hex_map.hex_clicked.connect(_on_hex_clicked)
	debug_label.text = "HexCombat | Loaded %d hexes, %d brigades. Click a hex to select." % [GameData.hex_lookup.size(), GameData.brigades.size()]


func _on_hex_clicked(hex_id: String) -> void:
	selected_hex = hex_id
	selected_brigade = ""
	EventBus.hex_selected.emit(hex_id)

	var brigade_ids: Array = GameData.get_brigades_in_hex(hex_id)
	if not brigade_ids.is_empty():
		selected_brigade = String(brigade_ids[0])
		EventBus.brigade_selected.emit(selected_brigade)

	debug_label.text = "Selected hex: %s" % hex_id
	print_debug("Clicked hex: %s" % hex_id)
