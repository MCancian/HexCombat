extends GdUnitTestSuite

# SealiftResolver pure resolver tests (plan 0004). Deterministic — no dice injected.
# Builds ShipDef and SealiftState fixtures locally; no GameData/autoload access.


# --- fixture helpers ----------------------------------------------------------------------------

func _ship_def(name: String, category := "", capacity := 0.0, infrastructure := false, is_decoy := false) -> ShipDef:
	var d := ShipDef.new()
	d.name = name
	d.id = name.hash()
	d.category = category
	d.carrying_capacity_bn_equiv = capacity
	d.infrastructure = infrastructure
	d.is_decoy = is_decoy
	return d


func _ship_defs() -> Dictionary:
	return {
		"LHA": _ship_def("LHA", "Military_Amphibious", 1.0),
		"LPD": _ship_def("LPD", "Military_Amphibious", 1.0),
		"DDG": _ship_def("DDG", "Escort", 0.0),
	}


func _bn(id: String, type := "Infantry Battalion") -> Dictionary:
	return {"id": id, "type": type}


func _reserve_entry(brigade_id: String, bns: Array, locked_beach := 0, beach_hex := "A1", offset_bearing := 0.0) -> Dictionary:
	return {
		"brigade_id": brigade_id,
		"locked_beach": locked_beach,
		"beach_hex": beach_hex,
		"offset_bearing": offset_bearing,
		"bns": bns,
	}


# --- test 1: adoption ---------------------------------------------------------------------------

func test_adoption_creates_sent_cohort_from_reserve_orphans() -> void:
	var defs := _ship_defs()
	var state := SealiftState.new()
	var bns := [_bn("a"), _bn("b")]
	var reserve := [_reserve_entry("BdeA", bns)]
	var ready := {"LHA": 3, "DDG": 5}

	var result := SealiftResolver.resolve(state, reserve, ready, defs)

	# Exactly one sent cohort wrapping both BNs
	assert_int(state.cohorts.size()).is_equal(1)
	var cohort := state.cohorts[0] as Dictionary
	assert_str(cohort.get("state", "")).is_equal(SealiftState.STATE_SENT)
	var bn_ids: Array = cohort.get("bn_ids", [])
	assert_int(bn_ids.size()).is_equal(2)
	assert_str(String(bn_ids[0])).is_equal("a")
	assert_str(String(bn_ids[1])).is_equal("b")
	assert_int(int(cohort.get("hulls_by_type", {}).get("LHA", 0))).is_equal(2)

	# carriers_sent_by_type non-empty
	assert_int(int(result["carriers_sent_by_type"].get("LHA", 0))).is_equal(2)

	# sent_by_type includes carriers + escort screen
	assert_int(int(result["sent_by_type"].get("LHA", 0))).is_equal(2)
	assert_int(int(result["sent_by_type"].get("DDG", 0))).is_equal(5)

	# No pipeline activity
	assert_bool(result["returned_by_type"].is_empty()).is_true()


# --- test 2: embark cap -------------------------------------------------------------------------

func test_embark_cap_leaves_leftover_bns_in_mainland_pool() -> void:
	var defs := _ship_defs()
	var state := SealiftState.new()
	state.mainland_pool = [_reserve_entry("BdeA", [_bn("a"), _bn("b"), _bn("c"), _bn("d"), _bn("e")])]
	var ready := {"LHA": 3}  # 3 hulls * 1.0 capacity = 3 BNs max

	var result := SealiftResolver.resolve(state, [], ready, defs)

	# Cohort holds exactly 3 BNs (all capacity consumed)
	assert_int(state.cohorts.size()).is_equal(1)
	var bn_ids: Array = state.cohorts[0].get("bn_ids", [])
	assert_int(bn_ids.size()).is_equal(3)
	assert_str(String(bn_ids[0])).is_equal("a")
	assert_str(String(bn_ids[1])).is_equal("b")
	assert_str(String(bn_ids[2])).is_equal("c")

	# Remainder stays in mainland_pool
	assert_int(state.mainland_pool.size()).is_equal(1)
	var remaining: Array = state.mainland_pool[0].get("bns", [])
	assert_int(remaining.size()).is_equal(2)


# --- test 3: priority ---------------------------------------------------------------------------

