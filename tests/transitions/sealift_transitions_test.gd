extends GdUnitTestSuite

## Plan 0045 — sealift/fleet aggregate mutation authority. These tests drive `SealiftTransitions`
## against tiny in-memory fleets so every hull transition and every invariant it guards is pinned
## without running a full turn. The conservation equation
## `ready + surviving_sent + offloading + returning + destroyed == fleet_total` is asserted after each
## operation, per ship type: it is the whole point of the aggregate, and it is exactly the equation the
## pre-0045 split broke between booking a loss and reprojecting the fleet.

const LHA := "LHA"           # a carrier: enters cohorts, goes busy
const DDG := "DDG"           # an escort: screens the wave out of the ready pool
const RETURN_TIME := 3


func _carrier_def(ship_type: String, capacity: float) -> ShipDef:
	var ship_def := ShipDef.new()
	ship_def.name = ship_type
	ship_def.category = "Military_Amphibious"
	ship_def.carrying_capacity_bn_equiv = capacity
	return ship_def


func _escort_def(ship_type: String) -> ShipDef:
	var ship_def := ShipDef.new()
	ship_def.name = ship_type
	ship_def.category = "Escort"
	ship_def.carrying_capacity_bn_equiv = 0.0
	return ship_def


func _ship_defs_by_name() -> Dictionary:
	return {LHA: _carrier_def(LHA, 2.0), DDG: _escort_def(DDG)}


## A fleet of `lha` carriers and `ddg` escorts, all hulls ready, plus an empty sealift state. Built
## through the real FleetBuilder so these tests cannot pass against a fleet the builder would never
## produce.
func _state(lha: int, ddg: int) -> GameStateData:
	var state := GameStateData.new()
	var lha_def := _carrier_def(LHA, 2.0)
	lha_def.total_count = lha
	var ddg_def := _escort_def(DDG)
	ddg_def.total_count = ddg
	state.fleet = FleetBuilder.build({LHA: lha_def, DDG: ddg_def})
	state.sealift_state = SealiftState.new()
	return state


func _cohort(hulls: Dictionary, bn_ids: Array, cohort_state: String) -> SealiftCohort:
	if cohort_state == SealiftState.STATE_SENT:
		return SealiftCohort.sent(hulls, bn_ids)
	return SealiftCohort.offloading(hulls, bn_ids)


func _cohort_hulls(state: GameStateData, index: int, ship_type: String) -> int:
	return int((state.sealift_state.cohorts[index] as SealiftCohort).hulls_by_type.get(ship_type, 0))


func _ship(state: GameStateData, ship_type: String) -> ShipState:
	return state.fleet[ship_type]


## Every surviving hull is in exactly one bucket and no hull is unaccounted for, for every type.
func _assert_conserved(state: GameStateData) -> void:
	for ship_type in state.fleet.keys():
		var ship: ShipState = state.fleet[ship_type]
		assert_bool(ship.validate()).override_failure_message(
			"conservation broken for %s" % ship_type).is_true()


# --- projection ---------------------------------------------------------------------------------

func test_projection_puts_cohort_hulls_in_sent_and_offloading_bins() -> void:
	var state := _state(6, 4)
	state.sealift_state.cohorts = [
		_cohort({LHA: 2}, ["a"], SealiftState.STATE_SENT),
		_cohort({LHA: 3}, ["b"], SealiftState.STATE_OFFLOADING),
	]

	SealiftTransitions.project_fleet(state)

	assert_int(_ship(state, LHA).surviving_sent).is_equal(2)
	assert_int(_ship(state, LHA).offloading).is_equal(3)
	assert_int(_ship(state, LHA).ready).is_equal(1)
	assert_int(_ship(state, DDG).ready).is_equal(4)
	_assert_conserved(state)


func test_projection_counts_return_pipeline_slots_as_returning() -> void:
	var state := _state(6, 4)
	state.sealift_state.return_pipeline = {
		LHA: [{"count": 2, "turns_remaining": RETURN_TIME}, {"count": 1, "turns_remaining": 1}],
	}

	SealiftTransitions.project_fleet(state)

	assert_int(_ship(state, LHA).returning).is_equal(3)
	assert_int(_ship(state, LHA).ready).is_equal(3)
	_assert_conserved(state)


