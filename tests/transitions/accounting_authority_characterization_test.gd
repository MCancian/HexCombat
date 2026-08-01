extends GdUnitTestSuite

## Plan 0049 step 1 — characterization. These pin the DOS-supply and order-buffer behaviours the plan
## is about to route through `SupplyTransitions` and `OrderTransitions`, BEFORE any of them moves.
##
## What is deliberately NOT re-tested here, because it is already covered and duplicating it would
## just be a second place to update:
##   - the consumption arithmetic itself (tons per BN, activity reductions) — tests/dos_consumption_test.gd
##   - pool-driven combat effectiveness — tests/supply_combat_effectiveness_test.gd
##   - move/commit legality codes one by one — tests/game_state_test.gd, tests/order_validation_test.gd
##   - air-insert order legality — tests/air_insertion_order_test.gd
##   - the multi-turn drain and clamp AS A LIVE GAME — tools/validate_dos_consumption.gd
##
## What is covered here is the seam those leave open: that the audit ledger CHAINS (each row starts
## where the last one ended, and the final row agrees with the authoritative balance), and that a
## rejected order leaves every buffer byte-identical. The chain is the property plan 0049 makes true
## by construction rather than by convention — before it, `SupplyResolver` computed `pool_after` and
## the row separately, so nothing stopped the two disagreeing.

const RED_BRIGADE_ID := GoldenScript.RED_MOVER_ID
const RED_START_HEX := GoldenScript.START_HEX
const TARGET_HEX := GoldenScript.TARGET_HEX


func before_test() -> void:
	_reset_fixture()


func after_test() -> void:
	_reset_fixture()


## Same fixture as tests/game_state_test.gd: the scripted mover starts in the ship reserve under the
## research default scenario, so it must be placed before any move order is reachable.
func _reset_fixture() -> void:
	GameData.load_all()
	GameState.reset_to_scenario()
	GameData.set_brigade_hex(RED_BRIGADE_ID, RED_START_HEX)


# --- 1. the supply ledger chains -------------------------------------------------------------------

func test_each_history_row_starts_where_the_previous_row_ended() -> void:
	var supply := GameState.supply_state
	var opening := supply.current_dos_tons

	GameState.resolve_turn(SeededDice.new(1))
	GameState.begin_next_turn()
	GameState.resolve_turn(SeededDice.new(2))

	var history := supply.day_history
	assert_int(history.size()).override_failure_message(
		"two resolved turns must bill two supply days"
	).is_equal(2)

	var expected_open := opening
	for row_value in history:
		var row: Dictionary = row_value
		assert_float(float(row["pool_before"])).override_failure_message(
			"a day's pool_before must be the previous day's pool_after — the ledger is a CHAIN"
		).is_equal_approx(expected_open, 0.0001)
		var consumed := float(row["red_dos_consumed_tons"])
		assert_float(float(row["pool_after"])).override_failure_message(
			"pool_after must be pool_before minus consumption, floored at zero"
		).is_equal_approx(maxf(0.0, expected_open - consumed), 0.0001)
		expected_open = float(row["pool_after"])

	assert_float(supply.current_dos_tons).override_failure_message(
		"the authoritative balance must equal the last row's pool_after"
	).is_equal_approx(expected_open, 0.0001)


func test_a_billed_day_is_marked_applied() -> void:
	GameState.resolve_supply_turn()

	var history := GameState.supply_state.day_history
	assert_int(history.size()).is_equal(1)
	assert_bool(bool((history[0] as Dictionary)["applied"])).is_true()


func test_the_pool_never_rises_across_a_billed_day() -> void:
	var supply := GameState.supply_state
	var before := supply.current_dos_tons

	GameState.resolve_supply_turn()

	assert_bool(supply.current_dos_tons <= before).override_failure_message(
		"supply is consumption-only; no billed day may raise the pool"
	).is_true()


