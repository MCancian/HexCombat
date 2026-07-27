extends GdUnitTestSuite

## Plan 0043 — the Green anti-ship establishment across crossings.
##
## Pins the ONE-crossing launch-attrition contract: the exact ScriptedDice draw count and order, and
## both report arrays. It is the guard on the whole plan — splitting the calculator from the mutation
## authority must not move a single die.
##
## Everything here drives the real seam the engine uses: FiresPhases applies the IJFS effects, the
## calculator rolls and reports, and AntishipTransitions — the only writer of these rows — books it.


# type 23: p_detect 0.5 * p_destroy_if_detected 0.7 = p_destroy 0.35; p_intercept_before_launch 0.6.
const LAUNCH_CONFIG := {"23": {
	"p_detect": 0.5, "p_destroy_if_detected": 0.7, "p_intercept_before_launch": 0.6}}

## Shot 1: 0.9 >= 0.35            -> launched.
## Shot 2: 0.1 < 0.35, 0.1 < 0.6  -> destroyed before launch (no missile away).
## Shot 3: 0.1 < 0.35, 0.9 >= 0.6 -> destroyed after launch (missile away).
## Shot 4: 0.5 >= 0.35            -> launched.
## Six floats for four shots: the second draw happens ONLY when the first one kills.
const SHOT_FLOATS := [0.9, 0.1, 0.1, 0.1, 0.9, 0.5]


## One (TO, type) row plus the state that carries the arsenal and the crossing identity.
func _state(to_number: int, type_id: int, quantity: int) -> GameStateData:
	var system := AntishipSystem.new()
	system.to_number = to_number
	system.type_id = type_id
	system.quantity = quantity
	system.original_quantity = quantity
	var state := GameStateData.new()
	state.antiship_systems = [system]
	state._antiship_built = true
	return state


func _row(state: GameStateData) -> AntishipSystem:
	return state.antiship_systems[0]


## One whole crossing the way the turn engine runs it: last turn's cleanup has cleared the crossing
## flags, FiresPhases applies the IJFS effects, the calculator rolls, and the authority books what it
## reported. `writeback` null = the IJFS killed nothing.
func _crossing(state: GameStateData, floats: Array, writeback: IjfsWriteback = null) -> Dictionary:
	AntishipTransitions.reset_transient_flags(state.antiship_systems)
	state.turn_number += 1
	AntishipTransitions.apply_ijfs_effects(state.antiship_systems, writeback)
	var plan := AntishipCalculator.build_firing_plan(
		state.antiship_systems, {}, [3], {"3:23": 40.0}, {}, null)
	var dice := ScriptedDice.new([], [], floats)
	var result := AntishipCalculator.resolve_launch_attrition(
		plan["allocation_plan"], plan["destroyed_firing_plan"], LAUNCH_CONFIG, dice)
	AntishipTransitions.apply_launch_attrition(state, result["outcomes"])
	result["dice"] = dice
	return result


func test_one_crossing_draw_order_and_reports_are_pinned() -> void:
	var result := _crossing(_state(3, 23, 10), SHOT_FLOATS)

	# Exactly six randf() draws for four attempted shots — no more (the queue is empty) and no
	# fewer (a short queue push_errors and returns 0.0, which would change the tallies below).
	var dice: ScriptedDice = result["dice"]
	assert_int(dice._floats.size()).is_equal(0)

	var fired: Array = result["systems_fired"]
	assert_int(fired.size()).is_equal(1)
	assert_int(int(fired[0]["attempted_firing"])).is_equal(4)
	assert_int(int(fired[0]["available_firing"])).is_equal(3)   # shots 1, 3, 4 got a missile away
	assert_int(int(fired[0]["destroyed_firing"])).is_equal(0)
	assert_int(int(fired[0]["systems_fired"])).is_equal(3)
	assert_int(int(fired[0]["prelaunch_destroyed"])).is_equal(1)
	assert_int(int(fired[0]["postlaunch_destroyed"])).is_equal(1)

	var attrition: Array = result["launch_attrition"]
	assert_int(attrition.size()).is_equal(1)
	assert_int(int(attrition[0]["to"])).is_equal(3)
	assert_int(int(attrition[0]["type"])).is_equal(23)
	assert_int(int(attrition[0]["attempted_firing"])).is_equal(4)
	assert_int(int(attrition[0]["launched"])).is_equal(3)
	assert_int(int(attrition[0]["prelaunch_destroyed"])).is_equal(1)
	assert_int(int(attrition[0]["postlaunch_destroyed"])).is_equal(1)
