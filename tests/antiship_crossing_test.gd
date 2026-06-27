extends GdUnitTestSuite

# D3-B3 — anti-ship crossing model. Mirrors TIV tests/python/unit/test_antiship_crossing.py.
# This is the count-based pipeline port (see PLAN.md Decisions 2026-06-27 D3-B3): the per-hull
# escort-magazine/ammo refinement is deferred. RNG comes from an injected SeededDice (formula +
# draw order, not Python's PRNG bitstream), so only structural/deterministic assertions are pinned.

const CATALOG_PATH := "res://data/antiship/antiship_combat_catalog.json"
const CROSSING_PATH := "res://data/antiship/antiship_crossing_config.json"

# Theater data (data/theaters.json) for range-tier gating in the real-catalog smoke test.
const ACTIVE_TOS := [2, 3, 4, 5]
const TO_ADJACENCY := {2: [3, 4], 3: [2, 5], 4: [2, 5], 5: [3, 4]}


func _snap(ship_type: String, surviving_sent: int) -> Dictionary:
	return {"ship_type": ship_type, "surviving_sent": surviving_sent}


func _missile(quantity: int, in_flight := 0.0, discrimination := "High", lethality := "High",
		susceptibility := "Low") -> Dictionary:
	return {
		"quantity": quantity,
		"terminal_defense_susceptibility": susceptibility,
		"discrimination_ability": discrimination,
		"lethality": lethality,
		"in_flight_failure_rate": in_flight,
	}


func _catalog(munitions := {}, launchers := {}) -> Dictionary:
	if munitions.is_empty():
		munitions = {"MissileA": _missile(1000)}
	if launchers.is_empty():
		launchers = {"1": {"missiles": ["MissileA"], "missiles_per_launcher": 4, "range_tier": "own_to"}}
	return {"munitions": munitions, "launchers": launchers}


func _crossing_config() -> Dictionary:
	return {
		"missile_group_size": 4,
		"escort_interception": {},
		"discrimination_probabilities": {"Low": 0.2, "Medium": 0.5, "High": 0.8},
		"terminal_defense": {
			"base_probability": 0.0,
			"susceptibility_adjustment": {"High": 0.0, "Medium": 0.0, "Low": 0.0, "None": 0.0},
			"capability_adjustment": {"None": 0.0, "Low": 0.0, "Medium": 0.0, "High": 0.0},
		},
		"neutralization_likelihoods": {"High": 1.0, "Medium": 0.5, "Low": 0.0},
		"lethality_multipliers": {"High": 1.0, "Medium": 1.0, "Low": 1.0},
		"ship_profiles": {
			"LST": {"target_value": 1, "terminal_defense_capability": "None", "vulnerability": "High"},
		},
	}


func _rows(rows: Array) -> Array:
	return rows


# --- launch stage (deterministic) ----------------------------------------------------------------

func test_empty_systems_fired_returns_empty_result() -> void:
	var r := AntishipCrossing.resolve_crossing_damage(
		[], [_snap("LST", 5)], _catalog(), _crossing_config(), [3], SeededDice.new(1))
	assert_int(int(r["missile_stage_totals"]["launched"])).is_equal(0)
	assert_dict(r["destroyed_by_ship_type"]).is_empty()


func test_launch_math_draws_global_pool() -> void:
	var sf := [{"location": 3, "type": 1, "systems_fired": 10}]
	var r := AntishipCrossing.resolve_crossing_damage(
		sf, [_snap("LST", 100)], _catalog(), _crossing_config(), [3], SeededDice.new(1))
	assert_dict(r["launched_by_munition"]).is_equal({"MissileA": 40})


func test_partial_fire_rule_on_pool_shortfall() -> void:
	var catalog := _catalog()
	catalog["munitions"]["MissileA"]["quantity"] = 30  # want 40, pool 30 -> 30 + (10*0.5) = 35
	var sf := [{"location": 3, "type": 1, "systems_fired": 10}]
	var r := AntishipCrossing.resolve_crossing_damage(
		sf, [_snap("LST", 100)], catalog, _crossing_config(), [3], SeededDice.new(1))
	assert_dict(r["launched_by_munition"]).is_equal({"MissileA": 35})


