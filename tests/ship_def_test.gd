extends GdUnitTestSuite

# ShipDef classification predicates (sails / is_carrier / is_amphibious_lift). These centralize the
# ship-type knowledge the sealift resolver used to hard-code as category strings; the amphibious-lift
# case in particular guards the substring bug where `.contains("Amphibious")` wrongly matched
# "Civilian_Non_Amphibious".


func _ship(category: String, capacity := 0.0, infrastructure := false, is_decoy := false) -> ShipDef:
	var d := ShipDef.new()
	d.category = category
	d.carrying_capacity_bn_equiv = capacity
	d.infrastructure = infrastructure
	d.is_decoy = is_decoy
	return d


func test_is_amphibious_lift_true_for_amphibious_carrier_categories() -> void:
	assert_bool(_ship("Military_Amphibious", 1.0).is_amphibious_lift()).is_true()
	assert_bool(_ship("Civilian_Amphibious", 0.25).is_amphibious_lift()).is_true()


func test_is_amphibious_lift_false_for_non_amphibious_despite_substring() -> void:
	# The regression: "Civilian_Non_Amphibious" CONTAINS "Amphibious" but is NOT amphibious lift.
	assert_bool(_ship("Civilian_Non_Amphibious", 1.0).is_amphibious_lift()).is_false()


func test_is_amphibious_lift_false_for_non_carrier() -> void:
	# An escort in an amphibious category (capacity 0) still isn't lift.
	assert_bool(_ship("Military_Amphibious", 0.0).is_amphibious_lift()).is_false()


func test_is_carrier_tracks_capacity() -> void:
	assert_bool(_ship("Civilian_Amphibious", 0.1).is_carrier()).is_true()
	assert_bool(_ship("Escort", 0.0).is_carrier()).is_false()


func test_sails_excludes_only_non_decoy_infrastructure() -> void:
	assert_bool(_ship("Escort", 0.0).sails()).is_true()
	assert_bool(_ship("Infrastructure", 0.0, true, false).sails()).is_false()
	assert_bool(_ship("Infrastructure", 0.0, true, true).sails()).is_true()  # decoy infra still sails
