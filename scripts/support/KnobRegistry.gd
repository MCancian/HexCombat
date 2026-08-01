class_name KnobRegistry
extends RefCounted

## Pure resolver for the research-knob registry (plan 0018). Reads data/knobs/registry.json and,
## for each knob, extracts its RESOLVED value (baseline JSON ⊕ active DataOverrides) so every game
## record can carry the full knob vector and be compared across sweeps. No autoload/GameState
## coupling — takes the active scenario path as an argument, which is what makes it unit-testable.
##
## Registry-path prefixes (this class owns these; the dot-path/array grammar after the ":" is
## JsonPath's — its header is the canonical spec):
##   "scenario:<dot.path>"          -> resolved against the ACTIVE scenario file (variants work)
##   "<data/rel/file.json>:<dot>"   -> a literal data file
## A "kind" entry (llm_model / prompt_hash) carries no path — the caller supplies those values.

const REGISTRY_PATH := "res://data/knobs/registry.json"
const SCENARIO_SENTINEL := "scenario:"


static func load_registry() -> Dictionary:
	var file := FileAccess.open(REGISTRY_PATH, FileAccess.READ)
	assert(file != null, "Knob registry not found: %s" % REGISTRY_PATH)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary and (parsed as Dictionary).has("knobs"),
		"Knob registry malformed (expected a Dictionary with a 'knobs' array): %s" % REGISTRY_PATH)
	return parsed


static func knobs() -> Array:
	return load_registry().get("knobs", [])


static func version() -> int:
	return int(load_registry().get("version", 0))


## Resolve the full knob vector: {knob_id -> resolved value}. `llm_model` / `prompt_hash` kinds are
## filled from the passed-in values (empty for non-LLM games); path knobs are read from disk with
## the active override map applied. A path that does not resolve yields null (see validator).
static func resolve_all(scenario_path: String, llm_model: String = "", llm_prompt_hash: String = "") -> Dictionary:
	var out: Dictionary = {}
	var active_map := DataOverrides.map()
	for entry_value in knobs():
		var entry: Dictionary = entry_value
		var id := String(entry["id"])
		if entry.has("kind"):
			match String(entry["kind"]):
				"llm_model": out[id] = llm_model
				"prompt_hash": out[id] = llm_prompt_hash
				_: out[id] = null
		else:
			out[id] = resolve_path(String(entry["path"]), scenario_path, active_map)
	return out


## Resolve a single "file:dot.path" (or scenario:dot.path) to its overridden value, or null if the
## file/keys do not resolve. `active_map` is DataOverrides.map(); applied via the pure apply_map so
## this never mutates DataOverrides' global applied-key tracker.
static func resolve_path(path: String, scenario_path: String, active_map: Dictionary) -> Variant:
	var split := _split_path(path, scenario_path)
	var res_file: String = split[0]
	var dot_path: String = split[1]
	var file := FileAccess.open(res_file, FileAccess.READ)
	if file == null:
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary and not active_map.is_empty():
		parsed = DataOverrides.apply_map(active_map, res_file, parsed, {})
	return _extract(parsed, dot_path)


## True when the knob is scenario-sourced — such a knob may be legitimately absent from a given
## scenario (the engine falls back to its code default), so a null resolution is not an error.
static func is_scenario_knob(entry: Dictionary) -> bool:
	return entry.has("path") and String(entry["path"]).begins_with(SCENARIO_SENTINEL)


static func _split_path(path: String, scenario_path: String) -> Array:
	if path.begins_with(SCENARIO_SENTINEL):
		return [scenario_path, path.trim_prefix(SCENARIO_SENTINEL)]
	var colon := path.find(":")
	assert(colon > 0, "Malformed knob path (expected 'file:dot.path'): %s" % path)
	return ["res://" + path.substr(0, colon), path.substr(colon + 1)]


## Traverse a parsed JSON value by dot path, per the shared JsonPath grammar. An all-elements array
## segment ("name[]"/"name[*]") projects the remaining path over EVERY element (returns an Array); an
## indexed segment ("name[N]") selects one. Read side: lenient — null on any missing key, out-of-range
## index, or type mismatch.
static func _extract(parsed: Variant, dot_path: String) -> Variant:
	var parts := dot_path.split(".")
	var current: Variant = parsed
	for i in range(parts.size()):
		var segment := JsonPath.parse_segment(parts[i])
		var key: String = segment["key"]
		if not (current is Dictionary) or not (current as Dictionary).has(key):
			return null
		if not segment["is_array"]:
			current = current[key]
			continue
		var arr: Variant = current[key]
		if not (arr is Array):
			return null
		var rest := ".".join(parts.slice(i + 1))
		if JsonPath.is_all_elements(segment["selector"]):
			var projected: Array = []
			for element in arr:
				projected.append(element if rest.is_empty() else _extract(element, rest))
			return projected
		var selection := JsonPath.select_indices(arr, segment["selector"])
		if not selection["valid"]:
			return null
		var index: int = selection["indices"][0]
		return arr[index] if rest.is_empty() else _extract(arr[index], rest)
	return current