## Zero return time never puts a hull in the pipeline at all, so a freed hull is ready the same turn.
## The projection has to read that as "no returning hulls", not as "an empty slot".
func test_projection_with_no_pipeline_leaves_every_survivor_ready() -> void:
	var state := _state(6, 4)

	SealiftTransitions.project_fleet(state)

	assert_int(_ship(state, LHA).ready).is_equal(6)
	assert_int(_ship(state, LHA).returning).is_equal(0)
	_assert_conserved(state)


## Plan 0004 D5: a reloading escort type has left the screen entirely, so ALL its surviving hulls are
## busy — not a counted few. This is the one whole-type bucket in the projection.
func test_reloading_escort_type_is_wholly_returning() -> void:
	var state := _state(6, 4)
	state.sealift_state.escort_sam = {DDG: 0}
	state.sealift_state.escort_sam_max = {DDG: 8}
	state.sealift_state.escort_sam_threshold = {DDG: 2}
	state.sealift_state.escort_reload = {DDG: 2}

	SealiftTransitions.project_fleet(state)

	assert_int(_ship(state, DDG).returning).is_equal(4)
	assert_int(_ship(state, DDG).ready).is_equal(0)
	_assert_conserved(state)


func test_projection_is_a_no_op_without_a_sealift_state() -> void:
	var state := _state(6, 4)
	state.sealift_state = null

	SealiftTransitions.project_fleet(state)

	assert_int(_ship(state, LHA).ready).is_equal(6)
	_assert_conserved(state)


# --- hull losses --------------------------------------------------------------------------------

## A carrier dies where it is: inside the sent cohort that was carrying troops when it was hit. The
## hull leaves the cohort AND the surviving fleet in one call, and the projection is re-run before the
## call returns — so the fleet is never observable with `destroyed` booked and `ready` stale.
func test_carrier_loss_comes_out_of_the_sent_cohort() -> void:
	var state := _state(6, 4)
	state.sealift_state.cohorts = [_cohort({LHA: 4}, ["a", "b"], SealiftState.STATE_SENT)]
	SealiftTransitions.project_fleet(state)

	var receipt := SealiftTransitions.apply_hull_losses(state, {LHA: 3}, _ship_defs_by_name())

	assert_int(_cohort_hulls(state, 0, LHA)).is_equal(1)
	assert_int(_ship(state, LHA).destroyed).is_equal(3)
	assert_int(_ship(state, LHA).fleet_surviving_total).is_equal(3)
	assert_int(_ship(state, LHA).surviving_sent).is_equal(1)
	assert_int(_ship(state, LHA).ready).is_equal(2)
	assert_int(receipt.applied_by_type[LHA]).is_equal(3)
	assert_str(receipt.source_by_type[LHA]).is_equal(SealiftHullLossReceipt.SOURCE_SENT_COHORTS)
	assert_bool(receipt.was_capped()).is_false()
	_assert_conserved(state)


## An escort is never bound to a cohort — it screens the wave and returns the same turn — so its losses
## come off the surviving fleet and the projection takes them out of `ready`.
func test_escort_loss_comes_out_of_the_ready_screen() -> void:
	var state := _state(6, 4)
	state.sealift_state.cohorts = [_cohort({LHA: 4}, ["a"], SealiftState.STATE_SENT)]
	SealiftTransitions.project_fleet(state)

	var receipt := SealiftTransitions.apply_hull_losses(state, {DDG: 1}, _ship_defs_by_name())

	assert_int(_ship(state, DDG).destroyed).is_equal(1)
	assert_int(_ship(state, DDG).ready).is_equal(3)
	assert_int(_ship(state, LHA).surviving_sent).is_equal(4)
	assert_str(receipt.source_by_type[DDG]).is_equal(SealiftHullLossReceipt.SOURCE_READY_SCREEN)
	_assert_conserved(state)


