# Run from the project root:
# godot --headless --path . -s res://tools/validate_llm_api_purity.gd
extends SceneTree

# Guards the load-bearing invariant documented at the top of scripts/LLMGameAPI.gd: that file must
# never NAME an autoload, nor any class that does, because the validators and the batch runner load
# it from `-s` SceneTree tools where autoload singletons are not registered as identifiers. A direct
# reference compiles fine in the game and fails every tool script with
# `Identifier not found: GameData` — an error pointing nowhere near the edit. Plan 0032 broke this
# and took four validators plus the batch runner down.
#
# The banned set is DERIVED, not hand-maintained: start from the three autoload identifiers, mark
# any class_name whose source names one, and iterate to a fixpoint so transitive taint is caught
# (LLMGameAPI -> TurnConductor -> GameData was the actual 0032 break). Comments and string literals
# are stripped first, so prose about GameData — including the header explaining this rule — is fine.
#
# Prints PASS:/FAIL: for the gate's verdict.

const GUARDED_PATH := "res://scripts/LLMGameAPI.gd"
const SCRIPT_DIRS := ["res://scripts"]
const AUTOLOADS := ["GameData", "EventBus", "GameState"]

var _failures: Array[String] = []


func _initialize() -> void:
	print("=== LLMGameAPI purity (no autoload identifiers) ===")

	var sources := _collect_sources(SCRIPT_DIRS)
	var tainted := _tainted_classes(sources)
	print("Autoload-touching classes (%d): %s" % [tainted.size(), ", ".join(_sorted(tainted))])

	var banned: Dictionary = {}
	for name in AUTOLOADS:
		banned[name] = true
	for class_id in tainted:
		banned[class_id] = true
	banned.erase(_class_name_of(GUARDED_PATH, sources))

	_check_identifiers(GUARDED_PATH, banned)
	_check_loads(GUARDED_PATH)

	if _failures.is_empty():
		print("PASS: LLMGameAPI names no autoload and no autoload-touching class.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("FAIL: LLMGameAPI purity found %d issue(s) — move the logic to a home that takes its inputs as arguments (see AirInsertionState.eligible_orders)." % _failures.size())
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


## Fixpoint over "names an autoload, or names a class that does". Returns the set of class_names.
func _tainted_classes(sources: Dictionary) -> Dictionary:
	var class_by_path: Dictionary = {}
	for path in sources.keys():
		var class_id := _class_name_of(String(path), sources)
		if not class_id.is_empty():
			class_by_path[path] = class_id

	var tainted: Dictionary = {}
	var changed := true
	while changed:
		changed = false
		for path in class_by_path.keys():
			var class_id := String(class_by_path[path])
			if tainted.has(class_id):
				continue
			var body: String = sources[path]
			var names: Array[String] = []
			names.append_array(AUTOLOADS)
			names.append_array(_sorted(tainted))
			for name in names:
				if name == class_id:
					continue
				if _names_identifier(body, name):
					tainted[class_id] = true
					changed = true
					break
	return tainted


func _check_identifiers(path: String, banned: Dictionary) -> void:
	var raw := FileAccess.get_file_as_string(path)
	var lines := raw.split("\n")
	for index in range(lines.size()):
		var line := _strip_comments_and_strings(String(lines[index]))
		for name in banned.keys():
			if _names_identifier(line, String(name)):
				_failures.append("%s:%d names '%s'" % [path.trim_prefix("res://"), index + 1, name])


## The invariant's real-world consequence: the script must resolve when loaded the way a `-s` tool
## script loads it. A compile failure here is the exact 0032 symptom.
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
