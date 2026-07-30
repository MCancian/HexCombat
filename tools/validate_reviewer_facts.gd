# Run from the project root:
# godot --headless --path . -s res://tools/validate_reviewer_facts.gd
extends SceneTree

# Fails when a reviewer INVOCATION FRAGMENT or MODEL ID appears in repo markdown outside
# `.claude/REVIEWERS.md`.
#
# WHAT IT DOES NOT PROVE. This is a token check, not a proof that every reviewer fact has one home. A
# tier claim, a byte band or a safety rule RESTATED IN PROSE passes it untouched, as do identifiers split
# across a line break. A reviewer raised this as a blocker against the original wording, correctly: the
# docs now claim only what is enforced (routes and ids), and prose duplication stays convention. Do not
# widen the fragment list into prose heuristics — a false positive in a doc gate teaches agents to
# route around the gate.
#
# WHY: before plan 0054, reviewer facts lived in eight overlapping homes — two skills, CLAUDE.md,
# AGENTS.md, the roster, and two files outside the repo. The copies diverged exactly as you would
# expect, and the divergence was not cosmetic: both review skills and the global slash command still
# listed a two-model `opencode/*-free` roster with NO tier-1 reviewer in it, and Nemotron's route had
# since moved to a different provider. An agent following the documented procedure could not reach the
# best reviewer it had. One home plus this gate is the fix; prose asking politely for one home is what failed.
#
# DELIBERATELY NARROW, in the style of validate_skill_references.gd. It checks for concrete
# invocation fragments and concrete model ids — never prose. Naming a reviewer in a sentence is fine
# and useful ("caught by the explore reviewer"); pasting the command or the id is what rots, because
# it is the part that changes when a route moves. The tool NAMES of the agy wrappers are deliberately
# absent from the pattern list for the same reason: they are stable, and skills legitimately discuss
# what those wrappers can and cannot see.
#
# HISTORY IS ALLOWED TO NAME DEAD ROUTES. A retrospective recording "nemotron mis-counted this" is the
# record of a measurement, not an instruction. Lines carrying an escape marker are skipped, and
# docs/archive is out of scope entirely — same convention as validate_doc_anchors.gd and
# validate_skill_references.gd, so there is one idiom to learn rather than three.
#
# CANNOT GATE ~/.claude/*. The global AGY contract and the global review slash command live outside
# the repo, so nothing here can watch them. They were rewritten to hold no roster at all (plan 0054),
# which is the only enforcement available for a file a repo validator cannot see.
#
# WHY MARKDOWN ONLY, AND WHY THESE EXCLUSIONS. Measured by an enumeration pass over the tree, 2026-07-30:
#   - Retrospectives hold reviewer facts as incident RECORDS ("two simultaneous opencode runs die on a
#     locked DB"). History by contract, excluded like docs/archive. NOTE the exclusion is by BASENAME:
#     any file called RETRO.md anywhere in the tree is skipped, not only docs/systems/**/RETRO.md.
#   - The DeepSeek route's model id is ALSO an LLM PLAYER model name in this game: tests/knob_registry_test.gd
#     asserts on it as a knob value, and docs/presentation.html prints it as run metadata. Scanning `.gd`
#     or `.html` would fail the gate on files that have nothing to do with reviewers. The fragments are
#     only unambiguous inside agent-facing markdown, which is what is scanned.
#
# Prints PASS:/FAIL: for the gate's verdict.

