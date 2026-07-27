# Run from the project root:
# godot --headless --path . -s res://tools/validate_combat_rules_threading.gd
extends SceneTree

# Guards the hand-maintained correspondence between the combat-rules data bag and the ONE function
# that fills it (plan 0040, option (c)).
#
# THE FAILURE THIS CATCHES: the rules class is a flat bag of 26 fields, each with a declared default,
# and the turn conductor assigns all 26 by hand — 22 of them straight off the game-data autoload. Add
# a field and forget the assignment line and the field keeps its DECLARED default. Combat still runs,
# every gate stays green, and the new knob does nothing. Nothing in the tree noticed. This is the same
# shape as the bug family plans 0034/0037 closed: two hand-kept lists with no gate on completeness.
#
# WHY TEXT, NOT REFLECTION: get_property_list() on a Resource also returns engine properties, and it
# cannot see whether an assignment EXISTS — only what the object ended up holding. The bug is a
# missing line of source, so source is what gets read.
#
# WHY NO CLASS IS NAMED AS AN IDENTIFIER HERE: validate_tool_script_purity.gd seeds its compile
# closure two ways — the class_name identifiers appearing in each tools/*.gd (comments and string
# literals stripped), AND literal preload()/load() res:// paths — then walks it transitively. Either
# would drag the turn conductor into the `-s` compile closure, where it legitimately names an autoload,
# and the purity gate would go red exactly as its header promises. So every file below is referenced by
# res:// PATH STRING and read with FileAccess; nothing is preloaded, nothing is loaded, and no repo
# class but ValidatorHarness is named. (That one is safe because the purity gate builds its class index
# from res://scripts only, so no tools/ class is in the identifier scan at all.)
#
# IF THE POPULATOR IS REFACTORED, THIS FAILS LOUD RATHER THAN SILENT. Move an assignment out into a
# helper and you get two failures, not a pass: "declared but never assigned" for the field, and
# "written here as well" for the helper. That pair is the signature of exactly that refactor. The fix
# is a judgement call — either keep the population in one function so it stays checkable, or teach this
# validator to follow the helper. What it must never do is quietly accept the field as populated.
#
# WHAT IT DOES NOT CHECK, DELIBERATELY:
#
# - Default parity between the two files. Two rules defaults differ from the autoload value that
#   overwrites them on purpose — the rules default is the neutral-for-unit-tests value that
#   tests/combat_golden_test.gd relies on, not the scenario value. Asserting parity would
#   false-positive on both and invite a golden-drifting "fix".
# - Anything under tests/. Six test sites build a rules bag, some setting a handful of fields and some
#   relying on the bare defaults; a test SHOULD be able to populate only what its case is about. The
#   scope here is res://scripts, i.e. production. That omission is a choice, not a gap.
#
# Prints PASS:/FAIL: for the gate's verdict.

const RULES_SOURCE := "res://scripts/model/CombatRules.gd"
const RULES_CLASS := "CombatRules"
const POPULATOR_SOURCE := "res://scripts/phases/TurnConductor.gd"
const POPULATOR_FUNC := "resolve_combat_at"
const AUTOLOAD_SOURCE := "res://scripts/GameData.gd"
const AUTOLOAD_ID := "GameData"
const CONSUMER_ROOT := "res://scripts"

# Fields the populator computes per turn or per hex instead of copying off the autoload. Each is here
# because a scenario value could not express it, and each must be justified in one line — an entry
# that turns out to be a plain autoload copy is itself a failure, so this list cannot rot silently.
const COMPUTED_SOURCES := {
	"red_supply_pool": "theatre DOS tons, read off the live supply state each turn",
	"isolated_red_brigade_ids": "air-landed brigades with no held corridor — turn state, plan 0032",
	"not_ashore_by_type": "the off-map remainder per brigade — turn state, plan 0037",
	"defender_terrain_modifier": "a terrain lookup for the contested hex, so per-hex by construction — there is no autoload property of this name and there could not be one",
}

# Fields allowed to be declared but never assigned. EMPTY, and it should stay that way: an unassigned
# field is precisely the silent no-op knob this validator exists to catch. An entry here needs a
# reason and a plan reference.
const UNASSIGNED_ALLOWED: Dictionary = {}

var _h := ValidatorHarness.new("combat-rules threading")


