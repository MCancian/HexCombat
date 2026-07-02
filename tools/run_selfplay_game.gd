# Run ONE seeded headless self-play game and write a reproducible JSON record (harness B2).
#
# C:\Godot_v4.7-stable_win64.exe --headless --path C:\Users\mdogg\Desktop\HexCombat ^
#   -s res://tools/run_selfplay_game.gd -- --seed=20260624 [--scenario=<id-or-path>] ^
#   [--turns=30] [--policy=selfplay_default] [--out=reports/game.json]
#
# --scenario is consumed by ScenarioCatalog inside GameData.load_all (no parsing here).
# The record is fully deterministic (no timestamps): re-running the same commit + scenario +
# policy + seed must reproduce it byte-for-byte — that IS the reproducibility contract, and
# tools/run_batch.ps1 relies on it for checkpoint/resume.
# Without --out the record prints to stdout between RECORD-BEGIN/RECORD-END markers.
extends SceneTree

const DEFAULT_TURNS := 30
const DEFAULT_POLICY := "selfplay_default"


func _initialize() -> void:
	var args := _parse_user_args()
	if not args.has("seed"):
		push_error("Missing required --seed=<int>")
		quit(1)
		return
	var base_seed := int(args["seed"])
	var turns := int(args.get("turns", DEFAULT_TURNS))
	var policy_id := String(args.get("policy", DEFAULT_POLICY))
	var out_path := String(args.get("out", ""))

	var policy: Object = PolicyCatalog.create(policy_id)
	if policy == null:
		quit(1)
		return

	var game: Dictionary = SelfPlayRunner.play_game(Callable(policy, "build_actions"), turns, base_seed, true)

	var game_state := get_root().get_node("GameState")
	var game_data := get_root().get_node("GameData")
	var cleanup: CleanupSummary = game_state.last_cleanup_summary
	var record := {
		"record_version": 1,
		"commit": _git_commit(),
		"scenario_id": ScenarioCatalog.scenario_id(game_data.scenario_path),
		"scenario_path": game_data.scenario_path,
		"scenario_name": game_data.scenario_name,
		"policy_id": policy_id,
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
	print("%s: scenario=%s policy=%s seed=%d turns=%d/%d game_over=%s winner=%s census=%d:%d" % [
		"GAME OK" if ok else "GAME FAILED",
		ScenarioCatalog.scenario_id(game_data.scenario_path), policy_id, base_seed,
		record["turns_played"], turns, str(game_state.game_over), game_state.winner,
		record["census"]["red"], record["census"]["green"],
	])
	quit(0 if ok else 1)


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
