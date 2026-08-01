#!/usr/bin/env -S godot --headless -s
# Validates WHERE a direct mutation-authority call may appear (plan 0055).
#
# WHAT THIS OWNS — one half of the placement rule in docs/STATUS.md -> "Where a file goes":
#
#   1. A directory whose claim FORBIDS applying campaign state must make ZERO direct authority
#      calls. (`scripts/calc/`, `builders/`, `loaders/`, `model/`, `transitions/`.)
#   2. Every file in `scripts/interleaved/` must make AT LEAST ONE. That directory's whole claim is
#      "computes AND applies at its own draw point"; a file that stops applying no longer belongs
#      there and must be re-homed to `calc/`.
#
# Rule 2 is not symmetry for its own sake. The failure mode this validator exists for is
# `AntishipResolver`, which became misplaced with NOBODY EDITING IT — plan 0044 deleted the seam
# elsewhere, and its directory's claim quietly stopped being true. A one-directional check ("the
# forbidden directories are clean") lets that exact case walk straight through.
#
# WHAT THIS DOES NOT OWN — read this before trusting a green run:
#
#   * It sees DIRECT calls only. `IjfsResolver` calls `IjfsEngine.run_daily`, which calls an
#     authority; a file can therefore apply campaign state TRANSITIVELY and read as pure here.
#     Closing that needs call-graph analysis over a dynamically-typed language and is deliberately
#     not attempted. This is the single biggest blind spot and it is not small.
#   * It cannot answer "does this apply at its own DRAW POINT?" — the actual test for
#     `scripts/interleaved/` membership. That needs knowing whether deferral changes the dice, which
#     is a human judgement. A file with one authority call passes rule 2 whether or not it belongs.
#   * It does not check `scripts/phases/`, which may call authorities freely (ordering them is the
#     job) and is not required to.
#   * It says nothing about whether a pure file is in the RIGHT non-applying directory.
#
# So: green here means "no forbidden directory makes a direct authority call, and no interleaved
# file has gone inert". It does not mean placement is correct. The name is deliberately
# `validate_authority_call_placement`, not `validate_role_directories`, because a broader name is
# what would make the next agent trust it past that line.
#
# The authority list is derived from `tools/mutation_authority_manifest.json` (`authority_path` per
# aggregate), never from a hard-coded `[A-Za-z]+Transitions` regex — the manifest is the single home
# for that list, and a regex would be a second one that drifts silently when an authority is renamed.
#
# Scans source as TEXT and names no `class_name`, so it stays clear of the tool-script compile
# closure that plan 0040 hit.
#
# It carries its own comment/string stripper, which makes a fifth copy in the repo. That is
# deliberate and already adjudicated: docs/plans/BACKLOG.md records the 2026-07-26 decision NOT to
# unify the existing strippers, to be revisited only on new evidence. Adding a fifth follows that
# decision rather than violating it.
#
# Prints PASS:/FAIL: for the gate's verdict.
extends SceneTree

const MANIFEST := "res://tools/mutation_authority_manifest.json"

## Directories whose claim forbids changing campaign state by ANY route. A direct authority call
## here is a finding.
const FORBIDDEN_DIRS := [
	"res://scripts/calc",
	"res://scripts/builders",
	"res://scripts/loaders",
	"res://scripts/model",
	"res://scripts/transitions",
]

## The directory whose claim REQUIRES applying. Every file here must make at least one call.
const REQUIRED_DIR := "res://scripts/interleaved"

var _failures: Array[String] = []


func _initialize() -> void:
	if not _self_test():
		print("FAIL: authority-call-placement self-test failed — the detector is broken, so a green run would prove nothing")
		quit(1)
		return

	var authorities := _authority_class_names()
	if authorities.is_empty():
		print("FAIL: no authority_path entries found in %s — cannot check placement" % MANIFEST)
		quit(1)
		return

	for dir_path in FORBIDDEN_DIRS:
		for file_path in _gd_files(dir_path):
			var hits := _authority_calls(_strip(_read(file_path)), authorities)
			if not hits.is_empty():
				_failures.append("%s calls %s — this directory applies NO campaign state (docs/STATUS.md -> 'Where a file goes'). Move the file to %s, or hoist the application into its caller." % [
					file_path, ", ".join(hits), REQUIRED_DIR.trim_prefix("res://")])

	var interleaved := _gd_files(REQUIRED_DIR)
	if interleaved.is_empty():
		_failures.append("%s holds no .gd files — either the directory was emptied without updating this validator, or the path is wrong" % REQUIRED_DIR)
	for file_path in interleaved:
		if _authority_calls(_strip(_read(file_path)), authorities).is_empty():
			_failures.append("%s makes NO direct authority call — %s means 'computes AND applies at its own draw point'. If it stopped applying, move it to scripts/calc/; if it now applies through a helper, this validator cannot see that and the file needs a header note saying so." % [
				file_path, REQUIRED_DIR.trim_prefix("res://")])

	if _failures.is_empty():
		print("PASS: authority-call placement — %d authorities, %d forbidden directories clean, %d interleaved file(s) all still applying" % [
			authorities.size(), FORBIDDEN_DIRS.size(), interleaved.size()])
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("FAIL: authority-call placement found %d issue(s)" % _failures.size())
	quit(1)


