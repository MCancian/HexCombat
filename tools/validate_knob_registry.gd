# Validates the research-knob registry (plan 0018): structural integrity + that every path knob
# resolves against the default research scenario. Catches typos and the silent-default bug class
# (a knob whose path no longer matches its data file would resolve null and silently vanish from
# the record). Run headless: godot --headless --path <repo> -s res://tools/validate_knob_registry.gd
extends SceneTree

const DEFAULT_SCENARIO := "res://data/scenario_default.json"
const VALID_KINDS := ["llm_model", "prompt_hash"]

var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Knob registry validation ===")
	_validate()
	_finish()


func _validate() -> void:
	var registry := KnobRegistry.load_registry()
	if int(registry.get("version", 0)) < 1:
		_fail("registry 'version' must be a positive integer")
	var knobs: Array = registry.get("knobs", [])
	if knobs.is_empty():
		_fail("registry has no knobs")
		return

	var active_map := DataOverrides.map()  # empty under the gate (no overrides) — resolves raw defaults
	var seen_ids: Dictionary = {}
	var resolved := 0
	for entry_value in knobs:
		var entry: Dictionary = entry_value
		_validate_entry_shape(entry, seen_ids)
		if entry.has("kind") or not entry.has("path"):
			continue
		var value: Variant = KnobRegistry.resolve_path(String(entry["path"]), DEFAULT_SCENARIO, active_map)
		if value == null:
			# Scenario knobs may be legitimately unset in a given scenario (code default applies);
			# a literal data-file knob resolving null is a real path typo.
			if KnobRegistry.is_scenario_knob(entry):
				print("  info: scenario knob '%s' unset in default scenario (code default applies)" % entry.get("id", "?"))
			else:
				_fail("knob '%s' path does not resolve: %s" % [entry.get("id", "?"), entry["path"]])
		else:
			resolved += 1

	print("Registry v%d: %d knobs, %d path knobs resolved against default scenario" % [
		int(registry.get("version", 0)), knobs.size(), resolved])


func _validate_entry_shape(entry: Dictionary, seen_ids: Dictionary) -> void:
	for required in ["id", "label", "group"]:
		if not entry.has(required):
			_fail("knob entry missing '%s': %s" % [required, entry])
	var id := String(entry.get("id", ""))
	if id.is_empty():
		_fail("knob entry has empty id: %s" % entry)
	elif seen_ids.has(id):
		_fail("duplicate knob id: %s" % id)
	seen_ids[id] = true
	if typeof(entry.get("sweepable")) != TYPE_BOOL:
		_fail("knob '%s' missing bool 'sweepable'" % id)
	var has_path := entry.has("path")
	var has_kind := entry.has("kind")
	if has_path == has_kind:
		_fail("knob '%s' must have exactly one of 'path' or 'kind'" % id)
	if has_kind and String(entry["kind"]) not in VALID_KINDS:
		_fail("knob '%s' has unknown kind: %s" % [id, entry["kind"]])
	if has_kind and bool(entry.get("sweepable", false)):
		_fail("knob '%s' is a captured 'kind' knob and cannot be sweepable" % id)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: Knob registry validation succeeded")
		quit(0)
	for failure in _failures:
		printerr("FAIL: %s" % failure)
	quit(1)
