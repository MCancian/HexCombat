extends Node
class_name HexGrid

var hexes: Array = []  # Array of hex dicts from JSON
var hex_lookup: Dictionary = {}  # hex_id -> hex dict
var neighbor_lookup: Dictionary = {}  # hex_id -> [neighbor hex_ids]
var position_lookup: Dictionary = {}  # hex_id -> Vector2 (screen pos)

# Taiwan bounding box (lat/lon)
const LAT_MIN = 21.9
const LAT_MAX = 25.3
const LON_MIN = 119.9
const LON_MAX = 122.1

# Screen dimensions (canvas size in pixels)
var screen_width: int = 1600
var screen_height: int = 1400

func _ready() -> void:
	load_hex_grid()
	build_neighbor_lookup()


func load_hex_grid() -> void:
	var file = FileAccess.open("res://data/taiwan_hex_grid.json", FileAccess.READ)
	if file == null:
		print_debug("Error: Could not open taiwan_hex_grid.json")
		return

	var json_str = file.get_as_text()
	var json = JSON.parse_string(json_str)

	# Handle both direct array and object with "hexes" field
	if json is Array:
		hexes = json
	elif json is Dictionary and "hexes" in json:
		hexes = json["hexes"]
	else:
		print_debug("Error: JSON format not recognized")
		return

	# Build lookup dictionaries
	for hex in hexes:
		var hex_id = hex.get("id", "")
		hex_lookup[hex_id] = hex

		# Store projected screen position at hex center
		var center = hex.get("center", {})
		var lat = center.get("lat", 0.0)
		var lon = center.get("lon", 0.0)
		position_lookup[hex_id] = project_coords(lat, lon)

	print_debug("Loaded %d hexes" % hexes.size())


func build_neighbor_lookup() -> void:
	# Build adjacency by checking row/col offsets (simpler and more reliable)
	# Odd-r hex grid neighbor offsets
	var neighbor_offsets = [
		[0, -1],  # N
		[1, -1],  # NE
		[1, 0],   # SE
		[0, 1],   # S
		[-1, 1],  # SW
		[-1, 0]   # NW
	]

	for hex_id in hex_lookup:
		var neighbors: Array = []
		var hex_data = hex_lookup[hex_id]
		var row = hex_data.get("row", 0)
		var col = hex_data.get("col", 0)

		for offset in neighbor_offsets:
			var n_row = row + offset[0]
			var n_col = col + offset[1]
			var neighbor_id = "hex_%d_%d" % [n_row, n_col]

			if neighbor_id in hex_lookup:
				neighbors.append(neighbor_id)

		neighbor_lookup[hex_id] = neighbors

	print_debug("Built neighbor lookup for %d hexes" % neighbor_lookup.size())


func project_coords(lat: float, lon: float) -> Vector2:
	"""Convert lat/lon to screen pixels using linear projection."""
	var x = (lon - LON_MIN) / (LON_MAX - LON_MIN) * screen_width
	var y = (1.0 - (lat - LAT_MIN) / (LAT_MAX - LAT_MIN)) * screen_height
	return Vector2(x, y)


func get_neighbors(hex_id: String) -> Array:
	"""Return list of neighbor hex IDs for the given hex."""
	return neighbor_lookup.get(hex_id, [])


func get_distance(hex_id_a: String, hex_id_b: String) -> int:
	"""Return Manhattan distance in hexes between two hexes (BFS distance)."""
	if not hex_id_a in hex_lookup or not hex_id_b in hex_lookup:
		return -1

	if hex_id_a == hex_id_b:
		return 0

	var visited: Dictionary = {}
	var queue: Array = [[hex_id_a, 0]]
	visited[hex_id_a] = true

	while queue.size() > 0:
		var current = queue.pop_front()
		var current_id = current[0]
		var current_dist = current[1]

		if current_id == hex_id_b:
			return current_dist

		for neighbor_id in get_neighbors(current_id):
			if not neighbor_id in visited:
				visited[neighbor_id] = true
				queue.append([neighbor_id, current_dist + 1])

	return -1  # No path found


func find_path(start_id: String, goal_id: String, blocked: Array = []) -> Array:
	"""BFS pathfinding. Return list of hex IDs from start to goal.
	blocked: array of hex_ids to treat as obstacles."""

	if not start_id in hex_lookup or not goal_id in hex_lookup:
		return []

	if start_id == goal_id:
		return [start_id]

	var blocked_set: Dictionary = {}
	for b in blocked:
		blocked_set[b] = true

	var visited: Dictionary = {}
	var parent: Dictionary = {}
	var queue: Array = [start_id]
	visited[start_id] = true

	while queue.size() > 0:
		var current_id = queue.pop_front()

		if current_id == goal_id:
			# Reconstruct path
			var path: Array = []
			var node = goal_id
			while node in parent:
				path.push_front(node)
				node = parent[node]
			path.push_front(start_id)
			return path

		for neighbor_id in get_neighbors(current_id):
			if not neighbor_id in visited and not neighbor_id in blocked_set:
				visited[neighbor_id] = true
				parent[neighbor_id] = current_id
				queue.append(neighbor_id)

	return []  # No path found


func find_reachable(start_id: String, max_distance: int, blocked: Array = []) -> Array:
	"""Return all hex IDs reachable within max_distance hexes from start.
	blocked: array of hex_ids to treat as obstacles."""

	if not start_id in hex_lookup:
		return []

	var blocked_set: Dictionary = {}
	for b in blocked:
		blocked_set[b] = true

	var reachable: Array = []
	var visited: Dictionary = {}
	var queue: Array = [[start_id, 0]]
	visited[start_id] = true
	reachable.append(start_id)

	while queue.size() > 0:
		var current = queue.pop_front()
		var current_id = current[0]
		var current_dist = current[1]

		if current_dist >= max_distance:
			continue

		for neighbor_id in get_neighbors(current_id):
			if not neighbor_id in visited and not neighbor_id in blocked_set:
				visited[neighbor_id] = true
				reachable.append(neighbor_id)
				queue.append([neighbor_id, current_dist + 1])

	return reachable


func get_hex_at_pos(hex_id: String) -> Vector2:
	"""Get screen position (center) of hex."""
	return position_lookup.get(hex_id, Vector2.ZERO)


func get_hex_vertices(hex_id: String) -> Array:
	"""Get screen-projected vertices of hex polygon."""
	if not hex_id in hex_lookup:
		return []

	var hex_data = hex_lookup[hex_id]
	var vertices = hex_data.get("vertices", [])
	var projected: Array = []

	for vertex in vertices:
		var lat = vertex.get("lat", 0.0)
		var lon = vertex.get("lon", 0.0)
		projected.append(project_coords(lat, lon))

	return projected


func get_hex_by_point(point: Vector2) -> String:
	"""Find hex at screen point. Return hex_id or empty string."""
	for hex_id in hex_lookup:
		var vertices = get_hex_vertices(hex_id)
		if vertices.size() < 3:
			continue

		# Simple point-in-polygon test (ray casting)
		if Geometry2D.is_point_in_polygon(point, PackedVector2Array(vertices)):
			return hex_id

	return ""
