# Run from the project root:
# godot --headless --path . -s res://tools/validate_skill_references.gd
extends SceneTree

# Fails when a skill cites a `.gd` path that does not exist.
#
# WHY SKILLS AND NOT JUST DOCS: a skill is the FIRST thing an agent reads for a task, and it is read as
# instruction rather than as description. `tools/validate_doc_anchors.gd` guards `docs/systems` only, so
# nothing watched the skills — and four of them spent an unknown period telling agents to consult
# `tools/validate_fixtures.gd`, a validator that had been deleted (fixture drift moved to a git-diff
# block in tools/run_all_tests.py). One of those was a triage row keyed on "`validate_fixtures.gd` red",
# an instruction to debug a state that can no longer occur.
#
# DELIBERATELY NARROW. A diff reviewer's objection to gating skills was that they are full of
# illustrative prose, and that is correct: the skills legitimately write `tools/validate_<thing>.gd`,
# `scripts/resolvers/<Phase>Resolver.gd`, `tools/export_llm_*.gd` and `tools/validate_*.gd`. So this
# checks ONE thing — a backticked, fully concrete `.gd` path — and skips any token carrying a glob or a
# placeholder. Measured against the tree at the time it was written: one hit, the real one, and no false
# positives. It does not check members, headings, links, or line citations; `validate_doc_anchors.gd`
# owns that job for the docs it covers.
#
# Prints PASS:/FAIL: for the gate's verdict.

const SKILLS_ROOT := "res://.claude/skills"
const CODE_PATH_PATTERN := "`((?:tools|scripts|tests)/[A-Za-z0-9_/.-]+\\.gd)`"

# A line saying a path is dead is not a dead reference — it is the record of one. Same escape-hatch
# convention validate_doc_anchors.gd uses, so there is one idiom to learn rather than two.
const ESCAPE_MARKERS := ["docs/archive", "(historical)"]

var _h := ValidatorHarness.new("skill references")


func _initialize() -> void:
	print("=== Skill references (every .gd path a skill cites exists) ===")

	var files := _markdown_files(SKILLS_ROOT)
	if files.is_empty():
		_h.fail("found no skill markdown under %s — the scan root is wrong, so this validator is checking nothing"
			% SKILLS_ROOT.trim_prefix("res://"))
		_h.finish(self)
		return

	var regex := RegEx.create_from_string(CODE_PATH_PATTERN)
	var checked := 0
	for path in files:
		checked += _check_file(path, regex)

	if checked == 0:
		_h.fail("scanned %d skill file(s) but matched no concrete `.gd` path at all — the pattern is broken, not the skills"
			% files.size())
	print("Scanned %d skill file(s), %d concrete .gd citation(s)." % [files.size(), checked])
	_h.finish(self)


## Returns how many concrete citations this file contributed, so _initialize can tell "everything is
## fine" apart from "the pattern stopped matching" — a distinction this validator would otherwise get
## wrong in the silent direction.
func _check_file(path: String, regex: RegEx) -> int:
	var text := FileAccess.get_file_as_string(path)
	var lines := text.split("\n")
	var checked := 0
	for index in range(lines.size()):
		var line := String(lines[index])
		if _is_escaped(line):
			continue
		for found in regex.search_all(line):
			var cited := found.get_string(1)
			if cited.contains("*") or cited.contains("<"):
				continue
			checked += 1
			if not FileAccess.file_exists("res://%s" % cited):
				_h.fail("%s:%d cites `%s`, which does not exist — a skill is read as instruction, so a dead path sends the next agent to a file that is not there"
					% [path.trim_prefix("res://"), index + 1, cited])
	return checked


func _is_escaped(line: String) -> bool:
	for marker in ESCAPE_MARKERS:
		if line.contains(marker):
			return true
	return false


func _markdown_files(root: String) -> Array[String]:
	var out: Array[String] = []
	var pending: Array[String] = [root]
	while not pending.is_empty():
		var dir_path: String = pending.pop_back()
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for sub in dir.get_directories():
			pending.append("%s/%s" % [dir_path, sub])
		for entry in dir.get_files():
			if entry.ends_with(".md"):
				out.append("%s/%s" % [dir_path, entry])
	out.sort()
	return out
