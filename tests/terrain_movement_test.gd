extends GdUnitTestSuite

# Terrain-aware find_reachable/find_path (Track F wiring). Real grid hexes, verified against
# data/terrain/hex_terrain.json (classes as of 2026-07-09):
#   hex_4_9   plains  (test start hex)
#   hex_5_9   hills   (dist 1 from hex_4_9)  -- min-one-step target
#   hex_5_10  hills   (dist 2 from hex_4_9)  -- hills at range, out of tactical reach for a slow brigade
#   hex_3_10  plains  (dist 2 from hex_4_9)  -- plains at same range, also out of reach for a slow
#                                                brigade (baseline distance limit, not terrain-special)
#   hex_6_9   plains  (dist 2 from hex_4_9)  -- reachable ONLY via hex_5_9 (hills); cumulative
#                                                entry cost hex_5_9(2) + hex_6_9(1) = 3
#
#   hex_39_15 hills   -- has three mountain neighbors (hex_38_15, hex_38_16, hex_39_16); used to
#                        prove find_reachable never returns a mountain hex.
#   hex_39_16 mountain -- direct neighbor of hex_39_15; must never appear in any reachable set.
#   hex_39_17 hills   -- also adjacent to hex_39_16; raw hex distance 2 from hex_39_15 (would cross
#                        the mountain), but the real (terrain-aware) path detours south through
#                        hex_40_16 / hex_40_17.

const START_HEX := "hex_4_9"
const HILLS_ADJACENT := "hex_5_9"
const HILLS_AT_DISTANCE_2 := "hex_5_10"
const PLAINS_AT_DISTANCE_2 := "hex_3_10"
const HILLS_THEN_PLAINS_CHAIN := "hex_6_9"  # cost 3 via HILLS_ADJACENT

const MOUNTAIN_ADJACENT_START := "hex_39_15"
const MOUNTAIN_HEX := "hex_39_16"
const MOUNTAIN_FAR_SIDE := "hex_39_17"


func before_test() -> void:
	_reset_fixture()


func after_test() -> void:
	_reset_fixture()


func test_slow_brigade_min_one_step_and_distance_limits() -> void:
	# Slow brigade (tactical allowance 1): min-one-step guarantee still lets it enter the adjacent
	# hills hex even though hills cost (2) exceeds its allowance.
	var slow_reachable := GameData.find_reachable(START_HEX, Movement.TACTICAL_SLOW)
	assert_array(slow_reachable).contains([HILLS_ADJACENT])

	# But a hills hex two hexes away is out of tactical reach for the slow brigade...
	assert_array(slow_reachable).not_contains([HILLS_AT_DISTANCE_2])
	# ...and so is a plains hex at the same distance (plain old distance limiting, not something
	# terrain-special about hills specifically at range).
	assert_array(slow_reachable).not_contains([PLAINS_AT_DISTANCE_2])


func test_fast_brigade_reaches_plains_at_two_but_not_hills_then_plains_chain() -> void:
	# Fast brigade (tactical allowance 2) reaches a plains hex two hexes away (cost 1+1 = 2).
	var fast_reachable := GameData.find_reachable(START_HEX, Movement.TACTICAL_FAST)
	assert_array(fast_reachable).contains([PLAINS_AT_DISTANCE_2])

	# But NOT a plains hex reached only by first crossing hills: hex_5_9 (hills, cost 2) then
	# hex_6_9 (plains, cost 1) = cumulative cost 3, over the allowance of 2. hex_6_9 has no cheaper
	# alternate route (verified against the real grid neighbor graph).
	assert_array(fast_reachable).not_contains([HILLS_THEN_PLAINS_CHAIN])


func test_no_mountain_hex_ever_reachable() -> void:
	# Sanity: the hex we're using really does have terrain classified.
	assert_str(GameData.get_terrain(MOUNTAIN_HEX).name).is_equal("mountain")
	assert_bool(GameData.get_terrain(MOUNTAIN_HEX).impassable).is_true()

	var reachable := GameData.find_reachable(MOUNTAIN_ADJACENT_START, 6)
	for hex_id in reachable:
		var terrain := GameData.get_terrain(String(hex_id))
		assert_bool(terrain != null and terrain.impassable).is_false()
	assert_array(reachable).not_contains([MOUNTAIN_HEX])


func test_find_path_routes_around_mountains() -> void:
	# hex_39_15 and hex_39_17 are raw hex-distance 2 apart with a mountain (hex_39_16) directly
	# between them; the terrain-aware path must detour around it rather than crossing it.
	assert_int(HexMath.distance(GameData.get_hex(MOUNTAIN_ADJACENT_START).coord, GameData.get_hex(MOUNTAIN_FAR_SIDE).coord)).is_equal(2)

	var path := GameData.find_path(MOUNTAIN_ADJACENT_START, MOUNTAIN_FAR_SIDE)
	assert_array(path).is_not_empty()
	assert_array(path).not_contains([MOUNTAIN_HEX])
	for hex_id in path:
		var terrain := GameData.get_terrain(String(hex_id))
		assert_bool(terrain != null and terrain.impassable).is_false()


func _reset_fixture() -> void:
	GameData.load_all()
	GameState.reset_to_scenario()
