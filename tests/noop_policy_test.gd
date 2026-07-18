## NoopPolicy (plan 0012): the empty-orders seat used by the canned calibration sweeps — must be
## registered in PolicyCatalog and always produce zero actions.
extends GdUnitTestSuite


func test_noop_policy_registered_and_produces_no_actions() -> void:
	var policy: Object = PolicyCatalog.create("noop")
	assert_object(policy).is_not_null()
	assert_int((policy.build_actions({}) as Array).size()).is_equal(0)
	assert_bool("noop" in PolicyCatalog.known_ids()).is_true()
