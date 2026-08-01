#!/usr/bin/env -S godot --headless -s
# Validates WHERE a direct mutation-authority call may appear (plan 0055; deny-by-default 0057).
#
# WHAT THIS OWNS — one half of the placement rule in docs/STATUS.md -> "Where a file goes":
#
#   1. Every directory under `scripts/` that contains GDScript must be CLASSIFIED here, and an
#      unclassified one FAILS. This is the deny-by-default half, added by plan 0057.
#   2. A directory classified FORBIDS must make ZERO direct authority calls.
#   3. Every file in the REQUIRES directory (`scripts/interleaved/`) must make AT LEAST ONE.
#   4. `scripts/` root is governed by an exact FILE allowlist, not a directory row. A root file that
#      is not named here FAILS.
#
# WHY DENY-BY-DEFAULT (plan 0057). Before it, this validator held an allow/deny LIST and anything
# unlisted was simply never scanned — including `scripts/` root, where 40 files sat making no claim
# at all. That is the same defect the role table exists to prevent: a directory that asserts nothing
# is a directory nothing can be wrong in. Adding rows for the new families and leaving the default
# open would have recreated it on the next family. So: classify or fail.
#
# WHY ROOT IS A FILE ALLOWLIST AND NOT A ROW. Of the four files left at root, `GameState.gd` and
# `GameData.gd` legitimately call authorities as the façade layer; `EventBus.gd` and
# `OffloadCalculator.gd` must not. A row saying "root may call authorities" would license any future
# root file to do so, which is exactly how the unpoliced root came about.
#
# SCOPED TO GDSCRIPT, DELIBERATELY (review finding, 2026-07-31). Rule 1 applies only to directories
# that actually contain a `.gd` file, directly or nested. A `scripts/shaders/` or a scratch directory
# holding no GDScript is not this validator's business, and failing for it would make the gate an
# obstacle for a reason this file has no opinion about. Nested directories inherit the nearest
# classified ancestor, so `scripts/model/ijfs/` needs no entry of its own.
#
# Rule 3 is not symmetry for its own sake. The failure mode it exists for is `AntishipResolver`,
# which became misplaced with NOBODY EDITING IT — plan 0044 deleted the seam elsewhere, and its
# directory's claim quietly stopped being true. A one-directional check lets that case walk through.
#
# WHAT THIS DOES NOT OWN — read this before trusting a green run:
#
#   * It sees DIRECT calls only. `IjfsResolver` calls `IjfsEngine.run_daily`, which calls an
#     authority; a file can therefore apply campaign state TRANSITIVELY and read as pure here.
#     Closing that needs call-graph analysis over a dynamically-typed language and is deliberately
#     not attempted. This is the single biggest blind spot and it is not small.
#   * It cannot see an application made by writing into a Dictionary or Array the file was HANDED.
#     That is not hypothetical: `scripts/OffloadCalculator.gd` writes `offload_progress_tons` into BN
#     dicts owned by `state.ship_reserve` and reads as clean here. It is why that file is FORBIDS at
#     root rather than living in `scripts/calc/`, and why plan 0058 exists. A green run does NOT mean
#     the FORBIDS directories apply nothing — only that they call no authority to do it.
#   * It cannot answer "does this apply at its own DRAW POINT?" — the actual test for
#     `scripts/interleaved/` membership. A file with one authority call passes rule 3 either way.
#   * It says nothing about whether a pure file is in the RIGHT non-applying directory.
#
# So: green here means "every GDScript directory is classified, no FORBIDS directory and no FORBIDS
# root file makes a direct authority call, and no interleaved file has gone inert". It does not mean
# placement is correct. The name is deliberately `validate_authority_call_placement`, not
# `validate_role_directories`, because a broader name is what would make the next agent trust it
# past that line.
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
# unify the existing strippers, to be revisited only on new evidence.
#
# Prints PASS:/FAIL: for the gate's verdict.
extends SceneTree

const MANIFEST := "res://tools/mutation_authority_manifest.json"
const SCRIPTS_ROOT := "res://scripts"

## A directory whose CLAIM in docs/STATUS.md is that it changes no campaign state. What is ENFORCED
## here is narrower and it matters: zero DIRECT authority calls. The two are not the same, and
## `scripts/ui/` and `scripts/api/` are the honest illustration — both route real state changes
## through the `GameState` façade (`GameController.gd` calls `GameState.resolve_turn()`,
## `LLMGameAPI.gd` calls `play_turn`/`begin_next_turn`), which is correct design and invisible here.
## So FORBIDS means "makes no direct authority call", never "applies nothing".
const FORBIDS := "FORBIDS"
## The directory whose claim REQUIRES applying: computes AND applies at its own draw point.
const REQUIRES := "REQUIRES"
## Ordering authority calls is this directory's job, so it may make as many as it likes.
const PERMITS := "PERMITS"