func _initialize() -> void:
	print("=== Combat-rules threading (every declared field is actually populated) ===")

	var declared := _declared_fields(_stripped(RULES_SOURCE))
	var populator_body := _stripped(POPULATOR_SOURCE)
	var block := _function_lines(populator_body, POPULATOR_FUNC)
	# The local the rules bag is built into, derived rather than assumed to be called `rules` — a
	# rename would otherwise blind the assignment scan and it would report every field missing.
	var locals := _rules_identifiers(populator_body)

	# Check 0 — anchors. Every check below is vacuous if the parse found nothing, and a vacuous pass is
	# indistinguishable from a real one. Plan 0038 moved this very function between files.
	_check_anchors(declared, block, locals)
	if not _h.failures.is_empty():
		_h.finish(self)
		return

	var assigned := _assignments(block, locals)
	_check_assignment_forms(block, locals)
	if assigned.is_empty():
		_h.fail("found %s() and its rules variable but no `%s.<field> = …` assignment in it — is the rules bag still populated there?"
			% [POPULATOR_FUNC, _alternation(locals)])
		_h.finish(self)
		return

	print("Declared %d field(s) in %s; %d assignment(s) in %s() of %s" % [
		declared.size(), RULES_SOURCE.trim_prefix("res://"), assigned.size(),
		POPULATOR_FUNC, POPULATOR_SOURCE.trim_prefix("res://")])

	var consumers := _consumers()
	if consumers.is_empty():
		_h.fail("found no script that takes a rules bag — the consumer derivation broke (looked for scripts naming '%s' under %s), so the write and read checks below would both be vacuous"
			% [RULES_CLASS, CONSUMER_ROOT.trim_prefix("res://")])
		_h.finish(self)
		return

	_check_allowlists_are_live(declared)
	_check_completeness(declared, assigned)
	_check_sources(assigned)
	_check_no_other_writers(consumers, declared, block)
	_check_every_field_is_read(consumers, declared)

	_h.finish(self)


## Every field declared at column 0, name -> line number.
##
## Deliberately permissive about the DECLARATION SHAPE. Matching `var <name>: <Type> = <default>`
## would miss `var x: float` (no default), `var x := 0.0` (inferred), and `@export var x: float = 0.0`
## — and a field missed here is missed by the completeness check too, which then compares two
## consistent sets and passes. That is a worse version of the bug this validator exists to catch, so
## the pattern captures the NAME and ignores everything about the type and initialiser.
func _declared_fields(body: String) -> Dictionary:
	var out: Dictionary = {}
	var regex := RegEx.create_from_string(
		"^(?:@\\w+(?:\\([^)]*\\))?\\s+)*var\\s+([A-Za-z_][A-Za-z0-9_]*)")
	var lines := body.split("\n")
	for index in range(lines.size()):
		var found := regex.search(String(lines[index]))
		if found != null:
			out[found.get_string(1)] = index + 1
	return out


## The lines of one function, keyed by their 1-based line number in the file. A function ends at the
## next line with content in column 0 — GDScript has no other terminator.
##
## Ending on ANY column-0 content, rather than on the keywords that start a new declaration, is
## deliberate and it is the safe direction to be wrong in. A bracketed expression continued at column 0
## would end the block early, and an early end means a field looks unassigned — a LOUD false alarm.
## Ending only on `func`/`var`/`const` would keep the block open past the function on a stray, pulling
## later lines in; and because the caller treats block lines as the sanctioned write site, that would
## SILENCE a second-writer failure. Loud beats silent here.
func _function_lines(body: String, func_name: String) -> Dictionary:
	var opener := RegEx.create_from_string(
		"^(?:static\\s+)?func\\s+%s\\s*\\(" % func_name)
	var lines := body.split("\n")
	var out: Dictionary = {}
	var inside := false
	for index in range(lines.size()):
		var line := String(lines[index])
		if not inside:
			if opener.search(line) != null:
				inside = true
			continue
		var is_column_zero := not line.is_empty() and line[0] != " " and line[0] != "\t"
		if is_column_zero:
			break
		out[index + 1] = line
	return out


