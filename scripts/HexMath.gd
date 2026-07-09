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


# entry_cost(hex_id) -> int: movement-point cost to ENTER hex_id. Defaults to a uniform cost of 1
# per hex (plain BFS distance), preserving prior behavior for callers that don't pass one.
static func _entry_cost(entry_cost: Callable, hex_id) -> int:
	if entry_cost.is_valid():
		return entry_cost.call(hex_id)
	return 1


# Cost-aware (Dijkstra) shortest path. Impassability is expressed via `blocked` (the caller merges
# in every impassable hex_id). No min-one-step guarantee here — that's a find_reachable-only rule.
static func find_path(start_id: String, goal_id: String, get_neighbors: Callable, blocked: Array = [], entry_cost: Callable = Callable()) -> Array:
	if start_id == goal_id:
		return [start_id]

	var blocked_set := {}
	for blocked_id in blocked:
		blocked_set[blocked_id] = true

	var best_cost := {start_id: 0}
	var parent := {}
	var visited := {}
	var frontier: Array = [[0, start_id]]  # [cost, hex_id]

	while frontier.size() > 0:
		var pop_index := _lowest_cost_index(frontier)
		var current = frontier.pop_at(pop_index)
		var current_cost: int = current[0]
		var current_id = current[1]
		if current_id in visited:
			continue
		visited[current_id] = true
		if current_id == goal_id:
			return _reconstruct_path(start_id, goal_id, parent)

		for neighbor_id in get_neighbors.call(current_id):
			if neighbor_id in visited or neighbor_id in blocked_set:
				continue
			var new_cost: int = current_cost + _entry_cost(entry_cost, neighbor_id)
			if not best_cost.has(neighbor_id) or new_cost < best_cost[neighbor_id]:
				best_cost[neighbor_id] = new_cost
				parent[neighbor_id] = current_id
				frontier.append([new_cost, neighbor_id])

	return []


# Cost-aware (Dijkstra) reachable set: every hex whose cumulative entry cost is <= max_distance,
# PLUS (min-one-step guarantee) every passable direct neighbor of start regardless of its cost —
# a unit that has not yet moved may always take one step into an adjacent passable hex.
static func find_reachable(start_id: String, max_distance: int, get_neighbors: Callable, blocked: Array = [], entry_cost: Callable = Callable()) -> Array:
	var blocked_set := {}
	for blocked_id in blocked:
		blocked_set[blocked_id] = true

	var reachable: Array = [start_id]
	var best_cost := {start_id: 0}
	var visited := {}
	var frontier: Array = [[0, start_id]]  # [cost, hex_id]

	while frontier.size() > 0:
		var pop_index := _lowest_cost_index(frontier)
		var current = frontier.pop_at(pop_index)
		var current_cost: int = current[0]
		var current_id = current[1]
		if current_id in visited:
			continue
		visited[current_id] = true

		for neighbor_id in get_neighbors.call(current_id):
			if neighbor_id in visited or neighbor_id in blocked_set:
				continue
			var new_cost: int = current_cost + _entry_cost(entry_cost, neighbor_id)
			if new_cost > max_distance:
				continue
			if not best_cost.has(neighbor_id) or new_cost < best_cost[neighbor_id]:
				best_cost[neighbor_id] = new_cost
				if not neighbor_id in reachable:
					reachable.append(neighbor_id)
				frontier.append([new_cost, neighbor_id])

	for neighbor_id in get_neighbors.call(start_id):
		if not neighbor_id in blocked_set and not neighbor_id in reachable:
			reachable.append(neighbor_id)

	return reachable


# Linear-scan min extraction (frontiers stay small — hex grids here run in the hundreds).
static func _lowest_cost_index(frontier: Array) -> int:
	var best_index := 0
	for i in range(1, frontier.size()):
		if frontier[i][0] < frontier[best_index][0]:
			best_index = i
	return best_index


static func _reconstruct_path(start_id: String, goal_id: String, parent: Dictionary) -> Array:
	var path: Array = []
	var node := goal_id
	while node in parent:
		path.push_front(node)
		node = parent[node]
	path.push_front(start_id)
	return path
