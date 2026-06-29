extends RefCounted
class_name HexMath

# Coordinates are stored as OFFSET (odd-r, pointy-top): coord = Vector2i(row, col), where odd rows
# are shifted right by half a hex (see data/taiwan_hex_grid.json generation). Neighbor offsets are
# therefore row-parity dependent, matching TIV's src/core/hex_grid.py get_hex_neighbors. Distance is
# computed by converting odd-r -> cube and taking the cube distance. (Empirically validated: odd-r
# neighbors match true great-circle geometry on 308/308 interior hexes; the prior axial scheme
# matched only 23/308.)
const ODDR_NEIGHBORS_EVEN: Array[Vector2i] = [
	Vector2i(-1, -1),
	Vector2i(-1, 0),
	Vector2i(0, -1),
	Vector2i(0, 1),
	Vector2i(1, -1),
	Vector2i(1, 0)
]
const ODDR_NEIGHBORS_ODD: Array[Vector2i] = [
	Vector2i(-1, 0),
	Vector2i(-1, 1),
	Vector2i(0, -1),
	Vector2i(0, 1),
	Vector2i(1, 0),
	Vector2i(1, 1)
]


static func neighbor_coords(coord: Vector2i) -> Array[Vector2i]:
	# coord.x = row, coord.y = col. Pick the offset table by row parity (odd-r layout).
	var offsets := ODDR_NEIGHBORS_ODD if (coord.x & 1) == 1 else ODDR_NEIGHBORS_EVEN
	var neighbors: Array[Vector2i] = []
	for offset in offsets:
		neighbors.append(coord + offset)
	return neighbors


# Convert an odd-r offset coord (Vector2i(row, col)) to cube coords.
static func _offset_to_cube(coord: Vector2i) -> Vector3i:
	var row := coord.x
	var col := coord.y
	var x := col - (row - (row & 1)) / 2  # (row - (row & 1)) is always even -> exact
	var z := row
	var y := -x - z
	return Vector3i(x, y, z)


static func distance(a: Vector2i, b: Vector2i) -> int:
	var ac := _offset_to_cube(a)
	var bc := _offset_to_cube(b)
	return int((abs(ac.x - bc.x) + abs(ac.y - bc.y) + abs(ac.z - bc.z)) / 2)


static func find_path(start_id: String, goal_id: String, get_neighbors: Callable, blocked: Array = []) -> Array:
	if start_id == goal_id:
		return [start_id]

	var blocked_set := {}
	for blocked_id in blocked:
		blocked_set[blocked_id] = true

	var visited := {}
	var parent := {}
	var queue: Array = [start_id]
	visited[start_id] = true

	while queue.size() > 0:
		var current_id = queue.pop_front()
		if current_id == goal_id:
			return _reconstruct_path(start_id, goal_id, parent)

		for neighbor_id in get_neighbors.call(current_id):
			if not neighbor_id in visited and not neighbor_id in blocked_set:
				visited[neighbor_id] = true
				parent[neighbor_id] = current_id
				queue.append(neighbor_id)

	return []


static func find_reachable(start_id: String, max_distance: int, get_neighbors: Callable, blocked: Array = []) -> Array:
	var blocked_set := {}
	for blocked_id in blocked:
		blocked_set[blocked_id] = true

	var reachable: Array = [start_id]
	var visited := {}
	visited[start_id] = true
	var queue: Array = [[start_id, 0]]

	while queue.size() > 0:
		var current = queue.pop_front()
		var current_id = current[0]
		var current_dist = current[1]
		if current_dist >= max_distance:
			continue

		for neighbor_id in get_neighbors.call(current_id):
			if not neighbor_id in visited and not neighbor_id in blocked_set:
				visited[neighbor_id] = true
				reachable.append(neighbor_id)
				queue.append([neighbor_id, current_dist + 1])

	return reachable


static func _reconstruct_path(start_id: String, goal_id: String, parent: Dictionary) -> Array:
	var path: Array = []
	var node := goal_id
	while node in parent:
		path.push_front(node)
		node = parent[node]
	path.push_front(start_id)
	return path
