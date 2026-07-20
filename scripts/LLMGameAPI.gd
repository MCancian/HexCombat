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
		"ship_reserve": _ship_reserve_observations(),
		"supply_state": _supply_state_observation(),
		"infrastructure": _infrastructure_observations(),
		"ijfs": _ijfs_observation(),
		"antiship": _antiship_observation(),
		"legal_moves": _legal_move_observations(perspective_team),
		"legal_commits": _legal_commit_observations(perspective_team),
		"pending_orders": _pending_orders(),
		"pending_commitments": _pending_commitments(),
		"last_contested_hexes": _game_state().last_contested_hexes.duplicate(),
		"last_combat": _last_combat_summaries(),
		"objectives": [],
		"game_over": _game_state().game_over,
		"winner": _game_state().winner
	}


static func apply_agent_response(response: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var resolved := false
	var turn_result_dict: Dictionary = {}
	var seed := -1

	if String(response.get("protocol_version", PROTOCOL_VERSION)) != PROTOCOL_VERSION:
		errors.append("unsupported protocol_version: %s" % String(response.get("protocol_version", "")))
	if response.has("schema") and String(response["schema"]) != ACTION_RESPONSE_SCHEMA:
		errors.append("unsupported action response schema: %s" % String(response["schema"]))

	var actions = response.get("actions", [])
	if not (actions is Array):
		return _action_result(false, errors + ["response.actions must be an array"], false, seed, String(response.get("perspective_team", "")), {})

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
			"deploy_jlsf":
				_apply_deploy_jlsf_action(action, errors)
			"end_turn":
				if not action.has("seed"):
					errors.append("end_turn action requires an explicit seed for reproducibility")
					continue
				seed = int(action["seed"])
				var turn_result = _game_state().play_turn([], [], SeededDice.new(seed))
				if turn_result != null and int(_game_state().phase) == 2:
					turn_result_dict = turn_result.to_dict()
					_game_state().begin_next_turn()
					resolved = true
				else:
					errors.append("end_turn rejected: game was not in planning phase")
			_:
				errors.append("unknown action type: %s" % action_type)

	return _action_result(errors.is_empty(), errors, resolved, seed, String(response.get("perspective_team", "")), turn_result_dict)


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
		"last_combat": "Combat summaries from the most recently resolved turn. Empty before any combat or if no contested hex produced combat.",
		"turn_result": "Structured record of the turn just resolved (only populated when resolved=true): turn_number, contested_hexes, combat_summaries, phase summaries, and an ordered `events` log."
	}


static func _action_result(ok: bool, errors: Array[String], resolved: bool, seed: int, perspective_team: String, turn_result: Dictionary = {}) -> Dictionary:
	return {
		"protocol_version": PROTOCOL_VERSION,
		"schema": "hexcombat.llm_action_result",
		"ok": ok,
		"errors": errors,
		"resolved": resolved,
		"seed": seed,
		"turn_result": turn_result,
		"observation": observation(perspective_team)
	}


## Parses an action's "team" field, appending an error and returning null when it is
## missing/unknown (callers bail on null). Centralizes the errors-count guard both order
## handlers relied on, since _parse_team_string returns RED on failure rather than a sentinel.
static func _parse_action_team(action: Dictionary, errors: Array[String]) -> Variant:
	var errors_before := errors.size()
	var team := _parse_team_string(String(action.get("team", "")), errors)
	if errors.size() != errors_before:
		return null
	return team


static func _apply_move_action(action: Dictionary, errors: Array[String]) -> void:
	var team_value: Variant = _parse_action_team(action, errors)
	if team_value == null:
		return
	var team: Brigade.Team = team_value
	var brigade_id := String(action.get("brigade_id", ""))
	var target_hex := String(action.get("target_hex", ""))
	var mode := String(action.get("mode", Movement.MODE_TACTICAL))
	var result: OrderResult = _game_state().add_move_order(team, brigade_id, target_hex, mode)
	if not result.ok:
		errors.append("move rejected: %s -> %s (%s): %s" % [brigade_id, target_hex, mode, result.message])


static func _apply_commit_action(action: Dictionary, errors: Array[String]) -> void:
	var team_value: Variant = _parse_action_team(action, errors)
	if team_value == null:
		return
	var team: Brigade.Team = team_value
	var brigade_id := String(action.get("brigade_id", ""))
	var target_hex := String(action.get("target_hex", ""))
	var result: OrderResult = _game_state().add_commit_order(team, brigade_id, target_hex)
	if not result.ok:
		errors.append("commit rejected: %s -> %s: %s" % [brigade_id, target_hex, result.message])


static func _apply_deploy_jlsf_action(action: Dictionary, errors: Array[String]) -> void:
	var port_id := String(action.get("port_id", ""))
	if _game_data().get_infrastructure(port_id) == null:
		errors.append("deploy_jlsf rejected: unknown infrastructure id '%s'" % port_id)
		return
	_game_state()._apply_order({"kind": "deploy_jlsf", "port_id": port_id}, Brigade.Team.RED)


