extends GdUnitTestSuite

const SPECIAL_FORCES := "Special Forces Battalion"
const FIELD_ARTILLERY := "Field Artillery Battalion"


func test_golden_formula_scenario_a() -> void:
	var dice := ScriptedDice.new([70, 23, 79], [], [], [0])
	var attacker_units := _make_units(SPECIAL_FORCES, 3, "A", "Red")
	var defender_units := _make_units(SPECIAL_FORCES, 2, "D", "Blue")

	var result := CombatCalculator.resolve_map_attack(dice, attacker_units, defender_units, 2.0, {}, {}, 1.0)
	var detail: Dictionary = result.combat_detail
	var losses: Dictionary = detail["losses"]
	var rolls: Dictionary = detail["rolls"]

	assert_float(result.attacker_strength).is_equal_approx(5.4, 0.0001)
	assert_float(result.defender_strength).is_equal_approx(3.6, 0.0001)
	assert_float(result.attacker_maneuver_strength).is_equal_approx(5.4, 0.0001)
	assert_float(result.defender_maneuver_strength).is_equal_approx(3.6, 0.0001)
	assert_float(result.force_ratio).is_equal_approx(1.5, 0.0001)
	assert_float(result.unmodified_force_ratio).is_equal_approx(1.5, 0.0001)
	assert_float(losses["attacker_loss_rate"]).is_equal_approx(0.18, 0.0001)
	assert_float(losses["defender_loss_rate"]).is_equal_approx(0.223, 0.0001)
	assert_int(result.attacker_losses).is_equal(1)
	assert_int(result.defender_losses).is_equal(0)
	assert_float(result.feba_movement_km).is_equal_approx(0.916, 0.0001)
	assert_str(detail["result"]).is_equal("Attacker Advantage")
	assert_int(rolls["attacker_loss_roll"]).is_equal(70)
	assert_int(rolls["defender_loss_roll"]).is_equal(23)
	assert_int(rolls["feba_movement_roll"]).is_equal(79)


func test_artillery_never_a_casualty_scenario_b() -> void:
	var dice := ScriptedDice.new([70, 23, 79], [], [], [0])
	var attacker_units := _make_units(SPECIAL_FORCES, 8, "A", "Red")
	var defender_units := [
		{"unit_id": "D-SF", "type": SPECIAL_FORCES, "team": "Blue"},
		{"unit_id": "D-ARTY", "type": FIELD_ARTILLERY, "team": "Blue"}
	]

	var result := CombatCalculator.resolve_map_attack(dice, attacker_units, defender_units, 2.0, {}, {}, 1.0)

	assert_int(result.defender_losses).is_equal(1)
	assert_int(result.attacker_losses).is_equal(0)
	assert_int(result.defender_casualties.size()).is_equal(1)
	assert_str(result.defender_casualties[0]["unit_id"]).is_equal("D-SF")

	var artillery_casualties := 0
	for casualty in result.defender_casualties:
		if casualty["type"] == FIELD_ARTILLERY:
			artillery_casualties += 1
	assert_int(artillery_casualties).is_equal(0)


func _make_units(unit_type: String, count: int, prefix: String, team: String) -> Array:
	var units := []
	for i in range(count):
		units.append({"unit_id": "%s%d" % [prefix, i], "type": unit_type, "team": team})
	return units
