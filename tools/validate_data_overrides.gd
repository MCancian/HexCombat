# Run from the project root:
# godot --headless --path . -s res://tools/validate_data_overrides.gd
extends SceneTree

var _h := ValidatorHarness.new("data overrides validation")


func _initialize() -> void:
	print("=== Data Overrides validation ===")
	_validate_empty_map()
	_validate_nested_path()
	_validate_address_normalization()
	_validate_unapplied_tracking()
	_validate_array_all_elements()
	_validate_array_indexed_element()
	_h.finish(self)


func _validate_empty_map() -> void:
	var parsed: Dictionary = {"some": "value"}
	var applied := DataOverrides.apply_map({}, "data/scenario.json", parsed.duplicate(true), {})
	if applied.hash() != parsed.hash():
		_h.fail("Empty map altered the structure")
	print("  Empty map -> no-op OK")


func _validate_nested_path() -> void:
	var parsed: Dictionary = {
		"level1": {
			"level2": {
				"target": 10
			}
		},
		"other": 5
	}
	var map: Dictionary = {
		"data/scenario.json:level1.level2.target": 20
	}
	var tracker := {}
	var applied := DataOverrides.apply_map(map, "data/scenario.json", parsed.duplicate(true), tracker)
	
	if applied["level1"]["level2"]["target"] != 20:
		_h.fail("Failed to apply nested override, got %s" % applied["level1"]["level2"]["target"])
	if applied["other"] != 5:
		_h.fail("Override altered sibling key")
	if not tracker.has("data/scenario.json:level1.level2.target"):
		_h.fail("Applied key not tracked")
		
	print("  Nested path override OK")


func _validate_address_normalization() -> void:
	var parsed: Dictionary = {"target": 1}
	var map: Dictionary = {
		"data/x.json:target": 2
	}
	var tracker := {}
	# Applying to "res://data/x.json" should match the "data/x.json:target" rule.
	var applied := DataOverrides.apply_map(map, "res://data/x.json", parsed.duplicate(true), tracker)
	if applied["target"] != 2:
		_h.fail("Failed to normalize res:// path")
	
	print("  Address normalization OK")


func _validate_unapplied_tracking() -> void:
	DataOverrides.set_map({
		"data/scenario.json:level1.target": 10,
		"data/other.json:missing": 5
	})
	
	var parsed: Dictionary = {"level1": {"target": 1}}
	DataOverrides.apply("data/scenario.json", parsed)
	
	var unapplied := DataOverrides.unapplied()
	if unapplied.size() != 1 or unapplied[0] != "data/other.json:missing":
		_h.fail("Unapplied tracking failed: expected [data/other.json:missing], got %s" % unapplied)
	
	print("  Unapplied tracking OK")


func _validate_array_all_elements() -> void:
	# "beaches[*].capacity" (and the "[]" alias) must set the field on EVERY element — the mechanism
	# that makes an array knob (e.g. beach capacity) sweepable with one override.
	for selector in ["*", ""]:
		var parsed: Dictionary = {"beaches": [{"cap": 2}, {"cap": 4}, {"cap": 2}]}
		var map := {"data/beaches.json:beaches[%s].cap" % selector: 6}
		var tracker := {}
		var applied := DataOverrides.apply_map(map, "data/beaches.json", parsed.duplicate(true), tracker)
		for beach in applied["beaches"]:
			if beach["cap"] != 6:
				_h.fail("Array all-elements override [%s] missed an element: %s" % [selector, applied["beaches"]])
		if not tracker.has("data/beaches.json:beaches[%s].cap" % selector):
			_h.fail("Array all-elements override [%s] not tracked" % selector)
	print("  Array all-elements override OK")


func _validate_array_indexed_element() -> void:
	# "beaches[1].cap" must touch ONLY element 1.
	var parsed: Dictionary = {"beaches": [{"cap": 2}, {"cap": 4}, {"cap": 2}]}
	var map := {"data/beaches.json:beaches[1].cap": 9}
	var applied := DataOverrides.apply_map(map, "data/beaches.json", parsed.duplicate(true), {})
	if applied["beaches"][1]["cap"] != 9:
		_h.fail("Indexed override did not set element 1: %s" % applied["beaches"])
	if applied["beaches"][0]["cap"] != 2 or applied["beaches"][2]["cap"] != 2:
		_h.fail("Indexed override touched other elements: %s" % applied["beaches"])
	print("  Array indexed override OK")
