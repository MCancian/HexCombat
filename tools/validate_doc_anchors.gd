# Doc-anchor freshness gate (docs architecture B, 2026-07-10). Module docs rot when code moves
# under them — the audit that motivated this found three docs/systems/*.md citing functions that
# no longer existed and line numbers hundreds of lines stale. This validator makes that class of
# rot a RED GATE instead of a prose rule:
#
#   1. No `file.gd:123` line-number citations in docs/systems/*.md (line numbers rot silently;
#      the docs-and-writing rule is "class names only — the reader greps").
#   2. Every backticked repo path (`scripts/...`, `tools/...`, `data/...`, `tests/...`,
#      `schemas/...`) must exist on disk.
#   3. Every backticked bare `SomeFile.gd` basename must exist under scripts/, tools/, or tests/.
#   4. Every backticked `UpperCamel.member` reference (e.g. `IjfsResolver.compute_writeback`)
#      must resolve: the UpperCamel names a real script (by filename OR `class_name`) and that
#      script's text contains `member`. A Godot built-in (`FileAccess.open`, `Dictionary.keys`)
#      is fine; ANYTHING ELSE IS A DEAD CLASS AND FAILS.
#
#      That last clause was added 2026-07-31 and is the point of the rule. Until then the check
#      began `if the class does not resolve: return`, so it was strongest for classes that still
#      exist and completely BLIND to classes that had been deleted — exactly inverted from the
#      real risk. `RosterMutations.apply_casualty` sat in docs/systems/turn-engine/turn-engine.md
#      for six plans after plan 0044 deleted the class: a scanned file, correct backtick syntax,
#      silently skipped. The 0050 closeout found eleven such references to `RosterMutations` and
#      `SupplyResolver` by hand, one of which had a BACKLOG item proposing a fix that called a
#      class no longer in the tree.
#
# Escape hatch: lines mentioning `docs/archive` or containing the marker `(historical)` are
# skipped — historical passages may cite dead names on purpose. Semantic rot (a wrong claim in
# valid prose) stays a human/agent problem; this only catches dead anchors, which the audit
# showed is the dominant failure mode.
#
# SCOPE (widened 2026-07-31): checks 2-4 run over docs/** AND .claude/skills/**, minus the kinds of
# doc where a dead anchor is CORRECT — docs/archive (history), docs/reports (dated snapshots), and
# the append-only history docs listed in HISTORY_DOCS. Check 1 stays scoped to docs/systems, where
# the "class names only" rule applies. Before this, the scope was docs/systems alone:
# docs/STATUS.md — the file every agent reads first — got no anchor checking at all, and carried a
# dead `RosterMutations` claim for six plans.
#
# SCOPE (widened 2026-08-03, docs/plans — BACKLOG item docs/plans/BACKLOG.md:35): docs/plans is now
# scanned too; an ACTIVE plan's code references were rotting silently (the 0003/0029 seam citations
# named CombatResolver.resolve_hex_combat six plans after the decomposition campaign renamed it to
# resolve_at). Proposals still legitimately name things not in the tree yet, so a line containing
# the marker `(planned)` suppresses ONLY "this does not exist here" — check 2's dead path, check 3's
# no-such-script, and check 4's class/member-does-not-resolve — for tokens naming what the plan
# proposes to build. Same per-token scoping as `(upstream)`, never a whole-line skip, so real
# anchors on a `(planned)` line stay fully checked. Two carve-outs from the carve-out: docs/plans/ARCHIVE.md
# (a closed-plan index — every row a shipped record, so its seven dead anchors are correct) is in
# HISTORY_DOCS; docs/plans/BACKLOG.md is a live queue, kept scanned, with its two historical
# references marked individually (a teaching placeholder added to PLACEHOLDER_CLASSES and a deleted
# symbol's record marked `(historical)`).
#
# The detector proves itself on every run (`_self_test`): four references that MUST fail and nine that
# MUST pass, asserted before any doc is read. Deleting the check-4 failure branch, or dropping the
# skills scan root, both go red — measured, not assumed.
#
#   5. Every `docs/plans/<name>.md` or `docs/archive/<name>.md` token anywhere under docs/**/*.md
#      or tools/**/*.gd must resolve to a real file — NOT subject to the historical/archive
#      escape hatch above (that hatch is for stale script/member citations *within* a historical
#      passage; a doc-to-doc pointer should always resolve, historical or not, since plan
#      closeout moves a file rather than deleting the fact). Added 2026-07-11 after a plan
#      closeout move left four such references dead across docs/STATUS.md,
#      docs/antiship_missile_pipeline_ref.md, and two tools/*.gd comments, caught only by manual
#      grep.
extends SceneTree

