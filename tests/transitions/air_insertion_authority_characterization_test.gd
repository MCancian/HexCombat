extends GdUnitTestSuite

## Plan 0048 step 1 — characterization. These pin the air-insertion behaviours the plan is about to
## route through `AirInsertionTransitions`, BEFORE any of them moves. They drive the WHOLE phase
## (`ReinforcementPhases.resolve_air_insertion_turn`) against the real `GameData` autoload, because
## what is being pinned is the interaction between the resolver, the force authority and the
## companion cap/history updates — not any one of them alone.
##
## What is deliberately NOT re-tested here, because duplicating it would just be a second place to
## update:
##   - packet selection, budget sharing and the attrition formula — tests/air_insertion_resolver_test.gd
##   - pool draining, roster losses and placement — tests/transitions/force_transitions_test.gd
##
## No shipped scenario opts the mechanic in, so the pool is built by hand from the OOB's real PLAAF
## brigades exactly as tests/air_insertion_order_test.gd does. Expectations are derived from measured
## values (`cap_before`, the summary's own counts) rather than hardcoded OOB numbers, so a future
## change to the airborne corps' size cannot make these tests lie.

const AIRBORNE_BRIGADE := "PLAAF-ABN-127-Airborne"
const AIR_ASSAULT_BRIGADE := "PLAAF-ABN-130-Air-Assault"
const DROP_HEX := "hex_3_9"        # plains, passable
const IMPASSABLE_HEX := "hex_10_10"  # mountain
const GHOST_BRIGADE := "TEST-0048-GHOST"


## Counts substream derivations so "no orders => no derive, no draws" is an assertion rather than a
## hope. `ScriptedDice.derive` returns self, so the base class cannot report this.
class CountingDice extends ScriptedDice:
	var derives: int = 0

	func derive(label: String) -> Dice:
		derives += 1
		return super.derive(label)


func before_test() -> void:
	GameData.load_all()
	GameState.reset_to_scenario()


func after_test() -> void:
	GameData.load_all()
	GameState.reset_to_scenario()


## `ad_health` drives the loss rate: 1.0 makes airborne attrition 0.75, so a scripted 0.0 roll is a
## loss and a scripted 1.0 roll is a survivor. 0.0 makes it impossible to lose anything.
func _state(ad_health: float) -> GameStateData:
	var state := GameStateData.new()
	state.turn_number = 1
	state.air_insertion_state = AirInsertionStateBuilder.build({"enabled": true}, GameData.brigades)
	state.last_ijfs_summary = {"taiwan_ad_health_after": {"effective_ad_health": ad_health}}
	return state


func _dice(floats: Array) -> CountingDice:
	return CountingDice.new([], [], floats)


func _rolls(value: float, count: int) -> Array:
	var floats: Array = []
	for _index in range(count):
		floats.append(value)
	return floats


func _order(brigade_id: String, hex_id: String) -> Dictionary:
	return {"brigade_id": brigade_id, "target_hex": hex_id}


func _airborne_cap(state: GameStateData) -> int:
	return int(state.air_insertion_state.caps[LiftClass.AIRBORNE])


# --- 1. cap erosion is exactly the loss count, and only for the class that flew -------------------

func test_losses_erode_only_the_flying_classes_cap_by_exactly_the_loss_count() -> void:
	var state := _state(1.0)
	var cap_before := _airborne_cap(state)
	var assault_cap_before := int(state.air_insertion_state.caps[LiftClass.AIR_ASSAULT])
	state.air_insert_orders = [_order(AIRBORNE_BRIGADE, DROP_HEX)]
	# First two battalions die, the rest of the packet lands.
	var floats: Array = [0.0, 0.0]
	floats.append_array(_rolls(1.0, 32))

	var summary := ReinforcementPhases.resolve_air_insertion_turn(state, _dice(floats))

	assert_int(summary.battalions_lost).is_equal(2)
	assert_int(_airborne_cap(state)).override_failure_message(
		"a lost battalion destroys the airframe that carried it — the cap falls by exactly the losses"
	).is_equal(cap_before - 2)
	assert_int(state.air_insertion_state.caps[LiftClass.AIR_ASSAULT]).is_equal(assault_cap_before)


