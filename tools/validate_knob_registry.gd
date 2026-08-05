# Validates the research-knob registry (plan 0018): structural integrity + that every path knob
# resolves against the default research scenario. Catches typos and the silent-default bug class
# (a knob whose path no longer matches its data file would resolve null and silently vanish from
# the record). Run headless: godot --headless --path <repo> -s res://tools/validate_knob_registry.gd
extends SceneTree

const DEFAULT_SCENARIO := "res://data/scenarios/scenario_default.json"
const VALID_KINDS := ["llm_model", "prompt_hash"]
const SCENARIO_SENTINEL := "scenario:"

var _h := ValidatorHarness.new("Knob registry validation")


func _initialize() -> void:
	print("=== Knob registry validation ===")
	_validate()
	_h.finish(self)


func _validate() -> void:
	var registry := KnobRegistry.load_registry()
	if int(registry.get("version", 0)) < 1:
		_h.fail("registry 'version' must be a positive integer")
	var knobs: Array = registry.get("knobs", [])
	if knobs.is_empty():
		_h.fail("registry has no knobs")
		return

	var active_map := DataOverrides.map()  # empty under the gate (no overrides) — resolves raw defaults
	var seen_ids: Dictionary = {}
	var resolved := 0
	for entry_value in knobs:
		var entry: Dictionary = entry_value
		_validate_entry_shape(entry, seen_ids)
		var id := String(entry.get("id", "?"))
		_validate_consumer_witness(entry, id)
		if entry.has("kind") or not entry.has("path"):
			continue
		var value: Variant = KnobRegistry.resolve_path(String(entry["path"]), DEFAULT_SCENARIO, active_map)
		if value == null:
			# Scenario knobs may be legitimately unset in a given scenario (code default applies);
			# a literal data-file knob resolving null is a real path typo.
			if KnobRegistry.is_scenario_knob(entry):
				print("  info: scenario knob '%s' unset in default scenario (code default applies)" % id)
			else:
				_h.fail("knob '%s' path does not resolve: %s" % [id, entry["path"]])
		else:
			resolved += 1

	print("Registry v%d: %d knobs, %d path knobs resolved against default scenario" % [
		int(registry.get("version", 0)), knobs.size(), resolved])


func _validate_entry_shape(entry: Dictionary, seen_ids: Dictionary) -> void:
	for required in ["id", "label", "group"]:
		if not entry.has(required):
			_h.fail("knob entry missing '%s': %s" % [required, entry])
	var id := String(entry.get("id", ""))
	if id.is_empty():
		_h.fail("knob entry has empty id: %s" % entry)
	elif seen_ids.has(id):
		_h.fail("duplicate knob id: %s" % id)
	seen_ids[id] = true
	if typeof(entry.get("sweepable")) != TYPE_BOOL:
		_h.fail("knob '%s' missing bool 'sweepable'" % id)
	var has_path := entry.has("path")
	var has_kind := entry.has("kind")
	if has_path == has_kind:
		_h.fail("knob '%s' must have exactly one of 'path' or 'kind'" % id)
	if has_kind and String(entry["kind"]) not in VALID_KINDS:
		_h.fail("knob '%s' has unknown kind: %s" % [id, entry["kind"]])
	if has_kind and bool(entry.get("sweepable", false)):
		_h.fail("knob '%s' is a captured 'kind' knob and cannot be sweepable" % id)


## Backlog check (a) (bundled 2026-08-01): a sweepable knob whose registry path is a file-sourced
## dot-path (not `scenario:`, which funnels through the single always-live scenario dict) must name
## a real runtime reader. Without this, a path can be syntactically valid — the file loads, the key
## resolves — while nothing outside this validator ever reads it, exactly how `offload_beach_base_rate`
## went phantom: it pointed at `data/offload_rates.json`, a JSON file that is only a validation mirror
## (real throughput came from `OffloadRates` GDScript constants), so sweeping it silently no-op'd
## (docs/reports/2026-07-23-monte-carlo-outcome-distribution.md). Scoped to file-sourced knobs only —
## a scenario knob is read into a named GameData field by the single load_scenario() pipeline, which
## is a structurally different (and already-exercised) path than a standalone data file nothing loads.
func _validate_consumer_witness(entry: Dictionary, id: String) -> void:
	if not entry.has("path") or entry.has("kind"):
		return
	if not bool(entry.get("sweepable", false)):
		return
	var path := String(entry["path"])
	if path.begins_with(SCENARIO_SENTINEL):
		return
	if not entry.has("consumer"):
		_h.fail("knob '%s' is sweepable and file-sourced but has no 'consumer' witness ('path/to/file.gd:function_name' naming the real runtime reader)" % id)
		return
	var consumer := String(entry["consumer"])
	var colon := consumer.find(":")
	if colon <= 0:
		_h.fail("knob '%s' consumer witness malformed (expected 'path/to/file.gd:function_name'): %s" % [id, consumer])
		return
	var consumer_path := "res://" + consumer.substr(0, colon)
	var consumer_fn := consumer.substr(colon + 1)
	var file := FileAccess.open(consumer_path, FileAccess.READ)
	if file == null:
		_h.fail("knob '%s' consumer witness names a file that does not exist: %s" % [id, consumer_path])
		return
	if not file.get_as_text().contains("func %s(" % consumer_fn):
		_h.fail("knob '%s' consumer witness names a function not found in %s: %s" % [id, consumer_path, consumer_fn])
