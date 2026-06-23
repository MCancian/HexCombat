extends Node2D
class_name HexMap

var projection: MapProjection
var symbol_library: SymbolLibrary
var hex_cells: Dictionary = {}  # hex_id -> Polygon2D
var projected_vertices: Dictionary = {}  # hex_id -> PackedVector2Array
var brigade_markers: Dictionary = {}  # brigade_id -> Node2D

var color_none = Color(0.85, 0.85, 0.85)
var color_red = Color(1.0, 0.3, 0.3)
var color_green = Color(0.3, 1.0, 0.3)
var color_contested_light = Color(0.9, 1.0, 0.7)
var color_contested_medium = Color(1.0, 1.0, 0.5)
var color_contested_heavy = Color(1.0, 0.8, 0.5)

signal hex_clicked(hex_id: String)


func _ready() -> void:
	projection = MapProjection.new(get_viewport_rect().size)
	symbol_library = SymbolLibrary.new()
	spawn_hex_cells()
	render_brigade_markers()


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


func render_brigade_markers() -> void:
	for brigade_id in brigade_markers:
		var existing_marker := brigade_markers[brigade_id] as Node
		if existing_marker != null:
			existing_marker.queue_free()
	brigade_markers.clear()

	for brigade_id in GameData.brigades:
		var brigade := GameData.brigades[brigade_id] as Brigade
		if brigade.hex_id.is_empty():
			continue

		var hex := GameData.get_hex(brigade.hex_id)
		if hex == null:
			push_error("Placed brigade '%s' references unknown hex_id '%s'" % [brigade.id, brigade.hex_id])
			continue

		var texture := symbol_library.texture_for_nato_type(brigade.nato_type)
		assert(texture != null, "Placed brigade '%s' nato_type '%s' has no renderable NATO symbol" % [brigade.id, brigade.nato_type])
		if texture == null:
			continue

		var center := projection.project(hex.center)
		var vertices := projected_vertices.get(hex.id, PackedVector2Array()) as PackedVector2Array
		var radius := _estimate_hex_radius(center, vertices)
		var bearing_radians := deg_to_rad(brigade.entry_bearing)
		var offset := Vector2(sin(bearing_radians), -cos(bearing_radians)) * (0.4 * radius)

		var marker := _build_brigade_marker(brigade, texture)
		marker.position = center + offset
		add_child(marker)
		brigade_markers[brigade.id] = marker

	print_debug("Rendered %d brigade markers" % brigade_markers.size())


func _estimate_hex_radius(center: Vector2, vertices: PackedVector2Array) -> float:
	assert(vertices.size() >= 3, "Cannot estimate hex radius without projected vertices")
	var total := 0.0
	for vertex in vertices:
		total += center.distance_to(vertex)
	return total / float(vertices.size())


func _build_brigade_marker(brigade: Brigade, texture: Texture2D) -> Node2D:
	var marker := Node2D.new()
	marker.name = "BrigadeMarker_%s" % brigade.id
	marker.z_index = 10

	var backing := Polygon2D.new()
	backing.name = "TeamBacking"
	backing.polygon = PackedVector2Array([
		Vector2(-41.0, -29.0),
		Vector2(41.0, -29.0),
		Vector2(41.0, 29.0),
		Vector2(-41.0, 29.0),
	])
	backing.color = _team_marker_color(brigade.team)
	backing.z_index = 0
	marker.add_child(backing)

	var sprite := Sprite2D.new()
	sprite.name = "NATOSymbol"
	sprite.texture = texture
	sprite.centered = true
	var texture_height := float(texture.get_height())
	assert(texture_height > 0.0, "NATO symbol texture has invalid height for brigade '%s'" % brigade.id)
	sprite.scale = Vector2.ONE * (48.0 / texture_height)
	sprite.z_index = 1
	marker.add_child(sprite)

	return marker


func _team_marker_color(team: Brigade.Team) -> Color:
	match team:
		Brigade.Team.RED:
			return Color(0.85, 0.05, 0.05, 0.9)
		Brigade.Team.GREEN:
			return Color(0.0, 0.55, 0.1, 0.9)
		_:
			push_error("Unknown brigade team for marker color: %d" % team)
			return Color(1.0, 0.0, 1.0, 0.82)


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
