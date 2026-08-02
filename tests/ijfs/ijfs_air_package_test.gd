extends GdUnitTestSuite

# Plan 0060 R8 (USER ruling 2026-08-01): an Organic strike is four real airframes drawn from real
# squadrons, not a bare sortie seat. These cases pin the assembly and the capacity arithmetic that
# bounds how many packages a day can produce.

const CLASSES := {"classes": {
	"Manned": {"kind": "manned", "rcs": 0, "wvr": 0, "isr_value": 0.4, "sead_eff": 0},
	"UCAV": {"kind": "unmanned", "rcs": 0, "wvr": 0, "isr_value": 0.0, "sead_eff": 0},
}}


func _squadron(id: String, aircraft_class: String, alive: int) -> IjfsSquadron:
	var squadron := IjfsSquadron.new()
	squadron.squadron_id = id
	squadron.aircraft_class = aircraft_class
	squadron.role = "strike"
	squadron.initial = alive
	squadron.alive = alive
	return squadron


func _organic(munition_id: String) -> IjfsMunition:
	var munition := IjfsMunition.new()
	munition.munition_id = munition_id
	munition.category = "Organic"
	munition.rounds_per_engagement_default = 4
	return munition


func test_link_config_reads_the_authored_shape_and_reports_an_unlinked_munition() -> void:
	var scenario := {"red_firing_capacity": {
		"strike_aircraft_medium": {
			"firing_units": 36, "sorties_per_unit_per_day": 0.8, "platform_type": "aircraft",
			"attrition_link": ["Manned"], "package_size": 4, "manpads_eligible": true},
		"cj10_lacm_glcm": {
			"firing_units": 24, "sorties_per_unit_per_day": 1.5, "platform_type": "ground",
			"attrition_link": null},
	}}
	var linked := IjfsAirPackage.link_config(scenario, "strike_aircraft_medium")
	assert_int(int(linked["package_size"])).is_equal(4)
	assert_bool(bool(linked["manpads_eligible"])).is_true()
	assert_array(linked["classes"]).contains(["Manned"])
	assert_dict(IjfsAirPackage.link_config(scenario, "cj10_lacm_glcm")).override_failure_message(
		"a ground-launched munition costs no airframes and must report an empty link").is_empty()


func test_reserve_draws_uniformly_over_airframes_not_over_squadrons() -> void:
	var small := _squadron("small", "Manned", 1)
	var big := _squadron("big", "Manned", 9)
	# Ten available airframes. Draw 0.0 -> index 0 -> `small` (the first candidate's single slot).
	# After that pick the pool is 9, all `big`, so every later draw lands there.
	var members := IjfsAirPackage.reserve(
		[small, big], 4, ScriptedDice.new([], [], [0.0, 0.5, 0.5, 0.5]))
	assert_int(members.size()).is_equal(4)
	assert_str(members[0].squadron_id).is_equal("small")
	for i in range(1, 4):
		assert_str(members[i].squadron_id).is_equal("big")


func test_reserve_refuses_a_short_package_rather_than_flying_one() -> void:
	var thin := _squadron("thin", "Manned", 3)
	assert_array(IjfsAirPackage.reserve([thin], 4, ScriptedDice.new([], [], [0.0, 0.0, 0.0]))
		).override_failure_message("four airframes is the package, not a maximum").is_empty()
	assert_int(thin.alive).override_failure_message(
		"a refused assembly must not touch the squadron").is_equal(3)


func test_reserve_clamps_the_inclusive_one_boundary() -> void:
	var squadron := _squadron("sq", "Manned", 4)
	# 1.0 * 4 = 4 would index one past the last airframe; clamped to the last eligible slot.
	var members := IjfsAirPackage.reserve([squadron], 4, ScriptedDice.new([], [], [1.0, 1.0, 1.0, 1.0]))
	assert_int(members.size()).is_equal(4)


func test_survivor_fraction_reports_what_reached_the_target() -> void:
	var squadron := _squadron("sq", "Manned", 8)
	var members: Array[IjfsSquadron] = [squadron, squadron, squadron, squadron]
	var package := IjfsAirPackage.build(IjfsAirPackage.STRIKE, "p1", members)
	assert_float(package.survivor_fraction()).is_equal_approx(1.0, 0.000001)
	package.remove_member(0)
	assert_float(package.survivor_fraction()).is_equal_approx(0.75, 0.000001)
	assert_int(int(package.members_by_squadron()["sq"])).is_equal(3)


