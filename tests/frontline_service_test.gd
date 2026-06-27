extends GdUnitTestSuite


# --- haversine_km -------------------------------------------------------------------------------

func test_haversine_km_one_deg_lat() -> void:
	var d := FrontLineService.haversine_km(0.0, 0.0, 1.0, 0.0)
	assert_float(d).is_greater(100.0)
	assert_float(d).is_less(120.0)


# --- polyline_cumulative_lengths ----------------------------------------------------------------

func test_cumulative_two_points_one_deg_lat() -> void:
	var coords := [Vector2(0.0, 0.0), Vector2(1.0, 0.0)]
	var lengths := FrontLineService.polyline_cumulative_lengths(coords)
	assert_int(len(lengths)).is_equal(2)
	assert_float(lengths[0]).is_equal_approx(0.0, 0.00001)
	assert_float(lengths[1]).is_greater(100.0)


func test_cumulative_single_point() -> void:
	var lengths := FrontLineService.polyline_cumulative_lengths([Vector2(5.0, 120.0)])
	assert_array(lengths).is_equal([0.0])


func test_cumulative_two_equal_segments() -> void:
	var coords := [Vector2(0.0, 0.0), Vector2(0.5, 0.0), Vector2(1.0, 0.0)]
	var lengths := FrontLineService.polyline_cumulative_lengths(coords)
	assert_int(len(lengths)).is_equal(3)
	assert_float(lengths[1]).is_equal_approx(lengths[2] - lengths[1], 0.1)


# --- interpolate_along_line ---------------------------------------------------------------------

func test_interpolate_start() -> void:
	var coords := [Vector2(0.0, 0.0), Vector2(1.0, 0.0)]
	var cum := FrontLineService.polyline_cumulative_lengths(coords)
	var pt := FrontLineService.interpolate_along_line(coords, cum, 0.0)
	assert_float(pt.x).is_equal_approx(0.0, 0.00001)
	assert_float(pt.y).is_equal_approx(0.0, 0.00001)


func test_interpolate_end() -> void:
	var coords := [Vector2(0.0, 0.0), Vector2(1.0, 0.0)]
	var cum := FrontLineService.polyline_cumulative_lengths(coords)
	var pt := FrontLineService.interpolate_along_line(coords, cum, cum[-1])
	assert_float(pt.x).is_equal_approx(1.0, 0.00001)
	assert_float(pt.y).is_equal_approx(0.0, 0.00001)


func test_interpolate_midpoint() -> void:
	var coords := [Vector2(0.0, 0.0), Vector2(2.0, 0.0)]
	var cum := FrontLineService.polyline_cumulative_lengths(coords)
	var pt := FrontLineService.interpolate_along_line(coords, cum, cum[-1] / 2.0)
	assert_float(pt.x).is_equal_approx(1.0, 0.0001)


func test_interpolate_clamp_beyond_end() -> void:
	var coords := [Vector2(0.0, 0.0), Vector2(1.0, 0.0)]
	var cum := FrontLineService.polyline_cumulative_lengths(coords)
	var pt := FrontLineService.interpolate_along_line(coords, cum, 9999.0)
	assert_float(pt.x).is_equal_approx(coords[-1].x, 0.00001)
	assert_float(pt.y).is_equal_approx(coords[-1].y, 0.00001)


func test_interpolate_single_point() -> void:
	var coords := [Vector2(5.0, 120.0)]
	var cum := [0.0]
	var pt := FrontLineService.interpolate_along_line(coords, cum, 5.0)
	assert_float(pt.x).is_equal_approx(5.0, 0.00001)
	assert_float(pt.y).is_equal_approx(120.0, 0.00001)


# --- point_to_hex -------------------------------------------------------------------------------

func _two_hex_centers() -> Array:
	return [
		{"id": "A", "lat": 23.0, "lon": 120.0},
		{"id": "B", "lat": 23.0, "lon": 121.0},
	]


func test_point_to_hex_near_A() -> void:
	var hid := FrontLineService.point_to_hex(23.01, 120.01, _two_hex_centers())
	assert_str(hid).is_equal("A")