func test_a_day_with_nobody_ashore_still_records_a_row_and_moves_nothing() -> void:
	# Nothing has landed yet at turn 1 before any offload, so the bill is empty by construction.
	var supply := GameState.supply_state
	var before := supply.current_dos_tons

	var summary := GameState.resolve_supply_turn()

	assert_int(supply.day_history.size()).override_failure_message(
		"an empty bill is still an audited day — the ledger must not skip it"
	).is_equal(1)
	assert_float(supply.current_dos_tons).is_equal_approx(before, 0.0001)
	assert_float(float(summary["pool_before"])).is_equal_approx(before, 0.0001)
	assert_float(float(summary["pool_after"])).is_equal_approx(before, 0.0001)


func test_the_pool_clamps_at_zero_rather_than_going_negative() -> void:
	var state := SupplyState.new()
	state.current_dos_tons = 1.0  # far less than one BN-day
	state.day_history = []

	var summary := SupplyTransitions.apply_daily_bill(state, DosConsumption.calculate_consumption(
		[{"brigade_id": "BDE-T1", "type": "Infantry Battalion", "brigade_type": "infantry"}],
		[], [], 1))

	assert_float(state.current_dos_tons).is_equal_approx(0.0, 0.0001)
	assert_float(float(summary["pool_after"])).is_equal_approx(0.0, 0.0001)
	assert_float(float(summary["pool_before"])).is_equal_approx(1.0, 0.0001)


func test_the_summary_key_order_is_the_serialized_contract() -> void:
	# day_history rows and EventBus.supply_updated are serialized straight from this Dictionary, so
	# its INSERTION ORDER is a public shape. Godot preserves it; a rewrite that stamps the applied
	# trio in a different order silently moves every fixture.
	GameState.resolve_supply_turn()
	var row: Dictionary = GameState.supply_state.day_history[0]
	var keys := row.keys()

	assert_int(keys.find("applied")).is_greater(-1)
	assert_bool(keys.find("applied") < keys.find("pool_before")).override_failure_message(
		"applied/pool_before/pool_after are stamped in that order after the consumption keys"
	).is_true()
	assert_bool(keys.find("pool_before") < keys.find("pool_after")).is_true()


# --- 2. a rejected order appends nothing -----------------------------------------------------------
# "Rejection never partially appends" is one of the plan's invariants. Today it holds only because the
# append happens to be the last statement of each validator.

func test_a_rejected_move_order_leaves_the_buffer_untouched() -> void:
	var before := GameState.orders_for(Brigade.Team.RED).size()

	var result := GameState.add_move_order(
		Brigade.Team.RED, "NO-SUCH-BRIGADE", TARGET_HEX, Movement.MODE_TACTICAL)

	assert_bool(result.ok).is_false()
	assert_int(result.code).is_equal(OrderResult.Code.UNKNOWN_BRIGADE)
	assert_int(GameState.orders_for(Brigade.Team.RED).size()).is_equal(before)


func test_a_duplicate_move_order_is_rejected_and_appends_nothing() -> void:
	var first := GameState.add_move_order(
		Brigade.Team.RED, RED_BRIGADE_ID, TARGET_HEX, Movement.MODE_TACTICAL)
	assert_bool(first.ok).is_true()
	var after_first := GameState.orders_for(Brigade.Team.RED).size()

	var second := GameState.add_move_order(
		Brigade.Team.RED, RED_BRIGADE_ID, TARGET_HEX, Movement.MODE_TACTICAL)

	assert_bool(second.ok).is_false()
	assert_int(second.code).is_equal(OrderResult.Code.DUPLICATE_MOVE)
	assert_int(GameState.orders_for(Brigade.Team.RED).size()).is_equal(after_first)


func test_an_order_outside_planning_is_rejected() -> void:
	GameState.resolve_turn(SeededDice.new(1))
	assert_int(GameState.phase).is_equal(GameStateData.Phase.END)
	var before := GameState.orders_for(Brigade.Team.RED).size()

	var result := GameState.add_move_order(
		Brigade.Team.RED, RED_BRIGADE_ID, TARGET_HEX, Movement.MODE_TACTICAL)

	assert_bool(result.ok).is_false()
	assert_int(result.code).is_equal(OrderResult.Code.WRONG_PHASE)
	assert_int(GameState.orders_for(Brigade.Team.RED).size()).is_equal(before)


