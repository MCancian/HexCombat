## Verifies the Red DOS supply pool degrades Red ground-combat effectiveness when exhausted
## (PLAN.md Decisions 2026-06-29 supply→combat). The pool→per-unit mapping lives in
## GameState._inject_supply_effectiveness; CombatCalculator already multiplies maneuver strength by it.
extends GdUnitTestSuite


func before_test() -> void:
	GameData.load_all()
	GameState.reset_to_scenario()


func after_test() -> void:
	GameData.load_all()
	GameState.reset_to_scenario()


func _red_units() -> Array:
	return [
		{"brigade_id": "X", "type": "Combined Arms Battalion", "supply_effectiveness": 1.0},
		{"brigade_id": "X", "type": "Amphibious Infantry Battalion", "supply_effectiveness": 1.0},
	]


func test_red_full_effectiveness_when_pool_positive() -> void:
	var units := _red_units()
	GameState.supply_state.current_dos_tons = 1000.0
	GameState._inject_supply_effectiveness(units, Brigade.Team.RED)
	for unit in units:
		assert_float(float(unit["supply_effectiveness"])).is_equal_approx(1.0, 1e-6)


func test_red_degraded_when_pool_exhausted() -> void:
	var units := _red_units()
	GameState.supply_state.current_dos_tons = 0.0
	GameState._inject_supply_effectiveness(units, Brigade.Team.RED)
	for unit in units:
		assert_float(float(unit["supply_effectiveness"])).is_equal_approx(GameData.red_out_of_supply_effectiveness, 1e-6)


func test_green_unaffected_by_red_pool() -> void:
	var units := [{"brigade_id": "G", "type": "Armor Battalion", "supply_effectiveness": 1.0}]
	GameState.supply_state.current_dos_tons = 0.0
	GameState._inject_supply_effectiveness(units, Brigade.Team.GREEN)
	assert_float(float(units[0]["supply_effectiveness"])).is_equal_approx(1.0, 1e-6)


func test_exhausted_supply_lowers_attacker_strength() -> void:
	# Integration: the same Red force resolves to a lower attacker_strength when out of supply.
	var dice := SeededDice.new(20260624)
	var full := _red_units()
	for unit in full:
		unit["supply_effectiveness"] = 1.0
	var defenders := [{"type": "Amphibious Infantry Battalion"}]
	var res_full: CombatResult = CombatCalculator.resolve_map_attack(dice, full, defenders)

	var degraded := _red_units()
	for unit in degraded:
		unit["supply_effectiveness"] = GameData.red_out_of_supply_effectiveness
	var dice2 := SeededDice.new(20260624)
	var res_degraded: CombatResult = CombatCalculator.resolve_map_attack(dice2, degraded, defenders)

	assert_float(res_degraded.attacker_maneuver_strength).is_less(res_full.attacker_maneuver_strength)
	assert_float(res_degraded.attacker_maneuver_strength).is_equal_approx(
		res_full.attacker_maneuver_strength * GameData.red_out_of_supply_effectiveness, 1e-4)
