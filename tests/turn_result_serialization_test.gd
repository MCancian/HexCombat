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

	var missing: Array[String] = []
	for key in TurnResult.new().to_dict().keys():
		if not declared.has(key):
			missing.append(String(key))
	missing.sort()

	assert_array(missing).override_failure_message(
		"TurnResult keys absent from llm_action_result.schema.json: %s — the published contract for "
		% [missing] + "the turn record understates it, and nothing else in the gate would say so"
	).is_empty()