## The crossing can report more kills of a type than the bucket holds (it fires at the sailing
## snapshot, and mine attrition resolves separately). The application is CAPPED at what is present and
## the cap is reported — a receipt that claimed the full request would over-count the fleet's losses.
func test_a_loss_request_larger_than_the_bucket_is_capped_and_reported() -> void:
	var state := _state(6, 4)
	state.sealift_state.cohorts = [_cohort({LHA: 2}, ["a"], SealiftState.STATE_SENT)]
	SealiftTransitions.project_fleet(state)

	var receipt := SealiftTransitions.apply_hull_losses(state, {LHA: 5}, _ship_defs_by_name())

	assert_int(_ship(state, LHA).destroyed).is_equal(2)
	assert_int(_ship(state, LHA).fleet_surviving_total).is_equal(4)
	assert_int(receipt.requested_by_type[LHA]).is_equal(5)
	assert_int(receipt.applied_by_type[LHA]).is_equal(2)
	assert_array(receipt.capped_types).contains([LHA])
	assert_bool(receipt.was_capped()).is_true()
	_assert_conserved(state)


## Carrier losses are only eligible from cohorts that are CROSSING. Hulls already offloading are ashore
## and cannot be sunk by this turn's crossing, so a request finds nothing to take.
func test_offloading_cohorts_are_not_eligible_for_crossing_losses() -> void:
	var state := _state(6, 4)
	state.sealift_state.cohorts = [_cohort({LHA: 4}, ["a"], SealiftState.STATE_OFFLOADING)]
	SealiftTransitions.project_fleet(state)

	var receipt := SealiftTransitions.apply_hull_losses(state, {LHA: 2}, _ship_defs_by_name())

	assert_int(_ship(state, LHA).destroyed).is_equal(0)
	assert_int(_ship(state, LHA).offloading).is_equal(4)
	assert_int(receipt.applied_by_type[LHA]).is_equal(0)
	_assert_conserved(state)


func test_zero_and_unknown_type_losses_change_nothing() -> void:
	var state := _state(6, 4)
	state.sealift_state.cohorts = [_cohort({LHA: 4}, ["a"], SealiftState.STATE_SENT)]
	SealiftTransitions.project_fleet(state)

	var receipt := SealiftTransitions.apply_hull_losses(
		state, {LHA: 0, "Nonexistent": 3}, _ship_defs_by_name())

	assert_int(_ship(state, LHA).destroyed).is_equal(0)
	assert_int(receipt.total_applied()).is_equal(0)
	assert_bool(receipt.applied_by_type.is_empty()).is_true()
	_assert_conserved(state)


## Losses spread across cohorts in cohort order until the request is satisfied, so a single type's
## kills can empty one cohort and bite into the next.
func test_carrier_losses_walk_cohorts_in_order() -> void:
	var state := _state(8, 4)
	state.sealift_state.cohorts = [
		_cohort({LHA: 2}, ["a"], SealiftState.STATE_SENT),
		_cohort({LHA: 3}, ["b"], SealiftState.STATE_SENT),
	]
	SealiftTransitions.project_fleet(state)

	SealiftTransitions.apply_hull_losses(state, {LHA: 4}, _ship_defs_by_name())

	assert_int(_cohort_hulls(state, 0, LHA)).is_equal(0)
	assert_int(_cohort_hulls(state, 1, LHA)).is_equal(1)
	assert_int(_ship(state, LHA).destroyed).is_equal(4)
	_assert_conserved(state)


# --- fleet lifecycle ----------------------------------------------------------------------------

