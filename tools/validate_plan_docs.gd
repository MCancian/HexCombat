# Run from the project root:
# godot --headless --path . -s res://tools/validate_plan_docs.gd
extends SceneTree

## Keeps the three plan-tracking indexes cheap to scan, which is what both files promise in their own
## headers and neither delivered before 2026-08-01: BACKLOG.md's documented
## `grep '^- \[ \]'` returned wrapped fragments for 20 of 21 items, and README.md's "index, not
## reading material" table held rows up to 1328 characters.
##
## Since 2026-08-02 it also requires every ACTIVE plan to carry a `## Golden-pin budget` heading whose
## first line names the validators it will re-baseline (or `none`). This is plan-0056's re-baseline
## lesson made structurally impossible: five separate re-baselines were each measured one validator at
## a time, when a plan that states "expect N re-baselines, one per stage; measure X and Y together"
## lets an agent batch the measurement. The heading is the contract; the validators named are free
## text, because only the plan author knows which goldens its mechanics move.
##
## Since 2026-08-03 it also enforces docs/DECISIONS.md's own "3–5 lines" header promise: every entry
## dated after DECISIONS_GRANDFATHER_DATE must be at most MAX_DECISIONS_ENTRY_LINES (bullet + non-blank
## continuation lines). The cutoff is load-bearing and deliberate: measured 2026-08-03, 76 of 94
## historical entries exceed 5 lines, so the file's past is exempt BY DESIGN (DECISIONS is append-only)
## and this check is strictly forward-looking. Do not lower the cutoff to "help" clean history — an
## entry over the cap belongs in a canonical home (STATUS, a validator PASS line, a system doc,
## hexcombat-failure-archaeology) with only what/who/pointer in DECISIONS.
##
## The budgets below are the CONTRACT. The self-test pins them with literal 120/121 and 200/201 —
## and pins the placeholder with its literal text — rather than reading these constants,
## deliberately: a test built from the same constant it is checking cannot notice the constant moving.
const MAX_BACKLOG_LINE := 120
const MAX_README_ROW := 200
const MAX_DECISIONS_ENTRY_LINES := 5
const DECISIONS_GRANDFATHER_DATE := "2026-08-03"

var _failures: Array[String] = []

func _initialize() -> void:
	_self_test()
	_check_backlog()
	_check_readme()
	_check_decisions()
	_check_plans()
	
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

	# --- Golden-pin budget: cases that must PASS ---
	_expect_clean("golden/none-decl", _capture(
		func() -> void: _check_plan_golden_budget_content("## Golden-pin budget\nnone", "plan")))
	_expect_clean("golden/named-decl", _capture(
		func() -> void: _check_plan_golden_budget_content(
			"## Golden-pin budget\nvalidate_golden_victory and validate_cleanup", "plan")))
	# A blank line after the heading is allowed — the declaration is the next non-empty line.
	_expect_clean("golden/blank-then-decl", _capture(
		func() -> void: _check_plan_golden_budget_content("## Golden-pin budget\n\nnone", "plan")))

	# --- Golden-pin budget: cases that must FAIL, each for its own stated reason ---
	_expect_failure("golden/missing", _capture(
		func() -> void: _check_plan_golden_budget_content("## Scope\nno budget here", "plan")), "missing")
	_expect_failure("golden/empty", _capture(
		func() -> void: _check_plan_golden_budget_content("## Golden-pin budget\n\n", "plan")), "no declaration")
	_expect_failure("golden/eof", _capture(
		func() -> void: _check_plan_golden_budget_content("## Golden-pin budget", "plan")), "no declaration")
	# The placeholder is spelled out, not formatted from GOLDEN_BUDGET_PLACEHOLDER: a test built from
	# the same constant it is checking cannot notice the constant moving out from under the docs.
	_expect_failure("golden/placeholder", _capture(
		func() -> void: _check_plan_golden_budget_content(
			"## Golden-pin budget\n<none — name the validators you will re-baseline>", "plan")), "placeholder")

	# --- DECISIONS: cases that must PASS ---
	# Exactly at the 5-line cap: bullet + four indented continuations.
	_expect_clean("decisions/short", _capture(
		func() -> void: _check_decisions_text("---\n- **2026-08-04 — Short.\n  a\n  b\n  c\n  d\n")))
	# Date on or before the grandfather cutoff is exempt however long it is — measured 2026-08-03,
	# 76 of 94 historical entries exceed the cap, and DECISIONS is append-only.
	_expect_clean("decisions/grandfathered", _capture(
		func() -> void: _check_decisions_text(
			"---\n- **2026-08-03 — Old.\n  a\n  b\n  c\n  d\n  e\n  f\n  g\n")))
	# A blank line between entries is not a continuation of the entry above it.
	_expect_clean("decisions/blank-between", _capture(
		func() -> void: _check_decisions_text(
			"---\n- **2026-08-04 — A.\n  a\n  b\n  c\n\n- **2026-08-04 — B.\n  d\n")))
	# Anything before the single '---' separator is the preamble and is skipped — a bullet-looking
	# line in it must not be treated as an entry.
	_expect_clean("decisions/preamble-skipped", _capture(
		func() -> void: _check_decisions_text(
			"## Decided\n- **2020-01-01 — Fake.\n---\n- **2026-08-04 — Real.\n")))

	# --- DECISIONS: cases that must FAIL, each for its own stated reason ---
	# One over the cap, with the message naming the count: counting alone lets a case pass for the
	# wrong reason.
	_expect_failure("decisions/over-limit", _capture(
		func() -> void: _check_decisions_text("---\n- **2026-08-04 — Long.\n  a\n  b\n  c\n  d\n  e\n")),
		"is 6 lines")
	_expect_failure("decisions/no-separator", _capture(
		func() -> void: _check_decisions_text("- **2026-08-04 — A.\n")), "preamble separator")
	_expect_failure("decisions/no-entries", _capture(
		func() -> void: _check_decisions_text("---\n")), "no entries found")


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