func test_priority_departed_brigade_embarks_first() -> void:
	var defs := _ship_defs()
	var state := SealiftState.new()
	# BdeA already has an at-sea entry; BdeB is new
	var reserve := [_reserve_entry("BdeA", [_bn("a1")])]
	state.mainland_pool = [
		_reserve_entry("BdeA", [_bn("a2"), _bn("a3")]),
		_reserve_entry("BdeB", [_bn("b1"), _bn("b2")]),
	]
	var ready := {"LHA": 2}  # capacity for 2 BNs total

	var result := SealiftResolver.resolve(state, reserve, ready, defs)

	# 2 cohorts: a1 (adopted orphan), a2 (embarked — A had priority over B)
	assert_int(state.cohorts.size()).is_equal(2)
	var all_ids: Array = []
	for cohort in state.cohorts:
		all_ids.append_array(cohort.get("bn_ids", []))
	assert_int(all_ids.size()).is_equal(2)
	assert_str(String(all_ids[0])).is_equal("a1")
	assert_str(String(all_ids[1])).is_equal("a2")

	# BdeB's BNs never left mainland_pool; BdeA's a3 stays too (capacity exhausted)
	assert_int(state.mainland_pool.size()).is_equal(2)


# --- test 4: drain_bn_ids full ------------------------------------------------------------------

func test_drain_bn_ids_full_removes_cohort_and_populates_pipeline() -> void:
	var state := SealiftState.new()
	state.cohorts = [{
		"hulls_by_type": {"LHA": 2},
		"bn_ids": ["a", "b"],
		"state": SealiftState.STATE_SENT,
	}]

	SealiftResolver.drain_bn_ids(state, ["a", "b"], 3)

	assert_bool(state.cohorts.is_empty()).is_true()
	assert_bool(state.return_pipeline.has("LHA")).is_true()
	var slots: Array = state.return_pipeline["LHA"]
	assert_int(slots.size()).is_equal(1)
	var slot: Dictionary = slots[0]
	assert_int(int(slot["count"])).is_equal(2)
	assert_int(int(slot["turns_remaining"])).is_equal(3)


func test_drain_bn_ids_full_zero_return_time_skips_pipeline() -> void:
	var state := SealiftState.new()
	state.cohorts = [{
		"hulls_by_type": {"LHA": 2},
		"bn_ids": ["a", "b"],
		"state": SealiftState.STATE_SENT,
	}]

	SealiftResolver.drain_bn_ids(state, ["a", "b"], 0)

	# Cohort gone; pipeline untouched (hulls implicitly ready)
	assert_bool(state.cohorts.is_empty()).is_true()
	assert_bool(state.return_pipeline.is_empty()).is_true()


# --- test 5: drain_bn_ids partial --------------------------------------------------------------

func test_drain_bn_ids_partial_keeps_cohort() -> void:
	var state := SealiftState.new()
	state.cohorts = [{
		"hulls_by_type": {"LHA": 2},
		"bn_ids": ["a", "b", "c"],
		"state": SealiftState.STATE_SENT,
	}]

	SealiftResolver.drain_bn_ids(state, ["a"], 3)

	# Cohort stays with remaining BNs
	assert_int(state.cohorts.size()).is_equal(1)
	var remaining_ids: Array = state.cohorts[0].get("bn_ids", [])
	assert_int(remaining_ids.size()).is_equal(2)
	assert_str(String(remaining_ids[0])).is_equal("b")
	assert_str(String(remaining_ids[1])).is_equal("c")

	# Pipeline untouched (cohort not freed)
	assert_bool(state.return_pipeline.is_empty()).is_true()


# --- test 6: return tick ------------------------------------------------------------------------

func test_return_tick_releases_hulls_from_pipeline() -> void:
	var defs := _ship_defs()
	var state := SealiftState.new()
	state.return_pipeline = {"LHA": [{"count": 2, "turns_remaining": 1}]}

	var result := SealiftResolver.resolve(state, [], {}, defs)

	# Pipeline released to returned_by_type
	assert_int(int(result["returned_by_type"].get("LHA", 0))).is_equal(2)

	# Pipeline bucket emptied
	assert_bool(state.return_pipeline.is_empty()).is_true()


# --- test 7: escort magazine --------------------------------------------------------------------

