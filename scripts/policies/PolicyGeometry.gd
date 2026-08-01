class_name PolicyGeometry
extends RefCounted

## Shared, pure hex-geometry helpers for self-play policies that reason over the observation's
## `hex_<row>_<col>` ids (no engine access). Single home for id parsing + nearest-target selection so
## policies don't each re-derive the odd-r distance (see GarrisonDrawPolicy, RocDefensePolicy).


## Parse a "hex_<row>_<col>" id into the Vector2i(row, col) that HexMath.distance expects.
## (Confirmed against data/taiwan_hex_grid.json: id "hex_A_B" -> row A, col B.)
static func parse_coord(hex_id: String) -> Vector2i:
	var parts := hex_id.split("_")
	if parts.size() >= 3:
		return Vector2i(parts[1].to_int(), parts[2].to_int())
	return Vector2i.ZERO


## From `candidates` (hex ids), the one whose minimum odd-r distance to any hex in `targets` is
## smallest. Deterministic: candidates are sorted, so ties resolve to the lexicographically smallest
## id. Returns "" if either list is empty.
static func nearest_hex_by_id(candidates: Array, targets: Array) -> String:
	if candidates.is_empty() or targets.is_empty():
		return ""
	var target_coords: Array[Vector2i] = []
	for t in targets:
		target_coords.append(parse_coord(String(t)))

	var best_hex := ""
	var min_dist := 1 << 30
	var sorted_candidates := candidates.duplicate()
	sorted_candidates.sort()
	for c_val in sorted_candidates:
		var candidate := String(c_val)
		var c_coord := parse_coord(candidate)
		var nearest := 1 << 30
		for t_coord in target_coords:
			var dist := HexMath.distance(c_coord, t_coord)
			if dist < nearest:
				nearest = dist
		if nearest < min_dist:
			min_dist = nearest
			best_hex = candidate
	return best_hex
