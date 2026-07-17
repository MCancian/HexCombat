extends GdUnitTestSuite

## Covers CombatResolver.resolve_at's defender_terrain_modifier plumbing (Track F golden
## re-baseline 2026-07-09): the dormant CombatCalculator parameter is now fed from
## GameState._defender_combat_modifier via GameData.get_terrain, instead of a hardcoded 1.0.
## Calls CombatResolver.resolve_at directly (pure core, no GameState/GameData involved) with a
## fixed 20-vs-5 Tank Battalion mismatch so integer-rounded loss counts move in opposite,
## unambiguous directions as the modifier climbs: attacker losses step 1 -> 2 -> 3 while defender
## losses step 3 -> 2 -> 1, and FEBA advance shrinks toward zero (worked by hand from
## CombatCalculator.resolve_map_attack's loss-rate/feba formulas at neutral rolls of 50).

const HEX_ID := "hex_43_16"
const FEBA_BASE_KM := 2.0
const RED_SUPPLY_POOL := 100.0  # positive pool: full supply effectiveness, out-of-supply rate is moot
const RED_OUT_OF_SUPPLY_EFFECTIVENESS := 0.5


func test_modifier_1_0_no_terrain_bonus() -> void:
	var outcome := _resolve(1.0, [50, 50, 50], [0, 0, 1, 2])
	var result: CombatResult = outcome["result"]
	assert_float(result.defender_terrain_modifier).is_equal_approx(1.0, 0.0001)
	assert_int(result.attacker_losses).is_equal(1)
	assert_int(result.defender_losses).is_equal(3)
	assert_float(result.feba_movement_km).is_greater(2.0)  # strong, unmitigated attacker advance


func test_modifier_2_0_urban_defender_bonus() -> void:
	var outcome := _resolve(2.0, [50, 50, 50], [0, 1, 0, 1])
	var result: CombatResult = outcome["result"]
	assert_float(result.defender_terrain_modifier).is_equal_approx(2.0, 0.0001)
	assert_int(result.attacker_losses).is_equal(2)
	assert_int(result.defender_losses).is_equal(2)
	assert_float(result.feba_movement_km).is_greater(0.0)
	assert_float(result.feba_movement_km).is_less(2.0)  # attacker advance shrinks vs. modifier 1.0


func test_modifier_3_0_metropolis_defender_bonus() -> void:
	var outcome := _resolve(3.0, [50, 50, 50], [0, 1, 2, 0])
	var result: CombatResult = outcome["result"]
	assert_float(result.defender_terrain_modifier).is_equal_approx(3.0, 0.0001)
	assert_int(result.attacker_losses).is_equal(3)
	assert_int(result.defender_losses).is_equal(1)
	assert_float(result.feba_movement_km).is_greater(0.0)
	assert_float(result.feba_movement_km).is_less(1.0)  # weakest attacker advance of the three


func _resolve(defender_terrain_modifier: float, rolls: Array, weighted: Array) -> Dictionary:
	var attacker := _make_brigade("TEST-ATTACKER", Brigade.Team.RED, "Tank Battalion", 20)
	var defender := _make_brigade("TEST-DEFENDER", Brigade.Team.GREEN, "Tank Battalion", 5)
	var dice := ScriptedDice.new(rolls, [], [], weighted)
	var rules := CombatRules.new()
	rules.feba_base_km = FEBA_BASE_KM
	rules.red_supply_pool = RED_SUPPLY_POOL
	rules.red_out_of_supply_effectiveness = RED_OUT_OF_SUPPLY_EFFECTIVENESS
	rules.defender_terrain_modifier = defender_terrain_modifier
	
	return CombatResolver.resolve_at(
		HEX_ID,
		[attacker],
		[defender],
		dice,
		rules
	)


func _make_brigade(brigade_id: String, team: Brigade.Team, battalion_type: String, qty: int) -> Brigade:
	var brigade := Brigade.new()
	brigade.id = brigade_id
	brigade.name = brigade_id
	brigade.team = team
	var battalion := Battalion.new()
	battalion.type = battalion_type
	battalion.qty = qty
	brigade.composition.append(battalion)
	return brigade
