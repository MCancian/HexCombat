extends Node
class_name GameController

@onready var hex_grid: HexGrid = $HexGrid
@onready var hex_map: HexMap = $HexMap
@onready var debug_label: Label = $UI/DebugLabel

var selected_hex: String = ""

func _ready() -> void:
	hex_map.hex_clicked.connect(_on_hex_clicked)
	debug_label.text = "HexCombat | Loaded %d hexes. Click a hex to select." % hex_grid.hex_lookup.size()


func _on_hex_clicked(hex_id: String) -> void:
	selected_hex = hex_id
	debug_label.text = "Selected hex: %s" % hex_id
	print_debug("Clicked hex: %s" % hex_id)
