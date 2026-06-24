# Run from the project root:
# C:\Godot_v4.7-stable_win64.exe --headless --path C:\Users\mdogg\Desktop\HexCombat -s res://tools/validate_offload_data.gd
extends SceneTree

const OFFLOAD_RATES_PATH := "res://data/offload_rates.json"

var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Offload data validation ===")
	_validate_offload_rates_json()
	_validate_offload_rates_constants_match_json()
	_finish()


func _validate_offload_rates_json() -> void:
	var file := FileAccess.open(OFFLOAD_RATES_PATH, FileAccess.READ)
	if file == null:
		_fail("Could not open %s" % OFFLOAD_RATES_PATH)
		return

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		_fail("offload_rates.json did not parse to a Dictionary")
		return

	var rates = parsed.get("rates", null)
	if not (rates is Dictionary):
		_fail("offload_rates.json missing 'rates' object")
		return

	for key in OffloadRates.REQUIRED_RATE_KEYS:
		if not (key in rates):
			_fail("offload_rates.json missing required key: %s" % key)
		elif float(rates[key]) < 0.0:
			_fail("offload_rates.json key %s has negative value: %s" % [key, rates[key]])

	print("offload_rates.json: %d required keys present" % OffloadRates.REQUIRED_RATE_KEYS.size())


func _validate_offload_rates_constants_match_json() -> void:
	var file := FileAccess.open(OFFLOAD_RATES_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return
	var rates: Dictionary = parsed.get("rates", {})

	var checks := {
		"beach_base": OffloadRates.BEACH_BASE,
		"jackup_barge": OffloadRates.JACKUP_BARGE,
		"floating_pier": OffloadRates.FLOATING_PIER,
		"operational_port": OffloadRates.OPERATIONAL_PORT,
		"degraded_port": OffloadRates.DEGRADED_PORT,
		"seized_port": OffloadRates.SEIZED_PORT,
		"operational_airbridge": OffloadRates.OPERATIONAL_AIRBRIDGE,
		"degraded_airbridge": OffloadRates.DEGRADED_AIRBRIDGE,
		"seized_airbridge": OffloadRates.SEIZED_AIRBRIDGE,
	}
	for key in checks.keys():
		if key in rates:
			var json_val := float(rates[key])
			var const_val := float(checks[key])
			if not is_equal_approx(json_val, const_val):
				_fail("OffloadRates.%s (%s) does not match JSON value (%s)" % [key.to_upper(), const_val, json_val])

	print("OffloadRates constants match JSON values")


func _fail(message: String) -> void:
	_failures.append(message)
	push_error(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: Offload data validation succeeded")
		quit(0)
		return
	print("FAIL: Offload data validation found %d issue(s):" % _failures.size())
	for failure in _failures:
		print("  - %s" % failure)
	quit(1)
