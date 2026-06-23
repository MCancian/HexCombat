extends RefCounted
class_name HexMath

const AXIAL_DIRECTIONS: Array[Vector2i] = [
	Vector2i(0, -1),
	Vector2i(1, -1),
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(-1, 1),
	Vector2i(-1, 0)
]


static func neighbor_coords(coord: Vector2i) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	for direction in AXIAL_DIRECTIONS:
		neighbors.append(coord + direction)
	return neighbors


static func distance(a: Vector2i, b: Vector2i) -> int:
	var dq := a.x - b.x
	var dr := a.y - b.y
	return int((abs(dq) + abs(dq + dr) + abs(dr)) / 2)


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
