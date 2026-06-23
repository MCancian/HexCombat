extends GdUnitTestSuite

## Minimal smoke test confirming GdUnit4 is installed and the headless
## CLI runner reports exit codes. Real suites live alongside the code they cover.

func test_framework_runs() -> void:
	assert_int(2 + 2).is_equal(4)
	assert_str("hex").is_equal("hex")
