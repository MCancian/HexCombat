extends GdUnitTestSuite

const TARGETS_PATH := "res://data/ijfs/targets_master.json"
const MUNITIONS_PATH := "res://data/ijfs/red_munitions.json"
const OOB_PATH := "res://data/ijfs/red_air_oob.json"
const SAM_PATH := "res://data/ijfs/sam_capabilities.json"

func test_qty_expansion_uses_padded_instance_ids() -> void:
	var targets: Array[IjfsTarget] = IjfsLoaders.load_targets(TARGETS_PATH)
	var expanded: Array[IjfsTarget] = []
	for target in targets:
		if target.source_target_id == "anti_ship_007":
			expanded.append(target)
	assert_int(expanded.size()).is_equal(152)
	assert_str(expanded[0].target_id).is_equal("anti_ship_007#001")
	assert_int(expanded[0].instance_index).is_equal(1)
	assert_str(expanded[151].target_id).is_equal("anti_ship_007#152")


func test_static_alive_auto_detected_and_known() -> void:
	var path := _write_json("static_targets.json", {
		"targets": [
			{
				"target_id": "alive_static",
				"category": "Government Buildings",
				"subcategory": "National Government",
				"quantity": 1,
				"mobility": "static",
				"hardness": "soft",
				"detectability_active": "high",
				"detectability_hiding": "high",
				"posture_default": "active",
				"status_default": {"destroyed": false},
			},
			{
				"target_id": "dead_static",
				"category": "Government Buildings",
				"subcategory": "National Government",
				"quantity": 1,
				"mobility": "static",
				"hardness": "soft",
				"detectability_active": "high",
				"detectability_hiding": "high",
				"posture_default": "active",
				"status_default": {"destroyed": true},
			},
		]
	})
	var by_id: Dictionary = {}
	for target in IjfsLoaders.load_targets(path, 4):
		by_id[target.target_id] = target
	assert_bool(by_id["alive_static"].known_to_red).is_true()
	assert_bool(by_id["alive_static"].detected_this_turn).is_true()
	assert_int(by_id["alive_static"].last_detected_day).is_equal(4)
	assert_bool(by_id["dead_static"].known_to_red).is_false()
	assert_bool(by_id["dead_static"].detected_this_turn).is_false()


func test_munition_inventory_prefers_remaining_default() -> void:
	var path := _write_json("munitions_remaining.json", {"munitions": [{"munition_id": "m1", "inventory_default": 100, "inventory_remaining_default": 60, "rounds_per_engagement_default": 10}]})
	assert_int(IjfsLoaders.load_munitions(path)["m1"].inventory_remaining).is_equal(60)
	path = _write_json("munitions_default.json", {"munitions": [{"munition_id": "m1", "inventory_default": 100, "rounds_per_engagement_default": 10}]})
	assert_int(IjfsLoaders.load_munitions(path)["m1"].inventory_remaining).is_equal(100)
	assert_int(IjfsLoaders.load_munitions(MUNITIONS_PATH)["pch191_bre6_crbm"].inventory_remaining).is_equal(28800)


func test_squadron_slug_id_determinism() -> void:
	var squadrons: Array[IjfsSquadron] = IjfsLoaders.expand_oob_to_squadrons(IjfsLoaders.load_oob(OOB_PATH))
	assert_str(squadrons[0].squadron_id).is_equal("5th_gen__strike__001")
	assert_str(squadrons[1].squadron_id).is_equal("5th_gen__strike__002")
	assert_str(squadrons[2].squadron_id).is_equal("4_5th_gen__strike__001")
	var custom: Array[IjfsSquadron] = IjfsLoaders.expand_oob_to_squadrons([{"class": "J-16D", "role": "sead", "squadrons": 1, "aircraft_per_sqn": 24}, {"class": "H-6", "role": "strike", "squadrons": 1, "aircraft_per_sqn": 12}])
	assert_str(custom[0].squadron_id).is_equal("j_16d__sead__001")
	assert_str(custom[1].squadron_id).is_equal("h_6__strike__001")


func test_sam_fallback_by_category() -> void:
	var target := IjfsTarget.new()
	target.target_id = "fallback_sam"
	target.category = "Static SAMs"
	target.subcategory = "Unknown SAM"
	var non_sam := IjfsTarget.new()
	non_sam.target_id = "radar"
	non_sam.category = "Mobile Radars"
	non_sam.subcategory = "Mobile Radar"
	var targets: Array[IjfsTarget] = [target, non_sam]
	IjfsLoaders.enrich_sam_scores(targets, IjfsLoaders.load_sam_capabilities(SAM_PATH))
	assert_int(target.sam_score).is_equal(2)
	assert_int(non_sam.sam_score).is_equal(-1)


func _write_json(file_name: String, payload: Dictionary) -> String:
	var path := "user://%s" % file_name
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(payload))
	file.close()
	return path