## Enforces the "3–5 lines" promise in docs/DECISIONS.md's own header for entries dated after
## DECISIONS_GRANDFATHER_DATE. Everything before the single `---` preamble separator is skipped
## (its "Fact type | Only home" table is not an entry). An entry is its bullet plus the non-blank
## continuation lines up to the next entry bullet or EOF; blank lines between entries never count.
func _check_decisions() -> void:
	var path := "res://docs/DECISIONS.md"
	if not FileAccess.file_exists(path):
		_failures.append("DECISIONS.md not found")
		return
	_check_decisions_text(FileAccess.get_file_as_string(path))


func _check_decisions_text(text: String) -> void:
	var lines := text.split("\n")
	var body_start := -1
	for i in range(lines.size()):
		if lines[i].strip_edges() == "---":
			body_start = i + 1
			break
	if body_start == -1:
		_failures.append("DECISIONS.md: no '---' preamble separator found")
		return
	var first_entry := -1
	for i in range(body_start, lines.size()):
		if not _decisions_entry_date(lines[i]).is_empty():
			first_entry = i
			break
	if first_entry == -1:
		_failures.append("DECISIONS.md: no entries found after the preamble separator")
		return
	var i := first_entry
	while i < lines.size():
		var date := _decisions_entry_date(lines[i])
		var block_end := i + 1
		while block_end < lines.size() and _decisions_entry_date(lines[block_end]).is_empty():
			block_end += 1
		var count := 0
		for j in range(i, block_end):
			if not lines[j].strip_edges().is_empty():
				count += 1
		if not date.is_empty() and date > DECISIONS_GRANDFATHER_DATE and count > MAX_DECISIONS_ENTRY_LINES:
			_failures.append("DECISIONS.md:%d: %s entry is %d lines (> %d)" % [
				i + 1, date, count, MAX_DECISIONS_ENTRY_LINES])
		i = block_end


## Returns the bullet's ISO date (`2026-08-03` in `- **2026-08-03 — text`) or "" if the line is not
## an entry bullet. Non-bullet lines always return "" so they read as continuation content.
func _decisions_entry_date(line: String) -> String:
	if not line.begins_with("- **20"):
		return ""
	var date := line.substr(4, 10)
	if date.length() != 10 or date[4] != "-" or date[7] != "-":
		return ""
	return date


var GOLDEN_BUDGET_HEADING := "## Golden-pin budget"


func _check_plans() -> void:
	var dir := DirAccess.open("res://docs/plans/")
	if dir == null:
		_failures.append("docs/plans/ not openable")
		return
	var seen_any := false
	for file in dir.get_files():
		if not file.ends_with(".md"):
			continue
		if file == "README.md" or file == "ARCHIVE.md" or file == "BACKLOG.md":
			continue
		seen_any = true
		_check_plan_golden_budget("res://docs/plans/" + file, file)
	if not seen_any:
		_failures.append("docs/plans/: no active plan docs found to check")


## A plan doc fails if the `## Golden-pin budget` heading is missing, is bare (no line beneath it
## declaring which validators get re-baselined), or its declaration line is the placeholder.
func _check_plan_golden_budget(path: String, label: String) -> void:
	if not FileAccess.file_exists(path):
		return
	_check_plan_golden_budget_content(FileAccess.get_file_as_string(path), label)


func _check_plan_golden_budget_content(text: String, label: String) -> void:
	var lines := text.split("\n")
	var heading_no := -1
	for i in range(lines.size()):
		if lines[i].strip_edges() == GOLDEN_BUDGET_HEADING:
			heading_no = i
			break
	if heading_no == -1:
		_failures.append("%s: missing '## Golden-pin budget' heading (name the validators it re-baselines, or 'none')" % label)
		return
	var decl := ""
	for i in range(heading_no + 1, lines.size()):
		var candidate := lines[i].strip_edges()
		if not candidate.is_empty():
			decl = candidate
			break
	if decl.is_empty():
		_failures.append("%s: '## Golden-pin budget' heading has no declaration line beneath it" % label)
		return
	if decl == GOLDEN_BUDGET_PLACEHOLDER:
		_failures.append("%s: '## Golden-pin budget' still uses the placeholder '%s'" % [label, GOLDEN_BUDGET_PLACEHOLDER])


const GOLDEN_BUDGET_PLACEHOLDER := "<none — name the validators you will re-baseline>"
