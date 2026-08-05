extends RefCounted
class_name ValidatorHarness

## Shared failure-collection + verdict boilerplate for the `tools/validate_*.gd` scripts.
##
## Before this existed, `_fail`, `_finish` and the `_assert_*` helpers were copy-pasted into
## almost every validator, differing only by a label string. A validator now holds one of these
## and calls into it; its domain checks stay in the validator itself.
##
## SCOPE — what this does NOT do: it does not make a validator harder to hang or crash. A script
## that fails to COMPILE never runs at all, this harness included; that hole is closed separately
## by `--quit-after` in tools/run_all_tests.py. This class is deduplication, nothing more.
##
## OUTPUT IS A CONTRACT. tools/run_all_tests.py decides pass/fail by scanning validator stdout for
## `^PASS` / `^FAIL` (and "SCRIPT ERROR"), so `finish()` reproduces the historical wording byte for
## byte. Do not reword it, and do not convert a validator whose own output deviates from it —
## preserving output beats converting everything.
##
## Names no autoload (GameData / GameState / EventBus) so it stays loadable from a bare
## `-s res://tools/...` SceneTree script.
##
## The per-assert message formats below are the MAJORITY formats found across the validators.
## A handful use different wording (e.g. validate_dos_consumption formats floats `%.2f`;
## validate_cleanup quotes strings; validate_headless_infrastructure's `_assert_true` fails with
## the bare label). Those must keep their local helpers until someone deliberately re-baselines
## them — converting them to this class would change their output.

var failures: Array[String] = []

var _label: String = ""
var _pass_suffix: String = ""


func _init(label: String, pass_suffix: String = "") -> void:
	_label = label
	_pass_suffix = pass_suffix


func fail(message: String) -> void:
	failures.append(message)
	push_error(message)


func check(condition: bool, message: String) -> void:
	if not condition:
		fail(message)


func equal_int(label: String, actual: int, expected: int) -> void:
	if actual != expected:
		fail("%s: expected %d, got %d" % [label, expected, actual])


func equal_float(label: String, actual: float, expected: float) -> void:
	if not is_equal_approx(actual, expected):
		fail("%s: expected %s, got %s" % [label, expected, actual])


func equal_string(label: String, actual: String, expected: String) -> void:
	if actual != expected:
		fail("%s: expected %s, got %s" % [label, expected, actual])


func is_true(label: String, value: bool) -> void:
	if not value:
		fail("%s: expected true" % label)


## Prints the verdict line the gate parses, then quits the tree: 0 on pass, 1 on failure.
## Optional pass_suffix appends to the PASS line only (e.g. " (seed=20260624)")
## to reproduce byte-identical output for validators that carry seed/turn metadata.
func finish(tree: SceneTree, pass_suffix: String = "") -> void:
	if failures.is_empty():
		print("PASS: %s succeeded%s" % [_label, pass_suffix if pass_suffix != "" else _pass_suffix])
		tree.quit(0)
		return
	print("FAIL: %s found %d issue(s):" % [_label, failures.size()])
	for failure in failures:
		print("  - %s" % failure)
	tree.quit(1)
