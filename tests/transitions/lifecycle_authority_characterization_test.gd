extends GdUnitTestSuite

## Plan 0049 step 1 — characterization. These pin the turn-lifecycle and victory-latch behaviours the
## plan is about to route through `TurnLifecycleTransitions`, BEFORE any of them moves.
##
## What is deliberately NOT re-tested here, because it is already covered and duplicating it would
## just be a second place to update:
##   - reset_to_scenario initialising turn/phase/days/buffers —
##     tests/game_state_test.gd::test_reset_to_scenario_initializes_turn_phase_days_and_empty_buffers
##   - begin_next_turn clearing flags/buffers and advancing turn+phase —
##     tests/game_state_test.gd::test_begin_next_turn_resets_flags_buffers_turn_and_phase
##   - the victory verdict itself — tests/victory_conditions_test.gd, victory_present_census_test.gd
##
## What is covered here is the seam those leave open, and it is the load-bearing half: the ILLEGAL
## edges of the phase machine, that a refused transition changes NOTHING, that campaign state survives
## a turn boundary, and that the three victory latches move together from one verdict and the landing
## latch is monotone. Today none of that is enforced — `phase` and `turn_number` are plain fields with
## public façade setters, so every property below currently holds by convention alone.

const RED_BRIGADE_ID := GoldenScript.RED_MOVER_ID
const GREEN_TARGET_HEX := GoldenScript.TARGET_HEX


func before_test() -> void:
	GameData.load_all()
	GameState.reset_to_scenario()


func after_test() -> void:
	GameData.load_all()
	GameState.reset_to_scenario()


# --- 1. the illegal edges -------------------------------------------------------------------------
# Both guards exist today as push_error + early return. The authority must keep REFUSING these, and
# must leave the state untouched when it does — a half-applied transition is the failure mode a
# generic phase setter cannot even express a defence against.

func test_begin_next_turn_outside_end_is_refused_and_changes_nothing() -> void:
	assert_int(GameState.phase).is_equal(GameStateData.Phase.PLANNING)

	await assert_error(func() -> void:
		GameState.begin_next_turn()
	).is_push_error("Cannot begin next turn outside END phase")

	assert_int(GameState.turn_number).override_failure_message(
		"a refused begin_next_turn must not advance the counter"
	).is_equal(1)
	assert_int(GameState.phase).is_equal(GameStateData.Phase.PLANNING)


func test_resolve_turn_outside_planning_is_refused_and_changes_nothing() -> void:
	GameState.resolve_turn(SeededDice.new(1))
	assert_int(GameState.phase).is_equal(GameStateData.Phase.END)
	var turn_before := GameState.turn_number

	await assert_error(func() -> void:
		GameState.resolve_turn(SeededDice.new(1))
	).is_push_error("Cannot resolve turn outside PLANNING phase")

	assert_int(GameState.phase).is_equal(GameStateData.Phase.END)
	assert_int(GameState.turn_number).is_equal(turn_before)


# --- 2. the turn counter moves on exactly ONE edge -------------------------------------------------

func test_resolving_a_turn_does_not_advance_the_counter() -> void:
	GameState.resolve_turn(SeededDice.new(1))

	assert_int(GameState.turn_number).override_failure_message(
		"resolve_turn ends in END without advancing; begin_next_turn is the caller's separate step"
	).is_equal(1)
	assert_int(GameState.phase).is_equal(GameStateData.Phase.END)


# --- 3. what a turn boundary must NOT reset --------------------------------------------------------
# The per-turn buffers go; campaign state stays. Supply is the clearest case — a pool restored at the
# turn boundary would make the whole DOS mechanic inert, and nothing else would fail.

func test_begin_next_turn_preserves_campaign_persistent_supply_state() -> void:
	GameState.resolve_turn(SeededDice.new(1))
	var pool_after_turn_1: float = GameState.supply_state.current_dos_tons
	var history_after_turn_1: int = GameState.supply_state.day_history.size()
	assert_int(history_after_turn_1).is_greater(0)

	GameState.begin_next_turn()

	assert_float(GameState.supply_state.current_dos_tons).override_failure_message(
		"the DOS pool is campaign state — beginning a turn must not restore it"
	).is_equal_approx(pool_after_turn_1, 0.0001)
	assert_int(GameState.supply_state.day_history.size()).is_equal(history_after_turn_1)


func test_begin_next_turn_clears_the_commitment_buffer_too() -> void:
	var green := GameData.get_brigade(GoldenScript.GREEN_DEFENDER_ID)
	assert_object(green).is_not_null()
	var neighbours := GameData.get_neighbors(green.hex_id)
	assert_array(neighbours).is_not_empty()
	GameState.add_commit_order(Brigade.Team.GREEN, green.id, String(neighbours[0]))
	assert_int(GameState.commitments_for(Brigade.Team.GREEN).size()).is_equal(1)

	GameState.resolve_turn(SeededDice.new(1))
	GameState.begin_next_turn()

	assert_array(GameState.commitments_for(Brigade.Team.GREEN)).override_failure_message(
		"commitments are per-turn requests and must not survive the boundary"
	).is_empty()


# --- 4. the victory latches move together, from ONE verdict ----------------------------------------

func test_cleanup_applies_game_over_and_winner_from_the_same_summary() -> void:
	GameState.resolve_cleanup_phase()

	var summary := GameState.last_cleanup_summary
	assert_object(summary).is_not_null()
	assert_bool(GameState.game_over).override_failure_message(
		"game_over must be the cleanup summary's verdict, not a separately computed one"
	).is_equal(summary.game_over)
	assert_str(GameState.winner).is_equal(summary.winner)


# --- 5. the landing latch is monotone --------------------------------------------------------------
# `_china_has_landed` arms the "after_first_landing" loss-check arm. A turn in which Red holds nothing
# ashore must not disarm it, or the victory condition silently re-arms mid-campaign.

func test_a_landed_latch_survives_a_turn_with_nobody_ashore() -> void:
	var latched := CleanupResolver.resolve(
		0, GameData.brigades, [], GameData.victory_config, 1, true)

	assert_bool(bool(latched["china_has_landed"])).override_failure_message(
		"a turn with ZERO Red battalions ashore must not un-latch a previous landing"
	).is_true()


func test_the_landing_latch_starts_false_and_needs_a_real_landing() -> void:
	var fresh := CleanupResolver.resolve(
		0, GameData.brigades, [], GameData.victory_config, 1, false)

	assert_bool(bool(fresh["china_has_landed"])).is_false()


# --- 6. multi-game reset in one process ------------------------------------------------------------
# A second game must not inherit the first one's turn, phase or latches.

func test_a_second_game_in_the_same_process_starts_clean() -> void:
	GameState.add_move_order(
		Brigade.Team.RED, RED_BRIGADE_ID, GREEN_TARGET_HEX, Movement.MODE_TACTICAL)
	GameState.resolve_turn(SeededDice.new(1))
	GameState.begin_next_turn()
	assert_int(GameState.turn_number).is_equal(2)

	GameState.reset_to_scenario()

	assert_int(GameState.turn_number).is_equal(1)
	assert_int(GameState.phase).is_equal(GameStateData.Phase.PLANNING)
	assert_bool(GameState.game_over).is_false()
	assert_str(GameState.winner).is_empty()
	assert_array(GameState.orders_for(Brigade.Team.RED)).is_empty()
	assert_array(GameState.commitments_for(Brigade.Team.GREEN)).is_empty()
	assert_array(GameState.air_insert_orders).is_empty()
	assert_array(GameState.jlsf_orders).is_empty()
