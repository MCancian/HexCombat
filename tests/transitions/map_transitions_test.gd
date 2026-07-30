extends GdUnitTestSuite

## The `map` aggregate's authority (plan 0047 step 6): grid lifecycle, derived ownership, and FEBA.
##
## These run against a tiny in-memory `GameDataStore` rather than the autoload, so each behaviour is
## pinned without a scenario load. The STICKY-ownership rule and the cross-game reset are pinned
## against the real autoload in map_authority_characterization_test.gd and are not duplicated here;
## what this suite adds is the authority's own surface — the clear/initialize split, FEBA
## accumulation, and the calculator's absence rule read directly.

const HEX_A := "hex_a"
const HEX_B := "hex_b"


func _store() -> GameDataStore:
	var store := GameDataStore.new()
	store.hex_lookup = {HEX_A: Hex.new(), HEX_B: Hex.new()}
	MapTransitions.initialize_hex_states(store, store.hex_lookup.keys())
	return store


func _brigade(store: GameDataStore, id: String, team: Brigade.Team, hex_id: String) -> Brigade:
	var brigade := Brigade.new()
	brigade.id = id
	brigade.team = team
	brigade.hex_id = hex_id
	store.brigades[id] = brigade
	var occupants: Array = store.brigades_by_hex.get(hex_id, [])
	occupants.append(id)
	store.brigades_by_hex[hex_id] = occupants
	return brigade


# --- Grid lifecycle ------------------------------------------------------------------------------

func test_initialize_gives_every_hex_a_default_state() -> void:
	var store := _store()
	assert_int(store.hex_states.size()).is_equal(2)
	var state: HexState = store.hex_states[HEX_A]
	assert_str(state.hex_owner).is_equal(HexOwner.GREEN)
	assert_float(state.feba_km).is_equal(0.0)


## `load_hex_grid` clears BEFORE reading the grid JSON and returns early on a parse failure. Clearing
## is therefore its own operation, not something initialize does on the way in: a failed load must
## leave the map EMPTY rather than retaining the previous game's ownership map.
func test_clear_leaves_the_map_empty_so_a_failed_load_retains_nothing() -> void:
	var store := _store()
	MapTransitions.recompute_ownership(store)

	MapTransitions.clear_hex_states(store)

	assert_int(store.hex_states.size()).override_failure_message(
		"a cleared map must stay empty — this is what makes a failed grid parse safe"
	).is_equal(0)


func test_reset_restores_defaults_without_dropping_hexes() -> void:
	var store := _store()
	_brigade(store, "RED-1", Brigade.Team.RED, HEX_A)
	MapTransitions.recompute_ownership(store)
	MapTransitions.apply_feba_delta(store, HEX_A, 7.5)

	MapTransitions.reset_hex_states(store)

	assert_int(store.hex_states.size()).is_equal(2)
	var state: HexState = store.hex_states[HEX_A]
	assert_str(state.hex_owner).is_equal(HexOwner.GREEN)
	assert_float(state.feba_km).is_equal(0.0)


# --- Derived ownership ---------------------------------------------------------------------------

func test_recompute_writes_red_green_and_contested() -> void:
	var store := _store()
	_brigade(store, "RED-1", Brigade.Team.RED, HEX_A)
	_brigade(store, "GREEN-1", Brigade.Team.GREEN, HEX_A)
	_brigade(store, "GREEN-2", Brigade.Team.GREEN, HEX_B)

	MapTransitions.recompute_ownership(store)

	assert_str((store.hex_states[HEX_A] as HexState).hex_owner).is_equal(HexOwner.CONTESTED)
	assert_str((store.hex_states[HEX_B] as HexState).hex_owner).is_equal(HexOwner.GREEN)


## The calculator omits unoccupied hexes, and MapTransitions iterates what it returned. Reading this
## through the calculator directly is the point: if a future change makes it emit an entry for an
## empty hex, sticky ownership dies whether or not the authority still "iterates the entries".
func test_calculator_omits_hexes_with_no_live_brigade() -> void:
	var store := _store()
	var destroyed := _brigade(store, "RED-DEAD", Brigade.Team.RED, HEX_A)
	destroyed.destroyed = true

	var occupancy := HexOwnershipCalculator.occupancy_from_placements(
		store, store.hex_lookup.keys())

	assert_bool(occupancy.has(HEX_A)).override_failure_message(
		"a hex holding only a destroyed brigade is UNOCCUPIED, and its absence is the sticky rule"
	).is_false()
	assert_bool(HexOwnershipCalculator.owners_from_occupancy(occupancy).has(HEX_A)).is_false()


# --- FEBA ----------------------------------------------------------------------------------------

func test_feba_accumulates_in_both_directions_and_clears() -> void:
	var store := _store()

	MapTransitions.apply_feba_delta(store, HEX_A, 4.0)
	MapTransitions.apply_feba_delta(store, HEX_A, 2.5)
	assert_float((store.hex_states[HEX_A] as HexState).feba_km).is_equal(6.5)

	MapTransitions.apply_feba_delta(store, HEX_A, -9.0)
	assert_float((store.hex_states[HEX_A] as HexState).feba_km).override_failure_message(
		"FEBA is a signed displacement — a Green push takes it negative, it does not clamp at zero"
	).is_equal(-2.5)

	MapTransitions.clear_feba(store, HEX_A)
	assert_float((store.hex_states[HEX_A] as HexState).feba_km).is_equal(0.0)
	assert_float((store.hex_states[HEX_B] as HexState).feba_km).is_equal(0.0)


func test_feba_on_an_unknown_hex_reports_and_changes_nothing() -> void:
	var store := _store()

	await assert_error(func() -> void:
		MapTransitions.apply_feba_delta(store, "hex_ghost", 3.0)
	).is_push_error("MapTransitions.apply_feba_delta: no HexState for hex 'hex_ghost'")

	assert_int(store.hex_states.size()).is_equal(2)
