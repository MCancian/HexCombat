## Verifies the mines-only baseline knob (plan 0012): a `disable_antiship_systems: true` override
## on the grouping spec makes AntishipLoaders.load_systems yield zero crossing interceptors while
## the container view (the IJFS target source) stays intact — isolating D3 crossing losses to the
## minefields with no writeback surgery.
extends GdUnitTestSuite

const GROUPING_KEY := "data/antiship/antiship_grouping_spec.json:disable_antiship_systems"


func after_test() -> void:
	DataOverrides.set_map({})
	GameData.load_all()


func test_override_disables_systems_but_keeps_containers() -> void:
	DataOverrides.set_map({GROUPING_KEY: true})

	var built: Dictionary = AntishipSystemsBuilder.build()

	assert_int((built["systems"] as Array).size()).is_equal(0)
	assert_int((built["containers"] as Array).size()).is_not_equal(0)
	assert_int(DataOverrides.unapplied().size()).is_equal(0)


func test_default_build_still_yields_systems() -> void:
	DataOverrides.set_map({})

	var built: Dictionary = AntishipSystemsBuilder.build()

	assert_int((built["systems"] as Array).size()).is_not_equal(0)