func test_escort_magazine_consumption_and_reload() -> void:
	var defs := _ship_defs()
	var state := SealiftState.new()
	state.escort_sam = {"DDG": 10}
	state.escort_sam_max = {"DDG": 10}
	state.escort_sam_threshold = {"DDG": 4}

	# Fire 7 missiles -> 3 remain, trigger reload
	SealiftResolver.apply_escort_consumption(state, {"DDG": 7}, 4)
	assert_int(int(state.escort_sam["DDG"])).is_equal(3)
	assert_int(int(state.escort_reload["DDG"])).is_equal(4)

	# Tick 3 times — still reloading, SAM stays at 3
	for _i in range(3):
		SealiftResolver.resolve(state, [], {}, defs)
		assert_bool(state.escort_reload.has("DDG")).is_true()
		assert_int(int(state.escort_sam["DDG"])).is_equal(3)

	# 4th tick completes reload -> SAM refilled, reload entry removed
	SealiftResolver.resolve(state, [], {}, defs)
	assert_int(int(state.escort_sam["DDG"])).is_equal(10)
	assert_bool(state.escort_reload.has("DDG")).is_false()


# --- test 8: flip to offloading -----------------------------------------------------------------

func test_flip_sent_to_offloading() -> void:
	var state := SealiftState.new()
	state.cohorts = [{
		"hulls_by_type": {"LHA": 2},
		"bn_ids": ["a", "b"],
		"state": SealiftState.STATE_SENT,
	}]

	SealiftResolver.flip_sent_to_offloading(state)
	assert_str(String(state.cohorts[0].get("state", ""))).is_equal(SealiftState.STATE_OFFLOADING)


# --- test 9: empty resolve ---------------------------------------------------------------------

func test_empty_resolve_does_not_crash() -> void:
	var defs := _ship_defs()
	var state := SealiftState.new()

	var result := SealiftResolver.resolve(state, [], {}, defs)

	assert_bool(result["carriers_sent_by_type"].is_empty()).is_true()
	assert_bool(result["sent_by_type"].is_empty()).is_true()
	assert_bool(result["returned_by_type"].is_empty()).is_true()
	assert_bool(result["embarked_reserve_entries"].is_empty()).is_true()
	assert_bool(state.cohorts.is_empty()).is_true()


# --- plan 0006: per-BN ship_category stamping ------------------------------------------------------

func test_adopted_bns_stamped_with_carrier_category() -> void:
	var defs := _ship_defs()
	var state := SealiftState.new()
	var bns := [_bn("a"), _bn("b")]
	var reserve := [_reserve_entry("BdeA", bns)]
	var ready := {"LHA": 3, "DDG": 5}

	SealiftResolver.resolve(state, reserve, ready, defs)

	# Both orphans adopted onto LHA hulls (Military_Amphibious) — stamped in place.
	assert_str(String(bns[0].get("ship_category", ""))).is_equal("Military_Amphibious")
	assert_str(String(bns[1].get("ship_category", ""))).is_equal("Military_Amphibious")


func test_embarked_bns_stamped_with_carrier_category() -> void:
	var defs := _ship_defs()
	var state := SealiftState.new()
	state.mainland_pool = [_reserve_entry("BdeA", [_bn("a"), _bn("b")])]
	var ready := {"LPD": 2}

	var result := SealiftResolver.resolve(state, [], ready, defs)

	var entries: Array = result["embarked_reserve_entries"]
	assert_int(entries.size()).is_equal(1)
	for bn_value in (entries[0] as Dictionary).get("bns", []):
		assert_str(String((bn_value as Dictionary).get("ship_category", ""))).is_equal("Military_Amphibious")


func test_adopt_stamping_splits_across_carrier_types_in_fill_order() -> void:
	# Two carrier types with different categories; capacity forces a split. Fill order is
	# capacity desc (ties by ship_type), so RO-RO (cap 2.0) fills before LST (cap 1.0).
	var defs := {
		"RO-RO": _ship_def("RO-RO", "Civilian_Amphibious", 2.0),
		"LST": _ship_def("LST", "Military_Amphibious", 1.0),
	}
	var state := SealiftState.new()
	var bns := [_bn("a"), _bn("b"), _bn("c")]
	var reserve := [_reserve_entry("BdeA", bns)]
	var ready := {"RO-RO": 1, "LST": 5}

	SealiftResolver.resolve(state, reserve, ready, defs)

	assert_str(String(bns[0].get("ship_category", ""))).is_equal("Civilian_Amphibious")
	assert_str(String(bns[1].get("ship_category", ""))).is_equal("Civilian_Amphibious")
	assert_str(String(bns[2].get("ship_category", ""))).is_equal("Military_Amphibious")