func test_rebuild_fleet_replaces_a_live_fleet_with_fresh_hulls() -> void:
	var state := _state(6, 4)
	state.sealift_state.cohorts = [_cohort({LHA: 4}, ["a"], SealiftState.STATE_SENT)]
	SealiftTransitions.project_fleet(state)
	SealiftTransitions.apply_hull_losses(state, {LHA: 2}, _ship_defs_by_name())

	var fresh_def := _carrier_def(LHA, 2.0)
	fresh_def.total_count = 9
	SealiftTransitions.rebuild_fleet(state, {LHA: fresh_def})

	assert_int(state.fleet.size()).is_equal(1)
	assert_int(_ship(state, LHA).fleet_total).is_equal(9)
	assert_int(_ship(state, LHA).ready).is_equal(9)
	assert_int(_ship(state, LHA).destroyed).is_equal(0)


func test_ready_by_type_reports_the_projected_ready_pool() -> void:
	var state := _state(6, 4)
	state.sealift_state.cohorts = [_cohort({LHA: 4}, ["a"], SealiftState.STATE_SENT)]
	SealiftTransitions.project_fleet(state)

	var ready := SealiftTransitions.ready_by_type(state)

	assert_int(int(ready[LHA])).is_equal(2)
	assert_int(int(ready[DDG])).is_equal(4)


# --- cohort legs --------------------------------------------------------------------------------

## After the crossing every cohort still afloat is ashore-bound, whichever leg it was on — a cohort
## already offloading stays offloading rather than being flipped back.
func test_apply_sent_to_offloading_flips_every_sent_cohort() -> void:
	var state := _state(4, 0)
	state.sealift_state.cohorts = [
		_cohort({LHA: 1}, ["a"], SealiftState.STATE_SENT),
		_cohort({LHA: 1}, ["b"], SealiftState.STATE_OFFLOADING),
	]

	SealiftTransitions.apply_sent_to_offloading(state.sealift_state)

	assert_str(state.sealift_state.cohorts[0].cohort_state).is_equal(SealiftState.STATE_OFFLOADING)
	assert_str(state.sealift_state.cohorts[1].cohort_state).is_equal(SealiftState.STATE_OFFLOADING)
	SealiftTransitions.project_fleet(state)
	assert_int(_ship(state, LHA).offloading).is_equal(2)
	assert_int(_ship(state, LHA).surviving_sent).is_equal(0)
	_assert_conserved(state)


## A scenario with no sealift state at all (the minimal fixtures) must not crash the crossing.
func test_apply_sent_to_offloading_without_a_sealift_state_is_a_no_op() -> void:
	SealiftTransitions.apply_sent_to_offloading(null)


# --- serialized view ----------------------------------------------------------------------------

## `SealiftState.to_dict()` has no production consumer — it is a debug view. It is pinned anyway so the
## typed cohorts introduced by plan 0045 keep serializing as plain data: a Resource left in there would
## render as an object reference the moment anyone did print it or feed it to JSON.
##
## Key ORDER is asserted, not just the key set. Nothing reads this dictionary today, so no golden fixture
## would notice a reordering — and a serialized shape whose order drifts before it acquires its first
## reader is a shape nobody can later depend on.
func test_sealift_state_serializes_cohorts_as_plain_data_in_a_fixed_order() -> void:
	var state := _state(4, 0)
	state.sealift_state.cohorts = [_cohort({LHA: 2}, ["a", "b"], SealiftState.STATE_SENT)]
	state.sealift_state.return_pipeline = {LHA: [{"count": 1, "turns_remaining": 2}]}

	var serialized := state.sealift_state.to_dict()

	assert_array(serialized.keys()).is_equal([
		"mainland_pool", "cohorts", "return_pipeline", "escort_sam", "escort_sam_max",
		"escort_sam_threshold", "escort_reload",
	])
	var cohorts: Array = serialized["cohorts"]
	assert_int(cohorts.size()).is_equal(1)
	var cohort: Dictionary = cohorts[0]
	assert_array(cohort.keys()).is_equal(["hulls_by_type", "bn_ids", "cohort_state"])
	assert_int(int((cohort["hulls_by_type"] as Dictionary)[LHA])).is_equal(2)
	assert_array(cohort["bn_ids"]).is_equal(["a", "b"])
	assert_str(String(cohort["cohort_state"])).is_equal(SealiftState.STATE_SENT)


# --- return pipeline ----------------------------------------------------------------------------

