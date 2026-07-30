extends GdUnitTestSuite

## Plan 0046 — the IJFS mutation authority's own contracts.
##
## Split of responsibility with tests/ijfs/ijfs_authority_characterization_test.gd: that suite pins
## the BEHAVIOUR the pipeline had before the migration, driving the real stages. This one pins the
## AUTHORITY — the guards that refuse a bad request, and the cross-day/cross-aggregate invariants
## that only exist because one class owns these writes.
##
## Guards push_error and change nothing rather than asserting, so each is exercisable here.


# --- munition magazines -------------------------------------------------------------------------
# NOTE: insufficiency is UNREACHABLE through the engine — IjfsTargeting._rule_affordable refuses an
# unaffordable pairing on every selection path, and nothing decrements between selection and the
# strike. So it is tested here, directly, or it is not tested at all: an engine-level scenario would
# pass while exercising nothing.

func test_consume_munition_deducts_exactly_the_rounds() -> void:
	var munition := _munition(40)
	assert_bool(IjfsTransitions.consume_munition(munition, 4)).is_true()
	assert_int(munition.inventory_remaining).is_equal(36)


func test_consume_munition_refuses_rather_than_going_negative() -> void:
	var munition := _munition(3)
	assert_bool(IjfsTransitions.consume_munition(munition, 4)).override_failure_message(
		"an exhausted magazine is a normal skip, reported as false").is_false()
	assert_int(munition.inventory_remaining).override_failure_message(
		"a refused consumption must change nothing").is_equal(3)


func test_consume_munition_of_exactly_the_remaining_stock_succeeds() -> void:
	var munition := _munition(4)
	assert_bool(IjfsTransitions.consume_munition(munition, 4)).is_true()
	assert_int(munition.inventory_remaining).is_equal(0)


func test_consume_munition_refuses_a_negative_request() -> void:
	var munition := _munition(10)
	assert_error(func() -> void: IjfsTransitions.consume_munition(munition, -5)) \
		.is_push_error("IjfsTransitions: refusing a negative consumption of -5 rounds of m1")
	assert_int(munition.inventory_remaining).is_equal(10)


# --- squadrons ----------------------------------------------------------------------------------

func test_squadron_losses_are_bounded_by_the_airframes_alive() -> void:
	var squadron := _squadron(6)
	assert_error(func() -> void: IjfsTransitions.apply_squadron_losses(squadron, 7)) \
		.is_push_error("IjfsTransitions: sq1 lost 7 of only 6 alive airframes")
	assert_int(squadron.alive).is_equal(6)
	assert_int(squadron.losses_today).is_equal(0)

	IjfsTransitions.apply_squadron_losses(squadron, 6)
	assert_int(squadron.alive).is_equal(0)
	assert_int(squadron.losses_today).is_equal(6)
	assert_int(squadron.alive).is_between(0, squadron.initial)


# --- MANPADS stock ------------------------------------------------------------------------------

func test_manpads_stock_refuses_to_go_negative() -> void:
	var bin := _manpads_bin(50)
	IjfsTransitions.set_manpads_remaining(bin, 10)
	assert_error(func() -> void: IjfsTransitions.set_manpads_remaining(bin, -1)) \
		.is_push_error("IjfsTransitions: refusing a negative MANPADS stock (-1) for mp1")
	assert_int(bin.manpads_remaining).is_equal(10)
	assert_int(int(bin.metadata["systems_remaining"])).is_equal(10)


# --- target lifecycle ---------------------------------------------------------------------------

func test_suppression_reset_never_touches_destruction() -> void:
	var state := IjfsDailyState.new()
	var dead := _target("t1")
	IjfsTransitions.apply_strike_destruction(dead)
	var suppressed := _target("t2")
	IjfsTransitions.apply_sead_suppression(suppressed)
	state.targets = [dead, suppressed]

	IjfsTransitions.carry_to_next_day(state)

	assert_bool(dead.destroyed).is_true()
	assert_bool(suppressed.suppressed).is_false()
	assert_str(suppressed.sead_result).is_equal("")
	assert_bool(suppressed.destroyed).is_false()


