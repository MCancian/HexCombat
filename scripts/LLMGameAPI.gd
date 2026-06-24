extends RefCounted
class_name LLMGameAPI

const PROTOCOL_VERSION := "0.1.0"
const OBSERVATION_SCHEMA := "hexcombat.llm_observation"
const ACTION_RESPONSE_SCHEMA := "hexcombat.llm_action_response"


static func _game_data() -> Node:
	return Engine.get_main_loop().root.get_node("GameData")


static func _game_state() -> Node:
	return Engine.get_main_loop().root.get_node("GameState")


static func observation(perspective_team: String = "") -> Dictionary:
	return {
		"protocol_version": PROTOCOL_VERSION,
		"schema": OBSERVATION_SCHEMA,
		"scenario": _game_data().scenario_name,
		"turn": _game_state().turn_number,
		"phase": _phase_to_string(int(_game_state().phase)),
		"turn_length_days": _game_state().turn_length_days,
		"perspective_team": perspective_team,
		"rules_summary": rules_summary(),
		"field_glossary": field_glossary(),
		"map_summary": _map_summary(),
		"brigades": _brigade_observations(),
		"occupied_hexes": _occupied_hex_observations(),
		"legal_moves": _legal_move_observations(perspective_team),
		"legal_commits": _legal_commit_observations(perspective_team),
		"pending_orders": _pending_orders(),
		"pending_commitments": _pending_commitments(),
		"last_contested_hexes": _game_state().last_contested_hexes.duplicate(),
		"last_combat": _last_combat_summaries(),
		"objectives": []
	}


