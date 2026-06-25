class_name Theaters
extends RefCounted

# Pure theater/TO lookup helpers backed by theater maps loaded by the GameData autoload.


static func to_for_beach(beach_id: int) -> int:
	if beach_id not in GameData.beach_to_to:
		push_error("Theaters.to_for_beach: unknown beach id %d" % beach_id)
		assert(false)
		return 0
	return int(GameData.beach_to_to[beach_id])


static func adjacent_tos(to: int) -> Array[int]:
	if to not in GameData.to_adjacency:
		push_error("Theaters.adjacent_tos: unknown TO %d" % to)
		assert(false)
		return []
	var result: Array[int] = []
	for neighbor_to in GameData.to_adjacency[to]:
		result.append(int(neighbor_to))
	return result


static func all_tos() -> Array[int]:
	var result: Array[int] = []
	for to in GameData.active_tos:
		result.append(int(to))
	return result


static func are_adjacent(a: int, b: int) -> bool:
	if a not in GameData.to_adjacency:
		push_error("Theaters.are_adjacent: unknown TO %d" % a)
		assert(false)
		return false
	if b not in GameData.to_adjacency:
		push_error("Theaters.are_adjacent: unknown TO %d" % b)
		assert(false)
		return false
	return b in GameData.to_adjacency[a]
