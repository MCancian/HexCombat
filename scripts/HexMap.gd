extends Node2D
class_name HexMap

@export var hex_grid: HexGrid
var hex_cells: Dictionary = {}  # hex_id -> HexCell node
var hex_states: Dictionary = {}  # hex_id -> {owner: "red"/"green"/"contested", feba_km: 0}

# Color scheme for hex ownership states
var color_none = Color(0.85, 0.85, 0.85)  # Light gray
var color_red = Color(1.0, 0.3, 0.3)  # Red
var color_green = Color(0.3, 1.0, 0.3)  # Green
var color_contested_light = Color(0.9, 1.0, 0.7)  # Light green for <2.5km FEBA
var color_contested_medium = Color(1.0, 1.0, 0.5)  # Yellow for 2.5-7.5km
var color_contested_heavy = Color(1.0, 0.8, 0.5)  # Orange for >7.5km

signal hex_clicked(hex_id: String)

func _ready() -> void:
	if hex_grid == null:
		print_debug("Warning: HexGrid not assigned to HexMap")
		return

	# Initialize hex states (all Green to start)
	for hex_id in hex_grid.hex_lookup:
		hex_states[hex_id] = {
			"owner": "green",
			"feba_km": 0.0
		}

	# Spawn hex cell meshes
	spawn_hex_cells()


func spawn_hex_cells() -> void:
	"""Create visual Polygon2D node for each hex."""
	for hex_id in hex_grid.hex_lookup:
		var vertices = hex_grid.get_hex_vertices(hex_id)
		if vertices.size() < 3:
			continue

		var poly = Polygon2D.new()
		poly.polygon = PackedVector2Array(vertices)
		poly.color = get_hex_color(hex_id)
		poly.z_index = 0

		# Add outline
		poly.outline_width = 2
		poly.outline_color = Color.BLACK

		# Add collision for click detection
		var area = Area2D.new()
		var collision = CollisionPolygon2D.new()
		collision.polygon = PackedVector2Array(vertices)
		area.add_child(collision)
		area.mouse_entered.connect(_on_hex_mouse_entered.bindv([hex_id, area]))

		poly.add_child(area)
		add_child(poly)
		hex_cells[hex_id] = poly

	print_debug("Spawned %d hex cells" % hex_cells.size())


func get_hex_color(hex_id: String) -> Color:
	"""Determine hex color based on ownership and FEBA state."""
	if not hex_id in hex_states:
		return color_none

	var state = hex_states[hex_id]
	var owner = state.get("owner", "green")
	var feba_km = state.get("feba_km", 0.0)

	if owner == "red":
		return color_red
	elif owner == "green":
		return color_green
	elif owner == "contested":
		# Colorize by FEBA depth
		if feba_km < 2.5:
			return color_contested_light
		elif feba_km < 7.5:
			return color_contested_medium
		else:
			return color_contested_heavy

	return color_none


func set_hex_owner(hex_id: String, owner: String) -> void:
	"""Set hex ownership state and update color."""
	if hex_id not in hex_states:
		return

	hex_states[hex_id]["owner"] = owner
	if hex_id in hex_cells:
		hex_cells[hex_id].color = get_hex_color(hex_id)


func set_hex_feba(hex_id: String, feba_km: float) -> void:
	"""Set FEBA cumulative movement for contested hex and update color."""
	if hex_id not in hex_states:
		return

	hex_states[hex_id]["feba_km"] = feba_km
	if hex_id in hex_cells:
		hex_cells[hex_id].color = get_hex_color(hex_id)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var click_pos = get_local_mouse_position()
		var hex_id = hex_grid.get_hex_by_point(click_pos)
		if hex_id != "":
			hex_clicked.emit(hex_id)
			get_tree().root.set_input_as_handled()


func _on_hex_mouse_entered(hex_id: String, area: Area2D) -> void:
	# Placeholder for future hover effects
	pass


func highlight_hexes(hex_ids: Array, highlight_color: Color = Color.YELLOW) -> void:
	"""Temporarily highlight a set of hexes (e.g., reachable movement range)."""
	for hex_id in hex_ids:
		if hex_id in hex_cells:
			var poly = hex_cells[hex_id]
			# Store original color and apply highlight overlay
			poly.modulate = highlight_color


func clear_highlights() -> void:
	"""Clear all highlight overlays."""
	for hex_id in hex_cells:
		hex_cells[hex_id].modulate = Color.WHITE
