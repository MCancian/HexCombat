extends GdUnitTestSuite

# Mirrors the full-run + continuity cases from TIV tests/python/unit/test_ijfs_standalone.py
# (test_run_daily_outputs_and_continuity, test_target_detected_in_both_phases_is_attacked_once,
# TestBudgetRouting). The structural runs use a SeededDice — per the project's RNG strategy we
# assert formulas/shape/draw-order invariants, not numpy's PCG64 bitstream. Determinism is asserted
# via two identical SeededDice runs rather than golden numbers.

const DATA := "res://data/ijfs/"


func _load_state(current_day: int) -> IjfsDailyState:
	var state := IjfsDailyState.new()
	state.targets = IjfsLoaders.load_targets(DATA + "targets_master.json", current_day)
	state.munitions = IjfsLoaders.load_munitions(DATA + "red_munitions.json")
	state.pairings = IjfsLoaders.load_pairings(DATA + "munition_target_pairings.json")
	state.scenario = IjfsLoaders.load_scenario(DATA + "ijfs_scenario.json")
	state.air_classes = IjfsLoaders.load_air_classes(DATA + "air_classes.json")
	state.squadron_force = IjfsLoaders.expand_oob_to_squadrons(IjfsLoaders.load_oob(DATA + "red_air_oob.json"))
	state.seed = 1234
	state.source_files = [DATA + "targets_master.json", DATA + "red_munitions.json"]
	return state


# --- Full-run ledger shape (mirrors test_run_daily_outputs_and_continuity day 1) -----------------

func test_full_run_produces_all_ledgers() -> void:
	var state := _load_state(1)
	var ledgers := IjfsEngine.run_daily(state, SeededDice.new(1234), 1)

	for key in ["metadata", "detection_log", "strike_log", "target_status_after",
			"munition_inventory_after", "engagement_log", "contest_log", "free_shot_log",
			"air_oob_after", "summary"]:
		assert_bool(ledgers.has(key)).override_failure_message("missing ledger key %s" % key).is_true()

	assert_str(ledgers["metadata"]["created_by"]).is_equal("ijfs_standalone")
	assert_int(ledgers["metadata"]["current_day"]).is_equal(1)
	assert_bool((ledgers["metadata"]["source_files"] as Array).size() > 0).is_true()

	# Detection log: at most two passes (phase1 + phase2) per target; phases constrained.
	var targets_after: Array = ledgers["target_status_after"]
	assert_int(ledgers["detection_log"].size()).is_less_equal(2 * targets_after.size())
	var phases: Dictionary = {}
	for entry in ledgers["detection_log"]:
		phases[entry["phase"]] = true
	for phase in phases.keys():
		assert_bool(phase == "phase1" or phase == "phase2").override_failure_message("unexpected detection phase %s" % phase).is_true()

	# Air OOB v3 with the expected role mix (mirrors TestPayloadFields).
	var oob: Dictionary = ledgers["air_oob_after"]
	assert_int(oob["model_version"]).is_equal(3)
	assert_bool((oob["squadrons"] as Array).size() > 0).is_true()
	var first_sq: Dictionary = oob["squadrons"][0]
	for f in ["squadron_id", "class", "role", "initial", "alive"]:
		assert_bool(first_sq.has(f)).is_true()

	# Summary surfaces the documented keys.
	var summary: Dictionary = ledgers["summary"]
	for key in ["target_counts_by_category_status", "taiwan_ad_health_after", "attacks",
			"red_air_losses", "detections_by_category"]:
		assert_bool(summary.has(key)).override_failure_message("missing summary key %s" % key).is_true()
	assert_bool(summary["red_air_losses"] is int).is_true()
	assert_int(summary["red_air_losses"]).is_greater_equal(0)

	# Strike entries carry the modifier-formula provenance from resolve_strike.
	if ledgers["strike_log"].size() > 0:
		var executed := _executed(ledgers["strike_log"])
		if executed.size() > 0:
			assert_bool(executed[0].has("probability_destroyed_formula")).is_true()


# --- Day-to-day continuity (mirrors test_run_daily_outputs_and_continuity day 2) -----------------

func test_continuity_carries_state_to_next_day() -> void:
	var state := _load_state(1)
	var day1 := IjfsEngine.run_daily(state, SeededDice.new(1234), 1)

	# Snapshot day-1 destroyed targets and a munition that was expended.
	var destroyed_after_day1: Dictionary = {}
	for target in state.targets:
		if target.destroyed:
			destroyed_after_day1[target.target_id] = true

	IjfsEngine.carry_to_next_day(state)

	# carry_to_next_day clears suppression + sead_result but preserves destruction/known flags.
	for target in state.targets:
		assert_bool(target.suppressed).is_false()
		assert_bool(target.suppressed_this_turn).is_false()
		assert_str(target.sead_result).is_equal("")
		if destroyed_after_day1.has(target.target_id):
			assert_bool(target.destroyed).override_failure_message("destroyed target resurrected on carry").is_true()

	var day2 := IjfsEngine.run_daily(state, SeededDice.new(1234), 2)
	assert_int(day2["metadata"]["current_day"]).is_equal(2)
	assert_bool((day2["air_oob_after"]["squadrons"] as Array).size() > 0).is_true()
	# Destroyed targets from day 1 remain destroyed in day-2 status output.
	for entry in day2["target_status_after"]:
		if destroyed_after_day1.has(entry["target_id"]):
			assert_bool(entry["destroyed"]).is_true()


# --- Determinism: identical seed -> identical summary --------------------------------------------

func test_same_seed_is_deterministic() -> void:
	var a := IjfsEngine.run_daily(_load_state(1), SeededDice.new(99), 1)
	var b := IjfsEngine.run_daily(_load_state(1), SeededDice.new(99), 1)
	assert_str(JSON.stringify(a["summary"])).is_equal(JSON.stringify(b["summary"]))
	assert_int(a["strike_log"].size()).is_equal(b["strike_log"].size())