# --- 2. a packet lost IN FULL still erodes caps and still logs ------------------------------------
# The load-bearing one for the migration. A total loss produces no surviving battalion, but
# `AirInsertionResolver._append_drop` appends to `landings` unconditionally, so the phase does NOT
# take its empty-landings early return and the companion updates still run. An implementation that
# gated cap erosion on "something landed" would silently make the bloodiest drops free.

func test_a_packet_lost_in_full_still_erodes_the_cap_and_appends_history() -> void:
	var state := _state(1.0)
	var cap_before := _airborne_cap(state)
	state.air_insert_orders = [_order(AIRBORNE_BRIGADE, DROP_HEX)]

	var summary := ReinforcementPhases.resolve_air_insertion_turn(state, _dice(_rolls(0.0, 32)))

	assert_int(summary.battalions_landed).is_equal(0)
	assert_int(summary.battalions_lost).is_greater(0)
	assert_int(_airborne_cap(state)).is_equal(cap_before - summary.battalions_lost)
	assert_array(state.air_insertion_state.history).has_size(1)
	var entry: Dictionary = state.air_insertion_state.history[0]
	assert_int(int(entry["landed"])).is_equal(0)
	assert_int(int(entry["lost"])).is_equal(summary.battalions_lost)


# --- 3/4. the ceiling never moves and the budget never rises --------------------------------------

func test_caps_only_fall_across_turns_and_initial_caps_never_moves() -> void:
	var state := _state(1.0)
	var initial := state.air_insertion_state.initial_caps.duplicate()
	var cap_before := _airborne_cap(state)

	state.air_insert_orders = [_order(AIRBORNE_BRIGADE, DROP_HEX)]
	ReinforcementPhases.resolve_air_insertion_turn(state, _dice(_rolls(0.0, 32)))
	var cap_after_turn_1 := _airborne_cap(state)

	state.turn_number = 2
	state.air_insert_orders = [_order("PLAAF-ABN-128-Airborne", DROP_HEX)]
	ReinforcementPhases.resolve_air_insertion_turn(state, _dice(_rolls(1.0, 32)))

	assert_int(cap_after_turn_1).is_less(cap_before)
	assert_int(_airborne_cap(state)).override_failure_message(
		"a clean drop must not refund lift the air defences already destroyed"
	).is_equal(cap_after_turn_1)
	assert_int(_airborne_cap(state)).is_less_equal(int(initial[LiftClass.AIRBORNE]))
	assert_dict(state.air_insertion_state.initial_caps).is_equal(initial)


# --- 5. the log: one row per drop, in resolution order, with the six documented keys --------------

func test_history_appends_one_row_per_drop_with_the_documented_shape() -> void:
	var state := _state(0.0)
	state.air_insert_orders = [
		_order(AIRBORNE_BRIGADE, DROP_HEX),
		_order("PLAAF-ABN-128-Airborne", DROP_HEX),
	]

	var summary := ReinforcementPhases.resolve_air_insertion_turn(state, _dice(_rolls(1.0, 32)))

	assert_array(state.air_insertion_state.history).has_size(summary.drops.size())
	var first: Dictionary = state.air_insertion_state.history[0]
	assert_array(first.keys()).contains(
		["turn", "brigade_id", "lift_class", "hex_id", "landed", "lost"])
	assert_int(int(first["turn"])).is_equal(1)
	assert_str(String(first["brigade_id"])).is_equal(AIRBORNE_BRIGADE)
	assert_str(String(first["hex_id"])).is_equal(DROP_HEX)
	assert_str(String(first["lift_class"])).is_equal(LiftClass.AIRBORNE)
	# Resolution order, not pool order: the log mirrors the order the packets flew in.
	var logged_ids: Array = []
	for row_value in state.air_insertion_state.history:
		logged_ids.append(String((row_value as Dictionary)["brigade_id"]))
	var dropped_ids: Array = []
	for drop_value in summary.drops:
		dropped_ids.append(String((drop_value as Dictionary)["brigade_id"]))
	assert_array(logged_ids).is_equal(dropped_ids)


# --- 6. the quiet paths touch neither state nor the RNG ------------------------------------------
# An empty pool or no orders is what keeps the golden byte-stable while the PLAAF corps sits in the
# OOB, so "no derive" is the assertion that matters, not merely "no change".

