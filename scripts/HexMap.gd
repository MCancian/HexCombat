extends Node2D
class_name HexMap

var projection: MapProjection
var hex_cells: Dictionary = {}  # hex_id -> Polygon2D
var projected_vertices: Dictionary = {}  # hex_id -> PackedVector2Array

var color_none = Color(0.85, 0.85, 0.85)
var color_red = Color(1.0, 0.3, 0.3)
var color_green = Color(0.3, 1.0, 0.3)
var color_contested_light = Color(0.9, 1.0, 0.7)
var color_contested_medium = Color(1.0, 1.0, 0.5)
var color_contested_heavy = Color(1.0, 0.8, 0.5)

signal hex_clicked(hex_id: String)


func _ready() -> void:
	projection = MapProjection.new(get_viewport_rect().size)
	spawn_hex_cells()


func spawn_hex_cells() -> void:
	for hex in GameData.hexes:
		var vertices := projection.project_vertices(hex.vertices)
		if vertices.size() < 3:
			continue

		var poly := Polygon2D.new()
		poly.polygon = vertices
		poly.color = get_hex_color(hex.id)
		poly.z_index = 0

		# Polygon2D has no outline in Godot 4; draw a closed border with Line2D.
		var outline := Line2D.new()
		outline.points = vertices
		outline.closed = true
		outline.width = 2.0
		outline.default_color = Color.BLACK
		poly.add_child(outline)

		add_child(poly)
		hex_cells[hex.id] = poly
		projected_vertices[hex.id] = vertices

	print_debug("Spawned %d hex cells" % hex_cells.size())


func get_hex_color(hex_id: String) -> Color:
	if hex_id not in GameData.hex_states:
		return color_none

	var state = GameData.hex_states[hex_id]
	var owner = state.get("owner", "green")
	var feba_km = state.get("feba_km", 0.0)

	if owner == "red":
		return color_red
	elif owner == "green":
		return color_green
	elif owner == "contested":
		if feba_km < 2.5:
			return color_contested_light
		elif feba_km < 7.5:
			return color_contested_medium
		else:
			return color_contested_heavy

	return color_none


func refresh_hex(hex_id: String) -> void:
	if hex_id in hex_cells:
		hex_cells[hex_id].color = get_hex_color(hex_id)


func set_hex_owner(hex_id: String, owner: String) -> void:
	GameData.set_hex_owner(hex_id, owner)
	refresh_hex(hex_id)


func set_hex_feba(hex_id: String, feba_km: float) -> void:
	GameData.set_hex_feba(hex_id, feba_km)
	refresh_hex(hex_id)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var hex_id := get_hex_by_point(get_local_mouse_position())
		if hex_id != "":
			hex_clicked.emit(hex_id)
			get_tree().root.set_input_as_handled()


func get_hex_by_point(point: Vector2) -> String:
	for hex_id in projected_vertices:
		if Geometry2D.is_point_in_polygon(point, projected_vertices[hex_id]):
			return hex_id
	return ""


func highlight_hexes(hex_ids: Array, highlight_color: Color = Color.YELLOW) -> void:
	for hex_id in hex_ids:
		if hex_id in hex_cells:
			hex_cells[hex_id].modulate = highlight_color


func clear_highlights() -> void:
	for hex_id in hex_cells:
		hex_cells[hex_id].modulate = Color.WHITE