## A slot whose timer reaches zero RELEASES its hulls rather than moving them to `ready` itself: they
## sail again the same turn they arrive back, so the sealift phase gets them as available capacity.
func test_tick_returns_releases_expiring_slots_and_keeps_the_rest() -> void:
	var state := _state(6, 0)
	state.sealift_state.return_pipeline = {
		LHA: [{"count": 2, "turns_remaining": 1}, {"count": 3, "turns_remaining": 2}],
	}

	var returned := SealiftTransitions.tick_returns(state.sealift_state)

	assert_int(int(returned[LHA])).is_equal(2)
	assert_int((state.sealift_state.return_pipeline[LHA] as Array).size()).is_equal(1)
	assert_int(int((state.sealift_state.return_pipeline[LHA][0] as Dictionary)["turns_remaining"])).is_equal(1)


## An emptied type bucket is dropped rather than left as an empty array, so a serialized sealift state
## carries no rows for types with nothing in the pipeline.
func test_tick_returns_drops_emptied_type_buckets() -> void:
	var state := _state(6, 0)
	state.sealift_state.return_pipeline = {LHA: [{"count": 2, "turns_remaining": 1}]}

	SealiftTransitions.tick_returns(state.sealift_state)

	assert_bool(state.sealift_state.return_pipeline.is_empty()).is_true()


## Slots stay SEPARATE, one per freed cohort per type. Two cohorts freed on the same turn return on the
## same turn, so summing them first would look equivalent — until return times differ per cohort.
func test_release_hulls_queues_one_slot_per_freed_cohort() -> void:
	var state := _state(8, 0)
	var plan := SealiftHullReleasePlan.of([{LHA: 2}, {LHA: 3}])

	SealiftTransitions.release_hulls(state.sealift_state, plan, RETURN_TIME)

	var slots: Array = state.sealift_state.return_pipeline[LHA]
	assert_int(slots.size()).is_equal(2)
	assert_int(int((slots[0] as Dictionary)["count"])).is_equal(2)
	assert_int(int((slots[1] as Dictionary)["count"])).is_equal(3)
	assert_int(int((slots[0] as Dictionary)["turns_remaining"])).is_equal(RETURN_TIME)
	SealiftTransitions.project_fleet(state)
	assert_int(_ship(state, LHA).returning).is_equal(5)
	_assert_conserved(state)


## Zero return time is the scenario saying there is no turnaround: the hulls are simply ready again, so
## nothing is queued at all. A zero-count batch is likewise not a slot.
func test_release_hulls_with_zero_return_time_queues_nothing() -> void:
	var state := _state(8, 0)

	SealiftTransitions.release_hulls(state.sealift_state, SealiftHullReleasePlan.of([{LHA: 2}]), 0)
	SealiftTransitions.release_hulls(
		state.sealift_state, SealiftHullReleasePlan.of([{LHA: 0}]), RETURN_TIME)

	assert_bool(state.sealift_state.return_pipeline.is_empty()).is_true()
	SealiftTransitions.project_fleet(state)
	assert_int(_ship(state, LHA).ready).is_equal(8)
	_assert_conserved(state)


## The full hull cycle: sent -> offloading -> (drained, freed) -> returning -> ready, with nothing lost
## or duplicated on the way round. This is the conservation claim the aggregate exists to make.
func test_a_hull_completes_the_full_cycle_back_to_ready() -> void:
	var state := _state(4, 0)
	state.sealift_state.cohorts = [_cohort({LHA: 4}, ["a"], SealiftState.STATE_SENT)]
	SealiftTransitions.project_fleet(state)
	assert_int(_ship(state, LHA).surviving_sent).is_equal(4)

	SealiftTransitions.apply_sent_to_offloading(state.sealift_state)
	SealiftTransitions.project_fleet(state)
	assert_int(_ship(state, LHA).offloading).is_equal(4)

	# The troops land: the force authority drains the cohort and hands over its hulls.
	(state.sealift_state.cohorts[0] as SealiftCohort).bn_ids = []
	var plan := ForceTransitions.free_emptied_cohorts(state.sealift_state)
	SealiftTransitions.release_hulls(state.sealift_state, plan, 2)
	SealiftTransitions.project_fleet(state)
	assert_int(_ship(state, LHA).offloading).is_equal(0)
	assert_int(_ship(state, LHA).returning).is_equal(4)
	_assert_conserved(state)

	# Two turns of turnaround and they are ready to sail again.
	SealiftTransitions.tick_returns(state.sealift_state)
	SealiftTransitions.project_fleet(state)
	assert_int(_ship(state, LHA).returning).is_equal(4)
	var returned := SealiftTransitions.tick_returns(state.sealift_state)
	SealiftTransitions.project_fleet(state)
	assert_int(int(returned[LHA])).is_equal(4)
	assert_int(_ship(state, LHA).ready).is_equal(4)
	_assert_conserved(state)