func test_point_to_hex_near_B() -> void:
	var hid := FrontLineService.point_to_hex(23.01, 121.01, _two_hex_centers())
	assert_str(hid).is_equal("B")


func test_point_to_hex_empty_centers() -> void:
	assert_str(FrontLineService.point_to_hex(23.0, 120.0, [])).is_equal("")


# --- find_hexes_for_polyline --------------------------------------------------------------------

func test_find_hexes_A_to_B_order_preserved() -> void:
	var centers := _two_hex_centers()
	var line := [Vector2(23.0, 120.0), Vector2(23.0, 121.0)]
	var result := FrontLineService.find_hexes_for_polyline(line, centers, 200.0)
	assert_array(result).is_equal(["A", "B"])


func test_find_hexes_degenerate_single_vertex() -> void:
	var centers := _two_hex_centers()
	var line := [Vector2(23.01, 120.01)]
	var result := FrontLineService.find_hexes_for_polyline(line, centers)
	assert_array(result).is_equal(["A"])


# --- sample_polyline ----------------------------------------------------------------------------

func test_sample_polyline_single_vertex() -> void:
	var line := [Vector2(23.0, 120.0)]
	var pts := FrontLineService.sample_polyline(line, 2.0)
	assert_array(pts).is_equal([Vector2(23.0, 120.0)])


func test_sample_polyline_two_vertices_first_and_last() -> void:
	var line := [Vector2(23.0, 120.0), Vector2(24.0, 121.0)]
	var pts := FrontLineService.sample_polyline(line, 10.0)
	assert_float(pts[0].x).is_equal_approx(23.0, 0.00001)
	assert_float(pts[0].y).is_equal_approx(120.0, 0.00001)
	assert_float(pts[-1].x).is_equal_approx(24.0, 0.00001)
	assert_float(pts[-1].y).is_equal_approx(121.0, 0.00001)
	assert_int(len(pts)).is_greater_equal(2)


func test_sample_polyline_regression_find_hexes_unchanged() -> void:
	var centers := [
		{"id": "A", "lat": 23.0, "lon": 120.0},
		{"id": "B", "lat": 23.0, "lon": 121.0},
	]
	var line := [Vector2(23.0, 120.0), Vector2(23.0, 121.0)]
	var interval := 200.0
	var sampled := FrontLineService.sample_polyline(line, interval)
	var expected: Array[String] = []
	var seen: Dictionary = {}
	for p in sampled:
		var hid := FrontLineService.point_to_hex(p.x, p.y, centers)
		if hid != "" and not seen.has(hid):
			seen[hid] = true
			expected.append(hid)
	var result := FrontLineService.find_hexes_for_polyline(line, centers, interval)
	assert_array(result).is_equal(expected)


# --- distribute_units_along_hexes ---------------------------------------------------------------

func test_distribute_four_units_over_two_hexes() -> void:
	var result := FrontLineService.distribute_units_along_hexes(
		["u1", "u2", "u3", "u4"], ["A", "B"])
	assert_str(result["u1"]).is_equal("A")
	assert_str(result["u2"]).is_equal("A")
	assert_str(result["u3"]).is_equal("B")
	assert_str(result["u4"]).is_equal("B")


func test_distribute_one_unit_over_five_hexes() -> void:
	var result := FrontLineService.distribute_units_along_hexes(
		["u1"], ["A", "B", "C", "D", "E"])
	assert_str(result["u1"]).is_equal("A")


func test_distribute_more_hexes_than_units() -> void:
	var result := FrontLineService.distribute_units_along_hexes(
		["u1", "u2"], ["A", "B", "C", "D", "E"])
	assert_str(result["u1"]).is_equal("A")
	assert_str(result["u2"]).is_equal("C")


func test_distribute_empty_unit_ids() -> void:
	var result := FrontLineService.distribute_units_along_hexes([], ["A", "B"])
	assert_dict(result).is_empty()


func test_distribute_empty_hex_sequence() -> void:
	var result := FrontLineService.distribute_units_along_hexes(["u1"], [])
	assert_dict(result).is_empty()


func test_distribute_both_empty() -> void:
	var result := FrontLineService.distribute_units_along_hexes([], [])
	assert_dict(result).is_empty()
