extends Node2D
class_name HexMap

var projection: MapProjection
var symbol_library: SymbolLibrary
var hex_cells: Dictionary = {}  # hex_id -> Polygon2D
var projected_vertices: Dictionary = {}  # hex_id -> PackedVector2Array
var brigade_markers: Dictionary = {}  # brigade_id -> Node2D
var _highlight_overlays: Array[Node2D] = []
var _selected_hex: String = ""
var _reachable_hexes: Array = []

var color_none = Color(0.85, 0.85, 0.85)
var color_red = Color(1.0, 0.3, 0.3)
var color_green = Color(0.3, 1.0, 0.3)
# Contested hexes use an amber→orange→red-orange ramp that reads clearly against
# the green/red owner fills (a near-green contested tint was invisible at map scale).
var color_contested_light = Color(1.0, 0.85, 0.3)
var color_contested_medium = Color(1.0, 0.6, 0.15)
var color_contested_heavy = Color(0.95, 0.35, 0.1)

signal hex_clicked(hex_id: String)
signal selection_cancelled()


func _ready() -> void:
	projection = MapProjection.new(get_viewport_rect().size)
	symbol_library = SymbolLibrary.new()
	EventBus.hex_selected.connect(_on_hex_selected)
	EventBus.reachable_hexes_changed.connect(_on_reachable_hexes_changed)
	EventBus.selection_cleared.connect(_on_selection_cleared)
	EventBus.turn_advanced.connect(_on_turn_advanced)
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
			var marker_parent := existing_marker.get_parent()
			if marker_parent != null:
				marker_parent.remove_child(existing_marker)
			existing_marker.free()
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

		var marker := _build_brigade_marker(brigade, texture, radius)
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


func _build_brigade_marker(brigade: Brigade, texture: Texture2D, radius: float) -> Node2D:
	var marker := Node2D.new()
	marker.name = "BrigadeMarker_%s" % brigade.id
	marker.z_index = 10

	# Size the marker relative to the hex so it never dwarfs or overflows the cell.
	var half_w := radius * 0.95
	var half_h := radius * 0.68

	var backing := Polygon2D.new()
	backing.name = "TeamBacking"
	backing.polygon = PackedVector2Array([
		Vector2(-half_w, -half_h),
		Vector2(half_w, -half_h),
		Vector2(half_w, half_h),
		Vector2(-half_w, half_h),
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
	sprite.scale = Vector2.ONE * (radius * 1.1 / texture_height)
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
	var owner = state.get("owner", HexOwner.GREEN)
	var feba_km = state.get("feba_km", 0.0)

	if owner == HexOwner.RED:
		return color_red
	elif owner == HexOwner.GREEN:
		return color_green
	elif owner == HexOwner.CONTESTED:
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


func refresh_all_hex_colors() -> void:
	for hex_id in hex_cells:
		var typed_hex_id := String(hex_id)
		hex_cells[typed_hex_id].color = get_hex_color(typed_hex_id)


func set_hex_owner(hex_id: String, owner: String) -> void:
	GameData.set_hex_owner(hex_id, owner)
	refresh_hex(hex_id)


func set_hex_feba(hex_id: String, feba_km: float) -> void:
	GameData.set_hex_feba(hex_id, feba_km)
	refresh_hex(hex_id)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			selection_cancelled.emit()
			get_tree().root.set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			var hex_id := get_hex_by_point(get_local_mouse_position())
			if hex_id != "":
				hex_clicked.emit(hex_id)
				get_tree().root.set_input_as_handled()


func _on_hex_selected(hex_id: String) -> void:
	_selected_hex = hex_id
	_refresh_highlights()


func _on_reachable_hexes_changed(hex_ids: Array) -> void:
	_reachable_hexes = hex_ids
	_refresh_highlights()


func _on_selection_cleared() -> void:
	_selected_hex = ""
	_reachable_hexes = []
	clear_highlights()


func _on_turn_advanced(_turn_number: int) -> void:
	refresh_all_hex_colors()


func get_hex_by_point(point: Vector2) -> String:
	for hex_id in projected_vertices:
		if Geometry2D.is_point_in_polygon(point, projected_vertices[hex_id]):
			return hex_id
	return ""


# Draw highlights as translucent overlays ABOVE the hex fill (z 5) but below
# brigade markers (z 10). Using a tint overlay instead of `modulate` keeps the
# highlight visible regardless of the underlying owner color (modulate multiplies
# against the saturated green fill and washes out).
func highlight_hexes(hex_ids: Array, fill_color: Color, border_color: Color = Color.TRANSPARENT, border_width: float = 0.0) -> void:
	for hex_id in hex_ids:
		var vertices := projected_vertices.get(hex_id, PackedVector2Array()) as PackedVector2Array
		if vertices.size() < 3:
			continue

		var overlay := Polygon2D.new()
		overlay.polygon = vertices
		overlay.color = fill_color
		overlay.z_index = 5
		add_child(overlay)
		_highlight_overlays.append(overlay)

		if border_width > 0.0:
			var border := Line2D.new()
			border.points = vertices
			border.closed = true
			border.width = border_width
			border.default_color = border_color
			overlay.add_child(border)


func clear_highlights() -> void:
	for overlay in _highlight_overlays:
		if overlay != null:
			overlay.queue_free()
	_highlight_overlays.clear()


func _refresh_highlights() -> void:
	clear_highlights()
	highlight_hexes(_reachable_hexes, Color(0.1, 0.55, 1.0, 0.5))
	if _selected_hex != "":
		highlight_hexes([_selected_hex], Color(1.0, 0.9, 0.1, 0.45), Color(1.0, 0.85, 0.0), 4.0)
