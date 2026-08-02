extends GdUnitTestSuite

# Plan 0060 R2 (USER ruling 2026-08-01): role exposure — altitude and flight profile — multiplies
# every per-airframe loss probability ALONGSIDE the RCS survival modifier that was already live.
# The load-bearing claim these cases pin is that the two COMPOSE: a low-observable striker gets the
# signature advantage and the exposure penalty, not whichever the code happened to apply last.

const CLASSES := {"classes": {
	"Stealthy": {"rcs": -3, "wvr": 0, "isr_value": 0.9, "sead_eff": 0},
	"Plain": {"rcs": 0, "wvr": 0, "isr_value": 0.4, "sead_eff": 0},
	"Fat": {"rcs": 2, "wvr": 0, "isr_value": 0.3, "sead_eff": 0},
}}
const SHIPPED_EXPOSURE := {"red_aircraft_attrition_and_sead":
	{"role_exposure_multipliers": {"isr": 0.7, "sead": 1.0, "strike": 1.2}}}


func _profile() -> IjfsAttritionProfile:
	return IjfsAttritionProfile.build(SHIPPED_EXPOSURE, CLASSES)


func test_role_and_rcs_compose_rather_than_replace_one_another() -> void:
	var profile := _profile()
	# Stealthy: rcs -3 -> survival 1 + (-3 * 0.1) = 0.7. Strike exposure 1.2.
	# Composed: 0.5 * 1.2 * 0.7 = 0.42 — neither 0.6 (role only) nor 0.35 (RCS only).
	var composed := profile.p_loss(0.5, "Stealthy", "strike")
	assert_float(composed).is_equal_approx(0.42, 0.000001)
	assert_float(composed).is_not_equal(profile.p_loss(0.5, "Plain", "strike"))
	assert_float(composed).is_not_equal(profile.p_loss(0.5, "Stealthy", "sead"))


func test_role_exposure_orders_the_three_flying_roles() -> void:
	var profile := _profile()
	var isr := profile.p_loss(0.5, "Plain", "isr")
	var sead := profile.p_loss(0.5, "Plain", "sead")
	var strike := profile.p_loss(0.5, "Plain", "strike")
	assert_float(isr).is_equal_approx(0.35, 0.000001)
	assert_float(sead).is_equal_approx(0.5, 0.000001)
	assert_float(strike).is_equal_approx(0.6, 0.000001)
	assert_bool(isr < sead and sead < strike).override_failure_message(
		"ISR must be the most survivable profile and strike the least").is_true()


func test_rcs_survival_is_floored_so_a_low_signature_cannot_go_unkillable() -> void:
	var profile := IjfsAttritionProfile.build(SHIPPED_EXPOSURE, {"classes": {
		"Ghost": {"rcs": -50, "wvr": 0, "isr_value": 0.0, "sead_eff": 0}}})
	# 1 + (-50 * 0.1) = -4.0, which without the floor would make p_loss negative.
	assert_float(profile.rcs_survival("Ghost")).is_equal_approx(
		IjfsAttritionProfile.MIN_RCS_SURVIVAL_MOD, 0.000001)
	assert_float(profile.p_loss(0.5, "Ghost", "strike")).is_equal_approx(0.12, 0.000001)


func test_p_loss_is_clamped_into_a_usable_probability() -> void:
	var profile := _profile()
	# rcs 2 -> survival 1.2; strike exposure 1.2; 0.9 * 1.2 * 1.2 = 1.296 before the clamp.
	assert_float(profile.p_loss(0.9, "Fat", "strike")).is_equal_approx(1.0, 0.000001)
	assert_float(profile.p_loss(-0.5, "Fat", "strike")).is_equal_approx(0.0, 0.000001)


func test_absent_configuration_is_the_identity_not_a_guess() -> void:
	var empty := IjfsAttritionProfile.build(null, null)
	assert_float(empty.role_exposure("strike")).is_equal_approx(
		IjfsAttritionProfile.NEUTRAL_EXPOSURE, 0.000001)
	assert_float(empty.rcs_survival("anything")).is_equal_approx(1.0, 0.000001)
	assert_float(empty.p_loss(0.4, "anything", "strike")).override_failure_message(
		"a scenario that models no exposure must get the base rate back unchanged"
	).is_equal_approx(0.4, 0.000001)
	# An unknown role falls back the same way rather than borrowing another role's multiplier.
	assert_float(_profile().role_exposure("unused")).is_equal_approx(
		IjfsAttritionProfile.NEUTRAL_EXPOSURE, 0.000001)


func test_shipped_scenario_activates_the_block_that_used_to_be_dead_data() -> void:
	# Until 2026-08-01 IjfsLoaders REQUIRED red_aircraft_attrition_and_sead to exist and nothing read
	# a field in it. This is the regression pin for that: the shipped numbers must reach a profile.
	var scenario := IjfsLoaders.load_scenario("res://data/ijfs/ijfs_scenario.json")
	var air_classes := IjfsLoaders.load_air_classes("res://data/ijfs/air_classes.json")
	var profile := IjfsAttritionProfile.build(scenario, air_classes)
	assert_float(profile.role_exposure("isr")).is_equal_approx(0.7, 0.000001)
	assert_float(profile.role_exposure("sead")).is_equal_approx(1.0, 0.000001)
	assert_float(profile.role_exposure("strike")).is_equal_approx(1.2, 0.000001)
	# 5th Gen carries rcs -2, so the shipped fleet really does span a survivability range.
	assert_float(profile.rcs_survival("5th Gen")).is_equal_approx(0.8, 0.000001)
	assert_float(profile.rcs_survival("H-6")).is_equal_approx(1.2, 0.000001)
