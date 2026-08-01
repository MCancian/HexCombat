# Run from the project root:
# godot --headless --path . -s res://tools/validate_plan_docs.gd
extends SceneTree

## Keeps the two plan-tracking indexes cheap to scan, which is what both files promise in their own
## headers and neither delivered before 2026-08-01: BACKLOG.md's documented
## `grep '^- \[ \]'` returned wrapped fragments for 20 of 21 items, and README.md's "index, not
## reading material" table held rows up to 1328 characters.
##
## The budgets below are the CONTRACT. The self-test pins them with literal 120/121 and 200/201
## rather than reading these constants, deliberately: a test built from the same constant it is
## checking cannot notice the constant moving.
const MAX_BACKLOG_LINE := 120
const MAX_README_ROW := 200

var _failures: Array[String] = []

func _initialize() -> void:
	_self_test()
	_check_backlog()
	_check_readme()
	
	if _failures.is_empty():
		print("PASS: plan docs validated")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("FAIL: plan doc validation found %d issue(s)" % _failures.size())
		quit(1)


func _check_backlog_line(line: String, line_no: int, is_standing_limits: bool) -> void:
	if not line.begins_with("- [ ]"):
		return
	if is_standing_limits:
		_failures.append("BACKLOG.md:%d: checkbox in 'Standing limits & blocked' section" % line_no)
	if line.length() > MAX_BACKLOG_LINE:
		_failures.append("BACKLOG.md:%d: checkbox line too long (%d > %d)" % [line_no, line.length(), MAX_BACKLOG_LINE])
	if not (line.ends_with(".") or line.ends_with(".**")):
		_failures.append("BACKLOG.md:%d: checkbox line does not end in '.' or '.**' — was '%s'" % [line_no, line])


func _check_readme_line(line: String, line_no: int) -> void:
	if line.begins_with("| 00"):
		if line.length() > MAX_README_ROW:
			_failures.append("README.md:%d: plan row too long (%d > %d)" % [line_no, line.length(), MAX_README_ROW])


## Runs one check in isolation and returns only what IT produced, leaving _failures untouched.
## The previous version mutated _failures and rewound with resize(), which made every assertion a
## count comparison — so a case could pass by tripping a DIFFERENT check than the one under test.
func _capture(case: Callable) -> Array[String]:
	var saved: Array[String] = _failures.duplicate()
	_failures.clear()
	case.call()
	var produced: Array[String] = _failures.duplicate()
	_failures.clear()
	_failures.append_array(saved)
	return produced


func _expect_clean(label: String, produced: Array[String]) -> void:
	if not produced.is_empty():
		_failures.append("SELF-TEST %s: expected no failure, got '%s'" % [label, produced[0]])


## Asserts a failure was produced AND that it is the expected one. Matching the message is the
## point: counting alone lets a case pass for the wrong reason.
func _expect_failure(label: String, produced: Array[String], expected: String) -> void:
	if produced.is_empty():
		_failures.append("SELF-TEST %s: expected a failure containing '%s', got none" % [label, expected])
		return
	for failure in produced:
		if failure.contains(expected):
			return
	_failures.append("SELF-TEST %s: expected a failure containing '%s', got '%s'" % [label, expected, produced[0]])


## Exactly `n` characters, ending in '.' so only the length rule can trip.
func _backlog_line_of_length(n: int) -> String:
	var prefix := "- [ ] "
	return prefix + "A".repeat(n - prefix.length() - 1) + "."


## Exactly `n` characters, beginning '| 00' so the row rule applies.
func _readme_row_of_length(n: int) -> String:
	var prefix := "| 0011 | "
	return prefix + "A".repeat(n - prefix.length())


func _self_test() -> void:
	# --- BACKLOG: lines that must PASS ---
	_expect_clean("backlog/short", _capture(
		func() -> void: _check_backlog_line("- [ ] Very short.", 1, false)))
	_expect_clean("backlog/bold-close", _capture(
		func() -> void: _check_backlog_line("- [ ] **A bolded headline.**", 2, false)))
	_expect_clean("backlog/not-a-checkbox", _capture(
		func() -> void: _check_backlog_line("- a plain bullet, no checkbox", 3, false)))
	# The budget itself must be allowed — the old test never checked the passing side of the boundary.
	var at_limit := _backlog_line_of_length(120)
	if at_limit.length() != 120:
		_failures.append("SELF-TEST backlog/at-limit: fixture is %d chars, expected 120" % at_limit.length())
	_expect_clean("backlog/at-limit", _capture(
		func() -> void: _check_backlog_line(at_limit, 4, false)))

	# --- BACKLOG: lines that must FAIL, each for its own stated reason ---
	# One character over, not seven: a fixture that overshoots would still be rejected by a
	# validator whose limit had drifted, and would prove nothing about 120.
	var over_limit := _backlog_line_of_length(121)
	if over_limit.length() != 121:
		_failures.append("SELF-TEST backlog/over-limit: fixture is %d chars, expected 121" % over_limit.length())
	_expect_failure("backlog/over-limit", _capture(
		func() -> void: _check_backlog_line(over_limit, 5, false)), "too long")
	_expect_failure("backlog/no-period", _capture(
		func() -> void: _check_backlog_line("- [ ] Missing period", 6, false)), "does not end in")
	_expect_failure("backlog/standing-limits", _capture(
		func() -> void: _check_backlog_line("- [ ] Checkbox in standing limits.", 7, true)), "Standing limits")

	# --- README ---
	_expect_clean("readme/other-table-row", _capture(
		func() -> void: _check_readme_line("| Bundle | Items | Why together |", 8)))
	var row_at_limit := _readme_row_of_length(200)
	if row_at_limit.length() != 200:
		_failures.append("SELF-TEST readme/at-limit: fixture is %d chars, expected 200" % row_at_limit.length())
	_expect_clean("readme/at-limit", _capture(
		func() -> void: _check_readme_line(row_at_limit, 9)))
	var row_over_limit := _readme_row_of_length(201)
	if row_over_limit.length() != 201:
		_failures.append("SELF-TEST readme/over-limit: fixture is %d chars, expected 201" % row_over_limit.length())
	_expect_failure("readme/over-limit", _capture(
		func() -> void: _check_readme_line(row_over_limit, 10)), "too long")


func _check_backlog() -> void:
	var path := "res://docs/plans/BACKLOG.md"
	if not FileAccess.file_exists(path):
		_failures.append("BACKLOG.md not found")
		return
	var text := FileAccess.get_file_as_string(path)
	var lines := text.split("\n")
	var in_standing_limits := false
	for i in range(lines.size()):
		var line := lines[i]
		if line.begins_with("## Standing limits & blocked"):
			in_standing_limits = true
		elif line.begins_with("## "):
			in_standing_limits = false
		_check_backlog_line(line, i + 1, in_standing_limits)


func _check_readme() -> void:
	var path := "res://docs/plans/README.md"
	if not FileAccess.file_exists(path):
		_failures.append("README.md not found")
		return
	var text := FileAccess.get_file_as_string(path)
	var lines := text.split("\n")
	for i in range(lines.size()):
		_check_readme_line(lines[i], i + 1)
