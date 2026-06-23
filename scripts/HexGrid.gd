extends RefCounted
class_name HexGrid


func get_neighbors(hex_id: String) -> Array:
	return GameData.get_neighbors(hex_id)


func get_distance(hex_id_a: String, hex_id_b: String) -> int:
	return GameData.get_distance(hex_id_a, hex_id_b)


func find_path(start_id: String, goal_id: String, blocked: Array = []) -> Array:
	return GameData.find_path(start_id, goal_id, blocked)


func find_reachable(start_id: String, max_distance: int, blocked: Array = []) -> Array:
	return GameData.find_reachable(start_id, max_distance, blocked)
