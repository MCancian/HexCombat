# Run from the project root:
# godot --headless --path . -s res://tools/validate_infrastructure_data.gd
extends SceneTree

const INFRA_PATH := "res://data/infrastructure.json"
const HEX_GRID_PATH := "res://data/taiwan_hex_grid.json"
const THEATERS_PATH := "res://data/theaters.json"
const BEACHES_PATH := "res://data/beaches.json"

var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Infrastructure data validation ===")
	_validate_all()
	_finish()


func _validate_all() -> void:
	var infra: Dictionary = _parse_infrastructure()
	if infra.is_empty():
		return

	var hexes: Array[Dictionary] = _parse_hex_grid()
	if hexes.is_empty():
		return

	var active_tos: Array[int] = _parse_active_tos()
	if active_tos.is_empty():
		return

	var beaches: Array[Dictionary] = _parse_beaches()
	if beaches.is_empty():
		return

	var beach_to_to: Dictionary = _parse_beach_to_to()
	if beach_to_to.is_empty():
		return

	_validate_entries(infra, hexes, active_tos, beaches, beach_to_to)

	var port_count := 0
	var airbridge_count := 0
	for entry in infra.values():
		if entry.kind == "port":
			port_count += 1
		elif entry.kind == "airbridge":
			airbridge_count += 1
	print("Infrastructure: %d ports, %d airbridges" % [port_count, airbridge_count])


func _parse_infrastructure() -> Dictionary:
	var file := FileAccess.open(INFRA_PATH, FileAccess.READ)
	if file == null:
		_fail("Could not open %s" % INFRA_PATH)
		return {}

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		_fail("infrastructure.json did not parse to a Dictionary")
		return {}

	var infra_list: Variant = (parsed as Dictionary).get("infrastructure", null)
	if not (infra_list is Array):
		_fail("infrastructure.json missing or non-Array 'infrastructure' key")
		return {}

	if infra_list.is_empty():
		_fail("infrastructure.json 'infrastructure' array is empty")
		return {}

	var result: Dictionary = {}
	var seen_ids: Dictionary = {}
	for entry_data in infra_list:
		if not (entry_data is Dictionary):
			_fail("infrastructure.json entry is not a Dictionary")
			continue
		var entry: Dictionary = entry_data
		var id_val: String = String(entry.get("id", ""))
		if id_val.is_empty():
			_fail("infrastructure.json entry missing or empty 'id'")
			continue
		if seen_ids.has(id_val):
			_fail("infrastructure.json duplicate id: '%s'" % id_val)
			continue
		seen_ids[id_val] = true

		var kind: String = String(entry.get("kind", ""))
		if kind != "port" and kind != "airbridge":
			_fail("infrastructure.json entry '%s' kind '%s' not in {port, airbridge}" % [id_val, kind])
			continue

		var name: String = String(entry.get("name", ""))
		if name.is_empty():
			_fail("infrastructure.json entry '%s' missing or empty 'name'" % id_val)
			continue

		var lat: float = float(entry.get("lat", 0.0))
		var lng: float = float(entry.get("lng", 0.0))
		if is_zero_approx(lat) or is_zero_approx(lng):
			_fail("infrastructure.json entry '%s' lat/lng is zero" % id_val)
			continue

		result[id_val] = {
			"id": id_val,
			"kind": kind,
			"name": name,
			"hex_id": String(entry.get("hex_id", "")),
			"to_number": int(entry.get("to_number", 0)),
			"lat": lat,
			"lng": lng
		}

	print("infrastructure.json: %d valid entries" % result.size())
	return result


func _parse_hex_grid() -> Array[Dictionary]:
	var file := FileAccess.open(HEX_GRID_PATH, FileAccess.READ)
	if file == null:
		_fail("Could not open %s" % HEX_GRID_PATH)
		return []

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		_fail("taiwan_hex_grid.json did not parse to a Dictionary")
		return []

	var root: Dictionary = parsed
	var hexes_data: Variant = root.get("hexes", null)
	if not (hexes_data is Array):
		_fail("taiwan_hex_grid.json missing 'hexes' array")
		return []

	var result: Array[Dictionary] = []
	for h in hexes_data:
		if not (h is Dictionary):
			continue
		var hd: Dictionary = h
		var hid: String = String(hd.get("id", ""))
		if hid.is_empty():
			continue
		var center: Variant = hd.get("center", null)
		if not (center is Dictionary):
			continue
		var cd: Dictionary = center
		result.append({
			"id": hid,
			"lat": float(cd.get("lat", 0.0)),
			"lon": float(cd.get("lon", 0.0))
		})

	print("taiwan_hex_grid.json: %d hexes parsed" % result.size())
	return result


