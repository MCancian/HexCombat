class_name InlandClearPolicy
extends RefCounted

## Deterministic research policy (promoted from the plan-0006 C8 study; same rule as
## validate_deep_pool_smoke's inland loop): every RED brigade standing on a beach hex moves to
## that hex's first sorted non-beach neighbor, keeping the beach occupancy valve open so
## follow-on echelons keep landing — the land -> vacate -> land tempo loop. Green passes.
##
## Beach + adjacency data come from GameData on FIRST use, not at construction: PolicyCatalog
## creates policies inside SceneTree._initialize, which runs BEFORE autoload _ready — GameData
## is still empty there (this bit the first version: an empty beach set = a silent pass policy).
## Tests inject synthetic data through _init instead. Decisions are otherwise a pure function of
## the observation, so games stay seed-reproducible.

var _beach_hexes: Dictionary = {}  # hex_id (String) -> true
var _neighbor_lookup: Dictionary = {}  # hex_id (String) -> Array[String]


func _init(beach_hexes: Dictionary = {}, neighbor_lookup: Dictionary = {}) -> void:
	_beach_hexes = beach_hexes
	_neighbor_lookup = neighbor_lookup


func build_actions(observation: Dictionary) -> Array:
	if _beach_hexes.is_empty():
		var game_data: Node = Engine.get_main_loop().root.get_node("GameData")
		for beach_value in game_data.beaches.values():
			_beach_hexes[String(beach_value.hex_id)] = true
		_neighbor_lookup = game_data.neighbor_lookup
	var legal_moves: Dictionary = observation.get("legal_moves", {})
	var actions: Array = []
	var brigade_ids: Array = legal_moves.keys()
	brigade_ids.sort()
	for brigade_id in brigade_ids:
		var lm: Dictionary = legal_moves[brigade_id] as Dictionary
		if String(lm.get("team", "")) != "Red":
			continue
		var from_hex := String(lm.get("from_hex", ""))
		if from_hex.is_empty() or not _beach_hexes.has(from_hex):
			continue
		var tactical: Array = lm.get("tactical", [])
		var neighbors: Array = (_neighbor_lookup.get(from_hex, []) as Array).duplicate()
		neighbors.sort()
		for neighbor_value in neighbors:
			var neighbor := String(neighbor_value)
			if _beach_hexes.has(neighbor) or neighbor not in tactical:
				continue
			actions.append({
				"type": "move",
				"team": "Red",
				"brigade_id": String(brigade_id),
				"target_hex": neighbor,
				"mode": Movement.MODE_TACTICAL,
			})
			break
	return actions
