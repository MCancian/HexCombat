extends GdUnitTestSuite

## Plan 0047 step 1 — characterization. These pin the hex-ownership behaviours the plan is about to
## route through `MapTransitions`, BEFORE any of them moves.
##
## What is deliberately NOT re-tested here, because it is already covered and duplicating it would
## just be a second place to update:
##   - RED / GREEN / CONTESTED recomputation from occupancy —
##     tests/combat_retreat_test.gd::test_hex_owner_constants_are_written_by_recompute_ownership
##   - FEBA accumulation by combat and zeroing by retreat —
##     tests/combat_resolution_test.gd::test_single_hex_combat_applies_casualties_feba_and_fought_flags
##     and tests/combat_retreat_test.gd::test_feba_threshold_retreat_moves_defender_and_flips_ownership
##
## What is covered here is the seam those leave open: the STICKY rule, which today exists only as a
## missing `else` branch (GameData.gd:582 "INVARIANT: no else-branch"), the cross-game reset, and the
## serialized shape the rename must not move.

const OWNED_HEX := "hex_44_16"


func before_test() -> void:
	GameData.load_all()
	GameData.brigades.clear()
	GameData.brigades_by_hex.clear()
	for hex_id in GameData.hex_states:
		GameData.hex_states[String(hex_id)].hex_owner = HexOwner.NONE
		GameData.hex_states[String(hex_id)].feba_km = 0.0


# --- 1. sticky ownership -------------------------------------------------------------------------
# The load-bearing one. Plan 0006 depends on it: infrastructure seizure must persist after Red moves
# inland, and it persists ONLY because recompute leaves an emptied hex alone. A refactor that
# "tidies up" by writing every hex from a defaulted lookup silently un-seizes every captured port,
# and no golden fixture would catch it — the golden scenario never empties a captured hex.

func test_emptied_hex_keeps_its_previous_owner() -> void:
	var red := _brigade("TEST-0047-STICKY-RED", Brigade.Team.RED)
	GameData.brigades[red.id] = red
	GameData.set_brigade_hex(red.id, OWNED_HEX)
	GameData.recompute_hex_ownership()
	assert_str(GameData.hex_states[OWNED_HEX].hex_owner).is_equal(HexOwner.RED)

	GameData.remove_brigade_from_map(red.id)
	GameData.recompute_hex_ownership()

	assert_array(GameData.get_brigades_in_hex(OWNED_HEX)).is_empty()
	assert_str(GameData.hex_states[OWNED_HEX].hex_owner).override_failure_message(
		"an emptied hex must KEEP its owner — this is what makes port seizure survive Red moving inland"
	).is_equal(HexOwner.RED)


## A destroyed brigade does not hold ground either, but the hex it dies in still keeps its owner
## rather than reverting: `recompute_hex_ownership` skips destroyed brigades, which empties the hex
## as far as the ownership rule is concerned.
func test_hex_holding_only_a_destroyed_brigade_keeps_its_owner() -> void:
	var red := _brigade("TEST-0047-DEAD-RED", Brigade.Team.RED)
	GameData.brigades[red.id] = red
	GameData.set_brigade_hex(red.id, OWNED_HEX)
	GameData.recompute_hex_ownership()
	assert_str(GameData.hex_states[OWNED_HEX].hex_owner).is_equal(HexOwner.RED)

	red.destroyed = true
	GameData.recompute_hex_ownership()

	assert_str(GameData.hex_states[OWNED_HEX].hex_owner).is_equal(HexOwner.RED)


# --- 2. cross-game reset -------------------------------------------------------------------------
# Surfaced 2026-07-09: an in-process replay of the 40-turn golden diverged 24/88 -> 25/90 on the
# second run because run 1's ownership/FEBA map leaked into run 2.

func test_reset_restores_defaults_for_a_second_game_in_one_process() -> void:
	GameData.hex_states[OWNED_HEX].hex_owner = HexOwner.RED
	GameData.hex_states[OWNED_HEX].feba_km = 7.5

	GameData.reset_hex_states()

	assert_str(GameData.hex_states[OWNED_HEX].hex_owner).is_equal(HexOwner.GREEN)
	assert_float(GameData.hex_states[OWNED_HEX].feba_km).is_equal_approx(0.0, 0.0001)

	# And again, so a reset that only works once fails here rather than in a research batch.
	GameData.hex_states[OWNED_HEX].hex_owner = HexOwner.CONTESTED
	GameData.reset_hex_states()
	assert_str(GameData.hex_states[OWNED_HEX].hex_owner).is_equal(HexOwner.GREEN)


func test_every_hex_gets_a_state_at_load() -> void:
	assert_int(GameData.hex_states.size()).is_equal(GameData.hex_lookup.size())


# --- 3. the serialized shape the rename must not move --------------------------------------------
# `HexState.to_dict()` is live: GameData.snapshot_state -> `final_snapshot` in every game record
# (SelfPlayRunner.gd:116) and the determinism comparison in tools/validate_play_turn.gd. The plan
# renames the FIELD to `hex_owner`; these two keys must not follow it.

func test_hex_state_to_dict_keys_and_order() -> void:
	var state := HexState.new()
	# NON-default values: serialized from a fresh HexState, this would also pass against an
	# implementation that hardcoded green/0.0 and forwarded nothing.
	state.hex_owner = HexOwner.CONTESTED
	state.feba_km = -3.25

	var as_dict := state.to_dict()

	assert_array(as_dict.keys()).override_failure_message(
		"final_snapshot consumers read these key names in this order"
	).is_equal(["owner", "feba_km"])
	assert_str(String(as_dict["owner"])).override_failure_message(
		"the FIELD is hex_owner but the serialized KEY stays 'owner'").is_equal(HexOwner.CONTESTED)
	assert_float(float(as_dict["feba_km"])).is_equal_approx(-3.25, 0.0001)


func _brigade(brigade_id: String, team: Brigade.Team) -> Brigade:
	var brigade := Brigade.new()
	brigade.id = brigade_id
	brigade.name = brigade_id
	brigade.team = team
	var battalion := Battalion.new()
	battalion.type = "Tank Battalion"
	battalion.qty = 1
	brigade.composition.append(battalion)
	return brigade
