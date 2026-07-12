# Anti-ship crossing-loss calibration harness (NOT part of the gate; run on demand).
# Run from the project root:
#   C:\Godot_v4.7-stable_win64.exe --headless --path C:\Users\mdogg\Desktop\HexCombat -s res://tools/sweep_antiship_crossing.gd
#
# Measures the crossing-loss fraction (bns_lost_at_sea / wave_size) for a grid of
# (exquisite_intel.antiship.initial_count, intel_locked strike-bonus magnitude). Supports the user's
# ~25% crossing-loss calibration target (docs/archive/0001-crossing-lethality-calibration.md). The
# strike bonus is the intel_locked_antiship_strike_bonus scenario knob (IjfsLoaders); this tool sets
# it directly rather than hand-building a strike_probability_modifiers entry. First prints a baseline
# diagnostic (distinct anti-ship subcategories, intel-locked count, destroyed count) to confirm the
# warmup is actually locking targets and what the strike bonus would key on, then a 3-point
# multi-seed reference, then the full grid at N=30 seeds/cell (SWEEP_N_SEEDS).
extends SceneTree

const SEED := 20260624

var GameData: Node = null
var GameState: Node = null


func _initialize() -> void:
	GameData = get_root().get_node("GameData")
	GameState = get_root().get_node("GameState")
	GameData.load_all()

	_baseline_diagnostic()
	_multiseed_reference()
	_run_sweep()
	quit(0)


# Configure the in-memory scenario, then run IJFS warmup + anti-ship crossing on the golden seed.
# Returns the anti-ship summary dict. initial_count<0 leaves the scenario value untouched; bonus==0.0
# injects no modifier (pure baseline).
func _run_once(initial_count: int, bonus: float, run_seed: int = SEED) -> Dictionary:
	GameState.reset_to_scenario()
	GameState.turn_number = 1
	GameState._rebuild_ijfs_state()  # loads a fresh scenario dict we can mutate before the warmup
	var scenario: Dictionary = GameState.ijfs_state.scenario
	if initial_count >= 0:
		scenario["prelanding"]["intel"]["exquisite_intel"]["antiship"]["initial_count"] = initial_count
	# Plan 0001: the strike bonus is now a scenario knob (IjfsLoaders.apply_intel_locked_strike_bonus
	# synthesizes the modifier); the sweep just sets the scalar and re-runs the synthesis, since
	# load_scenario already ran once inside _rebuild_ijfs_state() before we mutate the dict here.
	scenario["intel_locked_antiship_strike_bonus"] = bonus
	IjfsLoaders.apply_intel_locked_strike_bonus(scenario)
	GameState.resolve_ijfs_turn(SeededDice.new(run_seed))
	# The crossing wave denominator is BNs at sea (ship_reserve), captured BEFORE the phase removes
	# the lost ones. sent_by_type is ship HULLS -- wrong unit for a BN-loss fraction.
	var wave_bns := _reserve_bn_count()
	var summary: Dictionary = GameState.resolve_antiship_turn(SeededDice.new(run_seed))
	summary["_wave_bns"] = wave_bns
	return summary


# Mean crossing-loss %% over N seeds for one config (cuts the single-seed binary-kill noise).
func _mean_loss(initial_count: int, bonus: float, n_seeds: int) -> float:
	var samples := _loss_samples(initial_count, bonus, n_seeds)
	var acc := 0.0
	for v in samples:
		acc += v
	return acc / float(n_seeds)


# Per-seed crossing-loss %% samples for one config (common seed set SEED..SEED+n_seeds-1).
func _loss_samples(initial_count: int, bonus: float, n_seeds: int) -> Array[float]:
	var samples: Array[float] = []
	for s in range(n_seeds):
		samples.append(_loss_pct(_run_once(initial_count, bonus, SEED + s)))
	return samples


func _mean(samples: Array[float]) -> float:
	var acc := 0.0
	for v in samples:
		acc += v
	return acc / float(samples.size())


func _stdev(samples: Array[float], mean_val: float) -> float:
	if samples.size() < 2:
		return 0.0
	var acc := 0.0
	for v in samples:
		acc += (v - mean_val) * (v - mean_val)
	return sqrt(acc / float(samples.size() - 1))


func _multiseed_reference() -> void:
	var n := 24
	print("=== MULTI-SEED REFERENCE (mean crossing-loss %% over %d seeds) ===" % n)
	print("  baseline   ic=8  b=0.00 : %.1f%%" % _mean_loss(8, 0.0, n))
	print("  more-intel ic=36 b=0.20 : %.1f%%" % _mean_loss(36, 0.2, n))
	print("  max-intel  ic=73 b=0.80 : %.1f%%" % _mean_loss(73, 0.8, n))
	print("")


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


func _baseline_diagnostic() -> void:
	print("=== BASELINE DIAGNOSTIC (initial_count=8, no bonus) ===")
	var summary := _run_once(8, 0.0)
	# Inspect the post-warmup anti-ship target population.
	var subcats := {}
	var locked := 0
	var destroyed := 0
	var total := 0
	for target_value in GameState.ijfs_state.targets:
		var target: IjfsTarget = target_value
		if String(target.category) != "Anti-Ship Systems":
			continue
		total += 1
		subcats[target.subcategory] = int(subcats.get(target.subcategory, 0)) + 1
		if bool(target.intel_locked):
			locked += 1
		if target.destroyed:
			destroyed += 1
	print("  anti-ship targets: %d total, %d intel_locked, %d destroyed" % [total, locked, destroyed])
	print("  distinct anti-ship subcategories:")
	for k in subcats.keys():
		print("    %3d  %s" % [int(subcats[k]), k])
	_print_breakdown("  baseline ic=8 b=0.00", summary)
	# The "max intel" case: lock every container and apply a huge precision bonus. Reveals the loss
	# FLOOR the IJFS anti-ship lever cannot go below (mine losses are independent of it).
	_print_breakdown("  max-intel ic=73 b=0.80", _run_once(73, 0.8))
	_print_breakdown("  MINES-ONLY (all launchers killed)", _mines_only_run())
	print("")


# Isolate the mine-loss FLOOR: kill every anti-ship system via the IJFS writeback so the crossing
# fires nothing, leaving only mine losses. This is the lower bound the intel lever can never beat.
func _mines_only_run() -> Dictionary:
	GameState.reset_to_scenario()
	GameState.turn_number = 1
	GameState._rebuild_ijfs_state()
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


const SWEEP_N_SEEDS := 30


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
			var samples := _loss_samples(ic, b, SWEEP_N_SEEDS)
			var m := _mean(samples)
			var sd := _stdev(samples, m)
			line += "\t%.1f+/-%.1f" % [m, sd]
		print(line)
	print("")
	print("(golden warmup note: baseline ic=8/no-bonus measured 50.0%% single-seed = 18/36; target ~25%%)")