func test_munition_fallback_when_primary_pool_dry() -> void:
	var catalog := _catalog(
		{"Primary": _missile(10), "Backup": _missile(1000)},
		{"1": {"missiles": ["Primary", "Backup"], "missiles_per_launcher": 4, "range_tier": "own_to"}})
	var sf := [{"location": 3, "type": 1, "systems_fired": 10}]
	var r := AntishipCrossing.resolve_crossing_damage(
		sf, [_snap("LST", 100)], catalog, _crossing_config(), [3], SeededDice.new(1))
	assert_dict(r["launched_by_munition"]).is_equal({"Primary": 10, "Backup": 30})


func test_shared_pool_exhaustion_across_launcher_types_is_order_independent() -> void:
	var catalog := _catalog(
		{"Shared": _missile(30)},
		{
			"1": {"missiles": ["Shared"], "missiles_per_launcher": 4, "range_tier": "own_to"},
			"2": {"missiles": ["Shared"], "missiles_per_launcher": 4, "range_tier": "own_to"},
		})
	var rows := [
		{"location": 3, "type": 1, "systems_fired": 10},
		{"location": 3, "type": 2, "systems_fired": 10},
	]
	var forward := AntishipCrossing.resolve_crossing_damage(
		rows, [_snap("LST", 100)], catalog, _crossing_config(), [3], SeededDice.new(1))
	var reversed_rows := [rows[1], rows[0]]
	var reverse := AntishipCrossing.resolve_crossing_damage(
		reversed_rows, [_snap("LST", 100)], catalog, _crossing_config(), [3], SeededDice.new(1))
	# Type 1 drains pool (30 + 5 partial = 35); Type 2 gets only half-shortfall (20). Total 55.
	assert_dict(forward["launched_by_munition"]).is_equal({"Shared": 55})
	assert_dict(reverse["launched_by_munition"]).is_equal(forward["launched_by_munition"])


func test_range_tier_gates_out_of_range_launchers() -> void:
	# own_to launcher physically at TO 5, target TO 3 -> contributes nothing.
	var sf := [{"location": 5, "type": 1, "systems_fired": 10}]
	var r := AntishipCrossing.resolve_crossing_damage(
		sf, [_snap("LST", 100)], _catalog(), _crossing_config(), [3], SeededDice.new(1))
	assert_int(int(r["missile_stage_totals"]["launched"])).is_equal(0)


func test_in_flight_failure_removes_missiles() -> void:
	var catalog := _catalog()
	catalog["munitions"]["MissileA"]["in_flight_failure_rate"] = 1.0  # everything fails
	var sf := [{"location": 3, "type": 1, "systems_fired": 10}]
	var r := AntishipCrossing.resolve_crossing_damage(
		sf, [_snap("LST", 100)], catalog, _crossing_config(), [3], SeededDice.new(1))
	assert_dict(r["failed_in_flight_by_munition"]).is_equal({"MissileA": 40})
	assert_int(int(r["missile_stage_totals"]["leakers"])).is_equal(0)


# --- interception --------------------------------------------------------------------------------

func test_no_escorts_means_no_interception() -> void:
	var sf := [{"location": 3, "type": 1, "systems_fired": 10}]
	var r := AntishipCrossing.resolve_crossing_damage(
		sf, [_snap("LST", 100)], _catalog(), _crossing_config(), [3], SeededDice.new(1))
	assert_int(int(r["missile_stage_totals"]["intercepted"])).is_equal(0)
	assert_int(int(r["missile_stage_totals"]["leakers"])).is_equal(40)


