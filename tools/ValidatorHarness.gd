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
## OUTPUT IS A CONTRACT (But With Measured Latitude). tools/run_all_tests.py decides pass/fail by
## scanning validator stdout for `(?m)^PASS\b|^PASS:` and `(?m)^FAIL\b|^FAIL:`. Thus, the hard
## constraint is the column-0 marker prefix. You can safely add custom metrics or wording to the
## body of the PASS string using `pass_body`/`fail_header`. However, you MUST preserve the exact
## wording of any strings cited in the archives (e.g. docs/archive/0045 mutation-authority PASS,
## 0056 metric-ceilings prefix).
##
## MANGING GUARD: If you ever bulk-rename this class's properties (e.g. `failures`), use word
## boundaries (`\bfailures\b`) and run `grep -rn '_failh\|_capture_h\.' tools/` afterward to
## prove you didn't accidentally mangle a local variable or function name like `_capture_failures`.
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
var pass_body: Callable
var fail_header: Callable


func _init(label: String) -> void:
	_label = label


func collect(message: String) -> void:
	failures.append(message)


func fail(message: String) -> void:
	collect(message)
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
		var msg: String = pass_body.call() as String if pass_body.is_valid() else ("%s succeeded%s" % [_label, pass_suffix])
		print("PASS: %s" % msg)
		tree.quit(0)
		return
	if fail_header.is_valid():
		print("FAIL: %s" % (fail_header.call() as String))
	else:
		print("FAIL: %s found %d issue(s):" % [_label, failures.size()])
	for failure in failures:
		print("  - %s" % failure)
	tree.quit(1)
