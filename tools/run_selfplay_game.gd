# Run ONE seeded headless self-play game and write a reproducible JSON record (harness B2).
#
# C:\Godot_v4.7-stable_win64.exe --headless --path C:\Users\mdogg\Desktop\HexCombat ^
#   -s res://tools/run_selfplay_game.gd -- --seed=20260624 [--scenario=<id-or-path>] ^
#   [--turns=30] [--policy=selfplay_default] [--red-policy=<id>] [--green-policy=<id>]
#   [--out=reports/game.json] [--log=reports/game.jsonl] [--model=<served-id>]
#
# --scenario is consumed by ScenarioCatalog inside GameData.load_all (no parsing here).
# The record is fully deterministic (no timestamps): re-running the same commit + scenario +
# per-seat policy ids + seed must reproduce it byte-for-byte for deterministic policies — that IS
# the reproducibility contract, and tools/run_batch.py relies on it for checkpoint/resume.
# Without --out the record prints to stdout between RECORD-BEGIN/RECORD-END markers.
# --log=<path.jsonl> additionally writes one observation/actions entry per seat and turn, making
# the record consumable by tools/make_game_bundle.py --html (map rendering needs observations).
extends SceneTree

const DEFAULT_TURNS := 30
const DEFAULT_POLICY := "selfplay_default"

var _log_path := ""


func _initialize() -> void:
	var args := _parse_user_args()
	if not args.has("seed"):
		push_error("Missing required --seed=<int>")
		quit(1)
		return
	var base_seed := int(args["seed"])
	var turns := int(args.get("turns", DEFAULT_TURNS))
	var default_policy := String(args.get("policy", DEFAULT_POLICY))
	var red_policy_id := String(args.get("red-policy", default_policy))
	var green_policy_id := String(args.get("green-policy", default_policy))
	var out_path := String(args.get("out", ""))
	var has_llm_seat := red_policy_id == "llm_local" or green_policy_id == "llm_local"
	_log_path = String(args.get("log", _default_log_path(out_path) if has_llm_seat else ""))

	if args.has("model"):
		OS.set_environment("HEXCOMBAT_LLM_MODEL", String(args["model"]))

	var red_policy := PolicyCatalog.create_for_seat(red_policy_id, "Red", _log_path)
	var green_policy := PolicyCatalog.create_for_seat(green_policy_id, "Green", _log_path)
	if red_policy == null or green_policy == null:
		quit(1)
		return
	if not _log_path.is_empty() and not has_llm_seat:
		DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(_log_path).get_base_dir())
		var fresh := FileAccess.open(_log_path, FileAccess.WRITE)  # truncate any stale log
		if fresh != null:
			fresh.close()

	var red_driver := _policy_driver(red_policy)
	var green_driver := _policy_driver(green_policy)
	var game: Dictionary = SelfPlayRunner.play_game_seats(
		red_driver, green_driver, turns, base_seed, true)

	var game_state := get_root().get_node("GameState")
	var game_data := get_root().get_node("GameData")
	var cleanup: CleanupSummary = game_state.last_cleanup_summary
	var record := _build_record(
		game, game_state, game_data, cleanup, base_seed, turns, red_policy_id, green_policy_id,
		has_llm_seat)
	var record_json := JSON.stringify(record, "\t")
	_write_record(record_json, out_path)

	var ok: bool = bool(game["all_resolved"]) and (game["index_violations"] as Array).is_empty()
	print("%s: scenario=%s red_policy=%s green_policy=%s seed=%d turns=%d/%d game_over=%s winner=%s census=%d:%d" % [
		"GAME OK" if ok else "GAME FAILED",
		ScenarioCatalog.scenario_id(game_data.scenario_path), red_policy_id, green_policy_id, base_seed,
		record["turns_played"], turns, str(game_state.game_over), game_state.winner,
		record["census"]["red"], record["census"]["green"],
	])
	quit(0 if ok else 1)


func _policy_driver(policy: Object) -> Callable:
	if _log_path.is_empty() or policy is LLMPolicy:
		return Callable(policy, "build_actions")
	return Callable(self, "_logged_build_actions").bind(policy)


func _build_record(game: Dictionary, game_state: Object, game_data: Object,
		cleanup: CleanupSummary, base_seed: int, turns: int, red_policy_id: String,
		green_policy_id: String, has_llm_seat: bool) -> Dictionary:
	var record := {
		"record_version": 2,
		"commit": _git_commit(),
		"scenario_id": ScenarioCatalog.scenario_id(game_data.scenario_path),
		"scenario_path": game_data.scenario_path,
		"scenario_name": game_data.scenario_name,
		"red_policy_id": red_policy_id,
		"green_policy_id": green_policy_id,
		"base_seed": base_seed,
		"turns_requested": turns,
		"turns_played": (game["turn_digests"] as Array).size(),
		"final_turn": game["final_turn"],
		"all_resolved": game["all_resolved"],
		"game_over": game_state.game_over,
		"winner": game_state.winner,
		"victory_reason": cleanup.victory_reason if cleanup != null else "",
		"census": {
			"red": cleanup.china_battalions_on_taiwan if cleanup != null else 0,
			"green": cleanup.taiwan_battalions_on_taiwan if cleanup != null else 0,
		},
		"index_violations": game["index_violations"],
		"final_snapshot": game["final_snapshot"],
		"turn_digests": game["turn_digests"],
	}
	if has_llm_seat:
		record["model"] = OS.get_environment("HEXCOMBAT_LLM_MODEL")
		record["base_url"] = _llm_base_url()
		record["log_path"] = _log_path
	return record


func _write_record(record_json: String, out_path: String) -> void:
	if out_path.is_empty():
		print("RECORD-BEGIN")
		print(record_json)
		print("RECORD-END")
		return
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write record to %s" % out_path)
		quit(1)
		return
	file.store_string(record_json)
	file.close()


## Deterministic-policy wrapper that logs each perspective observation and its actions. LLMPolicy
## logs directly in its sidecar so it is never double-recorded here.
func _logged_build_actions(observation: Dictionary, policy: Object) -> Array:
	var actions: Array = policy.build_actions(observation)
	var file := FileAccess.open(_log_path, FileAccess.READ_WRITE)
	if file != null:
		file.seek_end()
		file.store_line(JSON.stringify({
			"perspective": observation.get("perspective_team", ""),
			"turn": observation.get("turn"), "actions": actions, "observation": observation,
		}))
		file.close()
	return actions


func _default_log_path(out_path: String) -> String:
	return "" if out_path.is_empty() else "%s.jsonl" % out_path.get_basename()


func _llm_base_url() -> String:
	var base_url := OS.get_environment("HEXCOMBAT_LLM_BASE_URL")
	return base_url if not base_url.is_empty() else "http://127.0.0.1:8088/v1"


func _parse_user_args() -> Dictionary:
	var parsed := {}
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--") or not arg.contains("="):
			continue
		var parts := arg.trim_prefix("--").split("=", true, 1)
		parsed[parts[0]] = parts[1]
	return parsed


func _git_commit() -> String:
	var output := []
	var code := OS.execute("git", ["rev-parse", "HEAD"], output)
	if code != 0 or output.is_empty():
		return ""
	return String(output[0]).strip_edges()