const HOME_FILE := "res://.claude/REVIEWERS.md"
const LAUNCHER_FILE := "res://tools/review_fanout.sh"
# The roster's machine-readable round block: `name  role  command`, two-or-more spaces between fields.
const ROSTER_ROW_PATTERN := "^([a-z0-9]+) {2,}(quorum|extra) {2,}(\\S.*\\S)$"
# `manifest+=("name<TAB>quorum|extra<TAB>command")` in the launcher.
# Leading whitespace matters: the tier-3 rows are indented inside an `if` block, and an anchored
# `^manifest` pattern silently matched only the three unindented quorum rows — which made the row-count
# check report zero extras. Found by the check failing on its own first run.
const LAUNCHER_ROW_PATTERN := "^[ \\t]*manifest\\+=\\(\"([a-z0-9]+)\\t(quorum|extra)\\t(.+)\"\\)$"
# The roster's round, by NAME and not merely by count. Counting alone let a tier-3 model be promoted into
# the quorum while the 3/2 totals stayed put — which is precisely the rule the USER was most explicit
# about ("tier 3 never counts toward the quorum"). Reviewer finding, round 5.
const EXPECTED_QUORUM := ["sol", "agy", "deepseek"]
const EXPECTED_EXTRA := ["minimax", "nemotron"]
# Every markdown file in the repo is scanned except the exclusions below. A reviewer's objection to the
# original four-root scan was correct: `.claude/*.md` outside skills, `docs/*.md`, `docs/systems/*.md`
# and any future live doc were all blind spots, and "one home" that only holds inside four directories
# is not one home.
const SCAN_ROOT := "res://"
# Deepest markdown in this repo sits at depth 3; the cap only has to terminate a symlink cycle.
const MAX_DEPTH := 8
# HISTORY, not instruction. A retrospective or an archived plan recording "nemotron mis-counted this" or
# "two opencode runs deadlock" is the record of a measurement; rewriting it would destroy the evidence.
# docs/reports holds dated measurement write-ups for the same reason.
const EXCLUDED_PREFIXES := [
	"res://docs/archive/", "res://docs/reports/",
	"res://.git/", "res://.godot/", "res://addons/", "res://reports/", "res://node_modules/",
]
const EXCLUDED_BASENAMES := ["RETRO.md", "RETROSPECTIVES_history.md"]

# Concrete fragments only. Each is either a CLI invocation shape or a model id — the things that stop
# working when a route changes, and that must therefore have exactly one home.
const FORBIDDEN := [
	"pi -p",
	"opencode run",
	"--tools read",
	"--agent explore",
	"AGY_TIMEOUT",
	"gpt-5.6-sol",
	"minimax-m3",
	"nemotron-3-ultra",
	"deepseek-v4-flash",
]

# A line recording what a reviewer once did is not an instruction to invoke it. `(llm-player)` is the
# escape for the OTHER meaning of a model id here: the same names are LLM PLAYER knob values in this
# game (tests/knob_registry_test.gd asserts on one), so a doc about self-play must be able to name the
# model it ran without tripping a reviewer-route gate.
const ESCAPE_MARKERS := ["docs/archive", "(historical)", "(llm-player)"]

var _h := ValidatorHarness.new("reviewer facts")


func _initialize() -> void:
	print("=== Reviewer facts (invocations and model ids live only in .claude/REVIEWERS.md) ===")

	if not FileAccess.file_exists(HOME_FILE):
		_h.fail("%s is missing — the single home for reviewer facts must exist, or every pointer to it is dead"
			% HOME_FILE.trim_prefix("res://"))
		_h.finish(self)
		return
	_check_home_is_populated()
	_check_launcher_matches_roster()

	var files := _markdown_files(SCAN_ROOT)
	if files.is_empty():
		_h.fail("found no markdown to scan — the scan roots are wrong, so this validator is checking nothing")
		_h.finish(self)
		return

	var hits := 0
	for path in files:
		hits += _check_file(path)

	print("Scanned %d file(s) outside the roster, %d forbidden fragment(s)." % [files.size(), hits])
	_h.finish(self)


## The gate would otherwise pass if the roster were emptied: no copies anywhere, and no home either.
func _check_home_is_populated() -> void:
	var text := FileAccess.get_file_as_string(HOME_FILE)
	var missing: Array[String] = []
	for fragment in FORBIDDEN:
		if not text.contains(fragment):
			missing.append(fragment)
	if not missing.is_empty():
		_h.fail("%s no longer names %s — a fragment this validator forbids elsewhere must be documented HERE, or it lives nowhere"
			% [HOME_FILE.trim_prefix("res://"), ", ".join(missing)])


