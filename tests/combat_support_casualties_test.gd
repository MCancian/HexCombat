extends GdUnitTestSuite

func test_maneuver_less_attacker_gets_unscreened_strength_and_takes_losses() -> void:
	var attacker_units := []
	var attacker_support_units := [
		{"brigade_id": "A", "type": "Field Artillery Battalion", "supply_effectiveness": 1.0},
		{"brigade_id": "A", "type": "Field Artillery Battalion", "supply_effectiveness": 1.0},
		{"brigade_id": "A", "type": "Field Artillery Battalion", "supply_effectiveness": 1.0},
		{"brigade_id": "A", "type": "Field Artillery Battalion", "supply_effectiveness": 1.0}
	]
	var attacker_support := {"artillery": 4}
	
	var defender_units := [
		{"brigade_id": "D", "type": "Tank Battalion", "supply_effectiveness": 1.0},
		{"brigade_id": "D", "type": "Tank Battalion", "supply_effectiveness": 1.0}
	]
	
	var dice := ScriptedDice.new([50, 50, 50], [], [], [0, 0])
	
	var result := CombatCalculator.resolve_map_attack(
		dice,
		attacker_units,
		defender_units,
		0.0,
		attacker_support,
		{},
		1.0,
		attacker_support_units,
		[]
	)
	
	var detail: Dictionary = result.combat_detail
	var attacker: Dictionary = detail["attacker"]
	
	assert_bool(attacker["unscreened"]).is_true()
	assert_float(attacker["total_combat_power_unmodified"]).is_equal_approx(2.0, 0.0001)
	
	# Attacker takes at least 1 loss (minimum blood rule fires)
	assert_int(result.attacker_losses).is_greater(0)
	assert_int(result.attacker_casualties.size()).is_equal(result.attacker_losses)
	assert_str(result.attacker_casualties[0]["type"]).is_equal("Field Artillery Battalion")

func test_mixed_force_weights_and_selection() -> void:
	var attacker_units := [
		{"brigade_id": "A", "type": "Tank Battalion", "supply_effectiveness": 1.0},
		{"brigade_id": "A", "type": "Tank Battalion", "supply_effectiveness": 1.0}
	]
	var attacker_support_units := [
		{"brigade_id": "A", "type": "Field Artillery Battalion", "supply_effectiveness": 1.0}
	]
	var defender_units := [
		{"brigade_id": "D", "type": "Tank Battalion", "supply_effectiveness": 1.0}
	]
	
	# Weighted selection for mixed force: 
	# Maneuver weights are 4.0, support weight is 1.0
	# Pool is: [Tank1 (idx=0), Tank2 (idx=1), Arty (idx=2)]
	# Force it to choose the Arty (index 2). We set weighted choices to [2]
	var dice := ScriptedDice.new([], [], [], [2])
	
	var casualties := CombatCalculator._select_casualties(
		attacker_units,
		attacker_support_units,
		1,
		dice,
		4.0,
		1.0
	)
	
	assert_int(casualties.size()).is_equal(1)
	assert_str(casualties[0]["type"]).is_equal("Field Artillery Battalion")
	
func test_unscreened_strength_scales_with_supply_effectiveness() -> void:
	var attacker_units := []
	var attacker_support_units := [
		{"brigade_id": "A", "type": "Field Artillery Battalion", "supply_effectiveness": 0.5}
	]
	
	var defender_units := [
		{"brigade_id": "D", "type": "Tank Battalion", "supply_effectiveness": 1.0}
	]
	
	var dice := ScriptedDice.new([50, 50, 50], [], [], [0, 0])
	
	var result := CombatCalculator.resolve_map_attack(
		dice,
		attacker_units,
		defender_units,
		0.0,
		{"artillery": 1},
		{},
		1.0,
		attacker_support_units,
		[]
	)
	
	var detail: Dictionary = result.combat_detail
	var attacker: Dictionary = detail["attacker"]
	
	assert_bool(attacker["unscreened"]).is_true()
	assert_float(attacker["total_combat_power_unmodified"]).is_equal_approx(0.25, 0.0001)