func test_no_orders_touches_nothing_and_derives_no_substream() -> void:
	var state := _state(1.0)
	var caps_before := state.air_insertion_state.caps.duplicate()
	var dice := _dice([])

	var summary := ReinforcementPhases.resolve_air_insertion_turn(state, dice)

	assert_int(dice.derives).is_equal(0)
	assert_dict(state.air_insertion_state.caps).is_equal(caps_before)
	assert_array(state.air_insertion_state.history).is_empty()
	assert_array(summary.drops).is_empty()


func test_a_rejected_order_touches_nothing_and_derives_no_substream() -> void:
	var state := _state(1.0)
	var caps_before := state.air_insertion_state.caps.duplicate()
	state.air_insert_orders = [_order(AIRBORNE_BRIGADE, IMPASSABLE_HEX)]
	var dice := _dice([])

	var summary := ReinforcementPhases.resolve_air_insertion_turn(state, dice)

	assert_int(dice.derives).is_equal(0)
	assert_array(summary.rejected).has_size(1)
	assert_dict(state.air_insertion_state.caps).is_equal(caps_before)
	assert_array(state.air_insertion_state.history).is_empty()


# --- 7. a refused force receipt leaves the lift ledger alone --------------------------------------
# The cross-authority seam. The force authority commits pool/roster/placement BEFORE the companion
# cap/history updates run, so its refusal must leave the ledger untouched — otherwise the two
# disagree about a drop that never happened.

func test_a_force_refusal_leaves_caps_and_history_untouched() -> void:
	var state := _state(0.0)
	var caps_before := state.air_insertion_state.caps.duplicate()
	# A pool entry for a brigade the OOB does not contain: the resolver flies it, the force authority
	# refuses it.
	state.air_insertion_state.pool.append({
		"brigade_id": GHOST_BRIGADE,
		"lift_class": LiftClass.AIRBORNE,
		"bns": [{"id": "%s-AIR-1" % GHOST_BRIGADE, "type": "Airborne Combined Arms Battalion"}],
	})
	state.air_insert_orders = [_order(GHOST_BRIGADE, DROP_HEX)]

	var summary := ReinforcementPhases.resolve_air_insertion_turn(state, _dice(_rolls(1.0, 32)))

	assert_array(summary.drops).has_size(1)
	assert_dict(state.air_insertion_state.caps).override_failure_message(
		"the force authority refused the packet, so no lift was spent flying it"
	).is_equal(caps_before)
	assert_array(state.air_insertion_state.history).is_empty()


# --- 8. the order buffer is drained on EVERY path -------------------------------------------------
# `air_insert_orders` is cleared before both early returns. An implementation that moved the clear
# into the success branch would silently re-fly rejected and refused orders next turn, and every
# assertion above would still pass.

func test_the_order_buffer_is_emptied_whether_the_drop_resolves_rejects_or_is_refused() -> void:
	var resolved := _state(0.0)
	resolved.air_insert_orders = [_order(AIRBORNE_BRIGADE, DROP_HEX)]
	ReinforcementPhases.resolve_air_insertion_turn(resolved, _dice(_rolls(1.0, 32)))
	assert_array(resolved.air_insert_orders).is_empty()

	var rejected := _state(1.0)
	rejected.air_insert_orders = [_order(AIRBORNE_BRIGADE, IMPASSABLE_HEX)]
	ReinforcementPhases.resolve_air_insertion_turn(rejected, _dice([]))
	assert_array(rejected.air_insert_orders).is_empty()

	var refused := _state(0.0)
	refused.air_insertion_state.pool.append({
		"brigade_id": GHOST_BRIGADE,
		"lift_class": LiftClass.AIRBORNE,
		"bns": [{"id": "%s-AIR-1" % GHOST_BRIGADE, "type": "Airborne Combined Arms Battalion"}],
	})
	refused.air_insert_orders = [_order(GHOST_BRIGADE, DROP_HEX)]
	ReinforcementPhases.resolve_air_insertion_turn(refused, _dice(_rolls(1.0, 32)))
	assert_array(refused.air_insert_orders).is_empty()