## The launcher is the EXECUTABLE copy of the roster's round, so the two drifting apart is the same defect
## this validator exists to prevent — with the worse property that the doc looks right while the round runs
## something else. This compares the two as KEYED SETS: reviewer name, role, and exact command.
##
## Three attempts, because the first two were each defeated by a reviewer on paper:
##   1. "every command appears somewhere in the roster" — deleting or duplicating a route passed.
##   2. "…and the quorum/extra COUNTS match" — swapping which NAME held which role passed (3/2 intact).
##   3. "…and the NAMES match" — swapping the COMMANDS between an `agy` row and a `minimax` row passed,
##      putting a tier-3 route in a quorum slot with every name and count still correct.
## Only an exact name→role→command mapping closes it, which is why the roster now carries that mapping in
## a fenced block instead of only in prose. EXPECTED_QUORUM/EXPECTED_EXTRA stay as the backstop: they pin
## the USER's tiering itself, so editing both files in step still cannot quietly promote a tier-3 model.
func _check_launcher_matches_roster() -> void:
	if not FileAccess.file_exists(LAUNCHER_FILE):
		_h.fail("%s is missing — the roster documents it as the way to run a round"
			% LAUNCHER_FILE.trim_prefix("res://"))
		return
	var roster_rows := _roster_rows()
	if roster_rows.is_empty():
		_h.fail("%s has no machine-readable round block (rows like `sol  quorum  <command>`) — without it the launcher cannot be checked against the roster at all"
			% HOME_FILE.trim_prefix("res://"))
		return
	var launcher_rows := {}
	var regex := RegEx.create_from_string(LAUNCHER_ROW_PATTERN)
	var seen_names := {}
	var quorum_found: Array[String] = []
	var extra_found: Array[String] = []
	for line in FileAccess.get_file_as_string(LAUNCHER_FILE).split("\n"):
		var found := regex.search(String(line))
		if found == null:
			continue
		var name := found.get_string(1)
		var role := found.get_string(2)
		var command := found.get_string(3).strip_edges()
		if seen_names.has(name):
			_h.fail("%s declares the reviewer `%s` twice — a duplicated row would run the same model as two independent returns and satisfy the quorum by itself"
				% [LAUNCHER_FILE.trim_prefix("res://"), name])
		seen_names[name] = true
		launcher_rows[name] = "%s\t%s" % [role, command]
		if role == "quorum":
			quorum_found.append(name)
		else:
			extra_found.append(name)
	# WHO holds each role, not how many. Swapping the tier-3 MiniMax row to `quorum` and the tier-2
	# DeepSeek row to `extra` preserves the 3/2 counts, the unique names and every roster command — and
	# lets a tier-3 model satisfy a round. Sets, therefore, not totals (reviewer finding, round 5).
	quorum_found.sort()
	extra_found.sort()
	var want_quorum := EXPECTED_QUORUM.duplicate()
	var want_extra := EXPECTED_EXTRA.duplicate()
	want_quorum.sort()
	want_extra.sort()
	if quorum_found != want_quorum:
		_h.fail("%s runs quorum reviewers %s; the roster's round is %s. WHO can satisfy a quorum is the rule the tiering exists to enforce — a tier-3 model promoted here would count toward a round it must never count toward"
			% [LAUNCHER_FILE.trim_prefix("res://"), str(quorum_found), str(want_quorum)])
	if extra_found != want_extra:
		_h.fail("%s runs non-quorum extras %s; expected %s. A tier-2 reviewer demoted to extra silently shrinks the quorum to two routes"
			% [LAUNCHER_FILE.trim_prefix("res://"), str(extra_found), str(want_extra)])

	# Keyed comparison: same names, and for each name the same role AND the same command.
	for name in launcher_rows:
		if not roster_rows.has(name):
			_h.fail("%s runs reviewer `%s`, which the roster's round block does not list"
				% [LAUNCHER_FILE.trim_prefix("res://"), name])
			continue
		if roster_rows[name] != launcher_rows[name]:
			var want: PackedStringArray = String(roster_rows[name]).split("\t")
			var got: PackedStringArray = String(launcher_rows[name]).split("\t")
			_h.fail("reviewer `%s` differs between the roster and the launcher — roster says role `%s` running `%s`; %s runs role `%s` running `%s`. Swapping a command between two rows is how a tier-3 route reaches a quorum slot with every name and count still looking right"
				% [name, want[0], want[1], LAUNCHER_FILE.trim_prefix("res://"), got[0], got[1]])
	for name in roster_rows:
		if not launcher_rows.has(name):
			_h.fail("the roster's round block lists reviewer `%s`, which %s does not run — a documented reviewer that never launches is a quorum slot that can never be filled"
				% [name, LAUNCHER_FILE.trim_prefix("res://")])


