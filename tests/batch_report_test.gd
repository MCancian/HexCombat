extends GdUnitTestSuite

## BatchReport (research harness B3): aggregation + rendering over synthetic game records.
## Pure statics — no autoload/file involvement.


func _record(scenario: String, policy: String, seed_value: int, winner: String, turns: int, red: int, green: int) -> Dictionary:
	return {
		"commit": "abc123",
		"scenario_id": scenario,
		"policy_id": policy,
		"base_seed": seed_value,
		"turns_played": turns,
		"game_over": winner != "",
		"winner": winner,
		"census": {"red": red, "green": green},
		"turn_digests": [{
			"combat_summaries": [{"attacker_losses": 2, "defender_losses": 1}],
			"antiship_summary": {"destroyed_by_ship_type": {"LST": 3}, "bns_lost_at_sea": 1},
		}],
	}


func test_aggregate_groups_by_condition_and_counts_wins() -> void:
	var records := [
		_record("a", "p", 1, "red", 3, 20, 16),
		_record("a", "p", 2, "green", 5, 0, 17),
		_record("a", "p", 3, "", 30, 10, 10),
		_record("b", "p", 1, "red", 4, 22, 12),
	]
	var conditions := BatchReport.aggregate(records)

	assert_int(conditions.size()).is_equal(2)
	var a: Dictionary = conditions["a|p"]
	assert_int(int(a["n"])).is_equal(3)
	assert_int(int(a["red_wins"])).is_equal(1)
	assert_int(int(a["green_wins"])).is_equal(1)
	assert_int(int(a["undecided"])).is_equal(1)
	assert_array(a["census_margin"]).contains_exactly([4, -17, 0])


func test_aggregate_sums_losses_from_digests() -> void:
	var conditions := BatchReport.aggregate([_record("a", "p", 1, "red", 3, 20, 16)])
	var a: Dictionary = conditions["a|p"]
	assert_array(a["red_bn_combat_losses"]).contains_exactly([2])
	assert_array(a["green_bn_combat_losses"]).contains_exactly([1])
	assert_array(a["ships_destroyed"]).contains_exactly([3])
	assert_array(a["bns_lost_at_sea"]).contains_exactly([1])


func test_median_and_mean() -> void:
	assert_float(BatchReport.median([3, 1, 2])).is_equal_approx(2.0, 0.0001)
	assert_float(BatchReport.median([4, 1, 2, 3])).is_equal_approx(2.5, 0.0001)
	assert_float(BatchReport.median([])).is_equal_approx(0.0, 0.0001)
	assert_float(BatchReport.mean([1, 2, 6])).is_equal_approx(3.0, 0.0001)


func test_render_markdown_contains_condition_rows_and_warnings() -> void:
	var records := [
		_record("a", "p", 1, "red", 3, 20, 16),
		_record("b", "p", 1, "green", 5, 0, 17),
	]
	var report := BatchReport.render_markdown(BatchReport.aggregate(records), {
		"batch_name": "unit_test", "turns": 30, "games_total": 2, "dirty": true, "created_utc": "T",
	})
	assert_str(report).contains("# Batch report — unit_test")
	assert_str(report).contains("| a | p | 1 | 1 (100%) |")
	assert_str(report).contains("| b | p | 1 | 0 (0%) | 1 (100%) |")
	assert_str(report).contains("dirty working tree")
	assert_str(report).contains("## Losses by condition")