## Roots scanned for dead anchors (checks 2-4). `docs/systems` was the original scope; the cross-cutting
## hub and the skills were added 2026-07-31 because they are what an agent reads FIRST and were getting
## no anchor checking at all — `docs/STATUS.md` carried a `RosterMutations` claim for six plans.
const DOC_ROOTS := ["res://docs", "res://.claude/skills"]
## Excluded from checks 2-4 (not from check 5, which always resolves). `docs/archive` is history by
## definition and `docs/reports/` holds dated audit snapshots — a point-in-time record, like an archive
## entry. One of them documents a REJECTED hallucinated claim about a symbol that never existed; flagging
## that symbol as a dead anchor is the gate arguing with a doc that already agrees with it. `docs/plans/`
## was excluded here until 2026-08-03 — see the SCOPE header: it is scanned now, with the `(planned)`
## escape hatch for proposals, and ARCHIVE.md/BACKLOG.md are handled via HISTORY_DOCS and line markers.
const DOC_ROOT_EXCLUDES := ["res://docs/archive/", "res://docs/reports/"]
## Check 1 (no `file.gd:123` citations) stays scoped to module docs. Everywhere else — DECISIONS
## entries, STATUS, the skills — a file:line is often the whole point of the sentence, and the
## docs-and-writing rule that motivated check 1 only ever applied to `docs/systems/<module>.md`.
const LINE_CITE_DIR := "res://docs/systems"
const CODE_ROOTS := ["res://scripts", "res://tools", "res://tests"]
const DOC_LINK_SCAN_ROOTS := [
	["res://docs", ".md"],
	["res://tools", ".gd"],
]
## Variant types are NOT in ClassDB (`ClassDB.class_exists("Dictionary")` is false), so built-in
## detection needs both this list and the ClassDB lookup.
const VARIANT_TYPES := [
	"Dictionary", "Array", "String", "StringName", "NodePath", "Variant", "Callable", "Signal",
	"Vector2", "Vector2i", "Vector3", "Vector3i", "Vector4", "Vector4i", "Rect2", "Rect2i",
	"Transform2D", "Transform3D", "Basis", "Quaternion", "AABB", "Plane", "Color", "RID",
	"PackedByteArray", "PackedInt32Array", "PackedInt64Array", "PackedFloat32Array",
	"PackedFloat64Array", "PackedStringArray", "PackedVector2Array", "PackedVector3Array",
	"PackedColorArray",
]
## A backticked token ending in one of these is a FILENAME, not a `Class.member` reference —
## `STATUS.md`, `ARCHIVE.md` and `SKILL.md` all match the UpperCamel.member shape otherwise.
## `.gd` is absent deliberately: check 3 handles it and returns before check 4.
const NON_SCRIPT_SUFFIXES := [
	".md", ".json", ".jsonl", ".py", ".sh", ".ps1", ".uid", ".tscn", ".tres", ".svg", ".png",
	".csv", ".html", ".xml", ".txt", ".cfg", ".godot", ".import", ".exe", ".yml", ".yaml",
]
## Generic stand-ins used when documenting the RULE rather than a call — `Class.field` is the phrase
## the mutation manifest and STATUS both use for the shape of a claim, and `ClassName.member` is the
## same shape spelled out in BACKLOG.md:145. Kept deliberately short: every addition here is a name
## the gate stops protecting repo-wide.
const PLACEHOLDER_CLASSES := ["Class", "ClassName", "Domain", "Type", "Model", "Aggregate", "Foo", "Bar", "Some"]
## Script names used to TEACH the citation format (this validator's own header cites `file.gd:123`),
## not to point at a file.
const PLACEHOLDER_SCRIPTS := ["file.gd", "script.gd", ".gd"]
## Docs whose every line is a record of the PAST, so a dead anchor in them is correct rather than rotten.
## `docs/plans/ARCHIVE.md` (added 2026-08-03) is a closed-plan index: each row records a SHIPPED plan,
## so a row naming a directory the plan later deleted is a true record, not a defect. Its seven dead
## anchors measured 2026-08-03 are all of that kind. BACKLOG.md is deliberately NOT here — it is a live
## queue, and its two historical references are marked inline instead.
##
## `docs/DECISIONS.md` is deliberately NOT here, though it is append-only. Review finding, 2026-07-31:
## AGENTS.md mandates a DECISIONS entry at the closeout of every plan, so it is the highest-churn doc in
## the repo and its newest entries name the classes that were JUST changed — exactly where a dead name
## is a live defect rather than a record. Measured before deciding: un-excluding it produced 20 failures
## across 16 lines, ALL of them in older entries (line 113 and below in a newest-first file), so the
## recent entries were already clean. Those 16 lines carry a `(historical)` marker now, which in a
## changelog is a true annotation rather than a silencer.
const HISTORY_DOCS := [
	"res://docs/RETROSPECTIVES.md",
	"res://docs/plans/ARCHIVE.md",
	"res://.claude/skills/hexcombat-failure-archaeology/SKILL.md",
	"res://.claude/skills/hexcombat-gamestate-decomposition-campaign/SKILL.md",
]

