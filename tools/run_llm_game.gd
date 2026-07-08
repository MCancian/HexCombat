# Play ONE full LLM-vs-LLM game headlessly (harness B6) and write a game record + replay log.
#
#   godot --headless --path . -s res://tools/run_llm_game.gd -- \
#     --seed=20260624 [--scenario=<id-or-path>] [--turns=30] [--model=<served-id>] \
#     [--out=reports/llm/game.json] [--log=reports/llm/game.jsonl]
#
# Both seats run the `llm_local` policy (LLMPolicy) against the LOCAL model configured in the
# environment (HEXCOMBAT_LLM_BASE_URL / HEXCOMBAT_LLM_MODEL / HEXCOMBAT_LLM_API_KEY); --model, if
# given, overrides HEXCOMBAT_LLM_MODEL for the sidecar. Each seat sees only its own perspective.
#
# UNLIKE tools/run_selfplay_game.gd this record is NOT byte-reproducible: the model is the decider
# and it is nondeterministic. The RESOLVER is still deterministic (the end_turn seed), and the
# JSONL obs/action log is the reproducibility artifact — every observation/action pair is recorded
# there so the game can be replayed even though the model's choices can't be reproduced from a seed.
# --scenario is consumed by ScenarioCatalog inside GameData.load_all (no parsing here).
extends SceneTree

const DEFAULT_TURNS := 30
const POLICY_ID := "llm_local"


func _initialize() -> void:
	var args := _parse_user_args()
	if not args.has("seed"):
		push_error("Missing required --seed=<int>")
		quit(1)
		return
	var base_seed := int(args["seed"])
	var turns := int(args.get("turns", DEFAULT_TURNS))
	var out_path := String(args.get("out", ""))
	var log_path := String(args.get("log", _default_log_path(out_path)))

	# --model overrides the sidecar's model for this run (sidecar reads it from the environment).
	if args.has("model"):
		OS.set_environment("HEXCOMBAT_LLM_MODEL", String(args["model"]))

	var base_url := OS.get_environment("HEXCOMBAT_LLM_BASE_URL")
	if base_url.is_empty():
		# 127.0.0.1, not localhost: a rootless-container pasta forward may only serve IPv4, and
		# localhost can resolve to ::1 first (connection reset).
		base_url = "http://127.0.0.1:8088/v1"
	var model := OS.get_environment("HEXCOMBAT_LLM_MODEL")

	if not log_path.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(log_path).get_base_dir())

	var red := LLMPolicy.for_seat("Red", log_path)
	var green := LLMPolicy.for_seat("Green", log_path)

	var game: Dictionary = SelfPlayRunner.play_game_seats(
		Callable(red, "build_actions"), Callable(green, "build_actions"), turns, base_seed, true)

	var game_state := get_root().get_node("GameState")
	var game_data := get_root().get_node("GameData")
	var cleanup: CleanupSummary = game_state.last_cleanup_summary
	var record := {
		"record_version": 1,
		"commit": _git_commit(),
		"scenario_id": ScenarioCatalog.scenario_id(game_data.scenario_path),
		"scenario_path": game_data.scenario_path,
		"scenario_name": game_data.scenario_name,
		# LLM-vs-LLM provenance (both seats share one local model in this entrypoint).
		"red_policy_id": POLICY_ID,
		"green_policy_id": POLICY_ID,
		"model": model,
		"base_url": base_url,
		"log_path": log_path,
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
	var record_json := JSON.stringify(record, "\t")

	if out_path.is_empty():
		print("RECORD-BEGIN")
		print(record_json)
		print("RECORD-END")
	else:
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		var file := FileAccess.open(out_path, FileAccess.WRITE)
		if file == null:
			push_error("Could not write record to %s" % out_path)
			quit(1)
			return
		file.store_string(record_json)
		file.close()

	var ok: bool = bool(game["all_resolved"]) and (game["index_violations"] as Array).is_empty()
	print("%s: scenario=%s model=%s seed=%d turns=%d/%d game_over=%s winner=%s census=%d:%d log=%s" % [
		"GAME OK" if ok else "GAME FAILED",
		ScenarioCatalog.scenario_id(game_data.scenario_path), model, base_seed,
		record["turns_played"], turns, str(game_state.game_over), game_state.winner,
		record["census"]["red"], record["census"]["green"], log_path,
	])
	quit(0 if ok else 1)


## Default JSONL replay log alongside --out (same basename, .jsonl); empty when no --out (a quick
## stdout-only run keeps no log unless --log is given explicitly).
func _default_log_path(out_path: String) -> String:
	if out_path.is_empty():
		return ""
	return "%s.jsonl" % out_path.get_basename()


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
