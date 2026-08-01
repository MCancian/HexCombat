class_name AntishipMagazine
extends RefCounted

## Port of the calculator-pure parts of TIV antiship_magazine_service.py: shared missile-magazine
## reservation for anti-ship launcher families (full-volley-or-nothing gating + on-kill deduction).
## The DB seed/load/persist functions are intentionally NOT ported — HexCombat seeds from
## data/antiship/antiship_magazine_defaults.json via AntishipLoaders.load_magazines.
##
## Magazine modes (from the loadout): additive (consume every entry), cross_draw (consume the volley
## from any entry in the pair, primary first), aircraft_pool (per-entry platform_cap, primary first;
## aircraft are exempt from on-kill deduction). Deterministic — no RNG.

var current_counts: Dictionary = {}   # magazine_key (String) -> count (int)
var loadout: Dictionary = {}          # type_id (int) -> loadout row (Dictionary)


## Build from AntishipLoaders.load_magazines(path) output (magazines[] + loadout[]).
static func from_defaults(magazine_data: Dictionary) -> AntishipMagazine:
	var magazine := AntishipMagazine.new()
	for mag_value in magazine_data.get("magazines", []):
		var mag: Dictionary = mag_value
		magazine.current_counts[String(mag["magazine_key"])] = int(mag["initial_count"])
	for row_value in magazine_data.get("loadout", []):
		var row: Dictionary = row_value
		magazine.loadout[int(row["type_id"])] = row
	return magazine


## Aircraft-pool launcher cap: how many launchers the remaining pool can support (platform_cap per
## entry). Non-aircraft-pool types are uncapped (return launcher_count). Mirrors cap_launcher_count.
func cap_launcher_count(type_id: int, launcher_count: int) -> int:
	var info: Variant = loadout.get(int(type_id), null)
	if info == null:
		return launcher_count
	if _mode(info) != "aircraft_pool":
		return launcher_count
	var supported_total := 0
	for entry in _sorted_entries(info):
		var key := String(entry["magazine_key"])
		var mpl := int(entry["missiles_per_launcher"])
		var platform_cap := int(entry.get("platform_cap", 0))
		if platform_cap <= 0:
			_fail("aircraft_pool type %s missing platform_cap for %s" % [type_id, key])
		@warning_ignore("integer_division")
		supported_total += mini(platform_cap, int(current_counts.get(key, 0)) / mpl)
	return mini(launcher_count, supported_total)


## Full-volley-or-nothing: reserve magazines for launcher_count launchers of type_id. On success,
## mutates current_counts and returns launcher_count; on shortfall, leaves counts unchanged and
## returns 0. Mirrors reserve_full_volley.
func reserve_full_volley(type_id: int, launcher_count: int) -> int:
	var info: Variant = loadout.get(int(type_id), null)
	if info == null:
		push_warning("reserve_full_volley: no loadout for type_id=%s" % type_id)
		return launcher_count
	if launcher_count <= 0:
		return 0

	var working: Dictionary = current_counts.duplicate()
	var mode := _mode(info)
	var ok := false
	if mode == "additive":
		ok = _reserve_additive(info, launcher_count, working)
	elif mode == "cross_draw":
		ok = _reserve_cross_draw(info, launcher_count, working)
	elif mode == "aircraft_pool":
		ok = _reserve_aircraft_pool(info, launcher_count, working)
	else:
		_fail("unknown magazine_mode '%s' for type_id=%s" % [mode, type_id])

	if not ok:
		return 0
	current_counts = working
	return launcher_count


## On-kill magazine deduction for ground (non-aircraft) launchers. Aircraft are exempt. Clamps to
## available on shortfall (warns). Mirrors deduct_launcher_kills (pure form).
func deduct_launcher_kills(type_id: int, destroyed_count: int) -> void:
	if destroyed_count <= 0:
		return
	var info: Variant = loadout.get(int(type_id), null)
	if info == null:
		push_warning("deduct_launcher_kills: no loadout for type_id=%s" % type_id)
		return
	if bool(info.get("is_aircraft", false)):
		return
	var mode := _mode(info)
	if mode == "additive":
		_reserve_additive(info, destroyed_count, current_counts)
	elif mode == "cross_draw":
		_reserve_cross_draw(info, destroyed_count, current_counts)
	# aircraft_pool: no ground deduction.


# --- reserve helpers (operate on a counts dict, mirror the Python privates) ----------------------

func _reserve_additive(info: Dictionary, launcher_count: int, counts: Dictionary) -> bool:
	var entries := _sorted_entries(info)
	var needed: Array = []
	for entry in entries:
		var key := String(entry["magazine_key"])
		var amount := launcher_count * int(entry["missiles_per_launcher"])
		if int(counts.get(key, 0)) < amount:
			return false
		needed.append([key, amount])
	for pair in needed:
		counts[pair[0]] = int(counts.get(pair[0], 0)) - int(pair[1])
	return true


func _reserve_cross_draw(info: Dictionary, launcher_count: int, counts: Dictionary) -> bool:
	var entries := _sorted_entries(info)
	if entries.is_empty():
		return true
	var missiles_per_launcher := int(entries[0]["missiles_per_launcher"])
	for entry in entries:
		if int(entry["missiles_per_launcher"]) != missiles_per_launcher:
			_fail("cross_draw type %s has mismatched missiles_per_launcher" % info.get("type_id"))
	return _consume_from_entry_counts(counts, entries, launcher_count * missiles_per_launcher)


func _reserve_aircraft_pool(info: Dictionary, launcher_count: int, counts: Dictionary) -> bool:
	var entries := _sorted_entries(info)
	if entries.is_empty():
		return true
	var working: Dictionary = counts.duplicate()
	var remaining := launcher_count
	for entry in entries:
		var key := String(entry["magazine_key"])
		var mpl := int(entry["missiles_per_launcher"])
		var platform_cap := int(entry.get("platform_cap", 0))
		if platform_cap <= 0:
			_fail("aircraft_pool type %s missing platform_cap for %s" % [info.get("type_id"), key])
		@warning_ignore("integer_division")
		var supported := mini(platform_cap, int(working.get(key, 0)) / mpl)
		var allocate := mini(remaining, supported)
		if allocate > 0:
			working[key] = int(working.get(key, 0)) - (allocate * mpl)
			remaining -= allocate
		if remaining <= 0:
			counts.clear()
			counts.merge(working, true)
			return true
	return false


func _consume_from_entry_counts(counts: Dictionary, entries: Array, amount: int) -> bool:
	var remaining := amount
	if remaining <= 0:
		return true
	var total := 0
	for entry in entries:
		total += maxi(0, int(counts.get(String(entry["magazine_key"]), 0)))
	if total < remaining:
		return false
	for entry in entries:
		var key := String(entry["magazine_key"])
		var available := maxi(0, int(counts.get(key, 0)))
		if available <= 0:
			continue
		var used := mini(available, remaining)
		counts[key] = available - used
		remaining -= used
		if remaining <= 0:
			return true
	return remaining <= 0


# Primary entries first (stable), mirroring sorted(..., key=-is_primary).
func _sorted_entries(info: Dictionary) -> Array:
	var primary: Array = []
	var secondary: Array = []
	for entry in info.get("entries", []):
		if int(entry.get("is_primary", 0)) != 0:
			primary.append(entry)
		else:
			secondary.append(entry)
	return primary + secondary


func _mode(info: Dictionary) -> String:
	var mode: Variant = info.get("magazine_mode", "")
	return String(mode) if mode != null and String(mode) != "" else "additive"


func _fail(message: String) -> void:
	push_error(message)
	assert(false, message)