## Offload infrastructure (plan 0006): every port/airbridge with its lifecycle status and JLSF
## marker, so an agent can decide where a deploy_jlsf order pays off.
static func _infrastructure_observations() -> Array:
	var result: Array = []
	var state: InfrastructureState = _game_state().infrastructure_state
	var ids: Array = _game_data().infrastructure.keys()
	ids.sort()
	for id_value in ids:
		var id := String(id_value)
		var def_data: InfrastructureDef = _game_data().infrastructure[id]
		var node: Dictionary = state.nodes.get(id, {}) if state != null else {}
		result.append({
			"id": id,
			"kind": def_data.kind,
			"name": def_data.name,
			"hex": def_data.hex_id,
			"to_number": def_data.to_number,
			"status": String(node.get("status", InfrastructureState.STATUS_TAIWANESE)),
			"jlsf": String(node.get("jlsf", InfrastructureState.JLSF_NONE)),
		})
	return result


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
			"team": Brigade.team_name(brigade.team),
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
		var state: HexState = _game_data().hex_states.get(hex_id, null)
		var terrain: TerrainType = _game_data().get_terrain(hex_id)
		result.append({
			"hex_id": hex_id,
			"owner": state.owner if state != null else HexOwner.NONE,
			"feba_km": state.feba_km if state != null else 0.0,
			"brigades": brigade_ids.duplicate(),
			"neighbors": _game_data().get_neighbors(hex_id),
			"terrain": terrain.name if terrain != null else ""
		})
	return result


static func _ship_reserve_observations() -> Array:
	var result: Array = []
	for reserve_entry_value in _game_state().ship_reserve:
		var reserve_entry: Dictionary = reserve_entry_value
		result.append({
			"brigade_id": String(reserve_entry["brigade_id"]),
			"locked_beach": int(reserve_entry["locked_beach"]),
			"beach_hex": String(reserve_entry["beach_hex"]),
			"bns_remaining": (reserve_entry["bns"] as Array).size()
		})
	return result


static func _supply_state_observation() -> Dictionary:
	var current_dos_tons: float = _game_state().supply_state.current_dos_tons
	return {
		"current_dos_tons": current_dos_tons,
		"current_dos_equivalent": current_dos_tons / float(DosConsumption.TONS_PER_DOS),
		"day_count": _game_state().supply_state.day_history.size()
	}


## IJFS (Red joint fires) — last resolved day's summary + the writeback aggregates. Empty before
## the first turn resolves. Keeps the JSON observation contract forward-compatible for D3/AI play.
static func _ijfs_observation() -> Dictionary:
	var summary: Dictionary = _game_state().last_ijfs_summary
	var writeback: IjfsWriteback = _game_state().last_ijfs_writeback
	return {
		"resolved_day": _game_state()._ijfs_day,
		"attacks": summary.get("attacks", {}),
		"taiwan_ad_health_after": summary.get("taiwan_ad_health_after", {}),
		"red_air_losses": summary.get("red_air_losses", 0),
		"antiship_destroyed_by_type": writeback.antiship_destroyed_by_type if writeback != null else {},
		"antiship_suppressed_by_type": writeback.antiship_suppressed_by_type if writeback != null else {},
		"sam_destroyed": writeback.sam_destroyed if writeback != null else 0,
		"sam_suppressed": writeback.sam_suppressed if writeback != null else 0,
		"maneuver_casualties": writeback.maneuver_casualties if writeback != null else [],
	}


# Anti-ship / mine-warfare resolution from the most recent crossing (D3-D). Empty until the first
# turn a crossing wave is at sea. `bns_lost_at_sea` feeds the offload reserve (BNs removed before
# landing); `destroyed_by_ship_type` is the combined crossing + mine hull toll.
static func _antiship_observation() -> Dictionary:
	var summary: AntishipSummary = _game_state().last_antiship_summary
	if summary != null:
		# to_dict() keys/order match this observation block exactly (single source of truth).
		return summary.to_dict()
	# No crossing wave resolved yet — emit the empty-case defaults. mine_status defaults to {} here
	# (an empty dict) while the resolved value is an Array; preserved verbatim for fixture stability.
	return {
		"resolved_turn": 0,
		"sent_by_type": {},
		"unliftable_bn": 0,
		"systems_fired_count": 0,
		"destroyed_by_ship_type": {},
		"crossing_casualties": {},
		"bns_lost_at_sea": 0,
		"target_beaches": [],
		"target_tos": [],
		"mine_status": {},
		"wave_bns": 0,
	}


static func _legal_move_observations(perspective_team: String) -> Dictionary:
	var result: Dictionary = {}
	for brigade_value in _game_data().brigades.values():
		var brigade: Brigade = brigade_value
		if brigade.hex_id.is_empty() or brigade.destroyed:
			continue
		if not perspective_team.is_empty() and Brigade.team_name(brigade.team) != perspective_team:
			continue
		if _has_pending_order(brigade.team, brigade.id):
			continue
		result[brigade.id] = {
			"team": Brigade.team_name(brigade.team),
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
			var team_string := Brigade.team_name(team)
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
		result[Brigade.team_name(team)] = team_orders
	return result


static func _pending_commitments() -> Dictionary:
	var result := {}
	for team in [Brigade.Team.RED, Brigade.Team.GREEN]:
		var team_commitments: Array = []
		for order_value in _game_state().commitments_for(team):
			var order: CommitOrder = order_value
			team_commitments.append({"brigade_id": order.brigade_id, "target_hex": order.target_hex})
		result[Brigade.team_name(team)] = team_commitments
	return result


static func _last_combat_summaries() -> Array:
	var out: Array = []
	for summary in _game_state().last_combat_summaries:
		out.append((summary as CombatSummary).to_dict())
	return out


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


## Thin API-layer wrapper over Brigade.team_from_name: appends a parse error for an
## unknown value (the errors-count guard _parse_action_team relies on) before delegating.
## team_from_name itself is silent (RED default), so the validity check lives here.
static func _parse_team_string(value: String, errors: Array[String]) -> Brigade.Team:
	if value.to_lower() not in [Brigade.TEAM_KEY_RED, Brigade.TEAM_KEY_GREEN]:
		errors.append("unknown team: %s" % value)
	return Brigade.team_from_name(value)


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
