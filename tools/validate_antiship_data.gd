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

var _h := ValidatorHarness.new("anti-ship data validation")


func _initialize() -> void:
	print("=== Anti-ship data validation ===")
	_validate_systems()
	_validate_combat_catalog()
	_validate_crossing_config()
	_validate_magazines()
	_validate_minefields()
	_h.finish(self)


func _validate_systems() -> void:
	var types := AntishipLoaders.load_system_types(DIR + "antiship_systems_consolidated.json")
	_h.is_true("system catalog non-empty", types.size() > 0)
	for type_id in EXPECTED_TYPE_TOTALS.keys():
		_h.is_true("system catalog has type %d" % type_id, types.has(type_id))

	var systems := AntishipLoaders.load_systems(DIR + "antiship_grouping_spec.json", types)
	_h.is_true("system rows expanded", systems.size() > 0)

	var by_type: Dictionary = {}
	var total := 0
	for system in systems:
		_h.is_true("system %d/%d quantity > 0" % [system.to_number, system.type_id], system.quantity > 0)
		_h.is_true("system TO %d valid" % system.to_number, system.to_number in VALID_TOS)
		_h.is_true("system %d has type_name" % system.type_id, system.type_name != "")
		by_type[system.type_id] = int(by_type.get(system.type_id, 0)) + system.quantity
		total += system.quantity
		# Aggregation invariant: at most one row per (TO, type_id).
		_h.is_true("original_quantity seeded for %d/%d" % [system.to_number, system.type_id], system.original_quantity == system.quantity)
		# Establishment equation (plan 0043): a freshly built row has taken no losses of either kind,
		# and its two projections agree with AntishipSystem's own definition of them.
		_h.equal_int("fresh row %d/%d ijfs_destroyed_cumulative" % [system.to_number, system.type_id], system.ijfs_destroyed_cumulative, 0)
		_h.equal_int("fresh row %d/%d launch_destroyed_cumulative" % [system.to_number, system.type_id], system.launch_destroyed_cumulative, 0)
		_assert_equal_string("establishment equation holds for %d/%d" % [system.to_number, system.type_id], system.establishment_error(), "")

	for type_id in EXPECTED_TYPE_TOTALS.keys():
		_h.equal_int("type %d total platforms" % type_id, int(by_type.get(type_id, -1)), int(EXPECTED_TYPE_TOTALS[type_id]))
	_h.equal_int("total platforms across all systems", total, EXPECTED_TOTAL)

	# (TO, type_id) uniqueness after aggregation.
	var seen: Dictionary = {}
	for system in systems:
		var key := "%d:%d" % [system.to_number, system.type_id]
		_h.is_true("unique (TO,type) row %s" % key, not seen.has(key))
		seen[key] = true


func _validate_combat_catalog() -> void:
	var catalog := AntishipLoaders.load_combat_catalog(DIR + "antiship_combat_catalog.json")
	_h.equal_int("combat catalog munitions", (catalog["munitions"] as Dictionary).size(), 9)
	_h.equal_int("combat catalog launchers", (catalog["launchers"] as Dictionary).size(), 12)
	_h.is_true("combat catalog has store_groups", (catalog["store_groups"] as Dictionary).size() > 0)


func _validate_crossing_config() -> void:
	var cfg := AntishipLoaders.load_crossing_config(DIR + "antiship_crossing_config.json")
	_h.equal_int("crossing missile_group_size", int(cfg["missile_group_size"]), 4)
	_h.equal_int("crossing ship_profiles", (cfg["ship_profiles"] as Dictionary).size(), 27)
	for key in ["escort_interception", "terminal_defense", "neutralization_likelihoods", "lethality_multipliers", "launch_attrition"]:
		_h.is_true("crossing config has %s" % key, cfg.has(key))


func _validate_magazines() -> void:
	var mags := AntishipLoaders.load_magazines(DIR + "antiship_magazine_defaults.json")
	_h.equal_int("magazine count", (mags["magazines"] as Array).size(), 8)
	_h.equal_int("loadout entries", (mags["loadout"] as Array).size(), 12)


func _validate_minefields() -> void:
	var path := DIR + "minefields.json"
	var minefields := AntishipLoaders.load_minefields(path)
	_h.equal_int("minefield count", minefields.size(), 9)
	_h.equal_int("available minesweepers", AntishipLoaders.available_minesweepers(path), 6)
	for minefield in minefields:
		_h.equal_int("beach %d num_mines" % minefield.beach_id, minefield.num_mines, 100)
		_h.equal_int("beach %d mines_per_sweeper" % minefield.beach_id, minefield.mines_per_sweeper_per_day, 1)
		_h.equal_int("beach %d remaining seeded to num_mines" % minefield.beach_id, minefield.remaining_mines, 100)
		_h.is_true("beach %d has name" % minefield.beach_id, minefield.name != "")


func _assert_equal_string(label: String, actual: String, expected: String) -> void:
	if actual != expected:
		_h.fail("%s: expected \"%s\", got \"%s\"" % [label, expected, actual])
