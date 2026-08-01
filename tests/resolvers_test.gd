extends GdUnitTestSuite

## Isolation tests for the pure resolver classes extracted from GameState (refactor_audit
## item 10, first slice). These deliberately construct inputs by hand — no GameData/GameState
## autoload involvement — proving the resolver interface's whole point: each phase's logic is
## testable without booting the game.


# --- Supply: DosConsumption calculates, SupplyTransitions applies ----------------------------------
# Plan 0049 split what `SupplyResolver.resolve` used to do in one call. The pairing below is the whole
# phase in isolation, and it still needs no autoload — which was this file's original point.

func _one_infantry_unit() -> Array:
	return [{"brigade_id": "BDE-T1", "type": "Infantry Battalion", "brigade_type": "infantry"}]


func _one_day_of_consumption() -> Dictionary:
	return DosConsumption.calculate_consumption(_one_infantry_unit(), [], [], 1)


func test_supply_authority_deducts_pool_and_records_history() -> void:
	var state := SupplyState.new()
	state.current_dos_tons = 1000.0
	state.day_history = []

	var summary := SupplyTransitions.apply_daily_bill(state, _one_day_of_consumption())

	var consumed := float(summary["red_dos_consumed_tons"])
	assert_bool(consumed > 0.0).is_true()
	assert_bool(bool(summary["applied"])).is_true()
	assert_float(float(summary["pool_before"])).is_equal_approx(1000.0, 0.0001)
	assert_float(float(summary["pool_after"])).is_equal_approx(1000.0 - consumed, 0.0001)
	assert_float(state.current_dos_tons).is_equal_approx(1000.0 - consumed, 0.0001)
	assert_int(state.day_history.size()).is_equal(1)
	assert_dict(state.day_history[0]).is_equal(summary)


func test_supply_authority_pool_floors_at_zero() -> void:
	var state := SupplyState.new()
	state.current_dos_tons = 1.0  # far less than one BN-day of consumption
	state.day_history = []

	var summary := SupplyTransitions.apply_daily_bill(state, _one_day_of_consumption())

	assert_float(state.current_dos_tons).is_equal_approx(0.0, 0.0001)
	assert_float(float(summary["pool_after"])).is_equal_approx(0.0, 0.0001)


## The authority derives the balance from the consumption row, so the ledger and the pool cannot
## disagree — there is no parameter through which a caller could supply a contradicting `pool_after`.
func test_supply_authority_refuses_a_negative_bill_and_changes_nothing() -> void:
	var state := SupplyState.new()
	state.current_dos_tons = 500.0
	state.day_history = []

	await assert_error(func() -> void:
		SupplyTransitions.apply_daily_bill(state, {"red_dos_consumed_tons": -10.0})
	).is_push_error("SupplyTransitions.apply_daily_bill: invalid consumption -10.000000")

	assert_float(state.current_dos_tons).override_failure_message(
		"a refused bill must not top the pool up"
	).is_equal_approx(500.0, 0.0001)
	assert_array(state.day_history).is_empty()


## A caller offering its own balance is refused rather than obeyed. This is what makes
## "derive, don't accept" a property of the API instead of a convention of the one caller.
func test_supply_authority_refuses_a_row_that_already_carries_a_balance() -> void:
	var state := SupplyState.new()
	state.current_dos_tons = 500.0
	state.day_history = []
	var forged := _one_day_of_consumption()
	forged["pool_after"] = 999999.0

	await assert_error(func() -> void:
		SupplyTransitions.apply_daily_bill(state, forged)
	).is_push_error("SupplyTransitions.apply_daily_bill: row already carries 'pool_after'")

	assert_float(state.current_dos_tons).is_equal_approx(500.0, 0.0001)
	assert_array(state.day_history).is_empty()


## The committed ledger row is the authority's own copy. A caller that keeps its consumption row and
## bills a SECOND day with the same object must not rewrite the first day's history.
func test_reusing_one_consumption_row_cannot_rewrite_committed_history() -> void:
	var state := SupplyState.new()
	state.current_dos_tons = 10000.0
	state.day_history = []

	var reused := _one_day_of_consumption()
	SupplyTransitions.apply_daily_bill(state, reused.duplicate(true))
	var first_row_after_day_1: Dictionary = (state.day_history[0] as Dictionary).duplicate(true)

	SupplyTransitions.apply_daily_bill(state, reused.duplicate(true))

	assert_int(state.day_history.size()).is_equal(2)
	assert_dict(state.day_history[0]).override_failure_message(
		"day 1's committed row must be untouched by day 2's bill"
	).is_equal(first_row_after_day_1)
	assert_float(float((state.day_history[1] as Dictionary)["pool_before"])).override_failure_message(
		"day 2 must open where day 1 closed — the ledger is a chain"
	).is_equal_approx(float(first_row_after_day_1["pool_after"]), 0.0001)