func test_escorts_intercept_missiles() -> void:
	var sf := [{"location": 3, "type": 1, "systems_fired": 10}]
	var cfg := _crossing_config()
	cfg["escort_interception"] = {"DDG": {"attempts": 100, "success_prob": 1.0}}
	var snaps := [_snap("LST", 100), _snap("DDG", 6)]
	var r := AntishipCrossing.resolve_crossing_damage(sf, snaps, _catalog(), cfg, [3], SeededDice.new(1))
	assert_int(int(r["missile_stage_totals"]["intercepted"])).is_equal(40)
	assert_int(int(r["missile_stage_totals"]["leakers"])).is_equal(0)


# --- damage resolution ---------------------------------------------------------------------------

func test_damage_split_destroyed_vs_damaged_and_capped() -> void:
	var sf := [{"location": 3, "type": 1, "systems_fired": 10}]
	var cfg := _crossing_config()
	cfg["ship_profiles"]["LST"]["vulnerability"] = "Medium"  # neutralization 0.5
	var r := AntishipCrossing.resolve_crossing_damage(
		sf, [_snap("LST", 100)], _catalog(), cfg, [3], SeededDice.new(7))
	var destroyed := int(r["destroyed_by_ship_type"].get("LST", 0))
	var damaged := int(r["damaged_by_ship_type"].get("LST", 0))
	var wasted := int(r["missile_stage_totals"]["wasted_hits"])
	assert_int(int(r["missile_stage_totals"]["hits"])).is_equal(40)
	assert_int(destroyed).is_greater(0)  # both outcomes occur at neutralization 0.5
	assert_int(damaged).is_greater(0)
	assert_bool(destroyed + damaged + wasted <= 40).is_true()
	assert_bool(destroyed + damaged <= 100).is_true()


func test_damage_capped_at_surviving_sent() -> void:
	var sf := [{"location": 3, "type": 1, "systems_fired": 10}]
	var cfg := _crossing_config()
	cfg["ship_profiles"]["LST"]["vulnerability"] = "High"  # neutralization 1.0
	var r := AntishipCrossing.resolve_crossing_damage(
		sf, [_snap("LST", 5)], _catalog(), cfg, [3], SeededDice.new(1))
	var destroyed := int(r["destroyed_by_ship_type"].get("LST", 0))
	var damaged := int(r["damaged_by_ship_type"].get("LST", 0))
	assert_bool(destroyed + damaged <= 5).is_true()
	assert_int(destroyed).is_equal(5)  # every affected hull sinks
	assert_int(int(r["missile_stage_totals"]["wasted_hits"])).is_equal(40 - 5)


func test_damaged_hull_more_fragile_on_rehit() -> void:
	var sf := [{"location": 3, "type": 1, "systems_fired": 10}]
	var cfg := _crossing_config()
	cfg["damaged_hull_neut_multiplier"] = 1000.0
	cfg["neutralization_likelihoods"] = {"High": 1.0, "Medium": 0.001, "Low": 0.0}
	cfg["ship_profiles"]["LST"]["vulnerability"] = "Medium"  # base 0.001
	var r := AntishipCrossing.resolve_crossing_damage(
		sf, [_snap("LST", 1)], _catalog(), cfg, [3], SeededDice.new(3))
	assert_int(int(r["destroyed_by_ship_type"].get("LST", 0))).is_equal(1)
	assert_int(int(r["damaged_by_ship_type"].get("LST", 0))).is_equal(0)


func test_decoys_absorb_missiles_with_no_fleet_damage() -> void:
	var catalog := _catalog()
	catalog["munitions"]["MissileA"]["discrimination_ability"] = "Low"
	var cfg := _crossing_config()
	cfg["ship_profiles"]["Decoys"] = {
		"target_value": 1, "terminal_defense_capability": "None", "vulnerability": "Low", "is_decoy": true}
	var sf := [{"location": 3, "type": 1, "systems_fired": 10}]
	var r := AntishipCrossing.resolve_crossing_damage(
		sf, [_snap("Decoys", 100)], catalog, cfg, [3], SeededDice.new(1))
	assert_int(int(r["missile_stage_totals"]["decoy_hits"])).is_greater(0)
	assert_dict(r["destroyed_by_ship_type"]).is_empty()
	assert_dict(r["damaged_by_ship_type"]).is_empty()


