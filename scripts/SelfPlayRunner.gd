extends RefCounted
class_name SelfPlayRunner

## Drives a full headless game through the public LLMGameAPI agent surface.
##
## play_game(policy, turns, base_seed) runs a deterministic self-play loop:
##   observation -> policy builds actions -> append end_turn -> apply_agent_response
##
## The policy is a Callable(observation: Dictionary) -> Array of action dicts.
## The runner appends the end_turn action with seed = base_seed + turn_index.
##
## Returns a dict with final_snapshot, turn_digests, all_resolved, final_turn,
## and index_violations. Deterministic given a deterministic policy + fixed base_seed.
##
## stop_on_game_over (default false, preserving the pinned always-play-N-turns behavior the
## self-play gate asserts): batch research runs pass true so a decided game stops consuming
## turns — turn_digests is then shorter than `turns`.

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
		actions.append({"type": "end_turn", "seed": base_seed + t})
		var response := {
			"protocol_version": LLMGameAPI.PROTOCOL_VERSION,
			"schema": LLMGameAPI.ACTION_RESPONSE_SCHEMA,
			"perspective_team": "",
			"actions": actions
		}
		var result: Dictionary = LLMGameAPI.apply_agent_response(response)
		if not bool(result.get("resolved", false)):
			all_resolved = false
		turn_digests.append((result.get("turn_result", {}) as Dictionary).duplicate(true))
		if stop_on_game_over and _gs().game_over:
			break

	return {
		"final_snapshot": _gd().snapshot_state(),
		"turn_digests": turn_digests,
		"all_resolved": all_resolved,
		"final_turn": _gs().turn_number,
		"index_violations": _gd().validate_runtime_indexes()
	}