# --- escort magazines ---------------------------------------------------------------------------

## Firing down to the threshold diverts the whole type off the screen for `reload_time` turns; the timer
## then refills it to its loadout max and it rejoins.
func test_escort_magazine_depletes_diverts_reloads_and_refills() -> void:
	var state := _state(0, 4)
	state.sealift_state.escort_sam = {DDG: 10}
	state.sealift_state.escort_sam_max = {DDG: 10}
	state.sealift_state.escort_sam_threshold = {DDG: 4}

	SealiftTransitions.apply_escort_consumption(state.sealift_state, {DDG: 7}, 4)

	assert_int(int(state.sealift_state.escort_sam[DDG])).is_equal(3)
	assert_int(int(state.sealift_state.escort_reload[DDG])).is_equal(4)
	SealiftTransitions.project_fleet(state)
	assert_int(_ship(state, DDG).returning).is_equal(4)

	for _turn in range(3):
		SealiftTransitions.tick_escort_reload(state.sealift_state)
		assert_bool(state.sealift_state.escort_reload.has(DDG)).is_true()
		assert_int(int(state.sealift_state.escort_sam[DDG])).is_equal(3)

	SealiftTransitions.tick_escort_reload(state.sealift_state)

	assert_int(int(state.sealift_state.escort_sam[DDG])).is_equal(10)
	assert_bool(state.sealift_state.escort_reload.has(DDG)).is_false()
	SealiftTransitions.project_fleet(state)
	assert_int(_ship(state, DDG).ready).is_equal(4)
	_assert_conserved(state)


## Firing above the threshold does not divert, and a magazine cannot go below empty however much the
## crossing claims was fired.
func test_escort_magazine_above_threshold_stays_on_the_screen() -> void:
	var state := _state(0, 4)
	state.sealift_state.escort_sam = {DDG: 10}
	state.sealift_state.escort_sam_max = {DDG: 10}
	state.sealift_state.escort_sam_threshold = {DDG: 4}

	SealiftTransitions.apply_escort_consumption(state.sealift_state, {DDG: 3}, 4)

	assert_int(int(state.sealift_state.escort_sam[DDG])).is_equal(7)
	assert_bool(state.sealift_state.escort_reload.is_empty()).is_true()

	SealiftTransitions.apply_escort_consumption(state.sealift_state, {DDG: 99}, 4)

	assert_int(int(state.sealift_state.escort_sam[DDG])).is_equal(0)
	assert_int(int(state.sealift_state.escort_reload[DDG])).is_equal(4)


## An unmodelled magazine (the pre-0004 default: unlimited interception) is left alone entirely, and a
## reload_time of 0 means the scenario models consumption without ever diverting.
func test_escort_consumption_is_a_no_op_when_unmodelled() -> void:
	var state := _state(0, 4)

	SealiftTransitions.apply_escort_consumption(state.sealift_state, {DDG: 7}, 4)

	assert_bool(state.sealift_state.escort_sam.is_empty()).is_true()
	assert_bool(state.sealift_state.escort_reload.is_empty()).is_true()

	state.sealift_state.escort_sam = {DDG: 2}
	state.sealift_state.escort_sam_max = {DDG: 10}
	state.sealift_state.escort_sam_threshold = {DDG: 4}

	SealiftTransitions.apply_escort_consumption(state.sealift_state, {DDG: 1}, 0)

	assert_int(int(state.sealift_state.escort_sam[DDG])).is_equal(1)
	assert_bool(state.sealift_state.escort_reload.is_empty()).is_true()