var _h := ValidatorHarness.new("doc-anchor validation")
var _gd_index: Dictionary = {}  # basename -> full res:// path (also keyed by `class_name` + ".gd")
var _alias_index: Dictionary = {}  # enum/const/inner-class name -> Array of declaring res:// paths
var _class_name_re := RegEx.create_from_string("(?m)^class_name\\s+([A-Za-z_][A-Za-z0-9_]*)")
## Top-level `enum X` / `const X` / inner `class X` — all three are referenced bare in docs (`Phase.END`)
## because that is how code references them, and none resolves to a FILE named X.gd.
var _type_alias_re := RegEx.create_from_string("(?m)^(?:enum|const|class)\\s+([A-Z][A-Za-z0-9]*)\\b")
## Line-marker flags passed to _check_token as one bitmask (the gate's param ceiling is 5).
## `upstream`: citing the TaiwanInvasionViewer source — forgives "no such thing here" but NOT a bad
## member on a class that resolves here. `planned`: naming what a docs/plans/*.md PROPOSES to build —
## forgives "no such thing here" including a proposed member on an existing class.
const FLAG_UPSTREAM := 1
const FLAG_PLANNED := 2


func _initialize() -> void:
	_build_gd_index()
	_self_test()
	var doc_files: Array[String] = []
	for root in DOC_ROOTS:
		_collect_files(root, ".md", doc_files)
	doc_files = doc_files.filter(func(p: String) -> bool:
		if p in HISTORY_DOCS:
			return false
		for excluded in DOC_ROOT_EXCLUDES:
			if p.begins_with(excluded):
				return false
		return true)
	if doc_files.is_empty():
		push_error("Cannot find any .md files under %s" % ", ".join(DOC_ROOTS))
		quit(1)
		return
	# The scope is the whole point of this validator, so prove it is not silently empty: a typo in
	# DOC_ROOTS, or Godot hiding a dot-directory, would otherwise look exactly like "all clean".
	var skills_seen := doc_files.filter(func(p: String) -> bool: return p.begins_with("res://.claude/skills")).size()
	if skills_seen == 0:
		push_error("Scanned zero skill docs — res://.claude/skills is a hidden directory and DirAccess may be skipping it")
		quit(1)
		return
	var checked := 0
	for path in doc_files:
		_check_doc(path)
		checked += 1

	var link_files_checked := _check_doc_links()

	_h.pass_body = func() -> String: return "doc anchors fresh (%d docs, %d indexed .gd files, %d links, %d queries)" % [doc_files.size(), _gd_index.size(), link_files_checked, 0]
	_h.fail_header = func() -> String: return "doc-anchor validation found %d issue(s) — a code move/rename left dead anchors" % _h.failures.size()
	_h.finish(self)


