# Run from project root:
# C:\Godot_v4.7-stable_win64.exe --headless --path C:\Users\mdogg\Desktop\HexCombat -s res://tools/validate_ijfs_data.gd
extends SceneTree

const TARGETS_PATH := "res://data/ijfs/targets_master.json"
const MUNITIONS_PATH := "res://data/ijfs/red_munitions.json"
const PAIRINGS_PATH := "res://data/ijfs/munition_target_pairings.json"
const SCENARIO_PATH := "res://data/ijfs/ijfs_scenario.json"
const AIR_CLASSES_PATH := "res://data/ijfs/air_classes.json"
const OOB_PATH := "res://data/ijfs/red_air_oob.json"
const SAM_PATH := "res://data/ijfs/sam_capabilities.json"

var _failures: Array[String] = []

func _initialize() -> void:
	print("=== IJFS data validation ===")
	var target_json: Dictionary = _read_json(TARGETS_PATH)
	var targets: Array[IjfsTarget] = IjfsLoaders.load_targets(TARGETS_PATH, 1)
	_validate_target_expansion(target_json, targets)

	var munition_json: Dictionary = _read_json(MUNITIONS_PATH)
	var munitions: Dictionary = IjfsLoaders.load_munitions(MUNITIONS_PATH)
	_validate_munitions(munition_json, munitions)

	var pairings: Array[IjfsPairing] = IjfsLoaders.load_pairings(PAIRINGS_PATH, munitions.keys())
	_validate_pairings(pairings)

	var scenario := IjfsLoaders.load_scenario(SCENARIO_PATH)
	_validate_scenario_blocks(scenario)
	var air_classes := IjfsLoaders.load_air_classes(AIR_CLASSES_PATH)
	var oob := IjfsLoaders.load_oob(OOB_PATH)
	_validate_squadrons(oob, IjfsLoaders.expand_oob_to_squadrons(oob), air_classes)

	var sam_caps := IjfsLoaders.load_sam_capabilities(SAM_PATH)
	IjfsLoaders.enrich_sam_scores(targets, sam_caps)
	_validate_sam_enrichment(targets)
	_finish()


func _validate_target_expansion(raw: Dictionary, targets: Array[IjfsTarget]) -> void:
	var raw_targets: Array = raw.get("targets", [])
	var expected_instances := 0
	for row in raw_targets:
		expected_instances += int(row.get("quantity", 1))
	_check(raw_targets.size() == 54, "Source target count expected 54, got %d" % raw_targets.size())
	_check(targets.size() == expected_instances, "Expanded target count expected %d, got %d" % [expected_instances, targets.size()])
	# 412, not the oracle's 2862: the 2,500 individual Stinger instances became 50 MANPADS bins of
	# 50 launchers (2026-07-10 USER design call — deliberate divergence; see PLAN.md Decisions).
	_check(targets.size() == 412, "Expanded target count expected 412, got %d" % targets.size())
	_validate_manpads_bins(targets)
	var anti_ship_007: Array[IjfsTarget] = []
	for target in targets:
		_check(target.quantity == 1, "Expanded target %s quantity should be 1" % target.target_id)
		if target.source_target_id == "anti_ship_007":
			anti_ship_007.append(target)
	_check(anti_ship_007.size() == 152, "anti_ship_007 expected 152 instances, got %d" % anti_ship_007.size())
	_check(not anti_ship_007.is_empty() and anti_ship_007[0].target_id == "anti_ship_007#001", "anti_ship_007 first id should be #001")
	print("Target expansion: %d source targets -> %d instances" % [raw_targets.size(), targets.size()])


## MANPADS bins (2026-07-10): category outside the SAM/SEAD categories, every bin carries
## to_number + systems_represented, and the four TO pools total 2,500 launchers.
func _validate_manpads_bins(targets: Array[IjfsTarget]) -> void:
	var bins := 0
	var launchers := 0
	for target in targets:
		if target.category != "MANPADS":
			continue
		bins += 1
		_check(target.metadata.has("to_number"), "MANPADS bin %s missing to_number" % target.target_id)
		var rep := int(target.metadata.get("systems_represented", 0))
		_check(rep == 50, "MANPADS bin %s systems_represented expected 50, got %d" % [target.target_id, rep])
		launchers += rep
	_check(bins == 50, "MANPADS bins expected 50, got %d" % bins)
	_check(launchers == 2500, "MANPADS launcher total expected 2500, got %d" % launchers)
	_check("MANPADS" not in IjfsEngagement.SAM_CATEGORIES, "MANPADS must stay outside SEAD's SAM_CATEGORIES")
	_check("MANPADS" not in IjfsAdHealth.AD_CATEGORIES, "MANPADS must stay outside AD-health categories")
	print("MANPADS bins: %d bins / %d launchers validated" % [bins, launchers])


func _validate_munitions(raw: Dictionary, munitions: Dictionary) -> void:
	_check(munitions.size() == raw.get("munitions", []).size(), "Munition count mismatch")
	for row in raw.get("munitions", []):
		var mid := String(row["munition_id"])
		var rounds := int(row["rounds_per_engagement_default"])
		_check(int(row["inventory_default"]) % rounds == 0, "%s inventory_default not clean multiple" % mid)
		if row.has("inventory_remaining_default"):
			_check(int(row["inventory_remaining_default"]) % rounds == 0, "%s inventory_remaining_default not clean multiple" % mid)
		var loaded: IjfsMunition = munitions[mid]
		_check(loaded.inventory_remaining == int(row.get("inventory_remaining_default", row.get("inventory_default", 0))), "%s loader did not prefer remaining_default" % mid)
	var bre6: IjfsMunition = munitions["pch191_bre6_crbm"]
	_check(bre6.inventory_remaining == 28800 and bre6.rounds_per_engagement_default == 48, "BRE6 required values changed")
	_check(munitions["yj_62_ascm"].inventory_remaining == 864 and munitions["yj_62_ascm"].rounds_per_engagement_default == 4, "YJ-62 ASCM required values changed")
	_check(munitions["yj_12_ascm"].inventory_remaining == 432 and munitions["yj_12_ascm"].rounds_per_engagement_default == 4, "YJ-12 ASCM required values changed")
	_check(munitions["cm401_asbm"].inventory_remaining == 432 and munitions["cm401_asbm"].rounds_per_engagement_default == 4, "CM-401 ASBM required values changed")
	print("Munition inventories: %d entries validated" % munitions.size())


