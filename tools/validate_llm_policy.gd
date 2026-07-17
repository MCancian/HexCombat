# Deterministic gate for the LLM-player adapter PLUMBING (B6) — no network, no model.
# Run:
#   godot --headless --path . -s res://tools/validate_llm_policy.gd
#
# Exercises scripts/LLMPolicy.gd against the network-free stub sidecar
# (tools/llm_sidecar_stub.py), plus direct unit checks of its parse/strip helpers. This gates the
# marshalling contract (observation -> sidecar -> actions), the malformed-output fallback, and the
# obs/action log WITHOUT contacting a real LLM, so it stays green inside run_all_tests.ps1. The
# nondeterministic live path (a real model) is verified separately by tools/run_selfplay_game.gd.
extends SceneTree

const STUB := "res://tools/llm_sidecar_stub.py"

var _failures: Array[String] = []


func _initialize() -> void:
	print("=== LLM policy plumbing validation (stub sidecar, no network) ===")

	get_root().get_node("GameData").load_all()
	get_root().get_node("GameState").reset_to_scenario()

	_check_helpers()
	_check_stub_modes()

	_finish()


## Direct unit checks of LLMPolicy's parse/strip helpers (underscore = convention, still callable).
func _check_helpers() -> void:
	var p := LLMPolicy.for_seat("Red")

	# end_turn is stripped; the runner owns turn resolution + its seed.
	var stripped: Array = p._strip_end_turn([
		{"type": "move", "team": "Red", "brigade_id": "X", "target_hex": "h", "mode": "tactical"},
		{"type": "end_turn", "seed": 1},
	])
	if stripped.size() != 1 or String((stripped[0] as Dictionary).get("type", "")) != "move":
		_fail("_strip_end_turn did not drop the end_turn action: %s" % str(stripped))

	# Parse: bare array, {"actions": [...]}, empty, and unparseable -> null.
	if not (p._parse_actions("[]") is Array and (p._parse_actions("[]") as Array).is_empty()):
		_fail("_parse_actions('[]') should be an empty array")
	var wrapped = p._parse_actions('{"actions": [{"type": "move"}]}')
	if not (wrapped is Array and (wrapped as Array).size() == 1):
		_fail("_parse_actions did not unwrap {actions:[...]}: %s" % str(wrapped))
	if p._parse_actions("not json at all") != null:
		_fail("_parse_actions of garbage should be null")
	if not (p._parse_actions("   ") is Array):
		_fail("_parse_actions of whitespace should be an empty array")


## End-to-end through the stub sidecar for each HEXCOMBAT_STUB_MODE. Uses the Green (ROC) seat:
## at scenario reset Red (PLA) is amphibious-in-reserve with zero legal moves, so Green is the seat
## that actually has a legal move to round-trip.
func _check_stub_modes() -> void:
	var log_path := OS.get_cache_dir().path_join("hexcombat_llm_policy_gate.jsonl")
	var seat := "Green"

	# first_move: exactly one LEGAL move for a Green brigade + a log line written.
	_set_mode("first_move")
	_delete_file(log_path)
	var obs: Dictionary = LLMGameAPI.observation(seat)
	var actions := _run_seat(seat, log_path)
	if actions.size() != 1:
		_fail("first_move: expected 1 action, got %d" % actions.size())
	elif not _is_legal_move(actions[0], obs):
		_fail("first_move: action is not a legal move: %s" % str(actions[0]))
	if _count_lines(log_path) != 1:
		_fail("first_move: expected exactly 1 JSONL log line, got %d" % _count_lines(log_path))

	# empty: sidecar returns [] -> policy returns [].
	_set_mode("empty")
	if not _run_seat(seat, "").is_empty():
		_fail("empty mode should yield no actions")

	# garbage: unparseable stdout -> policy falls back to [].
	_set_mode("garbage")
	if not _run_seat(seat, "").is_empty():
		_fail("garbage mode should fall back to no actions")

	_delete_file(log_path)


func _run_seat(seat: String, log_path: String) -> Array:
	var p := LLMPolicy.for_seat(seat, log_path)
	p.sidecar_path = STUB
	return p.build_actions(LLMGameAPI.observation(seat))


func _is_legal_move(action: Variant, obs: Dictionary) -> bool:
	if not (action is Dictionary):
		return false
	var a: Dictionary = action
	if String(a.get("type", "")) != "move":
		return false
	var bid := String(a.get("brigade_id", ""))
	var legal_moves: Dictionary = obs.get("legal_moves", {})
	if not legal_moves.has(bid):
		return false
	var mode := String(a.get("mode", ""))
	var targets: Array = (legal_moves[bid] as Dictionary).get(mode, [])
	return targets.has(String(a.get("target_hex", "")))


func _set_mode(mode: String) -> void:
	OS.set_environment("HEXCOMBAT_STUB_MODE", mode)


func _delete_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _count_lines(path: String) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var text := FileAccess.get_file_as_string(path).strip_edges()
	if text.is_empty():
		return 0
	return text.split("\n").size()


func _fail(message: String) -> void:
	_failures.append(message)
	push_error(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: LLM policy plumbing validation succeeded (stub sidecar, no network)")
		quit(0)
		return
	print("FAIL: LLM policy plumbing validation found %d issue(s):" % _failures.size())
	for failure in _failures:
		print("  - %s" % failure)
	quit(1)
