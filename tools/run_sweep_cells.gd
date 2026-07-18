# Single-process cell runner for parameter sweeps (Phase E).
# godot --headless --path . -s res://tools/run_sweep_cells.gd -- --spec=spec.json
#
# Spec format:
# {
#   "out_dir": "reports/sweeps/my_sweep/cells",
#   "seeds": [20260624, 20260625, ...],
#   "measurement": "antiship_crossing",
#   "cells": [
#     {"id": "baseline", "overrides": {}},
#     {"id": "cell1", "overrides": {"key": "val", "mines_only": true}}
#   ]
# }
extends SceneTree

var GameData: Node = null
var GameState: Node = null


func _initialize() -> void:
	var args := _parse_user_args()
	if not args.has("spec"):
		push_error("Missing required --spec=<json_path>")
		quit(1)
		return
		
	var spec_path := String(args["spec"])
	if not FileAccess.file_exists(spec_path):
		push_error("Spec not found: " + spec_path)
		quit(1)
		return
		
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(spec_path))
	
	GameData = get_root().get_node("GameData")
	GameState = get_root().get_node("GameState")
	GameData.load_all()

	# load_all consumed the --scenario user arg (via ScenarioCatalog); a silent fallback to the
	# process default would invalidate every cell, so fail loud on any mismatch with the spec.
	# The stem check alone can't catch a resolved-but-missing file (stems still match), hence
	# the file_exists belt.
	var want_scenario := String(spec.get("scenario", ""))
	if not want_scenario.is_empty():
		var got_scenario: String = ScenarioCatalog.scenario_id(GameData.scenario_path)
		if got_scenario != want_scenario or not FileAccess.file_exists(GameData.scenario_path):
			push_error("Scenario mismatch or missing file: spec wants '%s', loaded '%s' (%s)" % [
				want_scenario, got_scenario, GameData.scenario_path])
			quit(1)
			return

	var out_dir := String(spec["out_dir"])
	var measurement := String(spec["measurement"])
	var seeds: Array = spec["seeds"]
	var cells: Array = spec["cells"]
	
	print("=== IN-PROCESS SWEEP RUNNER ===")
	print("Cells: %d | Seeds: %d | Measurement: %s" % [cells.size(), seeds.size(), measurement])
	
	for c in cells:
		var cell: Dictionary = c
		var cell_id := String(cell["id"])
		var overrides: Dictionary = cell.get("overrides", {})
		
		# Allow a special key 'mines_only' to bypass the standard run for the floor check
		var is_mines_only := bool(overrides.get("mines_only", false))
		if is_mines_only:
			overrides.erase("mines_only")
			
		print("Running cell %s..." % cell_id)
		
		var samples: Array[Dictionary] = []
		for seed_val in seeds:
			var run_seed := int(seed_val)
			var s: Dictionary
			if measurement == "antiship_crossing":
				s = _run_antiship_crossing(overrides, run_seed, is_mines_only)
			elif measurement == "crbm_full_game":
				s = _run_crbm_full_game(overrides, run_seed)
			else:
				push_error("Unknown measurement: " + measurement)
				quit(1)
				return
				
			var unapplied := DataOverrides.unapplied()
			if not unapplied.is_empty():
				push_error("Override keys never matched a loaded file (typo'd path?): %s" % str(unapplied))
				quit(1)
				return

			s["seed"] = run_seed
			samples.append(s)

		var out_path := "%s/%s.json" % [out_dir, cell_id]
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		var file := FileAccess.open(out_path, FileAccess.WRITE)
		var cell_record := {"overrides": overrides, "samples": samples}
		if is_mines_only:
			cell_record["mines_only"] = true
		file.store_string(JSON.stringify(cell_record))
		file.close()
		
	print("All cells completed.")
	quit(0)


# Post-plan-0004 the anti-ship phase fires only on the crossing wave — the BNs whose sealift
# cohorts are "sent". Sealift must therefore resolve between IJFS and antiship (as the real turn
# pipeline does), and the wave is the sent cohort, not the whole ship reserve.
func _run_antiship_crossing(overrides: Dictionary, run_seed: int, mines_only: bool) -> Dictionary:
	DataOverrides.set_map(overrides)
	_fresh_ijfs_scenario(GameState)
	GameState.resolve_ijfs_turn(SeededDice.new(run_seed))

	if mines_only:
		var destroyed_all := {}
		for system_value in GameState.antiship_systems:
			var system: AntishipSystem = system_value
			var key: String = AntishipCalculator.encode_key(system.to_number, system.type_id)
			destroyed_all[key] = system.original_quantity
		var wb: Dictionary = GameState.last_ijfs_writeback.to_dict()
		wb["antiship_destroyed_by_type"] = destroyed_all
		GameState.last_ijfs_writeback = IjfsWriteback.from_dict(wb)

	GameState.resolve_sealift_turn()
	var wave_bns: int = SealiftResolver.sent_cohort_bn_ids(GameState.sealift_state).size()
	var summary: Dictionary = GameState.resolve_antiship_turn(SeededDice.new(run_seed))

	return {
		"wave_bns": wave_bns,
		"bns_lost_at_sea": summary.get("bns_lost_at_sea", 0)
	}


func _run_crbm_full_game(overrides: Dictionary, run_seed: int) -> Dictionary:
	DataOverrides.set_map(overrides)
	_fresh_ijfs_scenario(GameState)
	
	var pool := _alive_maneuver_targets()
	LLMGameAPI.apply_agent_response(_end_turn(run_seed))
	var after_warmup := _alive_maneuver_targets()
	
	var max_turns := 40
	for t in range(1, max_turns):
		LLMGameAPI.apply_agent_response(_end_turn(run_seed + t))
		
	var survivors := _alive_maneuver_targets()
	var census: Object = GameState.last_cleanup_summary
	
	return {
		"pool": pool,
		"killed": pool - survivors,
		"warmup_killed": pool - after_warmup,
		"taiwan": int(census.taiwan_battalions_on_taiwan) if census != null else -1,
	}


func _fresh_ijfs_scenario(game_state: Object) -> void:
	game_state.reset_to_scenario()
	game_state.turn_number = 1
	game_state._rebuild_ijfs_state()


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


func _parse_user_args() -> Dictionary:
	var parsed := {}
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--") or not arg.contains("="):
			continue
		var parts := arg.trim_prefix("--").split("=", true, 1)
		parsed[parts[0]] = parts[1]
	return parsed
