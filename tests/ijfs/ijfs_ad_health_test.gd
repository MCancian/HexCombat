extends GdUnitTestSuite

# Mirrors ijfs_standalone ad_health.py: per-category alive&unsuppressed fraction,
# SAM x radar coupled effective health.


func _target(id: String, category: String, destroyed: bool = false, suppressed: bool = false) -> IjfsTarget:
	var t := IjfsTarget.new()
	t.target_id = id
	t.category = category
	t.destroyed = destroyed
	t.suppressed = suppressed
	return t


func _scenario(weights: Dictionary) -> Dictionary:
	return {"taiwan_air_defense_health": {"surviving_unsuppressed_weighted_categories": weights}}


func test_category_and_coupled_health() -> void:
	var targets: Array[IjfsTarget] = [
		_target("ssam_alive", "Static SAMs"),
		_target("ssam_dead", "Static SAMs", true),
		_target("msam_alive", "Moveable SAMs"),
		_target("radar_alive", "Static Radars"),
	]
	var scenario := _scenario({
		"Moveable SAMs": 1.0,
		"Static SAMs": 1.0,
		"Static Radars": 1.0,
		"Mobile Radars": 0.0,
	})
	var health := IjfsAdHealth.compute_taiwan_ad_health(targets, scenario)
	# Static SAMs: 1 of 2 alive -> 0.5; Moveable SAMs: 1.0; Static Radars: 1.0
	assert_float(health["category_health"]["Static SAMs"]).is_equal_approx(0.5, 0.000001)
	# raw_sam_health = (1.0*1.0 + 0.5*1.0) / 2.0 = 0.75 (Mobile SAMs weight 0)
	assert_float(health["raw_sam_health"]).is_equal_approx(0.75, 0.000001)
	assert_float(health["radar_health"]).is_equal_approx(1.0, 0.000001)
	assert_float(health["effective_sam_health"]).is_equal_approx(0.75, 0.000001)
	assert_float(health["sam_weight_total"]).is_equal_approx(2.0, 0.000001)
	assert_float(health["radar_weight_total"]).is_equal_approx(1.0, 0.000001)
	# clamp(2.0*0.75 + 1.0*1.0) = clamp(2.5) = 1.0
	assert_float(health["effective_ad_health"]).is_equal_approx(1.0, 0.000001)


func test_suppressed_counts_as_unhealthy() -> void:
	var targets: Array[IjfsTarget] = [
		_target("a", "Static SAMs"),
		_target("b", "Static SAMs", false, true),
	]
	var scenario := _scenario({"Static SAMs": 1.0, "Static Radars": 1.0})
	var health := IjfsAdHealth.compute_taiwan_ad_health(targets, scenario)
	assert_float(health["category_health"]["Static SAMs"]).is_equal_approx(0.5, 0.000001)


func test_zero_total_weight_yields_unit_weighted_average() -> void:
	var targets: Array[IjfsTarget] = [_target("a", "Static SAMs", true)]
	var health := IjfsAdHealth.compute_taiwan_ad_health(targets, _scenario({}))
	# _weighted_average returns 1.0 when total weight <= 0
	assert_float(health["raw_sam_health"]).is_equal_approx(1.0, 0.000001)
	assert_float(health["radar_health"]).is_equal_approx(1.0, 0.000001)
	# both weight totals 0 -> effective_ad_health = clamp(0) = 0.0
	assert_float(health["effective_ad_health"]).is_equal_approx(0.0, 0.000001)