static func apply_agent_response(response: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var resolved := false
	var seed := -1

	if String(response.get("protocol_version", PROTOCOL_VERSION)) != PROTOCOL_VERSION:
		errors.append("unsupported protocol_version: %s" % String(response.get("protocol_version", "")))
	if response.has("schema") and String(response["schema"]) != ACTION_RESPONSE_SCHEMA:
		errors.append("unsupported action response schema: %s" % String(response["schema"]))

	var actions = response.get("actions", [])
	if not (actions is Array):
		return _action_result(false, errors + ["response.actions must be an array"], false, seed, String(response.get("perspective_team", "")))

	for action_value in actions:
		if not (action_value is Dictionary):
			errors.append("action must be a dictionary: %s" % str(action_value))
			continue
		var action: Dictionary = action_value
		var action_type := String(action.get("type", ""))
		match action_type:
			"move":
				_apply_move_action(action, errors)
			"commit":
				_apply_commit_action(action, errors)
			"end_turn":
				if not action.has("seed"):
					errors.append("end_turn action requires an explicit seed for reproducibility")
					continue
				seed = int(action["seed"])
				var phase_before := int(_game_state().phase)
				_game_state().resolve_turn(SeededDice.new(seed))
				if phase_before == 0 and int(_game_state().phase) == 2:
					_game_state().begin_next_turn()
					resolved = true
				else:
					errors.append("end_turn rejected: game was not in planning phase")
			_:
				errors.append("unknown action type: %s" % action_type)

	return _action_result(errors.is_empty(), errors, resolved, seed, String(response.get("perspective_team", "")))


static func rules_summary() -> Dictionary:
	return {
		"turn_model": "WeGo: both sides submit orders during planning, then one deterministic resolver applies movement and combat.",
		"movement": {
			"tactical": "Shorter range; costs less organization.",
			"administrative": "Longer range; costs all current organization and prevents commit support this turn."
		},
		"combat": "After movement, any hex containing both Red and Green brigades is contested and resolves one combat round.",
		"legal_actions": "Use legal_moves and legal_commits from this observation. Do not invent brigade IDs or hex IDs.",
		"randomness": "Every end_turn action must include an explicit seed so runs are reproducible."
	}


static func field_glossary() -> Dictionary:
	return {
		"feba_km": "Forward edge of battle movement/progress in kilometers within a contested hex.",
		"organization": "0-100 readiness value affected by movement and combat.",
		"battalions": "Current battalion count remaining in the brigade.",
		"legal_moves": "Authoritative target hex lists by brigade and movement mode.",
		"legal_commits": "Authoritative adjacent support options by target hex and team.",
		"last_contested_hexes": "Hex IDs that were contested in the most recently resolved turn.",
		"last_combat": "Combat summaries from the most recently resolved turn. Empty before any combat or if no contested hex produced combat."
	}


static func _action_result(ok: bool, errors: Array[String], resolved: bool, seed: int, perspective_team: String) -> Dictionary:
	return {
		"protocol_version": PROTOCOL_VERSION,
		"schema": "hexcombat.llm_action_result",
		"ok": ok,
		"errors": errors,
		"resolved": resolved,
		"seed": seed,
		"observation": observation(perspective_team)
	}


static func _apply_move_action(action: Dictionary, errors: Array[String]) -> void:
	var errors_before := errors.size()
	var team := _parse_team_string(String(action.get("team", "")), errors)
	if errors.size() != errors_before:
		return
	var brigade_id := String(action.get("brigade_id", ""))
	var target_hex := String(action.get("target_hex", ""))
	var mode := String(action.get("mode", Movement.MODE_TACTICAL))
	var before: int = _game_state().orders_for(team).size()
	_game_state().add_move_order(team, brigade_id, target_hex, mode)
	if _game_state().orders_for(team).size() != before + 1:
		errors.append("move rejected: %s -> %s (%s)" % [brigade_id, target_hex, mode])


static func _apply_commit_action(action: Dictionary, errors: Array[String]) -> void:
	var errors_before := errors.size()
	var team := _parse_team_string(String(action.get("team", "")), errors)
	if errors.size() != errors_before:
		return
	var brigade_id := String(action.get("brigade_id", ""))
	var target_hex := String(action.get("target_hex", ""))
	var before: int = _game_state().commitments_for(team).size()
	_game_state().add_commit_order(team, brigade_id, target_hex)
	if _game_state().commitments_for(team).size() != before + 1:
		errors.append("commit rejected: %s -> %s" % [brigade_id, target_hex])


static func _map_summary() -> Dictionary:
	return {
		"hex_count": _game_data().hex_lookup.size(),
		"placed_brigade_count": _placed_brigade_count(),
		"owner_values": [HexOwner.RED, HexOwner.GREEN, HexOwner.CONTESTED, HexOwner.NONE],
		"movement_modes": [Movement.MODE_TACTICAL, Movement.MODE_ADMINISTRATIVE],
		"teams": ["Red", "Green"]
	}


static func _placed_brigade_count() -> int:
	var count := 0
	for brigade_value in _game_data().brigades.values():
		var brigade: Brigade = brigade_value
		if not brigade.hex_id.is_empty():
			count += 1
	return count


static func _brigade_observations() -> Array:
	var result: Array = []
	for brigade_value in _game_data().brigades.values():
		var brigade: Brigade = brigade_value
		if brigade.hex_id.is_empty():
			continue
		result.append({
			"id": brigade.id,
			"name": brigade.name,
			"team": _team_to_string(brigade.team),
			"nato_type": brigade.nato_type,
			"hex_id": brigade.hex_id,
			"battalions": brigade.get_battalion_count(),
			"organization": brigade.organization,
			"destroyed": brigade.destroyed,
			"moved_this_turn": brigade.moved_this_turn,
			"moved_admin_this_turn": brigade.moved_admin_this_turn,
			"fought_this_turn": brigade.fought_this_turn
		})
	return result


static func _occupied_hex_observations() -> Array:
	var result: Array = []
	for hex_id_value in _game_data().brigades_by_hex.keys():
		var hex_id := String(hex_id_value)
		var brigade_ids: Array = _game_data().get_brigades_in_hex(hex_id)
		if brigade_ids.is_empty():
			continue
		var state: Dictionary = _game_data().hex_states.get(hex_id, {})
		result.append({
			"hex_id": hex_id,
			"owner": String(state.get("owner", HexOwner.NONE)),
			"feba_km": float(state.get("feba_km", 0.0)),
			"brigades": brigade_ids.duplicate(),
			"neighbors": _game_data().get_neighbors(hex_id)
		})
	return result


static func _legal_move_observations(perspective_team: String) -> Dictionary:
	var result: Dictionary = {}
	for brigade_value in _game_data().brigades.values():
		var brigade: Brigade = brigade_value
		if brigade.hex_id.is_empty() or brigade.destroyed:
			continue
		if not perspective_team.is_empty() and _team_to_string(brigade.team) != perspective_team:
			continue
		if _has_pending_order(brigade.team, brigade.id):
			continue
		result[brigade.id] = {
			"team": _team_to_string(brigade.team),
			"from_hex": brigade.hex_id,
			Movement.MODE_TACTICAL: _game_data().find_reachable(brigade.hex_id, Movement.move_allowance(brigade, Movement.MODE_TACTICAL)),
			Movement.MODE_ADMINISTRATIVE: _game_data().find_reachable(brigade.hex_id, Movement.move_allowance(brigade, Movement.MODE_ADMINISTRATIVE))
		}
	return result


static func _legal_commit_observations(perspective_team: String) -> Dictionary:
	var result: Dictionary = {}
	var teams: Array = [Brigade.Team.RED, Brigade.Team.GREEN]
	for hex_id_value in _game_data().brigades_by_hex.keys():
		var hex_id := String(hex_id_value)
		var by_team := {}
		for team in teams:
			var team_string := _team_to_string(team)
			if not perspective_team.is_empty() and team_string != perspective_team:
				continue
			var eligible: Array = _game_state().eligible_commit_brigades(team, hex_id)
			if not eligible.is_empty():
				by_team[team_string] = eligible
		if not by_team.is_empty():
			result[hex_id] = by_team
	return result


static func _pending_orders() -> Dictionary:
	var result := {}
	for team in [Brigade.Team.RED, Brigade.Team.GREEN]:
		var team_orders: Array = []
		for order_value in _game_state().orders_for(team):
			var order: MoveOrder = order_value
			team_orders.append({"brigade_id": order.brigade_id, "target_hex": order.target_hex, "mode": order.mode})
		result[_team_to_string(team)] = team_orders
	return result


static func _pending_commitments() -> Dictionary:
	var result := {}
	for team in [Brigade.Team.RED, Brigade.Team.GREEN]:
		var team_commitments: Array = []
		for order_value in _game_state().commitments_for(team):
			var order: CommitOrder = order_value
			team_commitments.append({"brigade_id": order.brigade_id, "target_hex": order.target_hex})
		result[_team_to_string(team)] = team_commitments
	return result


static func _last_combat_summaries() -> Array:
	return _game_state().last_combat_summaries.duplicate(true)


static func _has_pending_order(team: Brigade.Team, brigade_id: String) -> bool:
	for order_value in _game_state().orders_for(team):
		var order: MoveOrder = order_value
		if order.brigade_id == brigade_id:
			return true
	for commitment_value in _game_state().commitments_for(team):
		var commitment: CommitOrder = commitment_value
		if commitment.brigade_id == brigade_id:
			return true
	return false


static func _parse_team_string(value: String, errors: Array[String]) -> Brigade.Team:
	match value.to_lower():
		"red":
			return Brigade.Team.RED
		"green":
			return Brigade.Team.GREEN
		_:
			errors.append("unknown team: %s" % value)
			return Brigade.Team.RED


static func _team_to_string(team: Brigade.Team) -> String:
	match team:
		Brigade.Team.GREEN:
			return "Green"
		_:
			return "Red"


static func _phase_to_string(phase: int) -> String:
	match phase:
		0:
			return "planning"
		1:
			return "resolution"
		2:
			return "end"
		_:
			return "unknown"