## Every directory under `scripts/` that holds GDScript. Unlisted => FAIL (deny-by-default).
const DIR_POLICY := {
	"calc": FORBIDS,
	"builders": FORBIDS,
	"loaders": FORBIDS,
	"model": FORBIDS,
	"transitions": FORBIDS,
	"ui": FORBIDS,
	"policies": FORBIDS,
	"api": FORBIDS,
	"support": FORBIDS,
	"interleaved": REQUIRES,
	"phases": PERMITS,
}

## The exact files permitted at `scripts/` root, and whether each may call an authority.
## Anything else at root => FAIL.
const ROOT_FILE_POLICY := {
	"GameState.gd": PERMITS,
	"GameData.gd": PERMITS,
	"EventBus.gd": FORBIDS,
	# Applies campaign state, but by writing a handed dict — invisible to this validator. Kept at
	# root and FORBIDS so it cannot additionally acquire an authority call. Leaves under plan 0058.
	"OffloadCalculator.gd": FORBIDS,
}

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

	var dirs_with_gd := _top_level_dirs_with_gd()
	var root_files := _root_gd_files()
	_failures.append_array(_classification_failures(dirs_with_gd, root_files))

	var checked_dirs := 0
	for dir_name in dirs_with_gd:
		if not DIR_POLICY.has(dir_name):
			continue
		checked_dirs += 1
		var policy := String(DIR_POLICY[dir_name])
		var dir_path := "%s/%s" % [SCRIPTS_ROOT, dir_name]
		for file_path in _gd_files(dir_path):
			var hits := _authority_calls(_strip(_read(file_path)), authorities)
			var violation := _policy_violation(policy, file_path, "scripts/%s/" % dir_name, hits)
			if violation != "":
				_failures.append(violation)

	for file_name in root_files:
		if not ROOT_FILE_POLICY.has(file_name):
			continue
		var root_path := "%s/%s" % [SCRIPTS_ROOT, file_name]
		var root_hits := _authority_calls(_strip(_read(root_path)), authorities)
		var root_violation := _policy_violation(
			String(ROOT_FILE_POLICY[file_name]), root_path, "scripts/ root", root_hits)
		if root_violation != "":
			_failures.append(root_violation)

	if _failures.is_empty():
		print("PASS: authority-call placement — %d authorities; %d GDScript directory(ies) all classified and clean; %d root file(s) allowlisted" % [
			authorities.size(), checked_dirs, root_files.size()])
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("FAIL: authority-call placement found %d issue(s)" % _failures.size())
	quit(1)


## The per-file verdict, as a pure function of (policy, hits) so the self-test can drive EVERY branch
## — including PERMITS — without a filesystem. `_initialize` calls exactly this for both directory
## files and root files, so the test cannot drift away from the enforced path. Returns "" when fine.
## (Extracted on a review finding, 2026-07-31: the previous PERMITS "test" only asserted a table
## value and never exercised the enforcement branch, so that branch could have drifted while the
## self-test stayed green.)
func _policy_violation(policy: String, file_path: String, home: String, hits: Array[String]) -> String:
	if policy == FORBIDS and not hits.is_empty():
		return "%s calls %s — %s must make NO direct authority call (docs/STATUS.md -> 'Where a file goes'). Move the file to scripts/interleaved/, or hoist the application into its caller." % [
			file_path, ", ".join(hits), home]
	if policy == REQUIRES and hits.is_empty():
		return "%s makes NO direct authority call — %s means 'computes AND applies at its own draw point'. If it stopped applying, move it to scripts/calc/; if it now applies through a helper, this validator cannot see that and the file needs a header note saying so." % [
			file_path, home]
	return ""


## The deny-by-default half, as a pure function of two name lists so the self-test can drive it
## without a fake filesystem. Returns one failure per unclassified directory, unlisted root file, and
## stale policy entry naming something that no longer exists.
func _classification_failures(dirs_with_gd: Array[String], root_files: Array[String]) -> Array[String]:
	var failures: Array[String] = []
	for dir_name in dirs_with_gd:
		if not DIR_POLICY.has(dir_name):
			failures.append("scripts/%s/ holds GDScript but is NOT classified in DIR_POLICY. Every directory under scripts/ must declare FORBIDS / REQUIRES / PERMITS — an unclassified directory is one nothing can be wrong in, which is the defect plan 0057 closed. Add it, and add its row to docs/STATUS.md -> 'Where a file goes'." % dir_name)
	for file_name in root_files:
		if not ROOT_FILE_POLICY.has(file_name):
			failures.append("scripts/%s is not in ROOT_FILE_POLICY. scripts/ root is an exact allowlist: the three autoload singletons plus OffloadCalculator (until plan 0058). A new file belongs in a role directory, not at root." % file_name)
	for dir_name_value in DIR_POLICY.keys():
		var dir_name := String(dir_name_value)
		if not dirs_with_gd.has(dir_name):
			failures.append("DIR_POLICY classifies scripts/%s/ but no such directory holds GDScript — the entry is stale (directory renamed or emptied?)." % dir_name)
	for file_name_value in ROOT_FILE_POLICY.keys():
		var file_name := String(file_name_value)
		if not root_files.has(file_name):
			failures.append("ROOT_FILE_POLICY allowlists scripts/%s but the file is not there — the entry is stale (moved or deleted?)." % file_name)
	return failures


