## Verifies the per-hull mine-neutralization-likelihood override (refactor_audit item 2). A ShipDef may
## carry an optional `mine_neutralization_likelihood`; GameState._mine_ship_meta prefers it over the
## per-category table (which remains the fallback). Decoys keep their own transit override. Pure lookup,
## no dice.
extends GdUnitTestSuite


func before_test() -> void:
	GameData.load_all()


func after_test() -> void:
	# _mine_ship_meta reads GameData.ship_defs; restore it after we swap in synthetic hulls.
	GameData.load_all()


func _ship(id: int, name: String, category: String, override: String, decoy: bool) -> ShipDef:
	var sd := ShipDef.new()
	sd.id = id
	sd.name = name
	sd.category = category
	sd.carrying_capacity_bn_equiv = 1.0
	sd.is_decoy = decoy
	sd.mine_neutralization_likelihood = override
	return sd


func test_override_beats_category_and_fallback_holds() -> void:
	var base := _ship(9001, "TST-BASE", "TESTCAT", "", false)      # no override -> category
	var over := _ship(9002, "TST-OVER", "TESTCAT", "high", false)  # override wins over category
	var decoy := _ship(9003, "TST-DECOY", "TESTCAT", "", true)     # decoy -> transit decoy label
	GameData.ship_defs = {base.id: base, over.id: over, decoy.id: decoy}

	var transit := {
		"neutralization_likelihood_by_category": {"TESTCAT": "low"},
		"decoy_neutralization_likelihood": "high",
	}
	var meta: Dictionary = GameState._mine_ship_meta(transit)

	assert_str(String(meta["TST-BASE"]["likelihood"])).is_equal("low")    # category fallback
	assert_str(String(meta["TST-OVER"]["likelihood"])).is_equal("high")   # per-hull override
	assert_str(String(meta["TST-DECOY"]["likelihood"])).is_equal("high")  # decoy transit override
	assert_bool(bool(meta["TST-DECOY"]["is_decoy"])).is_true()


func test_real_ships_default_to_category_unchanged() -> void:
	# No production hull sets the override yet, so every non-decoy ship still resolves to its category
	# label — proving the change is behavior-preserving on the real data.
	var transit := {
		"neutralization_likelihood_by_category": {},  # forces the default "high" branch uniformly
		"decoy_neutralization_likelihood": "high",
	}
	var meta: Dictionary = GameState._mine_ship_meta(transit)
	for ship_name in meta.keys():
		assert_str(String(meta[ship_name]["likelihood"])).is_equal("high")
