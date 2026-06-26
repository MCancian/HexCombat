# Run from the project root:
# C:\Godot_v4.7-stable_win64.exe --headless --path C:\Users\mdogg\Desktop\HexCombat -s res://tools/validate_antiship_data.gd
#
# Validates the D3-A anti-ship / mine-warfare data layer: the five TIV-ported config JSONs load,
# the grouping spec expands into the expected per-(TO,type) system rows, and the minefield + catalog
# shapes match. Pure data-contract checks (no GameState).
extends SceneTree

const DIR := "res://data/antiship/"
# Expected total platforms per type_id, from antiship_grouping_spec.json group totals.
const EXPECTED_TYPE_TOTALS := {
	19: 4, 20: 10, 21: 6, 22: 6,        # destroyers / frigates (former type 1 split)
	16: 30, 17: 12, 18: 12,             # patrol boats (former type 2 split)
	3: 334,                             # air-launched AShM platforms
	23: 26, 24: 100,                    # mobile coastal launchers (former type 4 split)
	5: 104, 6: 2, 99: 4,               # static CDCMs, submarines, C2
}
const EXPECTED_TOTAL := 650
const VALID_TOS := [2, 3, 4, 5]

var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Anti-ship data validation ===")
	_validate_systems()
	_validate_combat_catalog()
	_validate_crossing_config()
	_validate_magazines()
	_validate_minefields()
	_finish()


func _validate_systems() -> void:
	var types := AntishipLoaders.load_system_types(DIR + "antiship_systems_consolidated.json")
	_assert_true("system catalog non-empty", types.size() > 0)
	for type_id in EXPECTED_TYPE_TOTALS.keys():
		_assert_true("system catalog has type %d" % type_id, types.has(type_id))

	var systems := AntishipLoaders.load_systems(DIR + "antiship_grouping_spec.json", types)
	_assert_true("system rows expanded", systems.size() > 0)

	var by_type: Dictionary = {}
	var total := 0
	for system in systems:
		_assert_true("system %d/%d quantity > 0" % [system.to_number, system.type_id], system.quantity > 0)
		_assert_true("system TO %d valid" % system.to_number, system.to_number in VALID_TOS)
		_assert_true("system %d has type_name" % system.type_id, system.type_name != "")
		by_type[system.type_id] = int(by_type.get(system.type_id, 0)) + system.quantity
		total += system.quantity
		# Aggregation invariant: at most one row per (TO, type_id).
		_assert_true("original_quantity seeded for %d/%d" % [system.to_number, system.type_id], system.original_quantity == system.quantity)

	for type_id in EXPECTED_TYPE_TOTALS.keys():
		_assert_equal_int("type %d total platforms" % type_id, int(by_type.get(type_id, -1)), int(EXPECTED_TYPE_TOTALS[type_id]))
	_assert_equal_int("total platforms across all systems", total, EXPECTED_TOTAL)

	# (TO, type_id) uniqueness after aggregation.
	var seen: Dictionary = {}
	for system in systems:
		var key := "%d:%d" % [system.to_number, system.type_id]
		_assert_true("unique (TO,type) row %s" % key, not seen.has(key))
		seen[key] = true


func _validate_combat_catalog() -> void:
	var catalog := AntishipLoaders.load_combat_catalog(DIR + "antiship_combat_catalog.json")
	_assert_equal_int("combat catalog munitions", (catalog["munitions"] as Dictionary).size(), 9)
	_assert_equal_int("combat catalog launchers", (catalog["launchers"] as Dictionary).size(), 12)
	_assert_true("combat catalog has store_groups", (catalog["store_groups"] as Dictionary).size() > 0)


func _validate_crossing_config() -> void:
	var cfg := AntishipLoaders.load_crossing_config(DIR + "antiship_crossing_config.json")
	_assert_equal_int("crossing missile_group_size", int(cfg["missile_group_size"]), 4)
	_assert_equal_int("crossing ship_profiles", (cfg["ship_profiles"] as Dictionary).size(), 27)
	for key in ["escort_interception", "terminal_defense", "neutralization_likelihoods", "lethality_multipliers", "launch_attrition"]:
		_assert_true("crossing config has %s" % key, cfg.has(key))


func _validate_magazines() -> void:
	var mags := AntishipLoaders.load_magazines(DIR + "antiship_magazine_defaults.json")
	_assert_equal_int("magazine count", (mags["magazines"] as Array).size(), 8)
	_assert_equal_int("loadout entries", (mags["loadout"] as Array).size(), 12)


func _validate_minefields() -> void:
	var path := DIR + "minefields.json"
	var minefields := AntishipLoaders.load_minefields(path)
	_assert_equal_int("minefield count", minefields.size(), 9)
	_assert_equal_int("available minesweepers", AntishipLoaders.available_minesweepers(path), 6)
	for minefield in minefields:
		_assert_equal_int("beach %d num_mines" % minefield.beach_id, minefield.num_mines, 100)
		_assert_equal_int("beach %d mines_per_sweeper" % minefield.beach_id, minefield.mines_per_sweeper_per_day, 1)
		_assert_equal_int("beach %d remaining seeded to num_mines" % minefield.beach_id, minefield.remaining_mines, 100)
		_assert_true("beach %d has name" % minefield.beach_id, minefield.name != "")


func _assert_true(label: String, value: bool) -> void:
	if not value:
		_fail("%s: expected true" % label)


func _assert_equal_int(label: String, actual: int, expected: int) -> void:
	if actual != expected:
		_fail("%s: expected %d, got %d" % [label, expected, actual])


func _fail(message: String) -> void:
	_failures.append(message)
	push_error(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: anti-ship data validation succeeded")
		quit(0)
		return
	print("FAIL: anti-ship data validation found %d issue(s):" % _failures.size())
	for failure in _failures:
		print("  - %s" % failure)
	quit(1)
