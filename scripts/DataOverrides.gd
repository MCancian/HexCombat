class_name DataOverrides
extends RefCounted

const OVERRIDES_ARG_PREFIX := "--overrides="
const OVERRIDES_ENV_VAR := "HEXCOMBAT_OVERRIDES"

static var _is_initialized := false
static var _cached_map: Dictionary = {}
static var _applied_keys: Dictionary = {}


## Programmatic injection of the override map. Used by in-process sweeps.
## Resets the applied-tracking state so a fresh sweep cell tracks its own unapplied keys.
static func set_map(new_map: Dictionary) -> void:
	_cached_map = new_map.duplicate(true)
	_is_initialized = true
	_applied_keys.clear()


## Lazily load the override map from args/env, cache it, and return it.
static func map() -> Dictionary:
	if _is_initialized:
		return _cached_map
	
	_cached_map = _load_map(OS.get_cmdline_user_args(), OS.get_environment(OVERRIDES_ENV_VAR))
	_is_initialized = true
	_applied_keys.clear()
	return _cached_map


## Pure core for loading the map from OS state strings.
static func _load_map(user_args: PackedStringArray, env_value: String) -> Dictionary:
	var selection := ""
	for arg in user_args:
		if arg.begins_with(OVERRIDES_ARG_PREFIX):
			selection = arg.trim_prefix(OVERRIDES_ARG_PREFIX)
			break
	if selection.is_empty():
		selection = env_value
	
	if selection.strip_edges().is_empty():
		return {}
	
	var parsed: Variant
	if selection.begins_with("{"):
		parsed = JSON.parse_string(selection)
		assert(typeof(parsed) == TYPE_DICTIONARY, "Inline --overrides JSON must be a Dictionary")
	else:
		if not FileAccess.file_exists(selection):
			push_error("Overrides file not found: %s" % selection)
			assert(false, "Overrides file not found")
		var content := FileAccess.get_file_as_string(selection)
		parsed = JSON.parse_string(content)
		assert(typeof(parsed) == TYPE_DICTIONARY, "Overrides file must contain a JSON Dictionary")
	
	return parsed as Dictionary


## Apply the override map to a just-parsed JSON dictionary. Returns the mutated dictionary.
## Strict no-op fast-path when the map is empty.
static func apply(path: String, parsed: Variant) -> Variant:
	var active_map := map()
	if active_map.is_empty() or typeof(parsed) != TYPE_DICTIONARY:
		return parsed
	return apply_map(active_map, path, parsed, _applied_keys)


## Pure core of the apply logic, isolated for testing. Mutates `parsed` and records matches in `applied_tracker`.
static func apply_map(active_map: Dictionary, path: String, parsed: Dictionary, applied_tracker: Dictionary) -> Dictionary:
	var normalized_path := path.trim_prefix("res://")
	var file_prefix := normalized_path + ":"
	
	for override_key: String in active_map.keys():
		if override_key.begins_with(file_prefix):
			var dot_path := override_key.trim_prefix(file_prefix)
			_set_override(parsed, Array(dot_path.split(".")), active_map[override_key], override_key)
			applied_tracker[override_key] = true

	return parsed


## Recursively assign `value` at `parts` within `container`. A segment is either a plain dict key
## ("beach_base"), an all-elements array segment ("beaches[]" or "beaches[*]"), or an indexed array
## segment ("beaches[2]"). Array segments fan out — an all-elements segment writes every element,
## which is how a single override sweeps e.g. every beach's capacity at once. Fail-loud on any
## missing key / out-of-range index / type mismatch (a bad override path is a typo, never a default).
static func _set_override(container: Variant, parts: Array, value: Variant, override_key: String) -> void:
	var segment := String(parts[0])
	var is_last := parts.size() == 1
	var key := segment
	var selector := ""
	var has_bracket := segment.find("[") != -1
	if has_bracket:
		assert(segment.ends_with("]"), "Malformed array segment in override %s: %s" % [override_key, segment])
		var bracket := segment.find("[")
		key = segment.substr(0, bracket)
		selector = segment.substr(bracket + 1, segment.length() - bracket - 2)

	if not (container is Dictionary) or not (container as Dictionary).has(key):
		push_error("Override path not found: %s (missing key '%s')" % [override_key, key])
		assert(false, "Override path not found")
		return

	if not has_bracket:
		if is_last:
			container[key] = value
		else:
			_set_override(container[key], parts.slice(1), value, override_key)
		return

	var arr: Variant = container[key]
	if not (arr is Array):
		push_error("Override array segment on non-Array: %s at '%s'" % [override_key, key])
		assert(false, "Override array segment on non-Array")
		return
	for index in _selected_indices(arr, selector, override_key):
		if is_last:
			arr[index] = value
		else:
			_set_override(arr[index], parts.slice(1), value, override_key)


## Indices an array selector addresses: "" or "*" => every element; a digit string => that one index
## (fail-loud if out of range).
static func _selected_indices(arr: Array, selector: String, override_key: String) -> Array:
	if selector.is_empty() or selector == "*":
		return range(arr.size())
	assert(selector.is_valid_int(), "Malformed array index '%s' in override %s" % [selector, override_key])
	var index := int(selector)
	if index < 0 or index >= arr.size():
		push_error("Override array index out of range: %s (size %d)" % [override_key, arr.size()])
		assert(false, "Override array index out of range")
		return []
	return [index]


## Returns any override keys that have not matched a loaded file. Checked at process end.
static func unapplied() -> Array[String]:
	var result: Array[String] = []
	for key: String in map().keys():
		if not _applied_keys.has(key):
			result.append(key)
	return result
