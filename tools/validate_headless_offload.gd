# Run from the project root:
# C:\Godot_v4.7-stable_win64.exe --headless --path C:\Users\mdogg\Desktop\HexCombat -s res://tools/validate_headless_offload.gd
extends SceneTree

const DICE_SEED := 12345
const EXPECTED_BEACH_HEX_BY_BRIGADE := {
	"PLA-71-2-Amphibious": "hex_44_16",
	"PLA-72-5-Amphibious": "hex_44_15",
	"PLA-73-14-Amphibious": "hex_43_14",
	"PLA-74-1-Amphibious": "hex_43_13",
}

var _h := ValidatorHarness.new("headless offload validation")
var GameData: Node = null
var GameState: Node = null


func _initialize() -> void:
	print("=== Headless offload validation ===")
	GameData = get_root().get_node("GameData")
	GameState = get_root().get_node("GameState")
	if GameData == null:
		_h.fail("Autoload GameData was not found on the SceneTree root")
	if GameState == null:
		_h.fail("Autoload GameState was not found on the SceneTree root")
	if not _h.failures.is_empty():
		_h.finish(self)
		return

	GameData.load_all()
	GameState.reset_to_scenario()
	_validate_initial_reserve()
	_validate_turn_1_offload()
	_validate_turn_2_offload()
	_h.finish(self)


func _validate_initial_reserve() -> void:
	_h.equal_int("initial ship_reserve size", GameState.ship_reserve.size(), 4)
	_h.equal_int("initial Red brigades on-map", _red_brigades_on_map(), 0)
	for brigade_id in EXPECTED_BEACH_HEX_BY_BRIGADE.keys():
		var brigade: Brigade = GameData.get_brigade(String(brigade_id))
		if brigade == null:
			_h.fail("initial reserve brigade missing from GameData: %s" % String(brigade_id))
			continue
		_h.equal_string("%s initially at sea" % String(brigade_id), brigade.hex_id, "")


func _validate_turn_1_offload() -> void:
	var m1: Dictionary = GameState.resolve_offload_turn(SeededDice.new(DICE_SEED))
	_h.equal_int("turn 1 bns_landed", int(m1["bns_landed"]), 16)
	_h.equal_int("turn 1 bns_waiting", int(m1["bns_waiting"]), 20)
	_h.is_true("turn 1 landed at least one brigade", (m1["landed_brigade_ids"] as Array).size() >= 1)
	_h.equal_int("turn 1 landed all four brigades", (m1["landed_brigade_ids"] as Array).size(), 4)

	for brigade_id_value in EXPECTED_BEACH_HEX_BY_BRIGADE.keys():
		var brigade_id := String(brigade_id_value)
		var expected_hex := String(EXPECTED_BEACH_HEX_BY_BRIGADE[brigade_id])
		var brigade: Brigade = GameData.get_brigade(brigade_id)
		if brigade == null:
			_h.fail("turn 1 brigade missing from GameData: %s" % brigade_id)
			continue
		_h.equal_string("%s beach hex after turn 1" % brigade_id, brigade.hex_id, expected_hex)
		_h.is_true("%s appears in brigades_by_hex for %s" % [brigade_id, expected_hex], brigade_id in GameData.get_brigades_in_hex(expected_hex))

	_h.is_true("turn 1 ship_reserve still has support BNs", not GameState.ship_reserve.is_empty())
	for reserve_entry_value in GameState.ship_reserve:
		var reserve_entry: Dictionary = reserve_entry_value
		_h.equal_int("%s remaining bns after turn 1" % String(reserve_entry["brigade_id"]), (reserve_entry["bns"] as Array).size(), 5)


func _validate_turn_2_offload() -> void:
	var remaining_before: Dictionary = _remaining_bns_by_brigade()
	# Advance a turn the only legal way: PLANNING -> RESOLUTION -> END -> PLANNING. There is no turn
	# setter any more (plan 0049) — the counter moves on exactly one edge, and driving the real edges
	# consumes no dice, so this stays deterministic.
	TurnLifecycleTransitions.begin_resolution(GameState.data)
	TurnLifecycleTransitions.end_resolution(GameState.data)
	TurnLifecycleTransitions.begin_next_turn(GameState.data)
	var m2: Dictionary = GameState.resolve_offload_turn(SeededDice.new(DICE_SEED))
	_h.is_true("turn 2 bns_landed > 0", int(m2["bns_landed"]) > 0)
	var remaining_after: Dictionary = _remaining_bns_by_brigade()
	var shrank := false
	for brigade_id_value in remaining_before.keys():
		var brigade_id := String(brigade_id_value)
		var before_count := int(remaining_before[brigade_id])
		var after_count := int(remaining_after.get(brigade_id, 0))
		if after_count < before_count:
			shrank = true
	_h.is_true("turn 2 ship_reserve remaining bns shrank", shrank)


func _remaining_bns_by_brigade() -> Dictionary:
	var result: Dictionary = {}
	for reserve_entry_value in GameState.ship_reserve:
		var reserve_entry: Dictionary = reserve_entry_value
		result[String(reserve_entry["brigade_id"])] = (reserve_entry["bns"] as Array).size()
	return result


func _red_brigades_on_map() -> int:
	var count := 0
	for brigade_value in GameData.brigades.values():
		var brigade: Brigade = brigade_value
		if brigade.team == Brigade.Team.RED and not brigade.hex_id.is_empty():
			count += 1
	return count
