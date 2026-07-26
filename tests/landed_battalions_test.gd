## Only battalions ASHORE fight and eat (plan 0037, USER call 2026-07-25).
##
## A brigade's `hex_id` is set the moment its FIRST battalion lands, but `composition` stays the full
## roster — the rest may still be at sea, on the mainland waiting for a hull, or waiting to fly. These
## cases pin the rule at every seam that reads it: the landed-qty arithmetic on Brigade, the force
## expansion in CombatForces, the presence test that keeps an empty brigade out of the fight, and the
## agreement between what a brigade fights with and what it is billed for in supply.
extends GdUnitTestSuite


func _battalion(type: String, qty: int) -> Battalion:
	var battalion := Battalion.new()
	battalion.type = type
	battalion.qty = qty
	return battalion


## Four maneuver BNs + two Field Artillery BNs, i.e. the shape an amphibious brigade lands in.
func _brigade(id: String) -> Brigade:
	var brigade := Brigade.new()
	brigade.id = id
	brigade.composition = [
		_battalion("Amphibious Infantry Battalion", 4),
		_battalion("Field Artillery Battalion", 2),
	]
	return brigade


func test_landed_qty_subtracts_by_type() -> void:
	var brigade := _brigade("R1")
	var not_ashore := {"Amphibious Infantry Battalion": 3}
	assert_int(Brigade.landed_qty(brigade.composition[0], not_ashore)).is_equal(1)
	# A type absent from the map is fully ashore — the map lists only what is missing.
	assert_int(Brigade.landed_qty(brigade.composition[1], not_ashore)).is_equal(2)


func test_landed_qty_clamps_at_zero() -> void:
	# The pools should never claim more than the roster holds (TurnConductor.pending_pool_roster_
	# violations is the tripwire for that), but if they ever do, the subtraction must not go negative
	# and hand a side imaginary strength via a negative unit count.
	var brigade := _brigade("R1")
	assert_int(Brigade.landed_qty(brigade.composition[0], {"Amphibious Infantry Battalion": 9})).is_equal(0)


func test_half_landed_brigade_fields_half_its_maneuver_units() -> void:
	var brigade := _brigade("R1")
	var not_ashore := {"R1": {"Amphibious Infantry Battalion": 2}}
	assert_int(CombatForces.maneuver_units([brigade], not_ashore).size()).is_equal(2)
	# Fully ashore is the pre-0037 behaviour exactly.
	assert_int(CombatForces.maneuver_units([brigade], {}).size()).is_equal(4)


func test_support_units_and_counts_subtract_by_type() -> void:
	var brigade := _brigade("R1")
	var not_ashore := {"R1": {"Field Artillery Battalion": 1}}
	assert_int(CombatForces.support_units([brigade], not_ashore).size()).is_equal(1)
	assert_int(int(CombatForces.support_counts([brigade], not_ashore)["artillery"])).is_equal(1)
	# The maneuver side is untouched by a support-type absence.
	assert_int(CombatForces.maneuver_units([brigade], not_ashore).size()).is_equal(4)


func test_not_ashore_map_of_another_brigade_does_not_leak() -> void:
	var brigade := _brigade("R1")
	var not_ashore := {"R2": {"Amphibious Infantry Battalion": 4}}
	assert_int(CombatForces.maneuver_units([brigade], not_ashore).size()).is_equal(4)


func test_brigade_with_nothing_ashore_is_not_present() -> void:
	var brigade := _brigade("R1")
	var all_at_sea := {"Amphibious Infantry Battalion": 4, "Field Artillery Battalion": 2}
	assert_int(brigade.landed_battalion_count(all_at_sea)).is_equal(0)
	assert_int(brigade.landed_battalion_count({})).is_equal(6)
	# One BN ashore is enough to be a contributor — presence is not "fully landed".
	assert_int(brigade.landed_battalion_count({"Amphibious Infantry Battalion": 4, "Field Artillery Battalion": 1})).is_equal(1)


func test_all_maneuver_at_sea_leaves_support_unscreened() -> void:
	# The support-only path is reachable through the landed subtraction, not just by handing
	# CombatCalculator an empty maneuver array directly: a brigade whose infantry is still at sea but
	# whose artillery has landed fights unscreened, at unscreened_support_strength.
	var brigade := _brigade("R1")
	var not_ashore := {"R1": {"Amphibious Infantry Battalion": 4}}
	var attacker_units := CombatForces.maneuver_units([brigade], not_ashore)
	var attacker_support_units := CombatForces.support_units([brigade], not_ashore)
	assert_array(attacker_units).is_empty()
	assert_int(attacker_support_units.size()).is_equal(2)

	var defender_units := [{"brigade_id": "G", "type": "Tank Battalion", "supply_effectiveness": 1.0}]
	var dice := ScriptedDice.new([50, 50, 50], [], [], [0, 0])
	var result := CombatCalculator.resolve_map_attack(
		dice,
		attacker_units,
		defender_units,
		CombatForces.support_counts([brigade], not_ashore),
		{},
		attacker_support_units,
		[],
		CombatRules.new()
	)
	assert_bool(result.combat_detail["attacker"]["unscreened"]).is_true()


