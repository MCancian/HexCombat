extends RefCounted
class_name SelfPlayPolicy

## Pluggable deterministic reference policy for headless self-play.
## Real agents implement the same build_actions(observation: Dictionary) -> Array contract.
##
## This implementation: for each brigade in legal_moves, issue a tactical move
## to the first reachable hex that is not the brigade's current hex.
## No randomness; deterministic given the observation content.

func build_actions(observation: Dictionary) -> Array:
	var legal_moves: Dictionary = observation.get("legal_moves", {})
	var actions: Array = []

	for brigade_id in legal_moves.keys():
		var lm: Dictionary = legal_moves[brigade_id] as Dictionary
		var from_hex := String(lm.get("from_hex", ""))
		var target := ""
		for h in (lm.get("tactical", []) as Array):
			if String(h) != from_hex:
				target = String(h)
				break
		if target != "":
			actions.append({
				"type": "move",
				"team": String(lm.get("team", "")),
				"brigade_id": String(brigade_id),
				"target_hex": target,
				"mode": Movement.MODE_TACTICAL
			})

	return actions