func _validate_pairings(pairings: Array[IjfsPairing]) -> void:
	_check(pairings.size() == 355, "Pairing count expected 355, got %d" % pairings.size())
	var ascm_allowed := ["Surface Combatant – Destroyer and Frigate", "Missile Patrol Boat", "Stealth Corvette / Fast Attack Craft"]
	for mid in ["yj_62_ascm", "yj_12_ascm", "cm401_asbm"]:
		var scoped := _pairings_for_munition(pairings, mid)
		_check(not scoped.is_empty(), "%s pairings must exist" % mid)
		var subs: Array[String] = []
		for p in scoped:
			if p.target_subcategory not in subs:
				subs.append(p.target_subcategory)
		subs.sort()
		var allowed_copy := ascm_allowed.duplicate()
		allowed_copy.sort()
		_check(subs == allowed_copy, "%s ASCM scope changed: %s" % [mid, str(subs)])
	var srbm_ids := ["pla_srbm_large_generic", "df15c_penetrator_srbm"]
	var crbm_ids := ["pch191_bre6_crbm", "pch191_bre8_crbm"]
	var found_srbm := false
	var found_crbm_nonstatic := false
	var maneuver_munitions: Array[String] = []
	for p in pairings:
		_check(p.rounds_expended_per_engagement > 0, "Pairing %s has non-positive rounds" % p.pairing_id)
		if p.munition_id in srbm_ids:
			found_srbm = true
			_check(p.target_mobility == "static", "SRBM pairing %s is not static" % p.pairing_id)
		if p.munition_id in crbm_ids and p.target_mobility != "static":
			found_crbm_nonstatic = true
		if p.target_category == "Maneuver Units" and p.munition_id not in maneuver_munitions:
			maneuver_munitions.append(p.munition_id)
	_check(found_srbm, "SRBM pairings must exist")
	_check(found_crbm_nonstatic, "CRBMs must retain non-static pairings")
	maneuver_munitions.sort()
	var expected_maneuver := ["pch191_bre6_crbm", "pch191_bre8_crbm", "strike_aircraft_medium"]
	expected_maneuver.sort()
	_check(maneuver_munitions == expected_maneuver, "Maneuver pairings munition scope changed: %s" % str(maneuver_munitions))
	print("Pairing scope checks: %d pairings validated" % pairings.size())


func _validate_scenario_blocks(scenario: Dictionary) -> void:
	for key in ["detection_model", "isr_sources", "taiwan_air_defense_health", "red_firing_capacity", "targeting_doctrine", "target_release", "prelanding"]:
		_check(scenario.has(key), "Scenario missing required block %s" % key)
	_check(scenario.has("strike_probability_modifiers") or scenario.has("mobile_target_destroy_caps"), "Scenario missing strike_probability_modifiers or mobile_target_destroy_caps")
	print("Scenario schema blocks validated")


func _validate_squadrons(oob: Dictionary, squadrons: Array[IjfsSquadron], air_classes: Dictionary) -> void:
	var expected := 0
	for row in oob["red_air_oob"]:
		expected += int(row["squadrons"])
	_check(squadrons.size() == expected, "Squadron expansion expected %d, got %d" % [expected, squadrons.size()])
	_check(squadrons[0].squadron_id == "5th_gen__strike__001", "First squadron id changed: %s" % squadrons[0].squadron_id)
	_check(squadrons[2].squadron_id == "4_5th_gen__strike__001", "4.5th Gen slug/id changed: %s" % squadrons[2].squadron_id)
	for sqn in squadrons:
		_check(air_classes["classes"].has(sqn.aircraft_class), "Squadron unknown air class %s" % sqn.aircraft_class)
	print("Squadron expansion: %d stable ids validated" % squadrons.size())


func _validate_sam_enrichment(targets: Array[IjfsTarget]) -> void:
	var found_pat := false
	var found_sam := false
	for target in targets:
		if target.category in ["Moveable SAMs", "Static SAMs", "Mobile SAMs"]:
			found_sam = true
			_check(target.sam_score >= 0, "SAM target %s did not receive sam_score" % target.target_id)
			if target.subcategory == "Long-Range SAM – Patriot":
				found_pat = true
				_check(target.sam_score == 4, "Patriot sam_score expected 4, got %d" % target.sam_score)
	_check(found_sam, "No SAM targets found for enrichment check")
	_check(found_pat, "No Patriot SAM targets found for enrichment check")
	print("SAM score enrichment validated")


func _pairings_for_munition(pairings: Array[IjfsPairing], mid: String) -> Array[IjfsPairing]:
	var result: Array[IjfsPairing] = []
	for p in pairings:
		if p.munition_id == mid:
			result.append(p)
	return result


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("Could not open %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		_fail("%s did not parse to a Dictionary" % path)
		return {}
	return parsed


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	_failures.append(message)
	push_error(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: IJFS data validation succeeded")
		quit(0)
		return
	print("FAIL: IJFS data validation found %d issue(s):" % _failures.size())
	for failure in _failures:
		print("  - %s" % failure)
	quit(1)
