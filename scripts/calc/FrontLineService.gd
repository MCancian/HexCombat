class_name FrontLineService
extends RefCounted

const EARTH_RADIUS_KM := 6371.0


static func haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
	var radius_km := EARTH_RADIUS_KM
	var dlat := deg_to_rad(lat2 - lat1)
	var dlon := deg_to_rad(lon2 - lon1)
	var a := (
		pow(sin(dlat / 2.0), 2.0)
		+ cos(deg_to_rad(lat1))
		* cos(deg_to_rad(lat2))
		* pow(sin(dlon / 2.0), 2.0)
	)
	return radius_km * (2.0 * atan2(sqrt(a), sqrt(maxf(1e-12, 1.0 - a))))


static func polyline_cumulative_lengths(coords: Array) -> Array:
	var lengths: Array[float] = [0.0]
	for i in range(1, len(coords)):
		var c0: Vector2 = coords[i - 1]
		var c1: Vector2 = coords[i]
		var dist := haversine_km(c0.x, c0.y, c1.x, c1.y)
		lengths.append(lengths[-1] + dist)
	return lengths


static func interpolate_along_line(coords: Array, cumulative: Array, target_km: float) -> Vector2:
	var total: float = cumulative[-1]
	if total <= 0.0:
		return coords[0]
	target_km = maxf(0.0, minf(target_km, total))
	for i in range(1, len(cumulative)):
		if cumulative[i] >= target_km:
			var seg_start: float = cumulative[i - 1]
			var seg_end: float = cumulative[i]
			var seg_len: float = seg_end - seg_start
			if seg_len < 1e-9:
				return coords[i]
			var frac: float = (target_km - seg_start) / seg_len
			var prev: Vector2 = coords[i - 1]
			var nxt: Vector2 = coords[i]
			var lat := prev.x + frac * (nxt.x - prev.x)
			var lon := prev.y + frac * (nxt.y - prev.y)
			return Vector2(lat, lon)
	return coords[-1]


static func point_to_hex(lat: float, lon: float, hex_centers: Array) -> String:
	var best_id := ""
	var best_dist: float = INF
	for entry in hex_centers:
		if not (entry is Dictionary and entry.has("id") and entry.has("lat") and entry.has("lon")):
			continue
		var eid: String = str(entry["id"])
		var clat: float = float(entry["lat"])
		var clon: float = float(entry["lon"])
		var d := haversine_km(lat, lon, clat, clon)
		if d < best_dist:
			best_dist = d
			best_id = eid
	return best_id


static func sample_polyline(polyline_coords: Array, sample_interval_km: float = 2.0) -> Array:
	var points: Array[Vector2] = []
	for i in range(len(polyline_coords)):
		var curr: Vector2 = polyline_coords[i]
		points.append(curr)
		if i < len(polyline_coords) - 1:
			var next_pt: Vector2 = polyline_coords[i + 1]
			var seg_km := haversine_km(curr.x, curr.y, next_pt.x, next_pt.y)
			var steps := maxi(1, int(seg_km / sample_interval_km))
			for s in range(1, steps):
				var frac := float(s) / float(steps)
				var mid_lat := curr.x + frac * (next_pt.x - curr.x)
				var mid_lon := curr.y + frac * (next_pt.y - curr.y)
				points.append(Vector2(mid_lat, mid_lon))
	return points


static func find_hexes_for_polyline(polyline_coords: Array, hex_centers: Array, sample_interval_km: float = 2.0) -> Array:
	var hex_ids: Array[String] = []
	var seen: Dictionary = {}
	for p in sample_polyline(polyline_coords, sample_interval_km):
		var pt: Vector2 = p
		_add_hex(pt.x, pt.y, hex_centers, hex_ids, seen)
	return hex_ids


static func _add_hex(lat: float, lon: float, hex_centers: Array, hex_ids: Array, seen: Dictionary) -> void:
	var hid := point_to_hex(lat, lon, hex_centers)
	if hid != "" and not seen.has(hid):
		seen[hid] = true
		hex_ids.append(hid)


static func distribute_units_along_hexes(unit_ids: Array, hex_sequence: Array) -> Dictionary:
	var result: Dictionary = {}
	var N := len(unit_ids)
	var M := len(hex_sequence)
	if N == 0 or M == 0:
		return result
	for k in range(N):
		var idx := clampi(int(floor(float(k) * M / N)), 0, M - 1)
		result[str(unit_ids[k])] = str(hex_sequence[idx])
	return result