func test_combat_and_supply_see_the_same_battalions() -> void:
	# Parity is the point of routing both through Brigade.landed_qty: fighting strength and the ration
	# bill must always describe the same battalions, or a brigade eats for troops it cannot field.
	var brigade := _brigade("R1")
	var brigade_not_ashore := {"Amphibious Infantry Battalion": 3, "Field Artillery Battalion": 1}
	var not_ashore := {"R1": brigade_not_ashore}
	var combat_count := (
		CombatForces.maneuver_units([brigade], not_ashore).size()
		+ CombatForces.support_units([brigade], not_ashore).size()
	)
	assert_int(combat_count).is_equal(brigade.landed_battalion_count(brigade_not_ashore))
	assert_int(combat_count).is_equal(2)


func test_pending_battalions_by_type_matches_its_own_total() -> void:
	var pools := [
		[{"brigade_id": "R1", "bns": [
			{"id": "R1-1", "type": "Amphibious Infantry Battalion"},
			{"id": "R1-2", "type": "Amphibious Infantry Battalion"},
		]}],
		[{"brigade_id": "R1", "bns": [{"id": "R1-5", "type": "Field Artillery Battalion"}]}],
	]
	var by_type := PendingBattalions.by_brigade_and_type(pools)
	assert_int(int(by_type["R1"]["Amphibious Infantry Battalion"])).is_equal(2)
	assert_int(int(by_type["R1"]["Field Artillery Battalion"])).is_equal(1)
	# by_brigade is derived from by_brigade_and_type, so the census and combat cannot disagree.
	assert_int(int(PendingBattalions.by_brigade(pools)["R1"])).is_equal(3)


# --- Integration: the two paths that make the rule load-bearing ------------------------------------
#
# The pure cases above prove the arithmetic. These two prove the arithmetic is actually WIRED: that a
# brigade with nothing ashore is dropped from the fight, and that the tripwire for the mirror-image
# bug actually fires. Both need the autoloads, so they register brigades into GameData the way
# tests/composition_test.gd does and reset the fixture around themselves.


func _register(brigade: Brigade) -> void:
	GameData.brigades[brigade.id] = brigade
	GameData.set_brigade_hex(brigade.id, brigade.hex_id)


func _reset_fixture() -> void:
	GameData.load_all()
	GameState.reset_to_scenario()


func test_brigade_with_nothing_ashore_is_dropped_from_combat_contributors() -> void:
	_reset_fixture()
	var ashore := _brigade("TEST-RED-ASHORE")
	ashore.team = Brigade.Team.RED
	ashore.hex_id = TestHexes.TARGET_HEX
	var all_at_sea := _brigade("TEST-RED-AT-SEA")
	all_at_sea.team = Brigade.Team.RED
	all_at_sea.hex_id = TestHexes.TARGET_HEX
	_register(ashore)
	_register(all_at_sea)

	# Everything of TEST-RED-AT-SEA is still in a pool; TEST-RED-ASHORE has landed in full.
	GameState.data.not_ashore_by_type = {
		"TEST-RED-AT-SEA": {"Amphibious Infantry Battalion": 4, "Field Artillery Battalion": 2},
	}
	var contributor_ids := CombatResolver.brigade_ids(
		TurnConductor.combat_contributors_for(GameState.data, Brigade.Team.RED, TestHexes.TARGET_HEX))
	assert_array(contributor_ids).contains(["TEST-RED-ASHORE"])
	# The blocker plan 0037 named: an empty contributor would still reach CombatCalculator, whose
	# combat_min_effective_strength floor lets a zero-strength side fight and inflict real casualties.
	assert_array(contributor_ids).not_contains(["TEST-RED-AT-SEA"])
	_reset_fixture()


func test_pending_pool_roster_violations_catches_a_desync() -> void:
	_reset_fixture()
	var brigade := _brigade("TEST-RED-DESYNC")
	brigade.team = Brigade.Team.RED
	brigade.hex_id = TestHexes.TARGET_HEX
	_register(brigade)

	# A consistent pool claims no more than the roster holds — no violation.
	GameState.data.ship_reserve = [{
		"brigade_id": "TEST-RED-DESYNC",
		"bns": [{"id": "d1", "type": "Amphibious Infantry Battalion"}],
	}]
	assert_array(TurnConductor.pending_pool_roster_violations(GameState.data)).is_empty()

	# Now claim more Field Artillery at sea than the brigade owns: the mirror-image of the
	# ghost-landing bug, where something killed a battalion that was never ashore.
	GameState.data.ship_reserve = [{
		"brigade_id": "TEST-RED-DESYNC",
		"bns": [
			{"id": "d1", "type": "Field Artillery Battalion"},
			{"id": "d2", "type": "Field Artillery Battalion"},
			{"id": "d3", "type": "Field Artillery Battalion"},
		],
	}]
	var violations := TurnConductor.pending_pool_roster_violations(GameState.data)
	assert_int(violations.size()).is_equal(1)
	assert_str(violations[0]).contains("TEST-RED-DESYNC")
	_reset_fixture()