# --- capacity units: seats, then packages -------------------------------------------------------

func test_capacity_counts_available_airframes_not_merely_alive_ones() -> void:
	# Plan 0060 R5: "build OrganicStrikeBudget only after R11 books sead_assigned_today, using
	# alive - sead_assigned_today - rtb_today". Before the diff-review fix it read `alive`, so a
	# squadron with 90 of 100 airframes flying SEAD still sold a full day of strike seats.
	var scenario := {"red_firing_capacity": {"strike_aircraft_medium": {
		"firing_units": 36, "sorties_per_unit_per_day": 0.8, "platform_type": "aircraft",
		"attrition_link": ["Manned"], "package_size": 4, "manpads_eligible": true}}}
	var munitions := {"strike_aircraft_medium": _organic("strike_aircraft_medium")}

	var full: Array[IjfsSquadron] = [_squadron("s1", "Manned", 100)]
	var at_full := IjfsFiringCapacity.OrganicStrikeBudget.new(scenario, full, munitions, CLASSES)

	var committed := _squadron("s1", "Manned", 100)
	IjfsTransitions.assign_to_sead(committed, 80)
	IjfsTransitions.book_rtb(committed, 10)
	var thin: Array[IjfsSquadron] = [committed]
	var at_ten_percent := IjfsFiringCapacity.OrganicStrikeBudget.new(scenario, thin, munitions, CLASSES)

	assert_int(int(at_full.utilization()["strike_aircraft_medium"]["budget"])).is_equal(7)
	assert_int(int(at_ten_percent.utilization()["strike_aircraft_medium"]["budget"])).override_failure_message(
		"10 of 100 airframes available must not buy a full day of packages"
	).is_less(int(at_full.utilization()["strike_aircraft_medium"]["budget"]))


func test_capacity_divides_airframe_sortie_seats_by_package_size() -> void:
	# The authored numbers are SEATS. R8's worked example: 36 x 0.8 = 28 seats -> 7 four-ship
	# packages; 40 x 2.0 = 80 seats -> 20 four-UCAV packages, never 80 attacks.
	var scenario := {"red_firing_capacity": {
		"strike_aircraft_medium": {
			"firing_units": 36, "sorties_per_unit_per_day": 0.8, "platform_type": "aircraft",
			"attrition_link": ["Manned"], "package_size": 4, "manpads_eligible": true},
		"attack_uav_small": {
			"firing_units": 40, "sorties_per_unit_per_day": 2.0, "platform_type": "uav",
			"attrition_link": ["UCAV"], "package_size": 4, "manpads_eligible": false},
	}}
	var force: Array[IjfsSquadron] = [
		_squadron("manned", "Manned", 100), _squadron("ucav", "UCAV", 60)]
	var munitions := {
		"strike_aircraft_medium": _organic("strike_aircraft_medium"),
		"attack_uav_small": _organic("attack_uav_small")}
	var budget := IjfsFiringCapacity.OrganicStrikeBudget.new(scenario, force, munitions, CLASSES)
	assert_int(int(budget.utilization()["strike_aircraft_medium"]["budget"])).is_equal(7)
	assert_int(int(budget.utilization()["attack_uav_small"]["budget"])).is_equal(20)


func test_losses_scale_the_seats_before_they_become_packages() -> void:
	var scenario := {"red_firing_capacity": {"attack_uav_small": {
		"firing_units": 40, "sorties_per_unit_per_day": 2.0, "platform_type": "uav",
		"attrition_link": ["UCAV"], "package_size": 4, "manpads_eligible": false}}}
	var half := _squadron("ucav", "UCAV", 60)
	half.alive = 30
	var force: Array[IjfsSquadron] = [half]
	var budget := IjfsFiringCapacity.OrganicStrikeBudget.new(
		scenario, force, {"attack_uav_small": _organic("attack_uav_small")}, CLASSES)
	# 80 seats x 0.5 health = 40 seats -> 10 packages.
	assert_int(int(budget.utilization()["attack_uav_small"]["budget"])).is_equal(10)
