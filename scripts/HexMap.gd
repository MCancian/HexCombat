extends Node2D
class_name HexMap

var projection: MapProjection
var symbol_library: SymbolLibrary
var hex_cells: Dictionary = {}  # hex_id -> Polygon2D
var projected_vertices: Dictionary = {}  # hex_id -> PackedVector2Array
var brigade_markers: Dictionary = {}  # brigade_id -> Node2D
var beach_markers: Dictionary = {}  # beach_id (int) -> Node2D
var _highlight_overlays: Array[Node2D] = []
var _stack_badges: Array[Node2D] = []
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
	render_beach_markers()
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


# Beaches are static (fixed hex_id per data/beaches.json) so this only needs to run once at
# startup, unlike brigade markers which re-render every turn. Glyphs anchor toward the hex's
# bottom-left rather than the center, so they never collide with the entry-bearing offset or
# center-pinned placements render_brigade_markers() uses for brigades landed on the same hex.
func render_beach_markers() -> void:
	for beach_id in GameData.beaches:
		var beach: BeachDef = GameData.beaches[beach_id]
		var hex := GameData.get_hex(beach.hex_id)
		if hex == null:
			push_error("Beach '%d' references unknown hex_id '%s'" % [beach.id, beach.hex_id])
			continue

		var center := projection.project(hex.center)
		var vertices := projected_vertices.get(beach.hex_id, PackedVector2Array()) as PackedVector2Array
		var radius := _estimate_hex_radius(center, vertices)

		var marker := _build_beach_marker(beach, radius)
		marker.position = center + Vector2(-0.55, 0.55).normalized() * (radius * 0.62)
		add_child(marker)
		beach_markers[beach.id] = marker

	print_debug("Rendered %d beach markers" % beach_markers.size())


func _build_beach_marker(beach: BeachDef, radius: float) -> Node2D:
	var marker := Node2D.new()
	marker.name = "BeachMarker_%d" % beach.id
	# Above hex fills (z 0) and the highlight overlay tint (z 5), below brigade markers (z 10).
	marker.z_index = 6

	var glyph_size := radius * 0.7
	var points := PackedVector2Array([
		Vector2(0, -glyph_size),
		Vector2(glyph_size * 0.87, glyph_size * 0.5),
		Vector2(-glyph_size * 0.87, glyph_size * 0.5),
	])

	var triangle := Polygon2D.new()
	triangle.name = "BeachGlyph"
	triangle.polygon = points
	triangle.color = Color(0.05, 0.15, 0.55, 0.95)  # dark blue
	marker.add_child(triangle)

	var outline := Line2D.new()
	outline.name = "BeachGlyphOutline"
	outline.points = points
	outline.closed = true
	outline.width = 1.5
	outline.default_color = Color.WHITE
	triangle.add_child(outline)

	# Number sits inside the triangle (white on dark blue) — beside/below it the digit
	# disappears against light terrain fills. Centered slightly below the glyph centroid,
	# where the triangle is widest.
	var label := Label.new()
	label.name = "BeachLabel"
	label.text = str(beach.id)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.15, 0.55))
	label.add_theme_constant_override("outline_size", 1)
	label.add_theme_font_size_override("font_size", maxi(10, int(radius * 0.55)))
	# Box must exceed the Label's minimum size or Godot clamps it and the centered text
	# drifts; oversize it and center it on the widest part of the triangle (just below
	# the centroid).
	var label_size := Vector2(glyph_size * 4.0, glyph_size * 3.0)
	label.size = label_size
	label.position = Vector2(-label_size.x / 2.0, -label_size.y / 2.0 + glyph_size * 0.05)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	marker.add_child(label)

	return marker