## field -> {line, rhs} for every `<rules local>.<field> = <rhs>` in the given lines. Compound
## assignments and dynamic `set()` writes are deliberately NOT parsed here — _check_assignment_forms
## rejects them instead of quietly reading past them.
##
## The right-hand side is REQUIRED on the same line. Accepting an empty one, so that a value continued
## on the next line still counts, was considered and rejected: the field would then be "assigned" with
## an unreadable source, which either produces a baffling source-check failure or — if someone silenced
## that by adding the field to COMPUTED_SOURCES — a genuine silent pass. A value split across lines
## instead reports the field as unassigned, which is loud, accurate about what the parser can see, and
## fixed by putting the assignment on one line.
func _assignments(block: Dictionary, locals: Array) -> Dictionary:
	var regex := RegEx.create_from_string(
		"^\\s*(?:%s)\\.([A-Za-z_][A-Za-z0-9_]*)\\s*=(?!=)\\s*(.+?)\\s*$" % _alternation(locals))
	var out: Dictionary = {}
	for line_no in block.keys():
		var found := regex.search(String(block[line_no]))
		if found == null:
			continue
		var field := found.get_string(1)
		if out.has(field):
			_fail_at(POPULATOR_SOURCE, int(line_no),
				"'%s' is assigned twice (the second assignment wins; a transposed line usually means some OTHER field lost its assignment)" % field)
			continue
		out[field] = {"line": int(line_no), "rhs": found.get_string(2)}
	return out


## Without this the validator could pass while having parsed nothing at all — the exact silent-success
## class it exists to close.
func _check_anchors(declared: Dictionary, block: Dictionary, locals: Array) -> void:
	if declared.is_empty():
		_h.fail("parsed no `var` declarations out of %s — has the field-declaration shape changed?"
			% RULES_SOURCE.trim_prefix("res://"))
	if block.is_empty():
		_h.fail("could not find the body of %s() in %s — if it was renamed or moved, update POPULATOR_FUNC / POPULATOR_SOURCE in this validator"
			% [POPULATOR_FUNC, POPULATOR_SOURCE.trim_prefix("res://")])
	if locals.is_empty():
		_h.fail("found no variable of the rules type in %s — the assignment scan has nothing to look for, so completeness cannot be judged"
			% POPULATOR_SOURCE.trim_prefix("res://"))


## The assignment regex only understands `<local>.<field> = <value>`. A write it cannot read must be a
## loud failure, never an unnoticed one: silently skipping a `set()` call would leave the field looking
## unassigned (a confusing false alarm) or, worse, mask a real gap behind a form nobody audits.
func _check_assignment_forms(block: Dictionary, locals: Array) -> void:
	var exotic := RegEx.create_from_string(
		"(?<![A-Za-z0-9_])(?:%s)\\s*\\.\\s*(?:set\\s*\\(|[A-Za-z_][A-Za-z0-9_]*\\s*(?:\\+=|-=|\\*=|/=))"
			% _alternation(locals))
	for line_no in block.keys():
		if exotic.search(String(block[line_no])) != null:
			_fail_at(POPULATOR_SOURCE, int(line_no),
				"write form this validator cannot verify (dynamic set() or compound assignment) — populate the field with a plain `<rules>.<field> = …` so completeness stays checkable")


## Both allowlists in this file name fields, and a name outlives the field it refers to. Delete or rename
## a field and its exception silently becomes dead text that still LOOKS like a considered decision — and
## the next reader trusts it. An exception must therefore point at something that exists.
func _check_allowlists_are_live(declared: Dictionary) -> void:
	for field in COMPUTED_SOURCES.keys():
		if not declared.has(field):
			_h.fail("COMPUTED_SOURCES names '%s', which is no longer a field of %s — drop the stale exception"
				% [field, RULES_SOURCE.trim_prefix("res://")])
	for field in UNASSIGNED_ALLOWED.keys():
		if not declared.has(field):
			_h.fail("UNASSIGNED_ALLOWED names '%s', which is no longer a field of %s — drop the stale exception"
				% [field, RULES_SOURCE.trim_prefix("res://")])


func _check_completeness(declared: Dictionary, assigned: Dictionary) -> void:
	for field in declared.keys():
		if assigned.has(field) or UNASSIGNED_ALLOWED.has(field):
			continue
		_fail_at(RULES_SOURCE, int(declared[field]),
			"'%s' is declared but never assigned in %s() — it would silently keep its declared default, so the knob does nothing. Add the assignment line."
				% [field, POPULATOR_FUNC])
	for field in assigned.keys():
		if declared.has(field):
			continue
		_fail_at(POPULATOR_SOURCE, int(assigned[field]["line"]),
			"'%s' is assigned but not declared in %s — stale name after a rename?"
				% [field, RULES_SOURCE.trim_prefix("res://")])


