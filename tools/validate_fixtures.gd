extends SceneTree

## Fixture-drift gate (refactor_audit item 8). Regenerates each committed docs/examples/*.json
## fixture IN MEMORY via LLMFixtures — the same builders the export tools use — and byte-compares
## (line-ending-normalized) against the committed copy. Fails loud when a fixture is stale, catching
## the silent rot that left llm_result_after_turn.json out of date through the 2026-06-29/30 balance
## work (the existing validate_llm_api only key-checks these fixtures; it never byte-compares them).
## Auto-picked-up by tools/run_all_tests.ps1.

var _failures: Array[String] = []


func _initialize() -> void:
	# Each LLMFixtures builder resets the scenario, so build order does not matter; capture the
	# observation string before build_result advances the turn.
	_check("res://docs/examples/llm_observation_red_turn1.json", JSON.stringify(LLMFixtures.build_observation("Red"), "\t"))
	_check("res://docs/examples/llm_result_after_turn.json", JSON.stringify(LLMFixtures.build_result(), "\t"))

	if _failures.is_empty():
		print("PASS: example fixtures match their regenerated output")
		quit(0)
		return

	print("FAIL: %d fixture(s) drifted from their generator:" % _failures.size())
	for f in _failures:
		print("  - %s" % f)
	print("  Fix: regenerate via tools/export_llm_observation.gd / tools/export_llm_result.gd to the")
	print("       docs/examples/ paths, confirm the diff is intended, and commit.")
	quit(1)


func _check(res_path: String, regenerated: String) -> void:
	if not FileAccess.file_exists(res_path):
		_failures.append("%s: committed fixture missing" % res_path)
		return
	var committed := FileAccess.get_file_as_string(res_path)
	if _normalize(committed) == _normalize(regenerated):
		return
	_failures.append("%s: committed != regenerated (%s)" % [res_path, _first_diff(_normalize(committed), _normalize(regenerated))])


func _normalize(s: String) -> String:
	return s.replace("\r\n", "\n").replace("\r", "\n")


func _first_diff(committed: String, regenerated: String) -> String:
	var lc := committed.split("\n")
	var lr := regenerated.split("\n")
	var n := mini(lc.size(), lr.size())
	for i in range(n):
		if lc[i] != lr[i]:
			return "first diff at line %d: committed='%s' regenerated='%s'" % [i + 1, lc[i].strip_edges(), lr[i].strip_edges()]
	if lc.size() != lr.size():
		return "line count differs: committed=%d regenerated=%d" % [lc.size(), lr.size()]
	return "content differs (no line-level diff found)"
