extends RefCounted
class_name SelfPlayRunner

## Drives a full headless game through the public LLMGameAPI agent surface.
##
## play_game(policy, turns, base_seed) runs a deterministic single-policy self-play loop:
##   observation -> policy builds actions -> append end_turn -> apply_agent_response
## The policy is a Callable(observation: Dictionary) -> Array of action dicts, driven off the
## omniscient observation (both teams' legal_moves visible); it may emit actions for either side.
## The runner appends the end_turn action with seed = base_seed + turn_index.
##
## play_game_seats(red_policy, green_policy, turns, base_seed) runs a TWO-SEAT loop for
## LLM-vs-LLM: each seat sees ONLY its own perspective observation and emits move/commit actions;
## both buffers are applied, then a single end_turn resolves them simultaneously (WeGo). Distinct
## deciders per side is the whole point — an LLM policy is nondeterministic, so this path is NOT
## seed-reproducible (unlike play_game); the caller logs observation/action pairs for replay.
##
## Both return a dict with final_snapshot, turn_digests, all_resolved, final_turn,
## and index_violations.
##
## stop_on_game_over (default false, preserving the pinned always-play-N-turns behavior the
## self-play gate asserts): batch/LLM runs pass true so a decided game stops consuming turns —
## turn_digests is then shorter than `turns`.

static func _gd():
	return Engine.get_main_loop().root.get_node("GameData")

static func _gs():
	return Engine.get_main_loop().root.get_node("GameState")


static func play_game(policy: Callable, turns: int, base_seed: int, stop_on_game_over: bool = false) -> Dictionary:
	_gd().load_all()
	_gs().reset_to_scenario()

	var turn_digests: Array = []
	var all_resolved := true

	for t in range(turns):
		var obs: Dictionary = LLMGameAPI.observation("")
		var actions: Array = (policy.call(obs) as Array).duplicate()
		var result: Dictionary = _resolve_turn(actions, base_seed + t)
		if not bool(result.get("resolved", false)):
			all_resolved = false
		turn_digests.append((result.get("turn_result", {}) as Dictionary).duplicate(true))
		if stop_on_game_over and _gs().game_over:
			break

	return _game_summary(turn_digests, all_resolved)


static func play_game_seats(red_policy: Callable, green_policy: Callable, turns: int, base_seed: int, stop_on_game_over: bool = false) -> Dictionary:
	_gd().load_all()
	_gs().reset_to_scenario()

	var turn_digests: Array = []
	var all_resolved := true

	for t in range(turns):
		# Each seat decides from its own perspective-filtered observation; neither sees the
		# other's legal set. Buffer both sides' move/commit orders before the single resolve.
		var red_actions: Array = _seat_actions(red_policy, "Red")
		var green_actions: Array = _seat_actions(green_policy, "Green")
		_buffer_actions(red_actions)
		_buffer_actions(green_actions)
		var result: Dictionary = _resolve_turn([], base_seed + t)
		if not bool(result.get("resolved", false)):
			all_resolved = false
		turn_digests.append((result.get("turn_result", {}) as Dictionary).duplicate(true))
		if stop_on_game_over and _gs().game_over:
			break

	return _game_summary(turn_digests, all_resolved)


## Call a seat policy on its perspective observation, returning a defensive copy of the action
## array with any end_turn action stripped (the runner owns turn resolution and its seed).
static func _seat_actions(policy: Callable, perspective_team: String) -> Array:
	var obs: Dictionary = LLMGameAPI.observation(perspective_team)
	var raw: Array = (policy.call(obs) as Array)
	var actions: Array = []
	for a in raw:
		if a is Dictionary and String((a as Dictionary).get("type", "")) == "end_turn":
			continue
		actions.append(a)
	return actions


## Buffer move/commit actions without resolving (no end_turn in the batch). Errors are non-fatal:
## a rejected order simply doesn't buffer, and the game still resolves whatever is valid.
static func _buffer_actions(actions: Array) -> void:
	if actions.is_empty():
		return
	LLMGameAPI.apply_agent_response(_response(actions))


## Apply `actions` (may be empty) then an end_turn with `seed`, resolving the turn. Returns the
## LLMGameAPI action result (carries resolved flag + turn_result).
static func _resolve_turn(actions: Array, seed: int) -> Dictionary:
	var batch: Array = actions.duplicate()
	batch.append({"type": "end_turn", "seed": seed})
	return LLMGameAPI.apply_agent_response(_response(batch))


static func _response(actions: Array) -> Dictionary:
	return {
		"protocol_version": LLMGameAPI.PROTOCOL_VERSION,
		"schema": LLMGameAPI.ACTION_RESPONSE_SCHEMA,
		"perspective_team": "",
		"actions": actions
	}


static func _game_summary(turn_digests: Array, all_resolved: bool) -> Dictionary:
	return {
		"final_snapshot": _gd().snapshot_state(),
		"turn_digests": turn_digests,
		"all_resolved": all_resolved,
		"final_turn": _gs().turn_number,
		"index_violations": _gd().validate_runtime_indexes()
	}
