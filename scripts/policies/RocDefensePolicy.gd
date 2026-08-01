class_name RocDefensePolicy
extends RefCounted

## Concentrating defender policy (plan 0029 Tier A). Where selfplay_default has every brigade wander
## to an arbitrary adjacent hex, this moves each GREEN brigade one tactical step toward the nearest
## threat — a red/contested hex or a red brigade's hex — so the ROC defence masses on the beachhead
## instead of dispersing. Pre-landing (no threat visible) it holds position. Pure decision over the
## observation; deterministic. No counterattack semantics (that is plan 0029 Tier B) — this only
## repositions; ground combat's roles are unchanged.

const GREEN_TEAM := "Green"  # legal_moves / brigades team tokens are capitalised in the observation
const RED_TEAM := "Red"


func build_actions(observation: Dictionary) -> Array:
	var threats := _collect_threat_hexes(observation)
	var actions: Array = []
	if threats.is_empty():
		return actions  # no landing yet — hold the garrison rather than wander off it

	var legal_moves: Dictionary = observation.get("legal_moves", {})
	var brigade_ids: Array = legal_moves.keys()
	brigade_ids.sort()
	for bid in brigade_ids:
		var lm: Dictionary = legal_moves[bid]
		if String(lm.get("team", "")) != GREEN_TEAM:
			continue
		var from_hex := String(lm.get("from_hex", ""))
		var tactical: Array = lm.get("tactical", [])
		if tactical.is_empty():
			continue
		# Include from_hex so a brigade already closest to the threat holds instead of drifting.
		var candidates := tactical.duplicate()
		candidates.append(from_hex)
		var target := PolicyGeometry.nearest_hex_by_id(candidates, threats)
		if target != "" and target != from_hex:
			actions.append({
				"type": "move",
				"team": GREEN_TEAM,
				"brigade_id": String(bid),
				"target_hex": target,
				"mode": Movement.MODE_TACTICAL,
			})
	return actions


## Hexes the defence should mass toward: red/contested ownership + any hex holding a red brigade.
static func _collect_threat_hexes(observation: Dictionary) -> Array[String]:
	var seen := {}
	for hex_info in observation.get("occupied_hexes", []):
		var owner := String(hex_info.get("owner", ""))
		if owner == HexOwner.RED or owner == HexOwner.CONTESTED:
			seen[String(hex_info.get("hex_id", ""))] = true
	for b in observation.get("brigades", []):
		if String(b.get("team", "")) == RED_TEAM:
			seen[String(b.get("hex_id", ""))] = true
	seen.erase("")
	var result: Array[String] = []
	for hex_id in seen:
		result.append(hex_id)
	result.sort()
	return result
