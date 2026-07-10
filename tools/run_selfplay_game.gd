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
# --log=<path.jsonl> additionally writes one observation/actions entry per turn (perspective
# "Red" — the omniscient observation carries both teams' occupied_hexes), making the record
# consumable by tools/make_game_bundle.py --html (map rendering needs per-turn observations).
extends SceneTree

const DEFAULT_TURNS := 30
const DEFAULT_POLICY := "selfplay_default"

var _log_path := ""
var _policy: Object = null


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
	_log_path = String(args.get("log", ""))

	_policy = PolicyCatalog.create(policy_id)
	if _policy == null:
		quit(1)
		return
	if not _log_path.is_empty():
		DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(_log_path).get_base_dir())
		var fresh := FileAccess.open(_log_path, FileAccess.WRITE)  # truncate any stale log
		if fresh != null:
			fresh.close()

	var driver: Callable = Callable(_policy, "build_actions") if _log_path.is_empty() \
		else Callable(self, "_logged_build_actions")
	var game: Dictionary = SelfPlayRunner.play_game(driver, turns, base_seed, true)

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


## Policy pass-through that appends one JSONL entry per turn: the omniscient observation under
## perspective "Red" (the viewer prefers Red's observation for the map and the observation holds
## both teams), plus each team's actions as its own entry so per-side attribution survives.
func _logged_build_actions(observation: Dictionary) -> Array:
	var actions: Array = _policy.build_actions(observation)
	var by_team := {"Red": [], "Green": []}
	for action in actions:
		var team := String((action as Dictionary).get("team", ""))
		if by_team.has(team):
			(by_team[team] as Array).append(action)
	var file := FileAccess.open(_log_path, FileAccess.READ_WRITE)
	if file != null:
		file.seek_end()
		file.store_line(JSON.stringify({
			"perspective": "Red", "turn": observation.get("turn"),
			"actions": by_team["Red"], "observation": observation,
		}))
		file.store_line(JSON.stringify({
			"perspective": "Green", "turn": observation.get("turn"),
			"actions": by_team["Green"],
		}))
		file.close()
	return actions


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