func test_sead_destruction_also_clears_the_detection_that_strike_leaves() -> void:
	# SEAD resolves BETWEEN the two detection passes, so a row it kills must not enter the second
	# pass still flagged as detected. A strike kill, which happens outside that window, does not.
	var by_sead := _target("t1")
	var by_strike := _target("t2")
	for target in [by_sead, by_strike]:
		target.detected_this_turn = true
		target.known_to_red = true

	IjfsTransitions.apply_sead_destruction(by_sead)
	IjfsTransitions.apply_strike_destruction(by_strike)

	assert_bool(by_sead.detected_this_turn).is_false()
	assert_str(by_sead.sead_result).is_equal("destroyed")
	assert_bool(by_strike.detected_this_turn).override_failure_message(
		"a strike kill must not inherit SEAD's extra clear").is_true()


func test_detection_forgets_destroyed_rows_and_records_the_day() -> void:
	var alive := _target("t1")
	var dead := _target("t2")
	IjfsTransitions.apply_strike_destruction(dead)
	dead.known_to_red = true
	var targets: Array[IjfsTarget] = [alive, dead]

	IjfsTransitions.apply_detection_results(targets, ["t1", "t2"], 5)

	assert_bool(alive.detected_this_turn).is_true()
	assert_int(alive.last_detected_day).is_equal(5)
	assert_bool(dead.detected_this_turn).override_failure_message(
		"a destroyed row cannot be detected however the ids read").is_false()
	assert_bool(dead.known_to_red).is_false()


func test_added_targets_are_appended_and_duplicates_refuse_the_whole_batch() -> void:
	var state := IjfsDailyState.new()
	state.targets = [_target("existing")]

	var fresh: Array[IjfsTarget] = [_target("new1"), _target("new2")]
	assert_int(IjfsTransitions.add_targets(state, fresh)).is_equal(2)
	assert_int(state.targets.size()).is_equal(3)
	assert_str(state.targets[0].target_id).override_failure_message(
		"existing rows must keep their positions, so detection continuity survives").is_equal("existing")

	var clashing: Array[IjfsTarget] = [_target("new3"), _target("existing")]
	assert_error(func() -> void: IjfsTransitions.add_targets(state, clashing)) \
		.is_push_error("IjfsTransitions: refusing the whole batch — duplicate target id 'existing'")
	assert_int(state.targets.size()).override_failure_message(
		"a half-applied append is worse than none").is_equal(3)


# --- daily-state lifecycle ----------------------------------------------------------------------

func test_install_zeroes_the_day_count_and_reset_drops_the_state() -> void:
	var state := GameStateData.new()
	state._ijfs_day = 7

	IjfsTransitions.install_daily_state(state, IjfsDailyState.new())
	assert_int(state._ijfs_day).override_failure_message(
		"day 0 is what makes the next IJFS run the multi-day prelanding warmup").is_equal(0)
	assert_object(state.ijfs_state).is_not_null()

	IjfsTransitions.advance_day(state, 3)
	assert_int(state._ijfs_day).is_equal(3)

	IjfsTransitions.reset_daily_state(state)
	assert_object(state.ijfs_state).is_null()
	assert_int(state._ijfs_day).is_equal(0)


func test_the_day_count_refuses_to_move_backwards() -> void:
	var state := GameStateData.new()
	IjfsTransitions.advance_day(state, 6)
	assert_error(func() -> void: IjfsTransitions.advance_day(state, 4)) \
		.is_push_error("IjfsTransitions: IJFS day moved backwards, 6 -> 4")
	assert_int(state._ijfs_day).override_failure_message(
		"a backwards day would re-run the prelanding warmup mid-campaign").is_equal(6)


# --- the cross-aggregate writeback seam (plan 0043 consumes this) --------------------------------