## The `class_name` of every registered mutation authority, derived from the manifest's
## authority_path values ("res://scripts/transitions/ForceTransitions.gd" -> "ForceTransitions").
func _authority_class_names() -> Array[String]:
	var text := _read(MANIFEST)
	if text == "":
		return []
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return []
	var names: Array[String] = []
	for aggregate in (parsed as Dictionary).get("aggregates", []):
		if not (aggregate is Dictionary):
			continue
		var path := String((aggregate as Dictionary).get("authority_path", ""))
		if path == "":
			continue
		var class_id := path.get_file().trim_suffix(".gd")
		if class_id != "" and not names.has(class_id):
			names.append(class_id)
	return names


## Every `<Authority>.<method>(` named in already-stripped source, de-duplicated.
func _authority_calls(stripped: String, authorities: Array[String]) -> Array[String]:
	var found: Array[String] = []
	for authority in authorities:
		var regex := RegEx.new()
		# The word boundary matters: without it `MyForceTransitions` would match `ForceTransitions`.
		regex.compile("(?<![A-Za-z0-9_])%s\\.[a-z_][a-z0-9_]*\\s*\\(" % authority)
		if regex.search(stripped) != null and not found.has(authority):
			found.append(authority)
	return found


## Remove `#` comments and string literals so that header prose and error messages naming an
## authority do not read as calls. Without this, `scripts/calc/` alone produces ten false hits from
## `##` documentation that legitimately names the authority a file's caller uses.
func _strip(source: String) -> String:
	var out := ""
	var in_string := false
	var quote := ""
	var i := 0
	while i < source.length():
		var ch := source[i]
		if in_string:
			if ch == "\\":
				i += 2
				continue
			if ch == quote:
				in_string = false
			elif ch == "\n":
				# An unterminated literal must not swallow the rest of the file.
				in_string = false
				out += ch
			i += 1
			continue
		if ch == "\"" or ch == "'":
			in_string = true
			quote = ch
			i += 1
			continue
		if ch == "#":
			while i < source.length() and source[i] != "\n":
				i += 1
			continue
		out += ch
		i += 1
	return out


## RECURSIVE, deliberately: a nested directory inherits its parent's claim. `scripts/model/ijfs/`
## exists and holds five files; a non-recursive scan would report `scripts/model/` clean while never
## opening them, which is the "green means nothing was checked" failure this validator is supposed to
## be the answer to.
func _gd_files(dir_path: String) -> Array[String]:
	var files: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return files
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if dir.current_is_dir():
			if not name.begins_with("."):
				files.append_array(_gd_files("%s/%s" % [dir_path, name]))
		elif name.ends_with(".gd"):
			files.append("%s/%s" % [dir_path, name])
		name = dir.get_next()
	dir.list_dir_end()
	files.sort()
	return files


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


## The detector proves itself before it is trusted — a validator whose pin never matched anything
## has already shipped here and passed for weeks. Each case asserts the exact confusion that would
## otherwise make a green run meaningless.
func _self_test() -> bool:
	var authorities: Array[String] = ["ForceTransitions", "IjfsTransitions"]
	var cases := [
		# [source, must_be_detected, why]
		["ForceTransitions.apply_activity(brigade)", true, "a plain call"],
		["\tvar n := ForceTransitions.latch_prior_activity(brigades)", true, "an assigned call"],
		["ForceTransitions.apply_activity (brigade)", true, "space before the paren"],
		["## calls ForceTransitions.apply_activity() every turn", false, "a `##` header comment"],
		["\t# ForceTransitions.apply_activity(b)", false, "an indented `#` comment"],
		["push_error(\"ForceTransitions.apply_activity refused\")", false, "an authority named inside a string"],
		["var s := 'IjfsTransitions.retire_target('", false, "a single-quoted string"],
		["MyForceTransitions.apply_activity(b)", false, "a longer identifier ENDING in an authority name"],
		["ForceTransitions.CONSTANT", false, "a constant read, not a call"],
		["var x := \"unterminated\nForceTransitions.apply_activity(b)", true, "a call after an unterminated literal"],
	]
	for case_value in cases:
		var case: Array = case_value
		var detected := not _authority_calls(_strip(String(case[0])), authorities).is_empty()
		if detected != bool(case[1]):
			push_error("self-test: %s — expected detected=%s, got %s for source %s" % [
				String(case[2]), case[1], detected, JSON.stringify(case[0])])
			return false
	return true
