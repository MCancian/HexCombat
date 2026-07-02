extends GdUnitTestSuite

## ScenarioCatalog (research-harness B1): id/path resolution, arg-vs-env selection precedence,
## and enumeration. Pure statics — no autoload involvement.


func test_resolve_path_empty_and_default_yield_default() -> void:
	assert_str(ScenarioCatalog.resolve_path("")).is_equal(ScenarioCatalog.DEFAULT_SCENARIO_PATH)
	assert_str(ScenarioCatalog.resolve_path("  ")).is_equal(ScenarioCatalog.DEFAULT_SCENARIO_PATH)
	assert_str(ScenarioCatalog.resolve_path("default")).is_equal(ScenarioCatalog.DEFAULT_SCENARIO_PATH)


func test_resolve_path_bare_id_maps_into_scenarios_dir() -> void:
	assert_str(ScenarioCatalog.resolve_path("more_mines")).is_equal("res://data/scenarios/more_mines.json")


func test_resolve_path_paths_pass_through_verbatim() -> void:
	assert_str(ScenarioCatalog.resolve_path("res://data/scenario_default.json")).is_equal("res://data/scenario_default.json")
	assert_str(ScenarioCatalog.resolve_path("C:/tmp/variant.json")).is_equal("C:/tmp/variant.json")
	assert_str(ScenarioCatalog.resolve_path("variant.json")).is_equal("variant.json")


func test_select_path_no_selection_yields_default() -> void:
	assert_str(ScenarioCatalog.select_path(PackedStringArray(), "")).is_equal(ScenarioCatalog.DEFAULT_SCENARIO_PATH)
	assert_str(ScenarioCatalog.select_path(PackedStringArray(["--other=1"]), "")).is_equal(ScenarioCatalog.DEFAULT_SCENARIO_PATH)


func test_select_path_arg_beats_env() -> void:
	var args := PackedStringArray(["--scenario=res://data/scenario_default.json"])
	assert_str(ScenarioCatalog.select_path(args, "res://does/not/matter.json")).is_equal("res://data/scenario_default.json")


func test_select_path_env_used_when_no_arg() -> void:
	assert_str(ScenarioCatalog.select_path(PackedStringArray(), "default")).is_equal(ScenarioCatalog.DEFAULT_SCENARIO_PATH)


func test_scenario_id_is_filename_stem() -> void:
	assert_str(ScenarioCatalog.scenario_id("res://data/scenarios/more_mines.json")).is_equal("more_mines")
	assert_str(ScenarioCatalog.scenario_id(ScenarioCatalog.DEFAULT_SCENARIO_PATH)).is_equal("scenario_default")


func test_list_scenario_paths_starts_with_default_and_all_exist() -> void:
	var paths := ScenarioCatalog.list_scenario_paths()
	assert_bool(paths.size() >= 1).is_true()
	assert_str(paths[0]).is_equal(ScenarioCatalog.DEFAULT_SCENARIO_PATH)
	for path in paths:
		assert_bool(FileAccess.file_exists(path)).override_failure_message("Missing scenario file: %s" % path).is_true()
