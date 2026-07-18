extends RefCounted

# No class_name: on-demand sweep tools preload this by path so a direct `-s` run doesn't depend on
# the global class cache being reimported first.

## Shared support for the on-demand IJFS calibration sweeps (sweep_antiship_crossing.gd,
## sweep_crbm_maneuver.gd) — NOT part of the gate. Holds the injection kernel (reset → force-build
## the IJFS daily state → hand back the mutable scenario dict so a sweep can tweak knobs before the
## warmup) and the multi-seed stats. Each sweep re-runs the loader synthesizers it needs after
## mutating the scenario, so the differing overrides stay in the sweeps; only the shared plumbing
## lives here.


## Reset to the selected scenario and force-build ijfs_state (normally lazy on turn 1), returning the
## mutable scenario dict. The caller mutates knobs on it then re-runs the relevant IjfsLoaders
## synthesizers; because ijfs_state is now non-null, resolve_ijfs_turn will reuse this mutated state.
static func fresh_ijfs_scenario(game_state) -> Dictionary:
	game_state.reset_to_scenario()
	game_state.turn_number = 1
	game_state._rebuild_ijfs_state()
	return game_state.ijfs_state.scenario


static func mean(samples: Array) -> float:
	if samples.is_empty():
		return 0.0
	var acc := 0.0
	for v in samples:
		acc += float(v)
	return acc / float(samples.size())


static func stdev(samples: Array, mean_val: float) -> float:
	if samples.size() < 2:
		return 0.0
	var acc := 0.0
	for v in samples:
		acc += (float(v) - mean_val) * (float(v) - mean_val)
	return sqrt(acc / float(samples.size() - 1))
