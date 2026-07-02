extends GdUnitTestSuite

## GameNarrative (research harness B4): rendering over a synthetic game record. Pure statics.


func _record() -> Dictionary:
	return {
		"commit": "abc123",
		"scenario_id": "test_scn",
		"scenario_name": "Test Scenario",
		"policy_id": "p",
		"base_seed": 7,
		"turns_requested": 5,
		"game_over": true,
		"winner": "red",
		"victory_reason": "china_landed_majority",
		"census": {"red": 20, "green": 16},
		"turn_digests": [{
			"turn_number": 1,
			"events": [
				{"kind": "ijfs", "team": "Red", "data": {
					"attacks": {"executed": 10, "skipped": 2},
					"destroyed_targets_by_category": {"Mobile SAMs": 3},
					"taiwan_ad_health_before": {"effective_ad_health": 0.5},
					"taiwan_ad_health_after": {"effective_ad_health": 0.25},
				}},
				{"kind": "antiship", "team": "Green", "data": {
					"sent_by_type": {"LST": 4, "Frigate": 2},
					"destroyed_by_ship_type": {"LST": 1},
					"bns_lost_at_sea": 2,
					"systems_fired_count": 9,
					"target_beaches": [1, 2],
				}},
				{"kind": "move", "team": "Green", "data": {"brigade_id": "BDE-66", "target_hex": "hex_1_1"}},
				{"kind": "combat", "hex_id": "hex_2_2", "data": {
					"hex_id": "hex_2_2",
					"attacker_brigade_ids": ["PLA-71"], "defender_brigade_ids": ["BDE-66"],
					"attacker_losses": 1, "defender_losses": 2,
					"feba_movement_km": -0.96, "owner_after": "contested",
				}},
				{"kind": "cleanup", "data": {
					"china_battalions_on_taiwan": 20, "taiwan_battalions_on_taiwan": 16,
					"game_over": true, "winner": "red", "victory_reason": "china_landed_majority",
				}},
			],
		}],
	}


func test_render_produces_turn_sections_and_outcome() -> void:
	var text := GameNarrative.render(_record())
	assert_str(text).contains("# Game narrative — Test Scenario")
	assert_str(text).contains("## Turn 1")
	assert_str(text).contains("10 strike(s) executed (2 skipped), destroying 3 Mobile SAMs")
	assert_str(text).contains("degraded 50% → 25% effective")
	assert_str(text).contains("6 ship(s) sail")
	assert_str(text).contains("Green moves BDE-66 to hex_1_1")
	assert_str(text).contains("Ground combat at hex_2_2")
	assert_str(text).contains("Green pushes the FEBA 0.96 km back toward the beach")
	assert_str(text).contains("**Red wins** after 1 turn(s) (china_landed_majority)")


func test_render_undecided_game_states_cap() -> void:
	var record := _record()
	record["game_over"] = false
	record["winner"] = ""
	var text := GameNarrative.render(record)
	assert_str(text).contains("Undecided at the 5-turn cap")
