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
			var parts := dot_path.split(".")
			
			var current: Dictionary = parsed
			for i in range(parts.size() - 1):
				var part := parts[i]
				if not current.has(part):
					push_error("Override path not found: %s in %s" % [override_key, path])
					assert(false, "Override path not found")
				if typeof(current[part]) != TYPE_DICTIONARY:
					push_error("Override path traverses non-Dictionary: %s at %s" % [override_key, part])
					assert(false, "Override path traverses non-Dictionary")
				current = current[part]
			
			var final_part := parts[-1]
			if not current.has(final_part):
				push_error("Override path final key not found: %s in %s" % [override_key, path])
				assert(false, "Override path final key not found")
			
			current[final_part] = active_map[override_key]
			applied_tracker[override_key] = true
			
	return parsed


## Returns any override keys that have not matched a loaded file. Checked at process end.
static func unapplied() -> Array[String]:
	var result: Array[String] = []
	for key: String in map().keys():
		if not _applied_keys.has(key):
			result.append(key)
	return result
