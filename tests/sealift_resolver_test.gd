extends GdUnitTestSuite

# SealiftResolver pure planner tests (plan 0004). Deterministic — no dice injected.
# Builds ShipDef and SealiftState fixtures locally; no GameData/autoload access.
#
# Scope after plan 0045: this suite covers PLANNING only — who is adopted, who embarks, in what order,
# and which carrier category stamps each battalion. The hull queues the resolver used to tick (return
# pipeline, escort magazines) moved to the fleet authority and are covered by
# tests/transitions/sealift_transitions_test.gd; hulls the pipeline released this turn arrive as the
# `returned_by_type` argument, which these tests pass as `{}` unless the case is about it.


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

	var result := SealiftResolver.resolve(state, reserve, ready, {}, defs)

	# Adopt plan from resolver — apply via ForceTransitions
	var adopt_plan: Dictionary = result.get("adopt_plan", {})
	assert_bool(adopt_plan.is_empty()).is_false()
	var adopt_receipt := ForceTransitions.apply_sent_cohort(
		state, adopt_plan["bn_ids"], adopt_plan["hulls_by_type"], reserve,
		adopt_plan["ship_categories"])
	assert_bool(adopt_receipt.success).is_true()

	# Exactly one sent cohort wrapping both BNs
	assert_int(state.cohorts.size()).is_equal(1)
	var cohort := state.cohorts[0] as SealiftCohort
	assert_str(cohort.cohort_state).is_equal(SealiftState.STATE_SENT)
	var bn_ids: Array = cohort.bn_ids
	assert_int(bn_ids.size()).is_equal(2)
	assert_str(String(bn_ids[0])).is_equal("a")
	assert_str(String(bn_ids[1])).is_equal("b")
	assert_int(int(cohort.hulls_by_type.get("LHA", 0))).is_equal(2)

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

	var reserve: Array = []
	var result := SealiftResolver.resolve(state, reserve, ready, {}, defs)

	# Apply embark via ForceTransitions
	var embark_request = result["embark_request"]
	assert_object(embark_request).is_not_null()
	var embark_receipts := ForceTransitions.apply_embark(state, embark_request, reserve)
	assert_bool(embark_receipts[0].success).is_true()

	# Cohort holds exactly 3 BNs (all capacity consumed)
	assert_int(state.cohorts.size()).is_equal(1)
	var bn_ids: Array = state.cohorts[0].bn_ids
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

	var result := SealiftResolver.resolve(state, reserve, ready, {}, defs)

	# Apply adopt plan (orphan a1)
	var adopt_plan: Dictionary = result.get("adopt_plan", {})
	assert_bool(adopt_plan.is_empty()).is_false()
	var adopt_receipt := ForceTransitions.apply_sent_cohort(
		state, adopt_plan["bn_ids"], adopt_plan["hulls_by_type"], reserve,
		adopt_plan["ship_categories"])
	assert_bool(adopt_receipt.success).is_true()

	# Apply embark (a2 — departed priority)
	var embark_request = result["embark_request"]
	assert_object(embark_request).is_not_null()
	var embark_receipts := ForceTransitions.apply_embark(state, embark_request, reserve)
	assert_bool(embark_receipts[0].success).is_true()

	# 2 cohorts: a1 (adopted orphan), a2 (embarked — A had priority over B)
	assert_int(state.cohorts.size()).is_equal(2)
	var all_ids: Array = []
	for cohort in state.cohorts:
		all_ids.append_array(cohort.bn_ids)
	assert_int(all_ids.size()).is_equal(2)
	assert_str(String(all_ids[0])).is_equal("a1")
	assert_str(String(all_ids[1])).is_equal("a2")

	# BdeB's BNs never left mainland_pool; BdeA's a3 stays too (capacity exhausted)
	assert_int(state.mainland_pool.size()).is_equal(2)


# --- test 4: empty resolve ---------------------------------------------------------------------

func test_empty_resolve_does_not_crash() -> void:
	var defs := _ship_defs()
	var state := SealiftState.new()

	var result := SealiftResolver.resolve(state, [], {}, {}, defs)

	assert_bool(result["carriers_sent_by_type"].is_empty()).is_true()
	assert_bool(result["sent_by_type"].is_empty()).is_true()
	assert_bool(result["returned_by_type"].is_empty()).is_true()
	assert_bool(result["embarked_reserve_entries"].is_empty()).is_true()
	assert_bool(state.cohorts.is_empty()).is_true()


# --- plan 0045: the planner writes nothing -------------------------------------------------------