func test_deterministic_with_fixed_seed() -> void:
	var sf := [{"location": 3, "type": 1, "systems_fired": 10}]
	var snaps := [_snap("LST", 50), _snap("DDG", 6)]
	var cfg := _crossing_config()
	cfg["escort_interception"] = {"DDG": {"attempts": 5, "success_prob": 0.5}}
	var r1 := AntishipCrossing.resolve_crossing_damage(sf, snaps, _catalog(), cfg, [3], SeededDice.new(99))
	var r2 := AntishipCrossing.resolve_crossing_damage(sf, snaps, _catalog(), cfg, [3], SeededDice.new(99))
	assert_dict(r1["missile_stage_totals"]).is_equal(r2["missile_stage_totals"])
	assert_dict(r1["casualty_totals"]).is_equal(r2["casualty_totals"])
	assert_dict(r1["destroyed_by_ship_type"]).is_equal(r2["destroyed_by_ship_type"])
	assert_dict(r1["damaged_by_ship_type"]).is_equal(r2["damaged_by_ship_type"])


func test_screen_preference_biases_hits_toward_escorts() -> void:
	var catalog := _catalog({"MissileA": _missile(10000)})
	var cfg := _crossing_config()
	cfg["screen_target_preference"] = 10.0
	cfg["ship_profiles"] = {
		"FFG": {"target_value": 1, "terminal_defense_capability": "None", "vulnerability": "High"},
		"LPD": {"target_value": 1, "terminal_defense_capability": "None", "vulnerability": "High"},
	}
	cfg["neutralization_likelihoods"]["High"] = 1.0
	var snaps := [_snap("FFG", 100), _snap("LPD", 100)]
	var sf := [{"location": 3, "type": 1, "systems_fired": 100}]
	var r := AntishipCrossing.resolve_crossing_damage(sf, snaps, catalog, cfg, [3], SeededDice.new(42))
	var ffg_destroyed := int(r["destroyed_by_ship_type"].get("FFG", 0))
	var lpd_destroyed := int(r["destroyed_by_ship_type"].get("LPD", 0))
	assert_int(ffg_destroyed).is_greater(lpd_destroyed)


func test_real_catalog_loads_and_runs() -> void:
	var catalog := AntishipLoaders.load_combat_catalog(CATALOG_PATH)
	var cfg := AntishipLoaders.load_crossing_config(CROSSING_PATH)
	assert_bool(catalog.is_empty()).is_false()
	assert_bool(cfg.is_empty()).is_false()
	var sf := [
		{"location": 3, "type": 20, "systems_fired": 8},
		{"location": 3, "type": 3, "systems_fired": 40},
	]
	var snaps := [_snap("LHA", 4), _snap("LST", 12), _snap("DDG", 6), _snap("Decoys", 15)]
	var r := AntishipCrossing.resolve_crossing_damage(
		sf, snaps, catalog, cfg, [3], SeededDice.new(2024), ACTIVE_TOS, TO_ADJACENCY)
	var m: Dictionary = r["missile_stage_totals"]
	var c: Dictionary = r["casualty_totals"]
	# Pipeline reconciliation invariants.
	assert_int(int(m["launched"])).is_equal(int(m["failed_in_flight"]) + int(m["intercepted"]) + int(m["leakers"]))
	assert_bool(int(m["hits"]) + int(m["decoy_hits"]) <= int(m["leakers"])).is_true()
	assert_bool(int(c["destroyed"]) + int(c["damaged"]) + int(m["wasted_hits"]) <= int(m["hits"])).is_true()
	assert_array(r["warnings"]).is_empty()
