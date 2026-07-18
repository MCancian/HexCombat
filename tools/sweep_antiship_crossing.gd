# Anti-ship crossing-loss calibration harness (NOT part of the gate; run on demand).
# Run from the project root:
#   C:\Godot_v4.7-stable_win64.exe --headless --path C:\Users\mdogg\Desktop\HexCombat -s res://tools/sweep_antiship_crossing.gd
#
# Measures the crossing-loss fraction (bns_lost_at_sea / wave_size) for a grid of
# (exquisite_intel.antiship.initial_count, intel_locked strike-bonus magnitude). Produced the
# golden dial (ic=36, bonus=0.20, ~27.3% mean loss) per
# docs/archive/0001-crossing-lethality-calibration.md; kept as the harness for any future
# re-calibration.
extends SceneTree

const IjfsSweepSupport = preload("res://tools/ijfs_sweep_support.gd")

const SEED := 20260624
const SWEEP_N_SEEDS := 30

var GameData: Node = null
var GameState: Node = null


func _initialize() -> void:
	GameData = get_root().get_node("GameData")
	GameState = get_root().get_node("GameState")
	GameData.load_all()

	_write_manifest()
	print("=== MINES-ONLY FLOOR ===")
	_print_breakdown("  MINES-ONLY (all launchers killed)", _mines_only_run())
	print("")
	_run_sweep()
	quit(0)


# Configure the overrides, reset the IJFS state, then run IJFS warmup + anti-ship crossing on the seed.
func _run_once(initial_count: int, bonus: float, run_seed: int = SEED) -> Dictionary:
	var overrides := {}
	if initial_count >= 0:
		overrides["data/ijfs/ijfs_scenario.json:prelanding.intel.exquisite_intel.antiship.initial_count"] = initial_count
	overrides["data/ijfs/ijfs_scenario.json:intel_locked_antiship_strike_bonus"] = bonus
	DataOverrides.set_map(overrides)

	IjfsSweepSupport.fresh_ijfs_scenario(GameState)
	GameState.resolve_ijfs_turn(SeededDice.new(run_seed))
	
	var wave_bns := _reserve_bn_count()
	var summary: Dictionary = GameState.resolve_antiship_turn(SeededDice.new(run_seed))
	summary["_wave_bns"] = wave_bns
	return summary


# Run N seeds for a cell, write the cell JSON, and return the mean.
func _run_cell(initial_count: int, bonus: float, n_seeds: int) -> Dictionary:
	var samples_pct: Array[float] = []
	var cell_samples: Array[Dictionary] = []
	
	for s in range(n_seeds):
		var run_seed = SEED + s
		var summary = _run_once(initial_count, bonus, run_seed)
		samples_pct.append(_loss_pct(summary))
		cell_samples.append({
			"seed": run_seed,
			"wave_bns": _wave_size(summary),
			"bns_lost_at_sea": summary.get("bns_lost_at_sea", 0)
		})
		
	_write_cell(initial_count, bonus, cell_samples)
	return {
		"mean": IjfsSweepSupport.mean(samples_pct),
		"stdev": IjfsSweepSupport.stdev(samples_pct, IjfsSweepSupport.mean(samples_pct))
	}


func _write_cell(ic: int, bonus: float, cell_samples: Array) -> void:
	var slug := "ic_%d__bonus_%.2f" % [ic, bonus]
	var path := "reports/sweeps/antiship_crossing/cells/%s.json" % slug
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var overrides := DataOverrides.map()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"overrides": overrides, "samples": cell_samples}))
	file.close()


func _write_manifest() -> void:
	var path := "reports/sweeps/antiship_crossing/sweep.json"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	var counts := [0, 2, 4, 8, 12, 16, 24, 36, 50, 73]
	var bonuses := [0.0, 0.05, 0.1, 0.2, 0.4, 0.8]
	var record = {
		"sweep_name": "antiship_crossing",
		"created_utc": Time.get_datetime_string_from_system(true),
		"commit": _git_commit(),
		"dirty": false,
		"base_scenario": GameData.scenario_path,
		"knobs": [
			"data/ijfs/ijfs_scenario.json:prelanding.intel.exquisite_intel.antiship.initial_count",
			"data/ijfs/ijfs_scenario.json:intel_locked_antiship_strike_bonus"
		],
		"grid": [counts, bonuses],
		"seeds": SWEEP_N_SEEDS,
		"runtime_mode": "in_process",
		"rerun_command": "godot --headless --path . -s res://tools/sweep_antiship_crossing.gd",
		"metrics": ["crossing_loss_pct"]
	}
	file.store_string(JSON.stringify(record, "\t"))
	file.close()