## The whole contract in one test: a full plan over a live reserve AND a live mainland pool leaves both
## byte-identical. The resolver used to stamp `ship_category` straight into these rows, which made it a
## second writer of force-owned storage and could leave a category behind from an embark the authority
## then refused.
func test_resolve_leaves_the_reserve_and_the_mainland_pool_byte_identical() -> void:
	var defs := _ship_defs()
	var state := SealiftState.new()
	var reserve := [_reserve_entry("BdeA", [_bn("a1")])]
	state.mainland_pool = [
		_reserve_entry("BdeA", [_bn("a2"), _bn("a3")]),
		_reserve_entry("BdeB", [_bn("b1")]),
	]
	state.return_pipeline = {"LHA": [{"count": 1, "turns_remaining": 2}]}
	state.escort_sam = {"DDG": 5}
	var reserve_before := JSON.stringify(reserve)
	var pool_before := JSON.stringify(state.mainland_pool)
	var pipeline_before := JSON.stringify(state.return_pipeline)
	var magazine_before := JSON.stringify(state.escort_sam)

	SealiftResolver.resolve(state, reserve, {"LHA": 2, "DDG": 3}, {"LHA": 1}, defs)

	assert_str(JSON.stringify(reserve)).is_equal(reserve_before)
	assert_str(JSON.stringify(state.mainland_pool)).is_equal(pool_before)
	assert_str(JSON.stringify(state.return_pipeline)).is_equal(pipeline_before)
	assert_str(JSON.stringify(state.escort_sam)).is_equal(magazine_before)
	assert_bool(state.cohorts.is_empty()).is_true()


# --- plan 0006 / 0045: per-BN ship_category, planned here and applied by the force authority --------

## The planner REPORTS the lifting category per BN id; nothing is written into the reserve until
## ForceTransitions applies the plan. That is what keeps this file free of force-owned writes (plan 0045).
func test_adopt_plan_reports_the_lifting_category_without_touching_the_reserve() -> void:
	var defs := _ship_defs()
	var state := SealiftState.new()
	var bns := [_bn("a"), _bn("b")]
	var reserve := [_reserve_entry("BdeA", bns)]
	var ready := {"LHA": 3, "DDG": 5}

	var result := SealiftResolver.resolve(state, reserve, ready, {}, defs)

	var adopt_plan: Dictionary = result["adopt_plan"]
	var categories: Dictionary = adopt_plan["ship_categories"]
	assert_str(String(categories["a"])).is_equal("Military_Amphibious")
	assert_str(String(categories["b"])).is_equal("Military_Amphibious")
	assert_bool(bns[0].has("ship_category")).is_false()
	assert_bool(bns[1].has("ship_category")).is_false()

	ForceTransitions.apply_sent_cohort(
		state, adopt_plan["bn_ids"], adopt_plan["hulls_by_type"], reserve, categories)

	assert_str(String(bns[0].get("ship_category", ""))).is_equal("Military_Amphibious")
	assert_str(String(bns[1].get("ship_category", ""))).is_equal("Military_Amphibious")


func test_embarked_bns_stamped_with_carrier_category() -> void:
	var defs := _ship_defs()
	var state := SealiftState.new()
	var pool_bns := [_bn("a"), _bn("b")]
	state.mainland_pool = [_reserve_entry("BdeA", pool_bns)]
	var ready := {"LPD": 2}

	var reserve: Array = []
	var result := SealiftResolver.resolve(state, reserve, ready, {}, defs)

	# Planning alone leaves the pool rows alone.
	assert_bool(pool_bns[0].has("ship_category")).is_false()
	ForceTransitions.apply_embark(state, result["embark_request"], reserve)

	var entries: Array = result["embarked_reserve_entries"]
	assert_int(entries.size()).is_equal(1)
	for bn_value in (entries[0] as Dictionary).get("bns", []):
		assert_str(String((bn_value as Dictionary).get("ship_category", ""))).is_equal("Military_Amphibious")


## A refused embark must leave no category behind: the stamp is applied by the authority, after its
## preflight, not by the planner that computed it.
func test_a_refused_embark_leaves_no_category_stamp() -> void:
	var defs := _ship_defs()
	var state := SealiftState.new()
	var pool_bns := [_bn("a"), _bn("b")]
	state.mainland_pool = [_reserve_entry("BdeA", pool_bns)]
	var ready := {"LPD": 2}
	var reserve: Array = []
	var result := SealiftResolver.resolve(state, reserve, ready, {}, defs)
	var request: ForceEmbarkRequest = result["embark_request"]
	# Duplicate the batch ids so the preflight refuses the whole transaction.
	request.batch_bn_ids.append("a")

	await assert_error(func() -> void:
		ForceTransitions.apply_embark(state, request, reserve)
	).is_push_error("ForceTransitions: duplicate or empty BN id in embark batch: a")

	assert_bool(pool_bns[0].has("ship_category")).is_false()
	assert_bool(pool_bns[1].has("ship_category")).is_false()
	assert_array(reserve).is_empty()


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

	var result := SealiftResolver.resolve(state, reserve, ready, {}, defs)

	var categories: Dictionary = (result["adopt_plan"] as Dictionary)["ship_categories"]
	assert_str(String(categories["a"])).is_equal("Civilian_Amphibious")
	assert_str(String(categories["b"])).is_equal("Civilian_Amphibious")
	assert_str(String(categories["c"])).is_equal("Military_Amphibious")