# --- Dedup: a target attacked in pre-AD is not re-attacked in post-AD ----------------------------
# Mirrors test_target_detected_in_both_phases_is_attacked_once.

func test_target_attacked_at_most_once_across_phases() -> void:
	var state := IjfsDailyState.new()
	state.scenario = IjfsLoaders.load_scenario(DATA + "ijfs_scenario.json")
	state.scenario["targeting_doctrine"] = []
	state.air_classes = null
	state.squadron_force = null

	var target := IjfsTarget.new()
	target.target_id = "cdcm1"
	target.source_target_id = "cdcm1"
	target.category = "Anti-Ship Systems"
	target.subcategory = "Static CDCM Launcher"
	target.mobility = "static"
	target.hardness = "hard"
	target.posture = "active"
	target.detected_this_turn = true
	target.known_to_red = true
	state.targets = [target]

	var missile := IjfsMunition.new()
	missile.munition_id = "missile"
	missile.category = "Inorganic-Fast"
	missile.inventory_remaining = 1
	missile.rounds_per_engagement_default = 1
	state.munitions = {"missile": missile}

	var pairing := IjfsPairing.new()
	pairing.order = 0
	pairing.pairing_id = "missile_pair"
	pairing.munition_id = "missile"
	pairing.target_category = "Anti-Ship Systems"
	pairing.target_subcategory = "Static CDCM Launcher"
	pairing.target_mobility = "static"
	pairing.target_hardness = "hard"
	pairing.rounds_expended_per_engagement = 1
	pairing.probability_destroyed = 0.0          # survives -> remains attackable, but deduped
	pairing.probability_suppressed_if_not_destroyed = 0.0
	var pairings: Array[IjfsPairing] = [pairing]
	state.pairings = pairings

	# No firing-capacity config -> capacity_budget admits the inorganic missile.
	state.scenario["red_firing_capacity"] = {}

	var ledgers := IjfsEngine.run_daily(state, SeededDice.new(7), 1)
	var for_target := []
	for entry in ledgers["strike_log"]:
		if entry["target_id"] == "cdcm1":
			for_target.append(entry)
	assert_int(for_target.size()).override_failure_message("target must appear exactly once in the strike log").is_equal(1)
	var executed := _executed(ledgers["strike_log"])
	assert_int(executed.size()).is_equal(1)
	assert_str(executed[0]["phase"]).is_equal(IjfsEngine.PRE_AD_PHASE)


# --- Budget routing: organic munition consumes organic_budget, not capacity_budget --------------
# Mirrors TestBudgetRouting.test_organic_munition_uses_organic_budget_not_capacity_budget.

func test_organic_munition_routes_to_organic_budget() -> void:
	var state := IjfsDailyState.new()
	state.scenario = IjfsLoaders.load_scenario(DATA + "ijfs_scenario.json")
	state.air_classes = null

	var mid := "strike_aircraft_medium"
	var mun := IjfsMunition.new()
	mun.munition_id = mid
	mun.category = "Organic"
	mun.inventory_remaining = 100
	mun.rounds_per_engagement_default = 1
	state.munitions = {mid: mun}

	var target := IjfsTarget.new()
	target.target_id = "t1"
	target.source_target_id = "t1"
	target.category = "Air Defense Systems"
	target.mobility = "static"
	target.hardness = "soft"
	target.detected_this_turn = true
	target.known_to_red = true
	state.targets = [target]

	var pairing := IjfsPairing.new()
	pairing.order = 0
	pairing.pairing_id = "p1"
	pairing.munition_id = mid
	pairing.target_category = "Air Defense Systems"
	pairing.target_subcategory = ""   # wildcard
	pairing.target_mobility = ""       # wildcard
	pairing.target_hardness = ""       # wildcard
	pairing.rounds_expended_per_engagement = 1
	pairing.probability_destroyed = 1.0
	var pairings: Array[IjfsPairing] = [pairing]
	state.pairings = pairings

	# capacity_budget that would falsely block the organic munition if routing were wrong.
	var capacity_budget := IjfsFiringCapacity.FiringCapacityBudget.new({})
	capacity_budget._daily_budget[mid] = 0
	capacity_budget._used[mid] = 0

	state.scenario["red_firing_capacity"] = {mid: {"firing_units": 36, "sorties_per_unit_per_day": 1.0, "platform_type": "aircraft"}}
	var force: Array[IjfsSquadron] = [_strike_squadron("s1", "4.5th Gen", 24)]
	var organic_budget := IjfsFiringCapacity.OrganicStrikeBudget.new(state.scenario, force, state.munitions, null)

	var attacked: Dictionary = {}
	var skips: Dictionary = {}
	IjfsEngine._run_strike_phase(state, 1, IjfsEngine.POST_AD_PHASE, attacked, skips,
		ScriptedDice.new([], [], [0.5, 0.5, 0.5]), capacity_budget, organic_budget, null, null, null)

	assert_bool(attacked.has("t1")).override_failure_message("organic munition must consume organic_budget, not be blocked by capacity_budget").is_true()
	assert_bool(skips.has("t1")).is_false()


# --- helpers ------------------------------------------------------------------------------------

func _executed(strike_log: Array) -> Array:
	var out := []
	for entry in strike_log:
		if entry.get("attack_executed"):
			out.append(entry)
	return out


func _strike_squadron(id: String, cls: String, alive: int) -> IjfsSquadron:
	var sq := IjfsSquadron.new()
	sq.squadron_id = id
	sq.aircraft_class = cls
	sq.role = "strike"
	sq.initial = alive
	sq.alive = alive
	return sq