func _parse_active_tos() -> Array[int]:
	var file := FileAccess.open(THEATERS_PATH, FileAccess.READ)
	if file == null:
		_fail("Could not open %s" % THEATERS_PATH)
		return []

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		_fail("theaters.json did not parse to a Dictionary")
		return []

	var tos: Variant = (parsed as Dictionary).get("active_tos", null)
	if not (tos is Array):
		_fail("theaters.json missing 'active_tos' array")
		return []

	var result: Array[int] = []
	for t in tos:
		result.append(int(t))
	return result


func _parse_beaches() -> Array[Dictionary]:
	var file := FileAccess.open(BEACHES_PATH, FileAccess.READ)
	if file == null:
		_fail("Could not open %s" % BEACHES_PATH)
		return []

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		_fail("beaches.json did not parse to a Dictionary")
		return []

	var beaches_list: Variant = (parsed as Dictionary).get("beaches", null)
	if not (beaches_list is Array):
		_fail("beaches.json missing 'beaches' array")
		return []

	var result: Array[Dictionary] = []
	for b in beaches_list:
		if not (b is Dictionary):
			continue
		var bd: Dictionary = b
		result.append({
			"id": int(bd.get("id", 0)),
			"lat": float(bd.get("lat", 0.0)),
			"lng": float(bd.get("lng", 0.0)),
			"hex_id": String(bd.get("hex_id", ""))
		})
	return result


func _parse_beach_to_to() -> Dictionary:
	var file := FileAccess.open(THEATERS_PATH, FileAccess.READ)
	if file == null:
		return {}

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return {}

	var btt: Variant = (parsed as Dictionary).get("beach_to_to", null)
	if not (btt is Dictionary):
		return {}

	var result: Dictionary = {}
	for key in (btt as Dictionary).keys():
		result[int(String(key))] = int((btt as Dictionary)[key])
	return result


func _validate_entries(infra: Dictionary, hexes: Array[Dictionary], active_tos: Array[int], beaches: Array[Dictionary], beach_to_to: Dictionary) -> void:
	var hex_lookup: Dictionary = {}
	for h in hexes:
		hex_lookup[h.id] = h

	var to_set: Dictionary = {}
	for t in active_tos:
		to_set[t] = true

	for entry_key in infra.keys():
		var entry: Dictionary = infra[entry_key]

		# Check 3: hex_id exists in grid
		var hex_id: String = entry.hex_id
		if hex_id == "" or not hex_lookup.has(hex_id):
			_fail("infrastructure.json entry '%s' hex_id '%s' not found in hex grid" % [entry.id, hex_id])
			continue

		# Check 4: to_number in active_tos
		var to_n: int = entry.to_number
		if not to_set.has(to_n):
			_fail("infrastructure.json entry '%s' to_number %d not in active_tos" % [entry.id, to_n])
			continue

		# Check 5: geometry — nearest hex center
		var closest_hex_id: String = _nearest_hex(entry.lat, entry.lng, hexes)
		if closest_hex_id != hex_id:
			_fail("infrastructure.json entry '%s' hex_id '%s' is not nearest hex; closest is '%s'" % [entry.id, hex_id, closest_hex_id])

		# Check 6: TO consistency via nearest beach
		var nearest_beach_id: int = _nearest_beach(entry.lat, entry.lng, beaches)
		var expected_to: int = beach_to_to.get(nearest_beach_id, -1)
		if expected_to == -1:
			_fail("infrastructure.json entry '%s' nearest beach %d not in beach_to_to" % [entry.id, nearest_beach_id])
		elif to_n != expected_to:
			_fail("infrastructure.json entry '%s' to_number %d != nearest beach %d to_number %d" % [entry.id, to_n, nearest_beach_id, expected_to])


func _nearest_hex(lat: float, lng: float, hexes: Array[Dictionary]) -> String:
	var best_id: String = ""
	var best_dist: float = INF
	var cos_lat: float = cos(deg_to_rad(lat))
	for h in hexes:
		var dlat: float = lat - h.lat
		var dlng: float = lng - h.lon
		var d: float = dlat * dlat + (dlng * cos_lat) * (dlng * cos_lat)
		if d < best_dist:
			best_dist = d
			best_id = h.id
	return best_id


func _nearest_beach(lat: float, lng: float, beaches: Array[Dictionary]) -> int:
	var best_id: int = -1
	var best_dist: float = INF
	var cos_lat: float = cos(deg_to_rad(lat))
	for b in beaches:
		var dlat: float = lat - b.lat
		var dlng: float = lng - b.lng
		var d: float = dlat * dlat + (dlng * cos_lat) * (dlng * cos_lat)
		if d < best_dist:
			best_dist = d
			best_id = b.id
	return best_id


func _fail(message: String) -> void:
	_failures.append(message)
	push_error(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: Infrastructure data validation succeeded")
		quit(0)
		return
	print("FAIL: Infrastructure data validation found %d issue(s):" % _failures.size())
	for failure in _failures:
		print("  - %s" % failure)
	quit(1)
