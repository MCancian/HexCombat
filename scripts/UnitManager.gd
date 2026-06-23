extends Node
class_name UnitManager

var brigades: Dictionary = {}  # brigade_id -> brigade dict
var battalions: Dictionary = {}  # battalion_id -> battalion dict
var brigades_by_hex: Dictionary = {}  # hex_id -> [brigade_ids]

func _ready() -> void:
	load_units()


func load_units() -> void:
	"""Load PLA ground forces from JSON."""
	var file = FileAccess.open("res://data/pla_ground_forces.json", FileAccess.READ)
	if file == null:
		print_debug("Error: Could not open pla_ground_forces.json")
		return

	var json_str = file.get_as_text()
	var json = JSON.parse_string(json_str)

	if not json:
		print_debug("Error: JSON parsing failed")
		return

	# JSON structure: { "brigades": [ {id, ..., battalions: [...]} ] }
	var brigades_data = json.get("brigades", [])

	for brigade_data in brigades_data:
		var brigade_id = brigade_data.get("id", "")
		if brigade_id == "":
			continue

		# Store brigade with tracked state
		brigades[brigade_id] = {
			"id": brigade_id,
			"name": brigade_data.get("name", ""),
			"group_army": brigade_data.get("group_army", ""),
			"designation": brigade_data.get("designation", ""),
			"owner": "red",  # Red units
			"hex_id": brigade_data.get("hex_id", ""),
			"moved_this_turn": false,
			"fought_this_turn": false,
			"destroyed": false,
			"battalions": []
		}

		# Process battalions
		var bn_list = brigade_data.get("battalions", [])
		for bn_data in bn_list:
			var bn_id = bn_data.get("id", "")
			if bn_id == "":
				continue

			battalions[bn_id] = {
				"id": bn_id,
				"brigade_id": brigade_id,
				"type": bn_data.get("type", ""),
				"role": bn_data.get("role", ""),
				"owner": "red",
				"destroyed": false,
				"casualty_marker": false
			}

			# Add battalion to brigade's list
			brigades[brigade_id]["battalions"].append(bn_id)

	# Index brigades by hex (for quick lookup)
	for brigade_id in brigades:
		var brigade = brigades[brigade_id]
		var hex_id = brigade.get("hex_id", "")
		if hex_id != "":
			if not hex_id in brigades_by_hex:
				brigades_by_hex[hex_id] = []
			brigades_by_hex[hex_id].append(brigade_id)

	print_debug("Loaded %d brigades, %d battalions" % [brigades.size(), battalions.size()])


func get_brigade(brigade_id: String) -> Dictionary:
	"""Get brigade dict by ID."""
	return brigades.get(brigade_id, {})


func get_battalions_in_brigade(brigade_id: String) -> Array:
	"""Get all battalion IDs in a brigade."""
	var brigade = brigades.get(brigade_id, {})
	return brigade.get("battalions", [])


func get_brigades_in_hex(hex_id: String) -> Array:
	"""Get all brigade IDs in a hex."""
	return brigades_by_hex.get(hex_id, [])


func set_brigade_hex(brigade_id: String, hex_id: String) -> void:
	"""Move brigade to new hex and update index."""
	if not brigade_id in brigades:
		return

	var old_hex = brigades[brigade_id].get("hex_id", "")
	brigades[brigade_id]["hex_id"] = hex_id

	# Update index
	if old_hex != "":
		if old_hex in brigades_by_hex:
			brigades_by_hex[old_hex] = brigades_by_hex[old_hex].filter(func(b): return b != brigade_id)

	if hex_id != "":
		if not hex_id in brigades_by_hex:
			brigades_by_hex[hex_id] = []
		if brigade_id not in brigades_by_hex[hex_id]:
			brigades_by_hex[hex_id].append(brigade_id)


func set_brigade_moved(brigade_id: String, moved: bool) -> void:
	"""Mark brigade as moved this turn."""
	if brigade_id in brigades:
		brigades[brigade_id]["moved_this_turn"] = moved


func set_brigade_fought(brigade_id: String, fought: bool) -> void:
	"""Mark brigade as fought this turn."""
	if brigade_id in brigades:
		brigades[brigade_id]["fought_this_turn"] = fought


func reset_brigade_state() -> void:
	"""Reset turn state (moved, fought) for all brigades."""
	for brigade_id in brigades:
		brigades[brigade_id]["moved_this_turn"] = false
		brigades[brigade_id]["fought_this_turn"] = false


func get_battalion_count_by_type(brigade_id: String, bn_type: String) -> int:
	"""Count battalions of a specific type in a brigade."""
	var brigade = brigades.get(brigade_id, {})
	var bn_list = brigade.get("battalions", [])
	var count = 0

	for bn_id in bn_list:
		var bn = battalions.get(bn_id, {})
		if bn.get("type", "") == bn_type:
			count += 1

	return count


func create_unit_dict_from_brigade(brigade_id: String) -> Dictionary:
	"""Create a unit dict suitable for combat calculations from a brigade."""
	var brigade = brigades.get(brigade_id, {})
	var bn_list = brigade.get("battalions", [])

	# Return a simplified unit record
	return {
		"brigade_id": brigade_id,
		"type": "Mechanized",  # Default type; would vary by brigade composition
		"unit_count": bn_list.size(),
		"supply_effectiveness": 1.0,  # All in supply initially
		"lat": 0.0,
		"lon": 0.0
	}


func get_unit_count_in_hex(hex_id: String, owner: String = "red") -> int:
	"""Count total battalions in a hex by owner."""
	var brigade_ids = get_brigades_in_hex(hex_id)
	var total = 0

	for brigade_id in brigade_ids:
		var brigade = brigades.get(brigade_id, {})
		if brigade.get("owner", "") == owner:
			total += brigade.get("battalions", []).size()

	return total
