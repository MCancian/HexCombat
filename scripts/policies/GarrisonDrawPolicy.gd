class_name GarrisonDrawPolicy
extends RefCounted

var _beach_to_to: Dictionary = {}
var _brigade_to_number: Dictionary = {}
var _draw_fraction: float = -1.0

func _init(beach_to_to: Dictionary = {}, brigade_to_number: Dictionary = {}, draw_fraction: float = -1.0) -> void:
	if not beach_to_to.is_empty():
		_beach_to_to = beach_to_to
		_brigade_to_number = brigade_to_number
		_draw_fraction = draw_fraction

func build_actions(observation: Dictionary) -> Array:
	if _draw_fraction < 0.0:
		var game_data: Node = Engine.get_main_loop().root.get_node("GameData")
		for beach_id in game_data.beach_to_to:
			var to_number: int = game_data.beach_to_to[beach_id]
			var beach = game_data.beaches[beach_id]
			_beach_to_to[String(beach.hex_id)] = to_number

		for brigade_id in game_data.brigades:
			var brigade = game_data.brigades[brigade_id]
			if brigade.team == Brigade.Team.GREEN:
				_brigade_to_number[String(brigade_id)] = brigade.to_number

		var content := FileAccess.get_file_as_string("res://data/policies/garrison_draw.json")
		var parsed: Dictionary = JSON.parse_string(content)
		parsed = DataOverrides.apply("data/policies/garrison_draw.json", parsed)
		_draw_fraction = float(parsed.get("draw_fraction", 0.0))

	var landing_tos := {}

	var occupied_hexes: Array = observation.get("occupied_hexes", [])
	for hex_info in occupied_hexes:
		var owner: String = hex_info.get("owner", "")
		if owner == "red" or owner == "contested":
			var hex_id: String = hex_info.get("hex_id", "")
			if _beach_to_to.has(hex_id):
				landing_tos[_beach_to_to[hex_id]] = true

	var brigades_obs: Array = observation.get("brigades", [])
	for b in brigades_obs:
		if b.get("team", "") == "Red":
			var hex_id: String = b.get("hex_id", "")
			if _beach_to_to.has(hex_id):
				landing_tos[_beach_to_to[hex_id]] = true

	var in_landing: Array[String] = []
	var other_to: Array[String] = []

	var legal_moves: Dictionary = observation.get("legal_moves", {})
	for bid in legal_moves.keys():
		var lm: Dictionary = legal_moves[bid]
		if lm.get("team", "") == "Green":
			var bid_str := String(bid)
			var to_num: int = _brigade_to_number.get(bid_str, 0)
			if landing_tos.has(to_num):
				in_landing.append(bid_str)
			else:
				other_to.append(bid_str)

	other_to.sort()
	var draw_count := int(ceil(other_to.size() * _draw_fraction))
	var drawn_brigades := {}
	for i in range(draw_count):
		drawn_brigades[other_to[i]] = true

	var landing_hexes: Array[String] = []
	for hex_id in _beach_to_to:
		if landing_tos.has(_beach_to_to[hex_id]):
			landing_hexes.append(hex_id)

	var red_hexes: Array[String] = []
	for b in brigades_obs:
		if b.get("team", "") == "Red":
			red_hexes.append(String(b.get("hex_id", "")))

	var actions: Array = []
	var brigade_ids: Array = legal_moves.keys()
	brigade_ids.sort()

	for bid in brigade_ids:
		var lm: Dictionary = legal_moves[bid]
		if String(lm.get("team", "")) != "Green":
			continue

		var from_hex := String(lm.get("from_hex", ""))
		var tactical: Array = lm.get("tactical", [])
		if tactical.is_empty():
			continue

		var b_is_drawn: bool = drawn_brigades.has(bid)
		var b_is_in_landing: bool = in_landing.has(bid)

		var best_target := ""

		if b_is_drawn and not landing_hexes.is_empty():
			best_target = PolicyGeometry.nearest_hex_by_id(tactical, landing_hexes)
		elif b_is_in_landing and not red_hexes.is_empty():
			best_target = PolicyGeometry.nearest_hex_by_id(tactical, red_hexes)
		else:
			continue

		if best_target != "" and best_target != from_hex:
			actions.append({
				"type": "move",
				"team": "Green",
				"brigade_id": String(bid),
				"target_hex": best_target,
				"mode": Movement.MODE_TACTICAL,
			})

	return actions