## Prove the detector FIRES before trusting it to stay silent. A doc-anchor gate that cannot fail is
## indistinguishable from a clean tree, and this file spent six plans in exactly that state: check 4
## returned early on an unresolved class, so every reference to a DELETED class passed. Both directions
## are asserted — a dead name must fail, and a live one must not — because a detector that fails on
## everything gets escape-hatched into uselessness within a week.
func _self_test() -> void:
	var member_ref := RegEx.create_from_string("^([A-Z][A-Za-z0-9]+)\\.([a-zA-Z_][A-Za-z0-9_]*)")
	var must_fail := {
		"RosterMutations.apply_casualty": "a class deleted from the tree (the case that was blind)",
		"GameData.no_such_member_xyz": "a live class, a member it does not have",
		"scripts/does_not_exist.gd": "a dead repo path",
		"TotallyMadeUpClass.field": "a name that was never in the tree",
	}
	var must_pass := {
		"GameData.load_all": "a live class and a real member",
		"GameStateType.Phase": "a class_name that differs from its filename",
		"Phase.PLANNING": "a top-level enum referenced bare, as code references it",
		"FileAccess.open": "a Godot ClassDB built-in",
		"Dictionary.keys": "a Variant type, which is NOT in ClassDB",
		"Class.field": "the generic placeholder the manifest and STATUS both use",
		"tools/validate_<thing>.gd": "a naming-shape template",
		"docs/STATUS.md": "a doc filename, not a Class.member reference",
		"data/ijfs/ijfs_scenario.json.crbm_maneuver_rounds_override": "a key addressed inside a real file",
	}
	for token in must_fail:
		var before := _h.failures.size()
		_check_token("<self-test>", 0, token, member_ref)
		if _h.failures.size() == before:
			_h.collect("SELF-TEST: `%s` should have failed (%s) — the detector is not firing" % [
				token, must_fail[token]])
		else:
			_h.failures.resize(before)  # expected failure; discard it
	for token in must_pass:
		var before := _h.failures.size()
		_check_token("<self-test>", 0, token, member_ref)
		if _h.failures.size() != before:
			var got: String = _h.failures[before]
			_h.failures.resize(before)
			_h.collect("SELF-TEST: `%s` should have passed (%s) but reported: %s" % [
				token, must_pass[token], got])
	# `(upstream)` is NOT a line skip: it forgives "no such thing here" and nothing else, so a line
	# citing an upstream name and one of ours keeps checking ours. Both halves pinned.
	var before_up := _h.failures.size()
	_check_token("<self-test>", 0, "TotallyMadeUpClass.field", member_ref, FLAG_UPSTREAM)
	if _h.failures.size() != before_up:
		_h.failures.resize(before_up)
		_h.collect("SELF-TEST: `(upstream)` should forgive an unresolved class and does not")
	_check_token("<self-test>", 0, "GameData.no_such_member_xyz", member_ref, FLAG_UPSTREAM)
	if _h.failures.size() == before_up:
		_h.collect("SELF-TEST: `(upstream)` wrongly forgives a bad member on a class that DOES resolve here")
	else:
		_h.failures.resize(before_up)
	# `(planned)` forgives "no such thing here" for a line naming what a plan proposes to build — and
	# for MEMBERS too, since the common plan pattern is a new member on an existing class
	# (`AirInsertionSummary.REASON_ON_COOLDOWN` in plan 0036). It is NOT a line skip and it is NOT a
	# global opt-out: a real class/member stays checked, a placeholder stays a placeholder, and a dead
	# name is forgiven only when the marker is present. Four passes and one fail, pinned in both
	# directions like the `(upstream)` block above.
	var before_pl := _h.failures.size()
	_check_token("<self-test>", 0, "TotallyMadeUpClass.field", member_ref, FLAG_PLANNED)
	if _h.failures.size() != before_pl:
		_h.failures.resize(before_pl)
		_h.collect("SELF-TEST: `(planned)` should forgive an unresolved class (a proposal name) and does not")
	_check_token("<self-test>", 0, "AirInsertionSummary.REASON_ON_COOLDOWN", member_ref, FLAG_PLANNED)
	if _h.failures.size() != before_pl:
		_h.failures.resize(before_pl)
		_h.collect("SELF-TEST: `(planned)` should forgive a proposed member on a real class and does not")
	_check_token("<self-test>", 0, "GameData.load_all", member_ref, FLAG_PLANNED)
	if _h.failures.size() != before_pl:
		_h.failures.resize(before_pl)
		_h.collect("SELF-TEST: `(planned)` should leave a real class/member checked and does not")
	_check_token("<self-test>", 0, "Class.field", member_ref, FLAG_PLANNED)
	if _h.failures.size() != before_pl:
		_h.failures.resize(before_pl)
		_h.collect("SELF-TEST: `(planned)` should not change how a placeholder reference resolves")
	# A dead name is forgiven ONLY when the marker is on the line — the flag must not be sticky.
	_check_token("<self-test>", 0, "TotallyMadeUpClass.field", member_ref, 0)
	if _h.failures.size() == before_pl:
		_h.collect("SELF-TEST: a dead name with no `(planned)` marker should still fail")
	else:
		_h.failures.resize(before_pl)


