extends RefCounted
class_name UnitManager


func get_brigade(brigade_id: String) -> Brigade:
	return GameData.get_brigade(brigade_id)


func get_brigades_in_hex(hex_id: String) -> Array:
	return GameData.get_brigades_in_hex(hex_id)


func set_brigade_hex(brigade_id: String, hex_id: String) -> void:
	GameData.set_brigade_hex(brigade_id, hex_id)


func reset_brigade_state() -> void:
	for brigade in GameData.brigades.values():
		brigade.moved_this_turn = false
		brigade.fought_this_turn = false


func create_unit_dict_from_brigade(brigade_id: String) -> Dictionary:
	var brigade := GameData.get_brigade(brigade_id)
	if brigade == null:
		return {}
	return {
		"brigade_id": brigade.id,
		"type": brigade.nato_type,
		"unit_count": brigade.get_battalion_count(),
		"supply_effectiveness": 1.0,
		"lat": 0.0,
		"lon": 0.0
	}


func get_unit_count_in_hex(hex_id: String, team: Brigade.Team = Brigade.Team.RED) -> int:
	return GameData.get_unit_count_in_hex(hex_id, team)
