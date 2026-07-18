# CRBM maneuver-attrition calibration harness (NOT part of the gate; run on demand).
# Run from the project root (default scenario = full ROC defense, the rich maneuver-target laydown):
#   godot --headless --path . -s res://tools/sweep_crbm_maneuver.gd
#
# Sweeps crbm_maneuver_strike_bonus over a value grid, measuring how many ROC maneuver battalions
# IJFS kills per game and the terminal on-Taiwan census, across a common seed set (common random
# numbers, so differences are attributable to the knob, not seed variance). The rounds override is
# held at its shipped value (480). Empty-orders self-play over MAX_TURNS turns per (bonus, seed).
extends SceneTree

const IjfsSweepSupport = preload("res://tools/ijfs_sweep_support.gd")

const SEED := 20260624
const MAX_TURNS := 40
const N_SEEDS := 24
const BONUSES := [0.0, 0.05, 0.10, 0.15, 0.20, 0.30, 0.50]

var GameData: Node = null
var GameState: Node = null


func _initialize() -> void:
	GameData = get_root().get_node("GameData")
	GameState = get_root().get_node("GameState")
	GameData.load_all()

	_write_manifest()
	print("=== CRBM MANEUVER-ATTRITION SWEEP ===")
	print("scenario=%s  turns=%d  seeds=%d (%d..%d)  rounds_override=480 (shipped)" % [
		GameData.scenario_path, MAX_TURNS, N_SEEDS, SEED, SEED + N_SEEDS - 1])
	print("Attrition = ROC maneuver-target instances killed by IJFS (pool - survivors), split into")
	print("the pre-D-day exquisite-intel WARMUP slaughter and in-game kills. taiwan_census = all ROC")
	print("battalions still on Taiwan at turn %d (downstream game outcome, not the direct measure)." % MAX_TURNS)
	print("")
	print("bonus\tpool\tkilled(mean+/-sd)\t%%pool\twarmup_killed(mean)\ttaiwan_census(mean)")
	
	for b in BONUSES:
		var stats := _run_cell(float(b), N_SEEDS)
		print("%+.2f\t%.0f\t%.1f+/-%.1f\t%.0f%%\t%.1f\t%.1f" % [
			b, stats["pool"], stats["killed"], stats["stdev"], stats["pct"], stats["warmup"], stats["taiwan"]])
	print("")
	print("(bonus=0.00 is the pre-plan-0009 baseline: rounds override alone, no lethality lever.)")
	quit(0)


func _run_cell(bonus: float, n_seeds: int) -> Dictionary:
	var pool_samples: Array[float] = []
	var killed: Array[float] = []
	var warmup: Array[float] = []
	var taiwan: Array[float] = []
	
	var cell_samples: Array[Dictionary] = []
	
	for s in range(n_seeds):
		var run_seed := SEED + s
		var r := _run_game(bonus, run_seed)
		pool_samples.append(float(r["pool"]))
		killed.append(float(r["killed"]))
		warmup.append(float(r["warmup_killed"]))
		taiwan.append(float(r["taiwan"]))
		
		r["seed"] = run_seed
		cell_samples.append(r)
	
	_write_cell(bonus, cell_samples)
	
	var mk := IjfsSweepSupport.mean(killed)
	var pool_mean := IjfsSweepSupport.mean(pool_samples)
	return {
		"pool": pool_mean,
		"killed": mk,
		"stdev": IjfsSweepSupport.stdev(killed, mk),
		"pct": 100.0 * mk / pool_mean if pool_mean > 0 else 0.0,
		"warmup": IjfsSweepSupport.mean(warmup),
		"taiwan": IjfsSweepSupport.mean(taiwan)
	}


# One empty-orders game with crbm_maneuver_strike_bonus = bonus. Returns the maneuver-target pool at
# start, total killed by IJFS over the game (pool - survivors), the pre-D-day warmup share, and the
# terminal ROC census. Attrition is measured by surviving-target count, NOT the per-turn writeback
# (which omits the multi-day warmup slaughter).
func _run_game(bonus: float, run_seed: int) -> Dictionary:
	DataOverrides.set_map({
		"data/ijfs/ijfs_scenario.json:crbm_maneuver_strike_bonus": bonus
	})
	IjfsSweepSupport.fresh_ijfs_scenario(GameState)
	
	var pool := _alive_maneuver_targets()  # full pool before the turn-1 warmup fires
	# Fixed 40-turn horizon (no early game_over break) — the same convention validate_golden_victory.gd
	# uses; play_turn keeps resolving after game_over so the horizon is comparable across cells.
	LLMGameAPI.apply_agent_response(_end_turn(run_seed))  # turn 1 includes the pre-D-day warmup
	var after_warmup := _alive_maneuver_targets()
	for t in range(1, MAX_TURNS):
		LLMGameAPI.apply_agent_response(_end_turn(run_seed + t))
	var survivors := _alive_maneuver_targets()
	var census: Object = GameState.last_cleanup_summary
	return {
		"pool": pool,
		"killed": pool - survivors,
		"warmup_killed": pool - after_warmup,
		"taiwan": int(census.taiwan_battalions_on_taiwan) if census != null else -1,
	}


func _write_cell(bonus: float, cell_samples: Array) -> void:
	var slug := "bonus_%.2f" % bonus
	var path := "reports/sweeps/crbm_maneuver/cells/%s.json" % slug
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var overrides := DataOverrides.map()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"overrides": overrides, "samples": cell_samples}))
	file.close()


func _write_manifest() -> void:
	var path := "reports/sweeps/crbm_maneuver/sweep.json"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	var record = {
		"sweep_name": "crbm_maneuver",
		"created_utc": Time.get_datetime_string_from_system(true),
		"commit": _git_commit(),
		"dirty": false,
		"base_scenario": GameData.scenario_path,
		"knobs": [
			"data/ijfs/ijfs_scenario.json:crbm_maneuver_strike_bonus"
		],
		"grid": [BONUSES],
		"seeds": N_SEEDS,
		"runtime_mode": "full_game",
		"rerun_command": "godot --headless --path . -s res://tools/sweep_crbm_maneuver.gd",
		"metrics": ["maneuver_attrition_pct"]
	}
	file.store_string(JSON.stringify(record, "\t"))
	file.close()


func _git_commit() -> String:
	var output := []
	var code := OS.execute("git", ["rev-parse", "HEAD"], output)
	return String(output[0]).strip_edges() if code == 0 and not output.is_empty() else ""


func _alive_maneuver_targets() -> int:
	var alive := 0
	for target_value in GameState.ijfs_state.targets:
		var target: IjfsTarget = target_value
		if target.category == "Maneuver Units" and not target.destroyed:
			alive += 1
	return alive


func _end_turn(seed: int) -> Dictionary:
	return {
		"protocol_version": LLMGameAPI.PROTOCOL_VERSION,
		"schema": LLMGameAPI.ACTION_RESPONSE_SCHEMA,
		"perspective_team": "",
		"actions": [{"type": "end_turn", "seed": seed}],
	}