func _git_commit() -> String:
	var output := []
	var code := OS.execute("git", ["rev-parse", "HEAD"], output)
	return String(output[0]).strip_edges() if code == 0 and not output.is_empty() else ""


func _reserve_bn_count() -> int:
	var total := 0
	for entry in GameState.ship_reserve:
		total += (entry.get("bns", []) as Array).size()
	return total


func _wave_size(summary: Dictionary) -> int:
	return int(summary.get("_wave_bns", 0))


func _loss_pct(summary: Dictionary) -> float:
	var wave := _wave_size(summary)
	if wave == 0:
		return 0.0
	return 100.0 * float(int(summary.get("bns_lost_at_sea", 0))) / float(wave)


# Isolate the mine-loss FLOOR: kill every anti-ship system via the IJFS writeback so the crossing
# fires nothing, leaving only mine losses. This is the lower bound the intel lever can never beat.
func _mines_only_run() -> Dictionary:
	DataOverrides.set_map({})
	IjfsSweepSupport.fresh_ijfs_scenario(GameState)
	GameState.resolve_ijfs_turn(SeededDice.new(SEED))
	
	var destroyed_all := {}
	for system_value in GameState.antiship_systems:
		var system: AntishipSystem = system_value
		var key: String = AntishipCalculator.encode_key(system.to_number, system.type_id)
		destroyed_all[key] = system.original_quantity
	var wb: Dictionary = GameState.last_ijfs_writeback.to_dict()
	wb["antiship_destroyed_by_type"] = destroyed_all
	GameState.last_ijfs_writeback = IjfsWriteback.from_dict(wb)
	
	var wave_bns := _reserve_bn_count()
	var summary: Dictionary = GameState.resolve_antiship_turn(SeededDice.new(SEED))
	summary["_wave_bns"] = wave_bns
	
	var path := "reports/sweeps/antiship_crossing/cells/mines_only.json"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"overrides": {},
		"mines_only": true,
		"samples": [{
			"seed": SEED,
			"wave_bns": wave_bns,
			"bns_lost_at_sea": summary.get("bns_lost_at_sea", 0)
		}]
	}))
	file.close()
	return summary


# Splits ship-hull losses into crossing vs mine so we can see how much of the BN loss the IJFS
# anti-ship lever can actually touch (it only affects crossing). Mine hulls come from mine_status.
func _print_breakdown(label: String, summary: Dictionary) -> void:
	var total_hulls := 0
	for v in (summary.get("destroyed_by_ship_type", {}) as Dictionary).values():
		total_hulls += int(v)
	var mine_hulls := 0
	for beach in (summary.get("mine_status", []) as Array):
		mine_hulls += int((beach as Dictionary).get("ships_destroyed", 0))
	var crossing_hulls := total_hulls - mine_hulls
	print("%s: wave=%d bns_lost=%d (%.1f%%) | hulls: %d crossing + %d mine = %d total" % [
		label, _wave_size(summary), int(summary.get("bns_lost_at_sea", 0)), _loss_pct(summary),
		crossing_hulls, mine_hulls, total_hulls])


# Full grid, N=30 seeds/condition (plan 0001 checklist item 2): mean +/- stdev crossing-loss %%
# per (initial_count, intel_locked strike-bonus) cell, common seed set SEED..SEED+29 across every
# cell so differences are attributable to the knobs, not seed variance.
func _run_sweep() -> void:
	var counts := [0, 2, 4, 8, 12, 16, 24, 36, 50, 73]
	var bonuses := [0.0, 0.05, 0.1, 0.2, 0.4, 0.8]
	print("=== SWEEP: crossing-loss %% mean+/-stdev over %d seeds (rows=initial_count, cols=intel_locked add-bonus) ===" % SWEEP_N_SEEDS)
	var header := "ic\\bonus"
	for b in bonuses:
		header += "\t%+.2f" % b
	print(header)
	for ic in counts:
		var line := str(ic)
		for b in bonuses:
			var stats := _run_cell(ic, b, SWEEP_N_SEEDS)
			line += "\t%.1f+/-%.1f" % [stats["mean"], stats["stdev"]]
		print(line)
	print("")
	print("(pre-calibration reference: ic=8/no-bonus measured 50.0%% single-seed = 18/36; golden dial is ic=36/b=0.20, ~27.3%%)")