## Mutating the report the authority handed back must not reach into the ledger either.
func test_mutating_the_returned_report_does_not_rewrite_history() -> void:
	var state := SupplyState.new()
	state.current_dos_tons = 10000.0
	state.day_history = []

	var report := SupplyTransitions.apply_daily_bill(state, _one_day_of_consumption())
	var committed := float((state.day_history[0] as Dictionary)["pool_after"])
	report["pool_after"] = -1.0

	assert_float(float((state.day_history[0] as Dictionary)["pool_after"])).override_failure_message(
		"the returned report is a detached projection, not a handle on the ledger row"
	).is_equal_approx(committed, 0.0001)


# --- FrontlineResolver ---------------------------------------------------------------------------

func _two_hex_centers() -> Array:
	return [
		{"id": "A", "lat": 23.0, "lon": 120.0},
		{"id": "B", "lat": 23.0, "lon": 121.0},
	]


func _brigade(id: String, hex_id: String) -> Brigade:
	var brigade := Brigade.new()
	brigade.id = id
	brigade.team = Brigade.Team.RED
	brigade.hex_id = hex_id
	return brigade


func test_frontline_resolver_empty_polyline_returns_empty_summary() -> void:
	var summary := FrontlineResolver.resolve([], _two_hex_centers(), [_brigade("u1", "A")])
	assert_array(summary.hex_sequence).is_empty()
	assert_array(summary.affected_brigades).is_empty()
	assert_dict(summary.moves).is_empty()


func test_frontline_resolver_redistributes_only_on_line_brigades() -> void:
	# Line passes A then B; u1 sits on A (affected), u9 sits off-line (untouched).
	var line := [Vector2(23.0, 120.0), Vector2(23.0, 121.0)]
	var brigades := [_brigade("u2", "A"), _brigade("u1", "B"), _brigade("u9", "off_line_hex")]

	var summary := FrontlineResolver.resolve(line, _two_hex_centers(), brigades)

	assert_array(summary.hex_sequence).is_equal(["A", "B"])
	# Affected set is sorted for determinism (u1 before u2 despite input order).
	assert_array(summary.affected_brigades).is_equal(["u1", "u2"])
	assert_dict(summary.moves).is_equal({"u1": "A", "u2": "B"})


func test_frontline_resolver_moves_nothing_itself() -> void:
	var brigade := _brigade("u1", "B")
	var line := [Vector2(23.0, 120.0), Vector2(23.0, 121.0)]
	var summary := FrontlineResolver.resolve(line, _two_hex_centers(), [brigade])
	assert_str(summary.moves["u1"]).is_equal("A")
	# The resolver only reports the move; applying it is the caller's job.
	assert_str(brigade.hex_id).is_equal("B")


# --- CleanupResolver -----------------------------------------------------------------------------

# The anti-ship flag reset and the brigade activity latch are NOT tested here — plan 0055 hoisted
# both into `TurnClosure.resolve_cleanup_phase`, and both keep their end-to-end coverage there:
# `tools/validate_cleanup.gd` for the reset, `tests/brigade_activity_history_test.gd` for the latch.
# What is left for this resolver is the census + verdict, and the guarantee below.
func test_cleanup_resolver_censuses_and_reports_the_reset_count_it_was_given() -> void:
	var brigade := Brigade.new()
	brigade.id = "bde-1"
	brigade.team = Brigade.Team.RED
	brigade.hex_id = "A"
	brigade.moved_this_turn = true
	brigade.fought_this_turn = true
	var bn := Battalion.new()
	bn.type = "Infantry Battalion"
	bn.qty = 1
	brigade.composition = [bn]
	var brigades := {"bde-1": brigade}

	var outcome := CleanupResolver.resolve(1, brigades, [], {}, 1, false)
	var summary: CleanupSummary = outcome["summary"]

	assert_int(summary.antiship_systems_reset).is_equal(1)
	assert_int(summary.china_battalions_on_taiwan).is_equal(1)

	# The resolver is PURE (plan 0055) — the reason it may live in `scripts/calc/`. It was handed a
	# brigade with both activity flags set and must not have latched them: doing so is what it used to
	# do, and the directory it now sits in forbids changing campaign state by any route.
	assert_bool(brigade.moved_last_turn).override_failure_message(
		"CleanupResolver latched activity — it applied campaign state and can no longer live in calc/"
	).is_false()
	assert_bool(brigade.fought_last_turn).is_false()