## Two directions, so the computed-source list cannot rot: a field copied off the autoload must be
## copied off the SAME-NAMED property (the transposition catch — 22 near-identical lines in a row),
## and a field NOT copied off it must be a declared exception.
func _check_sources(assigned: Dictionary) -> void:
	var autoload_vars := _autoload_properties()
	var mirror := RegEx.create_from_string(
		"^%s\\.([A-Za-z_][A-Za-z0-9_]*)$" % AUTOLOAD_ID)
	for field in assigned.keys():
		var line_no: int = assigned[field]["line"]
		var found := mirror.search(String(assigned[field]["rhs"]))
		if found == null:
			if not COMPUTED_SOURCES.has(field):
				_fail_at(POPULATOR_SOURCE, line_no,
					"'%s' is not copied off %s and is not a declared exception — if it is genuinely computed per turn or per hex, add it to COMPUTED_SOURCES in this validator with the reason"
						% [field, AUTOLOAD_ID])
			continue
		if COMPUTED_SOURCES.has(field):
			_fail_at(POPULATOR_SOURCE, line_no,
				"'%s' is listed in COMPUTED_SOURCES but is now a plain %s copy — drop the stale exception"
					% [field, AUTOLOAD_ID])
		var source := found.get_string(1)
		if source != field:
			_fail_at(POPULATOR_SOURCE, line_no,
				"'%s' is fed from %s.%s — the names differ, which in a block of near-identical lines is a transposition, not a choice"
					% [field, AUTOLOAD_ID, source])
		elif not autoload_vars.has(source):
			_fail_at(POPULATOR_SOURCE, line_no,
				"%s.%s does not exist as a `var` in %s — renamed there without updating this line, which fails only at runtime"
					% [AUTOLOAD_ID, source, AUTOLOAD_SOURCE.trim_prefix("res://")])


## Every field is written in exactly one place. A second writer — in another script, or in another
## function of the populator's own file — would mean the completeness check above is asking the right
## question of only one of the answers.
##
## This pattern is deliberately NOT anchored to the start of a line, and it accepts every mutating
## operator rather than just `=`. An earlier version required `^\s*<ident>.<field> =`, and a diff
## reviewer showed it could be walked straight past: `rules.feba_base_km += 1.0` in a helper, or
## `if cond: rules.feba_base_km = 9.0` on one line, both matched nothing and the validator printed PASS
## over a live second writer. Reproduced, then fixed. Dynamic `set()` writes are checked separately
## because their field name is a runtime string this cannot resolve at all.
func _check_no_other_writers(consumers: Dictionary, declared: Dictionary, block: Dictionary) -> void:
	for path in consumers.keys():
		var body: String = consumers[path]["body"]
		var idents: Array = consumers[path]["idents"]
		var alternation := _alternation(idents)
		var write := RegEx.create_from_string(
			"(?<![A-Za-z0-9_])(?:%s)\\s*\\.\\s*([A-Za-z_][A-Za-z0-9_]*)\\s*(?:[-+*/]?=)(?!=)" % alternation)
		var dynamic := RegEx.create_from_string(
			"(?<![A-Za-z0-9_])(?:%s)\\s*\\.\\s*set\\s*\\(" % alternation)
		var lines := body.split("\n")
		for index in range(lines.size()):
			var line_no := index + 1
			if path == POPULATOR_SOURCE and block.has(line_no):
				continue
			var line := String(lines[index])
			var found := write.search(line)
			if found != null and declared.has(found.get_string(1)):
				_fail_at(path, line_no,
					"'%s' is written here as well as in %s() — the completeness gate only watches the latter, so a second writer can silently override or diverge from it"
						% [found.get_string(1), POPULATOR_FUNC])
			if dynamic.search(line) != null:
				_fail_at(path, line_no,
					"a rules field is written here through set(), whose field name this validator cannot resolve — that write is invisible to the completeness gate. Assign the field by name instead.")


## A field that nothing reads is its own bug: a knob that resolves, populates, and changes nothing.
## The reader set is DERIVED (every script naming the rules class, minus the class itself and the
## populator) rather than hand-listed, so a third reader does not have to be remembered.
func _check_every_field_is_read(consumers: Dictionary, declared: Dictionary) -> void:
	var read: Dictionary = {}
	for path in consumers.keys():
		if path == POPULATOR_SOURCE:
			continue
		var body: String = consumers[path]["body"]
		var deref := RegEx.create_from_string(
			"(?<![A-Za-z0-9_])(?:%s)\\.([A-Za-z_][A-Za-z0-9_]*)"
				% _alternation(consumers[path]["idents"]))
		for found in deref.search_all(body):
			read[found.get_string(1)] = true
	if read.is_empty():
		_h.fail("consumers were found but not one of them dereferences a rules field — every field below would be reported unread, so the fault is in this check, not in the code it is judging")
		return
	for field in declared.keys():
		if read.has(field):
			continue
		_fail_at(RULES_SOURCE, int(declared[field]),
			"'%s' is declared but never read by any script that takes a rules bag — a knob that changes nothing. Either wire it up in the combat maths or delete it."
				% field)