func render_brigade_markers() -> void:
	for brigade_id in brigade_markers:
		var existing_marker := brigade_markers[brigade_id] as Node
		if existing_marker != null:
			var marker_parent := existing_marker.get_parent()
			if marker_parent != null:
				marker_parent.remove_child(existing_marker)
			existing_marker.free()
	brigade_markers.clear()

	for badge in _stack_badges:
		if badge != null:
			var badge_parent := badge.get_parent()
			if badge_parent != null:
				badge_parent.remove_child(badge)
			badge.free()
	_stack_badges.clear()

	var hex_groups: Dictionary = {}
	for brigade_id in GameData.brigades:
		var brigade := GameData.brigades[brigade_id] as Brigade
		if brigade.hex_id.is_empty():
			continue
		if not hex_groups.has(brigade.hex_id):
			hex_groups[brigade.hex_id] = []
		hex_groups[brigade.hex_id].append(brigade)

	for hex_id in hex_groups:
		var brigades_on_hex: Array = hex_groups[hex_id]
		brigades_on_hex.sort_custom(func(a: Brigade, b: Brigade): return a.id < b.id)

		var hex := GameData.get_hex(hex_id)
		if hex == null:
			for brigade in brigades_on_hex:
				push_error("Placed brigade '%s' references unknown hex_id '%s'" % [brigade.id, hex_id])
			continue

		var center := projection.project(hex.center)
		var vertices := projected_vertices.get(hex_id, PackedVector2Array()) as PackedVector2Array
		var radius := _estimate_hex_radius(center, vertices)
		var n := brigades_on_hex.size()

		for i in range(n):
			var brigade := brigades_on_hex[i] as Brigade
			var texture := symbol_library.texture_for_nato_type(brigade.nato_type)
			assert(texture != null, "Placed brigade '%s' nato_type '%s' has no renderable NATO symbol" % [brigade.id, brigade.nato_type])
			if texture == null:
				continue

			var marker := _build_brigade_marker(brigade, texture, radius)

			if n == 1:
				# A full-size marker (1.9×radius wide) overflows into adjacent hexes (1.73×radius
				# apart), so in crowded neighborhoods (any occupied neighbor hex) shrink it and
				# pin it to the hex center instead of the entry-bearing offset.
				if _has_occupied_neighbor(hex_id, hex_groups):
					marker.scale = Vector2.ONE * 0.75
					marker.position = center
				else:
					var bearing_radians := deg_to_rad(brigade.entry_bearing)
					var offset := Vector2(sin(bearing_radians), -cos(bearing_radians)) * (0.4 * radius)
					marker.position = center + offset
			else:
				marker.scale = Vector2.ONE * 0.62
				var angle := -PI / 2.0 + TAU * i / n
				marker.position = center + Vector2(cos(angle), sin(angle)) * (0.45 * radius)

			add_child(marker)
			brigade_markers[brigade.id] = marker

		if n >= 3:
			var badge := _build_stack_badge(n, radius)
			badge.position = center
			add_child(badge)
			_stack_badges.append(badge)

	print_debug("Rendered %d brigade markers" % brigade_markers.size())


func _has_occupied_neighbor(hex_id: String, hex_groups: Dictionary) -> bool:
	for neighbor_id in GameData.get_neighbors(hex_id):
		if hex_groups.has(neighbor_id):
			return true
	return false


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


func _build_stack_badge(n: int, radius: float) -> Node2D:
	var badge := Node2D.new()
	badge.z_index = 12

	var disc_radius := radius * 0.28
	var disc := Polygon2D.new()
	var points: PackedVector2Array = []
	var num_points := 16
	for i in range(num_points):
		var a := TAU * i / num_points
		points.append(Vector2(cos(a), sin(a)) * disc_radius)
	disc.polygon = points
	disc.color = Color(1, 1, 1, 0.92)
	badge.add_child(disc)

	var outline := Line2D.new()
	outline.points = points
	outline.closed = true
	outline.width = 1.5
	outline.default_color = Color.BLACK
	disc.add_child(outline)

	var label := Label.new()
	label.text = "×%d" % n
	label.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
	var font_size := maxi(10, int(radius * 0.45))
	label.add_theme_font_size_override("font_size", font_size)
	label.position = Vector2(-disc_radius, -disc_radius)
	label.size = Vector2(disc_radius * 2, disc_radius * 2)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(label)

	return badge


func _team_marker_color(team: Brigade.Team) -> Color:
	match team:
		Brigade.Team.RED:
			return Color(0.85, 0.05, 0.05, 0.9)
		Brigade.Team.GREEN:
			return Color(0.0, 0.55, 0.1, 0.9)
		_:
			push_error("Unknown brigade team for marker color: %d" % team)
			return Color(1.0, 0.0, 1.0, 0.82)


# Ownership-only color (pre-Track-F behavior): red/green/contested-ramp, gray when unowned.
func _ownership_color(hex_id: String) -> Color:
	if hex_id not in GameData.hex_states:
		return color_none

	var state: HexState = GameData.hex_states[hex_id]
	var owner := state.owner
	var feba_km := state.feba_km

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


func _is_hex_owned(hex_id: String) -> bool:
	if hex_id not in GameData.hex_states:
		return false
	return GameData.hex_states[hex_id].owner != HexOwner.NONE


# Terrain (data/terrain/terrain_types.json, via GameData.get_terrain) tints the base fill;
# ownership is blended over it so ownership always reads instantly. Unowned hexes show
# ~full terrain color (nudged toward mid-gray so fills don't look flat/saturated); owned or
# contested hexes lerp terrain->ownership at a weight that keeps ownership clearly dominant.
# Hexes with no terrain classification (empty TerrainType.color) fall back to the ownership-only
# color — pre-Track-F behavior.
func get_hex_color(hex_id: String) -> Color:
	var ownership_color := _ownership_color(hex_id)

	var terrain: TerrainType = GameData.get_terrain(hex_id)
	if terrain == null or terrain.color.is_empty():
		return ownership_color

	var terrain_color := Color(terrain.color)

	if _is_hex_owned(hex_id):
		return terrain_color.lerp(ownership_color, 0.35)

	return terrain_color.lerp(Color(0.5, 0.5, 0.5), 0.15)


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