## Parses the roster's fenced `name  role  command` block into {name: "role\tcommand"}.
func _roster_rows() -> Dictionary:
	var rows := {}
	var regex := RegEx.create_from_string(ROSTER_ROW_PATTERN)
	for line in FileAccess.get_file_as_string(HOME_FILE).split("\n"):
		var found := regex.search(String(line))
		if found == null:
			continue
		rows[found.get_string(1)] = "%s\t%s" % [found.get_string(2), found.get_string(3)]
	return rows


func _check_file(path: String) -> int:
	var text := FileAccess.get_file_as_string(path)
	var lines := text.split("\n")
	var hits := 0
	for index in range(lines.size()):
		var line := String(lines[index])
		if _is_escaped(line):
			continue
		for fragment in FORBIDDEN:
			if not line.contains(fragment):
				continue
			hits += 1
			_h.fail("%s:%d contains `%s` — reviewer invocations and model ids belong only in %s, which is why the copies there went stale. Point at it instead, or mark the line `(historical)` if it is a record of a past run."
				% [path.trim_prefix("res://"), index + 1, fragment, HOME_FILE.trim_prefix("res://")])
	return hits


func _is_escaped(line: String) -> bool:
	for marker in ESCAPE_MARKERS:
		if line.contains(marker):
			return true
	return false


## Walks the whole project for markdown, minus the history exclusions and the home file itself.
func _markdown_files(root: String) -> Array[String]:
	var out: Array[String] = []
	var pending: Array[String] = [root]
	# A symlink to an ancestor would otherwise walk forever, and a symlink can reach a directory the
	# lexical EXCLUDED_PREFIXES test would have rejected. Canonical paths are the loop guard.
	var visited := {}
	while not pending.is_empty():
		var dir_path: String = pending.pop_back()
		if dir_path.count("/") - SCAN_ROOT.count("/") > MAX_DEPTH:
			continue
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		var canonical := ProjectSettings.globalize_path(dir_path).simplify_path()
		if visited.has(canonical):
			continue
		visited[canonical] = true
		# `simplify_path()` is LEXICAL — it collapses `.`/`..` and does not resolve links, so the visited
		# set alone is not a loop guard (reviewer finding, round 4: my first fix was a false sense of
		# safety). The DEPTH CAP below is the real guard: a symlink cycle terminates at MAX_DEPTH, and
		# nothing legitimate is skipped, because the deepest markdown here sits at depth 3
		# (`.claude/skills/<name>/SKILL.md`, `docs/systems/<module>/RETRO.md`).
		#
		# `DirAccess.is_link()` was tried first and REJECTED on measurement: skipping directories it
		# reported as links dropped the scan from 113 files to 100, in a repository that contains no
		# symlinks at all (`find . -type l` is empty). A guard that silently stops scanning 13 real files
		# is the same failure as the hidden-directory bug it was meant to complement.
		# MUST be set: DirAccess hides dotted entries by default, and `.claude/` — the skills, the roster,
		# every agent-facing instruction in this repo — is a hidden directory. Without this the walker
		# scanned 89 files, silently skipped all 20 under `.claude`, and passed a `pi -p` line injected
		# into a skill. A gate that cannot see the files it exists to guard is worse than no gate.
		dir.include_hidden = true
		for sub in dir.get_directories():
			var sub_path := "%s%s/" % [dir_path, sub] if dir_path.ends_with("/") else "%s/%s/" % [dir_path, sub]
			if not _is_excluded_dir(sub_path):
				pending.append(sub_path.trim_suffix("/"))
		for entry in dir.get_files():
			if not entry.ends_with(".md"):
				continue
			if entry in EXCLUDED_BASENAMES:
				continue
			var path := "%s%s" % [dir_path, entry] if dir_path.ends_with("/") else "%s/%s" % [dir_path, entry]
			if path == HOME_FILE:
				continue
			out.append(path)
	out.sort()
	return out


func _is_excluded_dir(dir_path: String) -> bool:
	for prefix in EXCLUDED_PREFIXES:
		if dir_path.begins_with(prefix):
			return true
	return false