func test_antiship_writeback_stays_cumulative_across_days_and_books_once() -> void:
	# The anti-ship writeback is read from CUMULATIVE target state, not from a per-day log, so a
	# multi-day warmup reports a running total. AntishipTransitions ASSIGNS that total rather than
	# adding it — re-reporting the same kills must not kill twice.
	var ijfs_state := IjfsDailyState.new()
	var first := _antiship_target("as1", 3, 23, 2)
	var second := _antiship_target("as2", 3, 23, 5)
	ijfs_state.targets = [first, second]

	var system := AntishipSystem.new()
	system.to_number = 3
	system.type_id = 23
	system.quantity = 20
	system.original_quantity = 20
	var systems: Array = [system]

	# Day 1: one bin destroyed.
	IjfsTransitions.apply_strike_destruction(first)
	AntishipTransitions.apply_ijfs_effects(systems, _writeback(ijfs_state))
	assert_int(system.ijfs_destroyed_cumulative).is_equal(2)
	assert_int(system.quantity).is_equal(18)

	# Day 2: nothing new dies. The report still carries the running total, and re-applying it must
	# not compound.
	AntishipTransitions.apply_ijfs_effects(systems, _writeback(ijfs_state))
	assert_int(system.ijfs_destroyed_cumulative).override_failure_message(
		"a re-reported cumulative total must be assigned, never added").is_equal(2)
	assert_int(system.quantity).is_equal(18)

	# Day 3: the second bin dies too; the total grows by that bin's represented systems.
	IjfsTransitions.apply_strike_destruction(second)
	AntishipTransitions.apply_ijfs_effects(systems, _writeback(ijfs_state))
	assert_int(system.ijfs_destroyed_cumulative).is_equal(7)
	assert_int(system.quantity).is_equal(13)


func test_a_suppressed_antiship_bin_reports_suppression_not_a_loss() -> void:
	var ijfs_state := IjfsDailyState.new()
	var bin := _antiship_target("as1", 3, 23, 4)
	ijfs_state.targets = [bin]

	IjfsTransitions.apply_strike_suppression(bin)
	var writeback := _writeback(ijfs_state)
	var key := AntishipCalculator.encode_key(3, 23)

	assert_bool(writeback.antiship_destroyed_by_type.has(key)).override_failure_message(
		"suppression is not attrition").is_false()
	assert_int(int(writeback.antiship_suppressed_by_type[key])).is_equal(4)

	# Suppression describes THIS cycle only, so it clears with the carry-over.
	IjfsTransitions.carry_to_next_day(ijfs_state)
	assert_bool(_writeback(ijfs_state).antiship_suppressed_by_type.has(key)).is_false()


# --- helpers ------------------------------------------------------------------------------------

func _writeback(ijfs_state: IjfsDailyState) -> IjfsWriteback:
	return IjfsResolver.compute_writeback(ijfs_state, {"engagement_log": []}, [])


func _munition(remaining: int) -> IjfsMunition:
	var munition := IjfsMunition.new()
	munition.munition_id = "m1"
	munition.category = "Inorganic-Fast"
	munition.inventory_remaining = remaining
	return munition


func _squadron(alive: int) -> IjfsSquadron:
	var squadron := IjfsSquadron.new()
	squadron.squadron_id = "sq1"
	squadron.aircraft_class = "4th Gen"
	squadron.role = "strike"
	squadron.initial = alive
	squadron.alive = alive
	return squadron


func _target(id: String) -> IjfsTarget:
	var target := IjfsTarget.new()
	target.target_id = id
	target.source_target_id = id
	target.category = "Air Defense Systems"
	target.mobility = "static"
	return target


func _manpads_bin(represented: int) -> IjfsTarget:
	var bin := _target("mp1")
	bin.category = IjfsManpads.CATEGORY
	bin.metadata = {"to_number": 2, "systems_represented": represented}
	return bin


func _antiship_target(id: String, to_number: int, type_id: int, represented: int) -> IjfsTarget:
	var target := _target(id)
	target.category = "Anti-Ship Systems"
	target.metadata = {
		"to_number": to_number, "type_id": type_id, "systems_represented": represented}
	return target