# --- 3. the deploy_jlsf hole, now CLOSED -----------------------------------------------------------
# These two cases were committed first as a characterization of a DEFECT: deploy_jlsf was the only
# order with no validation API, so it was accepted outside PLANNING and with an id naming nothing.
# Plan 0049 commit 3 gave it one. The assertions are inverted here deliberately, in the commit that
# changes the behaviour, so the fix is visible in the diff rather than silent.

func test_a_jlsf_order_outside_planning_is_rejected_and_appends_nothing() -> void:
	GameState.resolve_turn(SeededDice.new(1))
	assert_int(GameState.phase).is_equal(GameStateData.Phase.END)

	var result := GameState.add_jlsf_order(_a_real_port_id())

	assert_bool(result.ok).is_false()
	assert_int(result.code).is_equal(OrderResult.Code.WRONG_PHASE)
	assert_array(GameState.jlsf_orders).is_empty()


func test_a_jlsf_order_with_an_unknown_port_is_rejected_and_appends_nothing() -> void:
	var result := GameState.add_jlsf_order("NO-SUCH-PORT")

	assert_bool(result.ok).is_false()
	assert_int(result.code).is_equal(OrderResult.Code.UNKNOWN_INFRASTRUCTURE)
	assert_array(GameState.jlsf_orders).is_empty()


func test_a_valid_jlsf_order_is_accepted() -> void:
	var result := GameState.add_jlsf_order(_a_real_port_id())

	assert_bool(result.ok).is_true()
	assert_array(GameState.jlsf_orders).contains([_a_real_port_id()])


## A REPEATED port id is REFUSED (USER call 2026-08-01). Until then it was accepted, purely to
## preserve pre-existing behaviour — plan 0049's diff review disproved the first draft's claim that
## anything depended on it, and the test below still proves that disproof: two buffered orders and one
## buffered order both emit exactly ONE pool entry, because InfrastructureTransitions.queue_jlsf
## refuses the second occurrence. That equivalence is precisely what makes refusing safe here: the
## pool is unchanged, so only the feedback to the seat differs.
func test_a_duplicate_jlsf_order_is_refused() -> void:
	var first := GameState.add_jlsf_order(_a_real_port_id())
	var second := GameState.add_jlsf_order(_a_real_port_id())

	assert_bool(first.ok).is_true()
	assert_bool(second.ok).override_failure_message(
		"a duplicate deploy_jlsf must be refused rather than silently buffered"
	).is_false()
	assert_int(second.code).is_equal(OrderResult.Code.DUPLICATE_JLSF)
	assert_int(GameState.jlsf_orders.size()).override_failure_message(
		"the refused order must not reach the buffer"
	).is_equal(1)


## The disproof, end to end: a duplicated order does NOT double the cargo. Since 2026-08-01 the order
## path can no longer PRODUCE a duplicate (check_jlsf_order refuses it), so this drives JlsfCargo
## directly and is kept as defence in depth — it is the reason refusing duplicates was safe, and it
## would catch a regression if the marker check in queue_jlsf were ever weakened.
func test_two_buffered_jlsf_orders_emit_exactly_one_pool_entry() -> void:
	var port_id := _a_real_port_id()
	var single := JlsfCargo.queue_deployments(
		[port_id], _fresh_infrastructure(), GameData.infrastructure, GameData.beaches,
		GameData.beach_to_to, false, GameData.jlsf_lift_bn_equiv)
	var doubled := JlsfCargo.queue_deployments(
		[port_id, port_id], _fresh_infrastructure(), GameData.infrastructure, GameData.beaches,
		GameData.beach_to_to, false, GameData.jlsf_lift_bn_equiv)

	assert_int(single.size()).is_equal(1)
	assert_int(doubled.size()).override_failure_message(
		"a duplicate order must not queue a second JLSF package — the marker refuses the second pass"
	).is_equal(1)


func _fresh_infrastructure() -> InfrastructureState:
	return InfrastructureStateBuilder.build(GameData.infrastructure)


func _a_real_port_id() -> String:
	for id_value in GameData.infrastructure.keys():
		return String(id_value)
	return ""