## Identifiers bound to the rules class in this file: `<name>: CombatRules` params and typed locals,
## plus `var <name> := CombatRules.new()`. Derived so the conventional local name is not load-bearing.
func _rules_identifiers(body: String) -> Array:
	var out: Dictionary = {}
	var typed := RegEx.create_from_string(
		"([A-Za-z_][A-Za-z0-9_]*)\\s*:\\s*%s\\b" % RULES_CLASS)
	for found in typed.search_all(body):
		out[found.get_string(1)] = true
	var constructed := RegEx.create_from_string(
		"var\\s+([A-Za-z_][A-Za-z0-9_]*)\\s*:?=\\s*%s\\s*\\.\\s*new\\s*\\(" % RULES_CLASS)
	for found in constructed.search_all(body):
		out[found.get_string(1)] = true
	return out.keys()


## Every script under CONSUMER_ROOT that names the rules class, minus its own declaration, as
## path -> {body, idents}. Built ONCE: the write check and the read check both need exactly this, and
## walking res://scripts twice to derive the same answer invites the two halves to disagree about who
## the consumers are. A file naming the class but binding no identifier to it (a bare
## `CombatRules.new()` passed straight as an argument, as several tests do) is dropped here, because
## with no identifier there is nothing for either check to look for.
func _consumers() -> Dictionary:
	var out: Dictionary = {}
	var names := RegEx.create_from_string(
		"(?<![A-Za-z0-9_])%s(?![A-Za-z0-9_])" % RULES_CLASS)
	for path in _gd_files(CONSUMER_ROOT):
		if path == RULES_SOURCE:
			continue
		var body := _stripped(path)
		if names.search(body) == null:
			continue
		var idents := _rules_identifiers(body)
		if idents.is_empty():
			continue
		out[path] = {"body": body, "idents": idents}
	return out


## The autoload's own `var` names, so a rename there is caught statically instead of at runtime. Safe
## as a purely textual check: that script declares no _get/_set/_get_property_list, so it has no
## property the source text does not show.
func _autoload_properties() -> Dictionary:
	var body := _stripped(AUTOLOAD_SOURCE)
	if RegEx.create_from_string("(?m)^func\\s+_(?:get|set)(?:_property_list)?\\s*\\(").search(body) != null:
		_h.fail("%s now defines a dynamic property hook (_get/_set/_get_property_list), so checking its properties by source text is no longer sound"
			% AUTOLOAD_SOURCE.trim_prefix("res://"))
	var out: Dictionary = {}
	for found in RegEx.create_from_string("(?m)^var\\s+([A-Za-z_][A-Za-z0-9_]*)").search_all(body):
		out[found.get_string(1)] = true
	return out


## A regex alternation of identifiers, sorted so the pattern is stable run to run. Shadowing (`rules`
## matching inside `combat_rules`) is prevented by the anchors at the use sites, not by ordering.
func _alternation(identifiers: Array) -> String:
	var parts := PackedStringArray()
	for identifier in identifiers:
		parts.append(String(identifier))
	parts.sort()
	return "|".join(parts)


func _gd_files(root: String) -> Array[String]:
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
			if entry.ends_with(".gd"):
				out.append("%s/%s" % [dir_path, entry])
	out.sort()
	return out


## Comments and string literals are prose, not code — this file's own header talks about the very
## identifiers it scans for.
##
## Known limitation, shared with validate_tool_script_purity.gd's identical stripper: an ESCAPED quote
## inside a string literal (`"say \"hi\""`) ends the match early and leaves the middle looking like code.
## Not reachable from anything scanned here — no file this validator parses contains one, and the single
## script under res://scripts that does never names the rules class, so it is not in the derived consumer
## set. If that changes, the failure direction is a spurious FAIL, not a silent pass.
func _stripped(path: String) -> String:
	var body := FileAccess.get_file_as_string(path)
	var without_strings := RegEx.create_from_string("\"[^\"\\n]*\"|'[^'\\n]*'").sub(body, "\"\"", true)
	return RegEx.create_from_string("(?m)#.*$").sub(without_strings, "", true)


func _fail_at(path: String, line_no: int, message: String) -> void:
	_h.fail("%s:%d — %s" % [path.trim_prefix("res://"), line_no, message])
