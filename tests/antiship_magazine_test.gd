extends GdUnitTestSuite

# Mirrors TIV tests/python/unit/test_antiship_magazine_service.py (the calculator-pure cases).
# Magazines are seeded from data/antiship/antiship_magazine_defaults.json (the source of truth the
# Python _DEFAULTS mirrors). DB seed/persist cases are N/A in the pure port.

const MAG_PATH := "res://data/antiship/antiship_magazine_defaults.json"


func _mag() -> AntishipMagazine:
	return AntishipMagazine.from_defaults(AntishipLoaders.load_magazines(MAG_PATH))


func test_seed_from_defaults_has_eight_magazines() -> void:
	var mag := _mag()
	assert_int(mag.current_counts.size()).is_equal(8)
	assert_int(int(mag.current_counts["block_i"])).is_equal(150)


func test_reserve_full_volley_additive_consumes_all_entries() -> void:
	var mag := _mag()
	assert_int(mag.reserve_full_volley(19, 2)).is_equal(2)
	assert_int(int(mag.current_counts["block_i"])).is_equal(142)        # 150 - 2*4
	assert_int(int(mag.current_counts["block_ii_surface"])).is_equal(63) # 71 - 2*4


func test_reserve_full_volley_cross_draw_uses_fallback_without_double_spend() -> void:
	var mag := _mag()
	mag.current_counts["hf_ii"] = 0
	mag.current_counts["hf_iii"] = 320
	assert_int(mag.reserve_full_volley(20, 1)).is_equal(1)   # 8 missiles, hf_ii empty -> from hf_iii
	assert_int(int(mag.current_counts["hf_ii"])).is_equal(0)
	assert_int(int(mag.current_counts["hf_iii"])).is_equal(312)


func test_reserve_full_volley_aircraft_pool_uses_caps_and_primary_first() -> void:
	var mag := _mag()
	assert_int(mag.reserve_full_volley(3, 100)).is_equal(100)
	# 60 to block_ii_aircraft (cap 60, 2 mpl -> 120->0), 40 to slam_er (2 mpl -> 135-80=55)
	assert_int(int(mag.current_counts["block_ii_aircraft"])).is_equal(0)
	assert_int(int(mag.current_counts["slam_er"])).is_equal(55)


func test_reserve_full_volley_aircraft_pool_blocks_when_cap_exceeded() -> void:
	var mag := _mag()
	var before := mag.current_counts.duplicate()
	assert_int(mag.reserve_full_volley(3, 128)).is_equal(0)  # cap is 60 + 67 = 127
	assert_str(JSON.stringify(mag.current_counts)).is_equal(JSON.stringify(before))


func test_deduct_launcher_kills_ground_based_consumes_magazine() -> void:
	var mag := _mag()
	mag.deduct_launcher_kills(5, 3)   # static CDCM, 1 block_i each
	assert_int(int(mag.current_counts["block_i"])).is_equal(147)


func test_deduct_launcher_kills_aircraft_exempt() -> void:
	var mag := _mag()
	var before := mag.current_counts.duplicate()
	mag.deduct_launcher_kills(3, 10)
	assert_str(JSON.stringify(mag.current_counts)).is_equal(JSON.stringify(before))


func test_full_volley_or_nothing_exact_and_shortfall() -> void:
	var mag := _mag()
	mag.current_counts["hf_ii"] = 8
	mag.current_counts["hf_iii"] = 0
	assert_int(mag.reserve_full_volley(20, 1)).is_equal(1)   # exact 8 from hf_ii
	assert_int(int(mag.current_counts["hf_ii"])).is_equal(0)

	var before := mag.current_counts.duplicate()
	assert_int(mag.reserve_full_volley(20, 1)).is_equal(0)   # nothing left -> blocked
	assert_str(JSON.stringify(mag.current_counts)).is_equal(JSON.stringify(before))


func test_cap_launcher_count_aircraft_pool_and_uncapped() -> void:
	var mag := _mag()
	assert_int(mag.cap_launcher_count(3, 200)).is_equal(127)  # 60 + 67 platform caps
	assert_int(mag.cap_launcher_count(5, 200)).is_equal(200)  # additive type uncapped
