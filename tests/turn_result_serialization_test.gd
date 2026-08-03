extends GdUnitTestSuite

## TurnResult is the turn record: SelfPlayRunner appends `result["turn_result"]` to `turn_digests`
## once per turn, and that array IS the research record a campaign is charted from. Plan 0059 put
## Red's air order of battle in it, so these tests pin the serialized shape of that block.
##
## The completeness test at the bottom exists because the published schema had SILENTLY DRIFTED:
## five fields were live on the model and absent from `schemas/llm_action_result.schema.json`, and
## nothing could see it — the result object allows additional properties, the nested properties are
## not `required`, and `validate_llm_api` inspects only top-level keys. Found while adding a sixth.
## Nested arrays are sampled at element [0] only (a typed array shares one schema); cross-element
## VALUE divergence is already caught by the full-payload drift compare in tools/validate_llm_api.gd.

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

	# Recurse into nested objects, scalar-array items, and additionalProperties maps
	for key in dict_val.keys():
		var val = dict_val[key]
		var prop_def = schema_props[key]
		var child_path := path + "." + String(key)
		if val is Dictionary:
			_check_object(val, prop_def, child_path)
		elif val is Array:
			_check_array(val, prop_def, child_path)
		else:
			_assert_scalar(child_path, val, prop_def)


func _check_object(val: Dictionary, prop_def, child_path: String) -> void:
	if prop_def.has("properties") and prop_def["properties"] is Dictionary:
		_check_two_way_schema(val, prop_def["properties"], child_path)
	elif prop_def.has("additionalProperties") and prop_def["additionalProperties"] is Dictionary:
		var ap: Dictionary = prop_def["additionalProperties"]
		for k in val.keys():
			_assert_scalar(child_path + "." + String(k), val[k], ap)


func _check_array(val: Array, prop_def, child_path: String) -> void:
	if not (prop_def.has("items") and prop_def["items"] is Dictionary):
		return
	var items: Dictionary = prop_def["items"]
	var items_type := String(items.get("type", ""))
	if items_type in ["integer", "number", "boolean", "string"]:
		for i in val.size():
			_assert_scalar(child_path + "[%d]" % i, val[i], items)
	elif val.size() > 0 and val[0] is Dictionary and items.has("properties"):
		_check_two_way_schema(val[0], items["properties"], child_path + "[0]")


func _assert_scalar(path: String, val, prop_def) -> void:
	# JSON.parse_string returns every number as float, so an integral float satisfies "integer"
	# (JSON Schema semantics: integer = number with zero fractional part).
	var expected_type := String(prop_def.get("type", ""))
	var ok := false
	match expected_type:
		"integer":
			ok = val is int or (val is float and floor(val) == val)
		"number":
			ok = val is int or val is float
		"boolean":
			ok = val is bool
		"string":
			ok = val is String
		"":
			if prop_def.has("enum") and prop_def["enum"] is Array:
				ok = (val is String) and (val in prop_def["enum"])
	assert_bool(ok).override_failure_message(
		"Schema type mismatch at %s: expected %s, got %s" % [
			path,
			expected_type if expected_type != "" else str(prop_def.get("enum", "any")),
			type_string(typeof(val))
		]
	).is_true()


func test_type_checker_accepts_integral_floats_and_enums() -> void:
	# JSON.parse_string turns every number into a float, so an integral float MUST satisfy
	# "integer" and an enum-typed field MUST accept one of its members — or the fixture check
	# would fail on values that validate fine under JSON Schema.
	var schema := {
		"n": {"type": "integer"},
		"rate": {"type": "number"},
		"kind": {"enum": ["ijfs", "move"]},
	}
	var data := {"n": 1.0, "rate": 0.35, "kind": "move"}
	_check_two_way_schema(data, schema, "turn_result")


func test_type_checker_rejects_a_fractional_value_in_an_integer_field() -> void:
	# Regression guard for the air_insertion_summary.attrition_by_class schema bug: an "integer"
	# field carrying a fractional float must be caught here, not shipped in a schema that would
	# reject every real payload at runtime.
	var schema := {"attrition_by_class": {"additionalProperties": {"type": "integer"}}}
	var data := {"attrition_by_class": {"IJFS": 0.35}}
	assert_failure(func() -> void:
		_check_two_way_schema(data, schema, "turn_result")
	).contains_message("Schema type mismatch")
