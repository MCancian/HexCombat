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


# --- D3-D (1-A): container-level (TO,type) anti-ship target generation -------------------------

func _container(to_number: int, type_id: int, type_name: String, systems_represented: int, subcategory: String, mobility: String = "moveable") -> Dictionary:
	return {
		"to_number": to_number,
		"type_id": type_id,
		"type_name": type_name,
		"systems_represented": systems_represented,
		"ijfs_profile": {
			"category": "Anti-Ship Systems",
			"subcategory": subcategory,
			"mobility": mobility,
			"hardness": "soft",
			"detectability_active": "high",
			"detectability_hiding": "low",
		},
	}


func test_build_antiship_targets_carries_to_type_and_systems_represented() -> void:
	var containers := [
		_container(2, 3, "Air-Launched", 19, "Air-Launched Anti-Ship Missile Platform"),
		_container(2, 3, "Air-Launched", 18, "Air-Launched Anti-Ship Missile Platform"),
		_container(3, 5, "CDCM", 24, "Static CDCMs", "static"),
	]
	var targets := IjfsLoaders.build_antiship_targets(containers, 1)
	assert_int(targets.size()).is_equal(3)  # one target per container bin (NOT per system)
	var bins: Array = []
	for t in targets:
		assert_str(t.category).is_equal("Anti-Ship Systems")
		assert_bool(t.metadata.has("to_number")).is_true()
		assert_bool(t.metadata.has("systems_represented")).is_true()
		if int(t.metadata["to_number"]) == 2 and int(t.metadata["type_id"]) == 3:
			bins.append(t)
	assert_int(bins.size()).is_equal(2)
	assert_str(bins[0].target_id).is_equal("antiship_to2_type3_c000")
	assert_int(int(bins[0].metadata["systems_represented"])).is_equal(19)


func test_load_targets_with_antiship_replaces_static_rows() -> void:
	var containers := [_container(2, 3, "Air-Launched", 19, "Air-Launched Anti-Ship Missile Platform")]
	var merged := IjfsLoaders.load_targets_with_antiship(TARGETS_PATH, containers, 1)
	var dynamic_antiship := 0
	for t in merged:
		# No static anti-ship rows survive; every anti-ship target carries (TO,type) metadata.
		assert_bool(t.source_target_id == "anti_ship_007").is_false()
		if t.category == "Anti-Ship Systems":
			assert_bool(t.metadata.has("to_number")).is_true()
			dynamic_antiship += 1
	assert_int(dynamic_antiship).is_equal(1)  # one container bin
