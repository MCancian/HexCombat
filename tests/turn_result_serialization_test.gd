extends GdUnitTestSuite

## TurnResult is the turn record: SelfPlayRunner appends `result["turn_result"]` to `turn_digests`
## once per turn, and that array IS the research record a campaign is charted from. Plan 0059 put
## Red's air order of battle in it, so these tests pin the serialized shape of that block.
##
## The completeness test at the bottom exists because the published schema had SILENTLY DRIFTED:
## five fields were live on the model and absent from `schemas/llm_action_result.schema.json`, and
## nothing could see it — the result object allows additional properties, the nested properties are
## not `required`, and `validate_llm_api` inspects only top-level keys. Found while adding a sixth.

const SCHEMA_PATH := "res://schemas/llm_action_result.schema.json"


func test_air_oob_reaches_to_dict() -> void:
	var result := TurnResult.new()
	result.air_oob = {
		"model_version": 4,
		"squadrons": [{"squadron_id": "sq1", "class": "5th Gen", "kind": "manned", "alive": 20}],
	}

	var out := result.to_dict()

	assert_bool(out.has("air_oob")).override_failure_message(
		"air_oob must be serialized — the turn record is the only surface that carries the air OOB"
	).is_true()
	var squadrons: Array = (out["air_oob"] as Dictionary)["squadrons"]
	assert_int(squadrons.size()).is_equal(1)
	assert_str(String((squadrons[0] as Dictionary)["kind"])).is_equal("manned")


func test_air_oob_defaults_to_an_empty_dict_not_null() -> void:
	# `{}` means "no turn has resolved yet" — never null, so a consumer has two cases, not three.
	# It does NOT mean "the force is gone": a wiped-out force is rows with alive: 0, because attrition
	# only decrements and the ledger appends every squadron.
	var out := TurnResult.new().to_dict()
	assert_bool(out["air_oob"] is Dictionary).is_true()
	assert_bool((out["air_oob"] as Dictionary).is_empty()).is_true()


func test_every_serialized_key_is_declared_in_the_action_result_schema() -> void:
	var file := FileAccess.open(SCHEMA_PATH, FileAccess.READ)
	assert_object(file).override_failure_message("cannot open %s" % SCHEMA_PATH).is_not_null()
	var schema: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()
	var declared: Dictionary = ((schema["properties"] as Dictionary)["turn_result"] as Dictionary)["properties"]

	var fixture_file := FileAccess.open("res://docs/examples/llm_result_after_turn.json", FileAccess.READ)
	assert_object(fixture_file).is_not_null()
	var fixture: Dictionary = JSON.parse_string(fixture_file.get_as_text())
	fixture_file.close()
	var tr_fixture: Dictionary = fixture["turn_result"]

	# Ensure the fixture is not empty so the recursive check actually traverses everything
	assert_bool(tr_fixture.has("cleanup_summary")).is_true()

	_check_two_way_schema(tr_fixture, declared, "turn_result")

func _check_two_way_schema(dict_val: Dictionary, schema_props: Dictionary, path: String) -> void:
	var missing_in_schema: Array[String] = []
	for key in dict_val.keys():
		if not schema_props.has(key):
			missing_in_schema.append(String(key))
	missing_in_schema.sort()
	assert_array(missing_in_schema).override_failure_message(
		"Model keys absent from schema at %s: %s" % [path, missing_in_schema]
	).is_empty()

	var missing_in_model: Array[String] = []
	if not dict_val.is_empty():
		for key in schema_props.keys():
			if not dict_val.has(key):
				missing_in_model.append(String(key))
	missing_in_model.sort()
	assert_array(missing_in_model).override_failure_message(
		"Schema properties absent from model fixture at %s: %s" % [path, missing_in_model]
	).is_empty()

	# Recurse into nested objects
	for key in dict_val.keys():
		var val = dict_val[key]
		var prop_def = schema_props[key]
		
		if val is Dictionary and prop_def.has("properties"):
			_check_two_way_schema(val, prop_def["properties"], path + "." + String(key))
		elif val is Array and not val.is_empty() and val[0] is Dictionary and prop_def.has("items") and (prop_def["items"] as Dictionary).has("properties"):
			_check_two_way_schema(val[0], prop_def["items"]["properties"], path + "." + String(key) + "[0]")
