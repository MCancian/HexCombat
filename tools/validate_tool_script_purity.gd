# Run from the project root:
# godot --headless --path . -s res://tools/validate_tool_script_purity.gd
extends SceneTree

# Guards the load-bearing invariant documented at the top of scripts/api/LLMGameAPI.gd, for EVERY script
# it actually applies to — not just that one file.
#
# THE INVARIANT: a `-s` SceneTree tool script is loaded BEFORE the autoload singletons are registered
# as identifiers. Every class the tool NAMES in its source is therefore compiled at that moment too,
# along with everything those classes name, and so on. If anything in that compile-time closure names
# `GameData` / `GameState` / `EventBus` as an identifier, the whole chain fails to compile with
# `Identifier not found: GameData` — an error pointing nowhere near the edit.
#
# A class reached only at RUNTIME (through a Node reference, e.g. GameState.resolve_turn -> …) is
# compiled later, once the autoloads exist, and is NOT subject to this rule. That is why
# TurnConductor may name GameData freely: no tool names it. If a tool ever does, this gate fails and
# says so, instead of the gate hanging.
#
# WHY IT HANGS RATHER THAN FAILING: the tool's own `_initialize` still runs and prints its banner, but
# the failed call never reaches `quit()`, so the SceneTree spins forever and the gate's thread pool
# never completes. Measured 2026-07-25: ~10 minutes per run, twice, with no diagnostic.
# (`run_all_tests.py` now passes `--quit-after` so this degrades to a loud failure.)
#
# SCOPE, DERIVED NOT HAND-MAINTAINED: seed = every script any tools/*.gd pulls in, by `class_name`
# OR by a literal `preload("res://…")` / `load("res://…")` path, then walk transitively. A hand-kept
# list of "tool-reachable scripts" would rot on the first new tool; this recomputes on every run.
# Plan 0032 broke the LLMGameAPI case and took four validators plus the batch runner down; plan 0037
# broke SelfPlayRunner, which the old single-file version did not cover.
#
# The closure is keyed on PATHS, not class names, so a script with NO class_name that is preloaded by
# path is still covered (tools/validate_ship_data.gd:9 does exactly that). A path built at runtime
# rather than written as a literal cannot be followed — that is the one known blind spot, and it is
# backstopped rather than silent: such a script still fails to COMPILE, which run_all_tests.py catches
# as SCRIPT ERROR. This gate exists to name the offending file:line instead of making you find it.
#
# Comments and string literals are stripped first, so prose about GameData — including this header —
# is fine. Prints PASS:/FAIL: for the gate's verdict.

const TOOL_DIR := "res://tools"
const SCRIPT_DIRS := ["res://scripts"]
const AUTOLOADS := ["GameData", "EventBus", "GameState"]

var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Tool-script purity (no autoload identifiers in the -s compile closure) ===")

	var sources := _collect_sources(SCRIPT_DIRS)
	var class_paths := _class_paths(sources)
	var guarded := _tool_reachable_closure(sources, class_paths)
	print("Scripts reachable at compile time from tools/*.gd (%d):" % guarded.size())
	for path in _sorted(guarded):
		print("  %s" % path.trim_prefix("res://"))

	for path in _sorted(guarded):
		_check_identifiers(path, _class_name_of(path, sources))
		_check_loads(path)

	if _failures.is_empty():
		print("PASS: %d tool-reachable script(s) name no autoload." % guarded.size())
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("FAIL: tool-script purity found %d issue(s) — reach the autoload through a get_node() accessor instead (see LLMGameAPI._game_state / SelfPlayRunner._gs), or move the logic to a home that takes its inputs as arguments (see AirInsertionState.eligible_orders)." % _failures.size())
		quit(1)


## path -> stripped source, for every .gd under the given roots.
func _collect_sources(roots: Array) -> Dictionary:
	var sources: Dictionary = {}
	var pending: Array[String] = []
	for root in roots:
		pending.append(String(root))
	while not pending.is_empty():
		var dir_path: String = pending.pop_back()
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			var full := "%s/%s" % [dir_path, entry]
			if dir.current_is_dir():
				pending.append(full)
			elif entry.ends_with(".gd"):
				sources[full] = _strip_comments_and_strings(FileAccess.get_file_as_string(full))
			entry = dir.get_next()
		dir.list_dir_end()
	return sources


## class_name -> path, for every script under SCRIPT_DIRS that declares one.
func _class_paths(sources: Dictionary) -> Dictionary:
	var class_paths: Dictionary = {}
	for path in sources.keys():
		var class_id := _class_name_of(String(path), sources)
		if not class_id.is_empty():
			class_paths[class_id] = path
	return class_paths


