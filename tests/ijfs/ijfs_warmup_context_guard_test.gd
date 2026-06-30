## Guards the IJFS warmup_context producer↔consumer key contract (refactor_audit item 1). A typo in
## GameState._build_warmup_context would otherwise make IjfsEngine.run_daily silently read a default
## (null/empty) and that config would go dead with no error — the bug class that left exquisite intel
## dormant. IjfsEngine.unknown_warmup_keys flags any key the engine doesn't read; run_daily asserts it
## is empty.
extends GdUnitTestSuite


func test_real_producer_emits_only_known_keys() -> void:
	# The actual producer must not emit a single key the engine won't read (the real regression guard).
	var wc: Dictionary = GameState._build_warmup_context(1, -3, 4, {}, {}, "even", {}, [])
	assert_array(IjfsEngine.unknown_warmup_keys(wc)).is_empty()


func test_all_allowlisted_keys_are_accepted() -> void:
	var good: Dictionary = {}
	for key in IjfsEngine.WARMUP_CONTEXT_KEYS.keys():
		good[key] = true
	assert_array(IjfsEngine.unknown_warmup_keys(good)).is_empty()


func test_typo_key_is_flagged() -> void:
	# 'sead_enable' is a plausible typo for 'sead_enabled' — it must be reported.
	var bad: Dictionary = {"sead_enable": true, "x_day": 1}
	assert_array(IjfsEngine.unknown_warmup_keys(bad)).contains(["sead_enable"])
