extends GdUnitTestSuite

# Isolation tests for IjfsResolver

func test_ijfs_resolver_compute_writeback_aggregates_ledgers() -> void:
	var state := IjfsDailyState.new()
	var target1 := IjfsTarget.new()
	target1.category = "Anti-Ship Systems"
	target1.destroyed = true
	target1.metadata = {"to_number": 1, "type_id": 100, "systems_represented": 2}
	
	var target2 := IjfsTarget.new()
	target2.category = "Anti-Ship Systems"
	target2.suppressed = true
	target2.metadata = {"to_number": 1, "type_id": 101, "systems_represented": 1}
	
	state.targets = [target1, target2]
	
	var ledgers := {
		"strike_log": [
			{
				"attack_executed": true,
				"category": "Maneuver Units",
				"destroyed": true,
				"metadata": {
					"battalion_id": "bde1-MU-1",
					"brigade_id": "bde1",
					"to_number": 1,
					"unit_type": "Infantry Battalion"
				}
			}
		],
		"engagement_log": [
			{"destroyed": true},
			{"suppressed": true},
			{"suppressed": true}
		]
	}
	
	var writeback := IjfsResolver.compute_writeback(state, ledgers, ledgers["strike_log"])
	
	var key1 = AntishipCalculator.encode_key(1, 100)
	var key2 = AntishipCalculator.encode_key(1, 101)
	assert_int(writeback.antiship_destroyed_by_type.get(key1, 0)).is_equal(2)
	assert_int(writeback.antiship_suppressed_by_type.get(key2, 0)).is_equal(1)
	
	assert_int(writeback.maneuver_casualties.size()).is_equal(1)
	assert_str(writeback.maneuver_casualties[0]["battalion_id"]).is_equal("bde1-MU-1")
	
	assert_int(writeback.sam_destroyed).is_equal(1)
	assert_int(writeback.sam_suppressed).is_equal(2)


# Regression (plan 0009 follow-up): maneuver casualties come from the ACCUMULATED multi-day strike
# log, not the final day's `ledgers`. Here the final ledgers carry zero maneuver kills (as a late
# warmup day would) yet the accumulated log holds two earlier-day kills — both must reach the OOB.
func test_compute_writeback_maneuver_reads_accumulated_log_not_final_ledgers() -> void:
	var state := IjfsDailyState.new()
	state.targets = []
	var ledgers := {"strike_log": [], "engagement_log": []}
	var accumulated := [
		{"attack_executed": true, "category": "Maneuver Units", "destroyed": true,
			"metadata": {"battalion_id": "bde1-MU-1", "brigade_id": "bde1"}},
		{"attack_executed": true, "category": "Maneuver Units", "destroyed": true,
			"metadata": {"battalion_id": "bde1-MU-2", "brigade_id": "bde1"}},
	]
	var writeback := IjfsResolver.compute_writeback(state, ledgers, accumulated)
	assert_int(writeback.maneuver_casualties.size()).is_equal(2)