## A type already reloading sat the crossing out, so it fired nothing and its timer must not be
## extended by a crossing it was not on the screen for.
func test_a_reloading_escort_type_does_not_restart_its_timer() -> void:
	var state := _state(0, 4)
	state.sealift_state.escort_sam = {DDG: 1}
	state.sealift_state.escort_sam_max = {DDG: 10}
	state.sealift_state.escort_sam_threshold = {DDG: 4}
	state.sealift_state.escort_reload = {DDG: 2}

	SealiftTransitions.apply_escort_consumption(state.sealift_state, {DDG: 1}, 4)

	assert_int(int(state.sealift_state.escort_reload[DDG])).is_equal(2)


# --- invariants ---------------------------------------------------------------------------------

## Hull counts only ever enter a cohort from the ready pool, which is derived from the fleet, so a
## positive count under a type the fleet does not have means the cohort and the fleet have drifted
## apart. The projection would silently ignore those hulls and still read as conserved.
func test_a_cohort_naming_an_unknown_hull_type_is_reported() -> void:
	var state := _state(6, 4)
	state.sealift_state.cohorts = [_cohort({"Ghost": 2}, ["a"], SealiftState.STATE_SENT)]

	await assert_error(func() -> void:
		SealiftTransitions.project_fleet(state)
	).is_push_error("SealiftTransitions: sent hulls of unknown ship type Ghost")


func test_an_escort_magazine_over_its_loadout_is_reported() -> void:
	var state := _state(6, 4)
	state.sealift_state.escort_sam = {DDG: 9}
	state.sealift_state.escort_sam_max = {DDG: 8}
	state.sealift_state.escort_sam_threshold = {DDG: 2}

	await assert_error(func() -> void:
		SealiftTransitions.project_fleet(state)
	).is_push_error("SealiftTransitions: escort magazine for DDG holds 9 of a 8 loadout")


## The three per-type magazine maps describe ONE magazine each. A missing threshold reads as 0, which
## would silently stop a type ever diverting to reload.
func test_an_incomplete_magazine_key_set_is_reported() -> void:
	var state := _state(6, 4)
	state.sealift_state.escort_sam = {DDG: 4}
	state.sealift_state.escort_sam_max = {DDG: 8}

	await assert_error(func() -> void:
		SealiftTransitions.project_fleet(state)
	).is_push_error("SealiftTransitions: escort magazine for DDG has an incomplete key set")


func test_reloading_a_magazine_the_type_does_not_have_is_reported() -> void:
	var state := _state(6, 4)
	state.sealift_state.escort_reload = {DDG: 2}
	state.sealift_state.escort_sam = {LHA: 4}
	state.sealift_state.escort_sam_max = {LHA: 4}
	state.sealift_state.escort_sam_threshold = {LHA: 1}

	await assert_error(func() -> void:
		SealiftTransitions.project_fleet(state)
	).is_push_error("SealiftTransitions: DDG is reloading a magazine it does not have")


## The same battalion in two cohorts means its hulls are freed twice — once per cohort that thinks it
## carried the last battalion ashore. The force authority refuses to create that state; this guard
## catches a hull operation that produced it.
func test_a_bn_bound_to_two_cohorts_is_reported() -> void:
	var state := _state(6, 4)
	state.sealift_state.cohorts = [
		_cohort({LHA: 2}, ["a"], SealiftState.STATE_SENT),
		_cohort({LHA: 2}, ["a"], SealiftState.STATE_OFFLOADING),
	]

	await assert_error(func() -> void:
		SealiftTransitions.project_fleet(state)
	).is_push_error("SealiftTransitions: BN a is bound to more than one cohort")