func _check_doc(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	var doc := path.get_file()
	var line_cite := RegEx.create_from_string("\\.gd:\\d+")
	var backtick := RegEx.create_from_string("`([^`\\n]+)`")
	var member_ref := RegEx.create_from_string("^([A-Z][A-Za-z0-9]+)\\.([a-zA-Z_][A-Za-z0-9_]*)")
	var lines := text.split("\n")
	var cite_scoped := path.begins_with(LINE_CITE_DIR)
	for i in range(lines.size()):
		var line := lines[i]
		if line.contains("docs/archive") or line.contains("(historical)") or doc == "RETRO.md":
			continue
		# `(upstream)` marks a line citing the TaiwanInvasionViewer source this game was ported from —
		# a real name in a repo that is not this one. Unlike `(historical)` it does NOT skip the line:
		# it suppresses only "this does not exist here", because such a line usually cites an upstream
		# name and one of OURS in the same breath (`GameView.IJFS` -> our `resolve_ijfs_turn`), and
		# skipping the line would stop checking our half too. Review finding, 2026-07-31.
		var upstream := line.contains("(upstream)")
		# `(planned)` (added 2026-08-03, see SCOPE) marks a plan line naming what the plan PROPOSES to
		# build. Same per-token scoping as `(upstream)`: it forgives only "this does not exist here" —
		# but for members too, since the common plan pattern is a NEW member on an EXISTING class
		# (`AirInsertionSummary.REASON_ON_COOLDOWN` in plan 0036). Never a line skip: real anchors on
		# the same line stay checked.
		var planned := line.contains("(planned)")
		if cite_scoped and line_cite.search(line) != null:
			_h.collect("%s:%d: file:line citation (line numbers rot — cite the class name): %s" % [doc, i + 1, line.strip_edges().left(90)])
		for m in backtick.search_all(line):
			var token := m.get_string(1).strip_edges()
			var flags := (FLAG_UPSTREAM if upstream else 0) | (FLAG_PLANNED if planned else 0)
			_check_token(doc, i + 1, token, member_ref, flags)


## `upstream` (FLAG_UPSTREAM): the citing line is marked `(upstream)`, so "no such thing here" is
## expected and suppressed — but a member on a class that DOES resolve here is still checked.
## `planned` (FLAG_PLANNED): the citing line is marked `(planned)`, so "no such thing here" is
## expected too. Unlike `upstream`, a proposed MEMBER on a class that resolves here is also forgiven
## (a plan proposes new members on existing classes) — but a real member that resolves is still
## checked, and a placeholder is still a placeholder.
func _check_token(doc: String, line_no: int, token: String, member_ref: RegEx, flags: int = 0) -> void:
	var upstream := flags & FLAG_UPSTREAM != 0
	var planned := flags & FLAG_PLANNED != 0
	# A template (`validate_<thing>.gd`, `<Phase>Resolver.gd`) illustrates a NAMING SHAPE, the same way
	# a glob does. Neither is an anchor, and neither can resolve.
	if token.contains("*") or token.contains("<") or token.contains(">"):
		return
	# A token with a space is prose that happened to be backticked (`-s script.gd`), not a reference.
	if token.contains(" "):
		return
	# 2) explicit repo paths (strip :line suffixes, [key] indexing, trailing anchors)
	for root in ["scripts/", "tools/", "data/", "tests/", "schemas/"]:
		if token.begins_with(root):
			var clean := token.split("#")[0].split("[")[0].split(":")[0]
			# `data/x.json.some_key` addresses a KEY INSIDE the file; the anchor is the file part.
			clean = _truncate_to_file(clean)
			if clean.ends_with("/"):
				clean = clean.trim_suffix("/")
			if not (FileAccess.file_exists("res://" + clean) or DirAccess.dir_exists_absolute("res://" + clean)):
				if not upstream and not planned:
					_h.collect("%s:%d: dead path `%s`" % [doc, line_no, token])
			return
	# 3) bare .gd basename (strip :line suffix — the file:line check reports the citation itself)
	if token.contains(".gd"):
		var base := token.split(":")[0]
		if base in PLACEHOLDER_SCRIPTS:
			return
		if not base.contains("/") and base.ends_with(".gd") and not _gd_index.has(base):
			if not upstream and not planned:
				_h.collect("%s:%d: no such script `%s` under scripts/tools/tests" % [doc, line_no, token])
		return
	# 4) UpperCamel.member — the class must resolve, and then the member must exist in it.
	for suffix in NON_SCRIPT_SUFFIXES:
		if token.ends_with(suffix):
			return  # a filename (`STATUS.md`), not a Class.member reference
	var m := member_ref.search(token)
	if m == null:
		return
	var class_token := m.get_string(1)
	# Order matters: OUR tree wins. A placeholder or built-in name that a real script later claims
	# (`Type.gd`, `Model.gd`, a `Color` of our own) must be CHECKED, not waved through — otherwise
	# adding such a class would silently switch off this gate for every reference to it.
	var script_path: String = _gd_index.get(class_token + ".gd", "")
	if script_path.is_empty() and (class_token in VARIANT_TYPES or ClassDB.class_exists(class_token)):
		return  # Godot built-in; its members are the engine's business, not ours
	if script_path.is_empty() and class_token in PLACEHOLDER_CLASSES:
		return
	var member := m.get_string(2)
	if script_path.is_empty():
		# A top-level `enum`/`const`/inner `class` name can be declared in SEVERAL files (`const RED`
		# is in ten). Resolve against all of them and pass if any one declares the member, rather than
		# letting whichever file was indexed first decide. Review finding, 2026-07-31.
		for candidate in _alias_index.get(class_token, []):
			if FileAccess.get_file_as_string(candidate).contains(member):
				return
		if upstream or planned:
			return
		# The inverted case (see header): a class that resolves to NOTHING used to pass silently,
		# which made every reference to a DELETED class invisible to this gate.
		_h.collect("%s:%d: `%s` — no class or script named '%s' anywhere under scripts/tools/tests (deleted? mark the line '(historical)' if it is describing the past)" % [
			doc, line_no, token, class_token])
		return
	if member == "new":
		return  # Godot constructor, always valid
	if not FileAccess.get_file_as_string(script_path).contains(member):
		if not planned:
			_h.collect("%s:%d: `%s` — no '%s' in %s (renamed/moved?)" % [doc, line_no, token, member, script_path.get_file()])


## `data/ijfs/ijfs_scenario.json.some_knob` -> `data/ijfs/ijfs_scenario.json`. Docs address a key inside
## a content file this way; the part that has to exist on disk is the file.
func _truncate_to_file(path: String) -> String:
	for suffix in [".json", ".gd", ".md", ".ps1", ".sh", ".py", ".tscn", ".cfg", ".csv", ".svg"]:
		var at := path.find(suffix + ".")
		if at != -1:
			return path.substr(0, at + suffix.length())
	return path


# Check 5 (see header): every docs/plans/<name>.md or docs/archive/<name>.md token under
# docs/**/*.md or tools/**/*.gd must resolve to a real file. Not gated by the historical/archive
# escape hatch used by _check_doc — a moved-but-not-deleted plan should always resolve.
func _check_doc_links() -> int:
	var link_re := RegEx.create_from_string("docs/(plans|archive)/[A-Za-z0-9_.\\-]+\\.md")
	var files: Array[String] = []
	for entry in DOC_LINK_SCAN_ROOTS:
		_collect_files(entry[0], entry[1], files)
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		var lines := text.split("\n")
		for i in range(lines.size()):
			for m in link_re.search_all(lines[i]):
				var token := m.get_string()
				if token.contains("*"):
					continue  # glob illustration, not an anchor
				if not FileAccess.file_exists("res://" + token):
					_h.collect("%s:%d: dead doc-link `%s`" % [path.trim_prefix("res://"), i + 1, token])
	return files.size()


func _collect_files(root: String, suffix: String, out: Array[String]) -> void:
	var dir := DirAccess.open(root)
	if dir == null:
		return
	# `.claude/skills` is a hidden directory; without this the skills scan silently returns nothing,
	# which is indistinguishable from "the skills are clean". The empty-scope guard in _initialize
	# is the backstop for exactly that failure.
	dir.include_hidden = true
	for sub in dir.get_directories():
		_collect_files("%s/%s" % [root, sub], suffix, out)
	for file in dir.get_files():
		if file.ends_with(suffix):
			out.append("%s/%s" % [root, file])


func _build_gd_index() -> void:
	for root in CODE_ROOTS:
		_index_dir(root)


func _index_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_index_dir("%s/%s" % [path, sub])
	for file in dir.get_files():
		if not file.ends_with(".gd"):
			continue
		var full := "%s/%s" % [path, file]
		_gd_index[file] = full
		# Also index the DECLARED class_name, which need not match the filename: GameState.gd declares
		# `class_name GameStateType`, so `GameStateType.Phase` resolves to nothing by filename alone —
		# and once an unresolved class is a failure, that gap becomes a false positive.
		var text := FileAccess.get_file_as_string(full)
		var declared := _class_name_re.search(text)
		if declared != null:
			_gd_index[declared.get_string(1) + ".gd"] = full
		# Aliases are MANY-to-many: `const RED` is declared in ten files, and an inner `class Verdict`
		# in another. Collect every declaring file so the member check can ask all of them, instead of
		# letting whichever was indexed first answer for the rest.
		for decl in _type_alias_re.search_all(text):
			var alias := decl.get_string(1)
			if not _alias_index.has(alias):
				_alias_index[alias] = []
			(_alias_index[alias] as Array).append(full)