## Every script reachable at compile time from a tool script: named by class_name, or preloaded by a
## literal path, transitively. This is exactly the set GDScript compiles while loading a `-s` tool,
## which is exactly the set the autoload rule binds. Tool scripts themselves are NOT in it: they are
## the entry point, they run after the SceneTree exists, and they legitimately hold autoload Nodes in
## local vars of the same name. Returns path -> true.
func _tool_reachable_closure(sources: Dictionary, class_paths: Dictionary) -> Dictionary:
	var pending: Array[String] = []
	for tool_path in _tool_scripts():
		pending.append_array(_referenced_paths(String(tool_path), class_paths, sources))

	var closure: Dictionary = {}
	while not pending.is_empty():
		var path: String = pending.pop_back()
		if closure.has(path):
			continue
		closure[path] = true
		for next_path in _referenced_paths(path, class_paths, sources):
			if not closure.has(next_path):
				pending.append(next_path)
	return closure


## Scripts the file at `path` pulls in: every class_name it names, plus every literal preload/load
## path. Literal paths are what makes a class_name-less script visible; anything else is invisible by
## construction.
##
## Identifiers are matched against the STRIPPED body (prose about GameData must not count) but the
## preload paths are matched against the RAW one — stripping blanks string literals, which is exactly
## where those paths live.
func _referenced_paths(path: String, class_paths: Dictionary, sources: Dictionary) -> Array[String]:
	var raw := FileAccess.get_file_as_string(path)
	var stripped: String = sources.get(path, _strip_comments_and_strings(raw))
	var out: Array[String] = []
	for class_id in class_paths.keys():
		if _names_identifier(stripped, String(class_id)):
			out.append(String(class_paths[class_id]))
	var literal := RegEx.new()
	literal.compile("(?:preload|load)\\(\\s*\"(res://[^\"]+\\.gd)\"")
	for found in literal.search_all(_without_comments(raw)):
		var found_path := found.get_string(1)
		if sources.has(found_path):
			out.append(found_path)
	return out


## Comments only — a commented-out preload is not a reference, but its path string must survive the
## scan that string-stripping would otherwise destroy.
func _without_comments(body: String) -> String:
	var regex := RegEx.new()
	regex.compile("(?m)#.*$")
	return regex.sub(body, "", true)


func _tool_scripts() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(TOOL_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".gd"):
			out.append("%s/%s" % [TOOL_DIR, entry])
		entry = dir.get_next()
	dir.list_dir_end()
	return out


func _check_identifiers(path: String, class_id: String) -> void:
	var raw := FileAccess.get_file_as_string(path)
	var lines := raw.split("\n")
	for index in range(lines.size()):
		var line := _strip_comments_and_strings(String(lines[index]))
		for name in AUTOLOADS:
			if name == class_id:
				continue
			if _names_identifier(line, String(name)):
				_failures.append("%s:%d names '%s'" % [path.trim_prefix("res://"), index + 1, name])


## The invariant's real-world consequence: the script must resolve when loaded the way a `-s` tool
## script loads it. A compile failure here is the exact 0032 / 0037 symptom.
func _check_loads(path: String) -> void:
	if load(path) == null:
		_failures.append("%s failed to load (compile error — check for autoload references)" % path)


func _class_name_of(path: String, sources: Dictionary) -> String:
	var body: String = sources.get(path, "")
	var regex := RegEx.new()
	regex.compile("(?m)^class_name\\s+([A-Za-z_][A-Za-z0-9_]*)")
	var found := regex.search(body)
	return found.get_string(1) if found != null else ""


## Whole-identifier match, so 'GameStateData' never counts as a hit for 'GameState'.
func _names_identifier(body: String, identifier: String) -> bool:
	var regex := RegEx.new()
	regex.compile("(?<![A-Za-z0-9_])%s(?![A-Za-z0-9_])" % identifier)
	return regex.search(body) != null


## Comments and string literals are prose, not references — the header explaining this very rule
## talks about GameData at length.
func _strip_comments_and_strings(body: String) -> String:
	var without_strings := RegEx.new()
	without_strings.compile("\"[^\"\\n]*\"|'[^'\\n]*'")
	var stripped := without_strings.sub(body, "\"\"", true)
	var without_comments := RegEx.new()
	without_comments.compile("(?m)#.*$")
	return without_comments.sub(stripped, "", true)


func _sorted(set_dict: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for key in set_dict.keys():
		out.append(String(key))
	out.sort()
	return out