## Top-level directory names under `scripts/` that contain at least one .gd, directly or nested.
## A directory with no GDScript is not this validator's business and is not returned.
func _top_level_dirs_with_gd() -> Array[String]:
	var names: Array[String] = []
	var dir := DirAccess.open(SCRIPTS_ROOT)
	if dir == null:
		return names
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if dir.current_is_dir() and not name.begins_with("."):
			if not _gd_files("%s/%s" % [SCRIPTS_ROOT, name]).is_empty():
				names.append(name)
		name = dir.get_next()
	dir.list_dir_end()
	names.sort()
	return names


func _root_gd_files() -> Array[String]:
	var names: Array[String] = []
	var dir := DirAccess.open(SCRIPTS_ROOT)
	if dir == null:
		return names
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".gd"):
			names.append(name)
		name = dir.get_next()
	dir.list_dir_end()
	names.sort()
	return names


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
	return _self_test_detector() and _self_test_classification()


func _self_test_detector() -> bool:
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


## The deny-by-default half needs its own cases: rule 1 and rule 4 are new failure modes, and a new
## failure mode that no case asserts is a validator whose green run proves less than it looks like.
func _self_test_classification() -> bool:
	var every_dir: Array[String] = []
	for key in DIR_POLICY.keys():
		every_dir.append(String(key))
	every_dir.sort()
	var every_root: Array[String] = []
	for key in ROOT_FILE_POLICY.keys():
		every_root.append(String(key))
	every_root.sort()

	# Baseline: exactly what the policy tables describe must produce no classification failure.
	if not _classification_failures(every_dir, every_root).is_empty():
		push_error("self-test: the policy tables disagree with themselves — a baseline built from DIR_POLICY/ROOT_FILE_POLICY should classify cleanly")
		return false

	# An unclassified directory holding GDScript FAILS.
	var with_stray := every_dir.duplicate()
	with_stray.append("not_a_registered_role")
	if _classification_failures(with_stray, every_root).size() != 1:
		push_error("self-test: an unclassified GDScript directory must produce exactly one failure")
		return false

	# An unlisted root file FAILS.
	var with_root_stray := every_root.duplicate()
	with_root_stray.append("SomethingNew.gd")
	if _classification_failures(every_dir, with_root_stray).size() != 1:
		push_error("self-test: an unlisted root .gd file must produce exactly one failure")
		return false

	# A classified directory that has vanished FAILS as a stale entry.
	var missing_dir := every_dir.duplicate()
	missing_dir.erase("calc")
	if _classification_failures(missing_dir, every_root).size() != 1:
		push_error("self-test: a DIR_POLICY entry naming a directory that holds no GDScript must fail as stale")
		return false

	# An allowlisted root file that has vanished FAILS as a stale entry.
	var missing_root := every_root.duplicate()
	missing_root.erase("EventBus.gd")
	if _classification_failures(every_dir, missing_root).size() != 1:
		push_error("self-test: a ROOT_FILE_POLICY entry naming an absent file must fail as stale")
		return false

	if String(ROOT_FILE_POLICY.get("GameState.gd", "")) != PERMITS:
		push_error("self-test: GameState.gd must be PERMITS — it is the order/lifecycle façade and calls authorities by design")
		return false
	return _self_test_policy_branches()


## Every branch of the enforced per-file verdict, driven through the same helper `_initialize` uses.
func _self_test_policy_branches() -> bool:
	var some: Array[String] = ["ForceTransitions"]
	var none: Array[String] = []
	var cases := [
		# [policy, hits, must_be_a_violation, why]
		[PERMITS, some, false, "a PERMITS file calling an authority is fine — this is GameState/GameData and scripts/phases/"],
		[PERMITS, none, false, "a PERMITS file calling nothing is fine — PERMITS never requires a call"],
		[FORBIDS, some, true, "a FORBIDS file calling an authority is the core finding"],
		[FORBIDS, none, false, "a FORBIDS file calling nothing is the normal case"],
		[REQUIRES, none, true, "a REQUIRES file that has gone inert — the AntishipResolver failure mode"],
		[REQUIRES, some, false, "a REQUIRES file still applying is the normal case"],
	]
	for case_value in cases:
		var case: Array = case_value
		var got := _policy_violation(String(case[0]), "res://scripts/x/Fixture.gd", "scripts/x/", case[1])
		if (got != "") != bool(case[2]):
			push_error("self-test: %s — expected violation=%s, got %s" % [
				String(case[3]), case[2], JSON.stringify(got)])
			return false
	return true
