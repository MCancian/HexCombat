# Run from the project root:
# godot --headless --path . -s res://tools/validate_pool_enumeration.gd
extends SceneTree

# Closes the ghost-landing bug family (plans 0034 and 0037) by GATE, not by memory.
#
# THE BUG, TWICE: a mechanic parks battalions off-map in a new field, and whoever added it does not
# also add that field to the enumeration the victory census subtracts. The battalions are then
# counted as standing on Taiwan while they are actually at sea / on the mainland / waiting to fly —
# always in Red's favour, and completely silent. `GameStateData.pending_battalion_pools()` carries a
# comment saying "ADD NEW OFF-MAP POOLS HERE", but a comment is not a gate: `mainland_pool` was
# missing from it for weeks and every phase stayed green, because nothing was watching.
#
# THE CHECK IS STRUCTURAL, NOT A NAME LIST. Off-map pool entries all share one shape —
# `{brigade_id: String, bns: Array}` — so this walks the LIVE state object (and the phase-state
# objects it holds) at runtime looking for any array of that shape, and fails if one is not among the
# arrays `pending_battalion_pools()` returns. A name list would rot on the next mechanic; a shape
# probe finds a pool nobody told it about, which is exactly the failure mode.
#
# Matching is by REFERENCE identity (is_same), not by value: two distinct arrays that happen to hold
# equal entries are still two pools, and only one of them would be subtracted. This makes
# `pending_battalion_pools()` returning the arrays the state actually HOLDS part of the contract — if
# it ever returned copies (`.duplicate()`, `.map()`), this validator fails loudly rather than silently
# passing, which is the correct direction for that mistake.
#
# A FALSE POSITIVE is possible in principle: some future array of {brigade_id, bns} dictionaries that
# is not an off-map pool would be flagged. No such array exists today, and the failure would be loud
# and immediate rather than silent — the opposite of the bug class this closes — so the shape probe is
# deliberately kept broad rather than narrowed with exceptions.
#
# Scenarios are chosen so all three known pools are actually populated — an empty pool has no shape to
# recognise, so a scenario where nothing is off-map would make this validator vacuous.
#
# Prints PASS:/FAIL: for the gate's verdict.

const DEFAULT_SCENARIO := "res://data/scenarios/scenario_default.json"
const AIRBORNE_SCENARIO := "res://data/scenarios/red_airborne.json"
const TURNS := 3
const SEED := 20260624

var _h := ValidatorHarness.new("off-map pool enumeration")
var _pools_seen := 0


func _initialize() -> void:
	print("=== Off-map pool enumeration completeness ===")
	var game_data: Node = get_root().get_node("GameData")
	var game_state: Node = get_root().get_node("GameState")

	# scenario_default drains a follow-on mainland_pool across turns (the 0034 bug's home);
	# red_airborne additionally populates the air insertion pool.
	_probe(game_data, game_state, DEFAULT_SCENARIO, "scenario_default")
	_probe(game_data, game_state, AIRBORNE_SCENARIO, "red_airborne")

	if _pools_seen == 0:
		_h.fail("no off-map pool was populated in either scenario — this validator proved nothing")

	_h.pass_body = func() -> String: return "every off-map battalion pool (%d observation(s)) is enumerated by pending_battalion_pools()." % _pools_seen
	_h.finish(self)


## Play a few turns, then check the enumeration at each of several points: pools appear and drain at
## different turns, and a pool that only exists mid-run is exactly the one an endpoint check misses.
func _probe(game_data: Node, game_state: Node, scenario: String, label: String) -> void:
	game_data.load_all(scenario)
	game_state.reset_to_scenario()
	_check_state(game_state.data, "%s turn 0" % label)
	for turn in range(TURNS):
		game_state.resolve_turn(SeededDice.new(SEED + turn))
		game_state.begin_next_turn()
		_check_state(game_state.data, "%s turn %d" % [label, turn + 1])


func _check_state(state: GameStateData, where: String) -> void:
	var enumerated: Array = state.pending_battalion_pools()
	for found in _find_pool_shaped_arrays(state):
		var array: Array = found["array"]
		var origin := String(found["origin"])
		_pools_seen += 1
		if not _contains_same(enumerated, array):
			_h.fail(
				"%s: %s holds %d battalion-pool entr(ies) but is NOT returned by pending_battalion_pools() — the victory census, combat and supply will all count those battalions as ashore. Add it to GameStateData.pending_battalion_pools()."
				% [where, origin, array.size()]
			)


## Every array of {brigade_id, bns} entries reachable from `state`, at ANY depth: its own properties,
## the phase-state objects it holds (SealiftState, AirInsertionState, …) where two of the three known
## pools live, and anything nested below those — including inside Dictionaries and Arrays.
##
## Full recursion rather than the one level the known pools need today, because the promise this
## validator makes is that a pool is found by its SHAPE, not by someone registering it. A depth limit
## would quietly break that promise the first time a refactor nests a pool one level deeper.
## `visited` is keyed on object instance so a cycle (or a shared sub-object) cannot loop or double-report.
func _find_pool_shaped_arrays(state: GameStateData) -> Array:
	var found: Array = []
	var visited: Array = []
	_scan_object(state, "GameStateData", found, visited)
	return found


func _scan_object(target: Object, prefix: String, found: Array, visited: Array) -> void:
	for seen in visited:
		if is_same(seen, target):
			return
	visited.append(target)
	for property in target.get_property_list():
		var property_name := String(property["name"])
		var value = target.get(property_name)
		_scan_value(value, "%s.%s" % [prefix, property_name], found, visited)


func _scan_value(value, origin: String, found: Array, visited: Array) -> void:
	if value is Array:
		var array: Array = value
		if _looks_like_pool(array):
			found.append({"array": array, "origin": origin})
			return
		for index in range(array.size()):
			_scan_value(array[index], "%s[%d]" % [origin, index], found, visited)
	elif value is Dictionary:
		for key in (value as Dictionary).keys():
			_scan_value((value as Dictionary)[key], "%s[%s]" % [origin, str(key)], found, visited)
	elif value is Object and value != null:
		_scan_object(value as Object, origin, found, visited)


## A pool entry names the brigade its battalions belong to and carries the battalion manifest. Empty
## arrays are skipped deliberately: they carry no shape, so they can be neither recognised nor missed.
func _looks_like_pool(value: Array) -> bool:
	if value.is_empty():
		return false
	for entry in value:
		if not (entry is Dictionary):
			return false
		var entry_dict: Dictionary = entry
		if not entry_dict.has("brigade_id") or not entry_dict.has("bns"):
			return false
		if not (entry_dict["bns"] is Array):
			return false
	return true


## Reference identity, not equality: pending_battalion_pools() hands back the very arrays the state
## holds, and two equal-but-distinct arrays would be two pools with only one of them subtracted.
func _contains_same(haystack: Array, needle: Array) -> bool:
	for candidate in haystack:
		if is_same(candidate, needle):
			return true
	return false


	_h.pass_body = func() -> String: return "every off-map battalion pool (%d observation(s)) is enumerated by pending_battalion_pools()." % _pools_seen
	_h.finish(self)