# --- 9. a successful landing recomputes hex ownership ---------------------------------------------
# Without this the drop zone stays on last turn's ownership for the rest of the turn, so the
# movement, combat and supply-corridor logic that runs next all read a map the brigade is not on.

func test_a_successful_landing_puts_the_brigade_on_the_map_and_recomputes_ownership() -> void:
	var state := _state(0.0)
	state.air_insert_orders = [_order(AIRBORNE_BRIGADE, DROP_HEX)]

	ReinforcementPhases.resolve_air_insertion_turn(state, _dice(_rolls(1.0, 32)))

	assert_array(GameData.get_brigades_in_hex(DROP_HEX)).contains([AIRBORNE_BRIGADE])
	assert_array([HexOwner.RED, HexOwner.CONTESTED]).override_failure_message(
		"a Red brigade standing in the hex must be visible to the ownership map this same turn"
	).contains([GameData.hex_states[DROP_HEX].hex_owner])


# --- 10. the applied budget and the reported budget cannot drift ----------------------------------
# `summary.caps_after` is what the observation and the LLM payload report; `state.caps` is what the
# next turn flies against. Plan 0048 makes the authority DERIVE the erosion instead of copying the
# summary, so this is the pin that the two calculations stay identical.

func test_the_applied_caps_equal_the_caps_the_summary_reports() -> void:
	var state := _state(1.0)
	state.air_insert_orders = [_order(AIRBORNE_BRIGADE, DROP_HEX)]
	var floats: Array = [0.0, 1.0, 0.0]
	floats.append_array(_rolls(1.0, 32))

	var summary := ReinforcementPhases.resolve_air_insertion_turn(state, _dice(floats))

	assert_dict(state.air_insertion_state.caps).is_equal(summary.caps_after)


# --- 11. the log records the turn each packet actually flew on -----------------------------------
# Every other case resolves on turn 1, so hardcoding `"turn": 1` in the authority would leave them
# all green while corrupting every multi-turn report and the LLM history block.

func test_history_records_the_turn_each_packet_flew_on() -> void:
	var state := _state(0.0)
	state.air_insert_orders = [_order(AIRBORNE_BRIGADE, DROP_HEX)]
	ReinforcementPhases.resolve_air_insertion_turn(state, _dice(_rolls(1.0, 32)))

	state.turn_number = 2
	state.air_insert_orders = [_order("PLAAF-ABN-128-Airborne", DROP_HEX)]
	ReinforcementPhases.resolve_air_insertion_turn(state, _dice(_rolls(1.0, 32)))

	var turns: Array = []
	for row_value in state.air_insertion_state.history:
		turns.append(int((row_value as Dictionary)["turn"]))
	assert_array(turns).is_equal([1, 2])


# --- 12. the two authorities' requests describe the same packets ----------------------------------
# Force is handed the landings, the lift ledger is handed the drops, and neither can see the other's
# request. `AirInsertionResolver._append_drop` emits both in one call, which is the ONLY reason they
# agree; nothing else in the tree pins it, so a change there would silently let force move battalions
# no drop paid lift for.

func test_the_resolver_emits_one_drop_per_landing() -> void:
	var state := _state(1.0)
	# Two DIFFERENT lift classes, because they draw on separate budgets: a second airborne order
	# would be rejected for an exhausted cap rather than flying, and one drop proves nothing here.
	state.air_insert_orders = [
		_order(AIRBORNE_BRIGADE, DROP_HEX),
		_order(AIR_ASSAULT_BRIGADE, DROP_HEX),
	]
	# First packet dies in full, second lands in full: the two extremes in one resolution.
	var floats: Array = _rolls(0.0, 8)
	floats.append_array(_rolls(1.0, 32))
	var dice := _dice(floats)

	var outcome := AirInsertionResolver.resolve(
		state.air_insertion_state, state.air_insert_orders, state.turn_number,
		AirInsertionResolver.threat_from_ijfs_summary(state.last_ijfs_summary),
		GameData.air_insertion_attrition_config(),
		func(_hex_id: String) -> bool: return true,
		dice)
	var summary: AirInsertionSummary = outcome["summary"]

	assert_array(summary.drops).has_size((outcome["landings"] as Array).size())
	assert_int(summary.drops.size()).is_equal(2)
