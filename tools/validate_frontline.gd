# Run from the project root:
# C:\Godot_v4.7-stable_win64.exe --headless --path C:\Users\mdogg\Desktop\HexCombat -s res://tools/validate_frontline.gd
#
# Validates D5-A: GameState.resolve_frontline_phase wiring (polyline -> hex_sequence ->
# affected brigades -> redistribute -> summary). Covers: basic distribution, empty-polyline
# early-return, no-relevant-brigades early-return, and determinism under identical input.
# resolve_frontline_phase consumes NO RNG, so the result is byte-identical given the same input.
extends SceneTree

const SEED := 20260624

var _h := ValidatorHarness.new("frontline (D5-A) validation")
var GameData: Node = null
var GameState: Node = null


func _initialize() -> void:
	print("=== Frontline (D5-A) validation ===")
	GameData = get_root().get_node("GameData")
	GameState = get_root().get_node("GameState")
	if GameData == null or GameState == null:
		_h.fail("Autoloads GameData/GameState not found")
		_h.finish(self, " (seed=%d)" % SEED)
		return

	GameData.load_all()
	_validate_basic_distribution()
	_validate_empty_polyline()
	_validate_no_relevant_brigades()
	_validate_determinism()
	_h.finish(self, " (seed=%d)" % SEED)


func _reload() -> void:
	GameData.load_all()
	GameState.reset_to_scenario()


func _pick_test_hexes(count: int) -> Array:
	var selected: Array = []
	for i in range(mini(count, GameData.hexes.size())):
		selected.append(GameData.hexes[i])
	return selected


func _move_red_brigades(target_hex_id: String, limit: int) -> Array[String]:
	var placed: Array[String] = []
	for brigade_value in GameData.brigades.values():
		var brigade: Brigade = brigade_value
		if brigade.team == Brigade.Team.RED and not brigade.destroyed:
			if placed.size() >= limit:
				break
			GameData.set_brigade_hex(brigade.id, target_hex_id)
			placed.append(brigade.id)
	return placed


func _validate_basic_distribution() -> void:
	_reload()

	var selected := _pick_test_hexes(3)
	if selected.size() < 3:
		_h.fail("Need at least 3 hexes in GameData.hexes")
		return

	var polyline: Array = []
	for hex in selected:
		polyline.append(hex.center)

	var placed := _move_red_brigades(selected[0].id, 2)
	if placed.size() < 2:
		_h.fail("Need at least 2 non-destroyed Red brigades")
		return

	var summary: Dictionary = GameState.resolve_frontline_phase(polyline)
	var hex_sequence: Array = summary.get("hex_sequence", [])
	var affected: Array = summary.get("affected_brigades", [])
	var moves: Dictionary = summary.get("moves", {})

	_h.is_true("hex_sequence is non-empty", not hex_sequence.is_empty())
	_h.equal_int("affected_brigades count matches placed", affected.size(), placed.size())
	_h.is_true("moves has one entry per affected brigade", moves.size() == affected.size())

	for brigade_id in affected:
		var brigade: Brigade = GameData.get_brigade(String(brigade_id))
		_h.is_true(
			"affected brigade %s hex (%s) is in hex_sequence" % [brigade_id, brigade.hex_id],
			String(brigade.hex_id) in hex_sequence)

	for pid in placed:
		_h.is_true("placed brigade %s is in affected list" % pid, pid in affected)


func _validate_empty_polyline() -> void:
	_reload()
	var summary: Dictionary = GameState.resolve_frontline_phase([])
	_h.is_true("empty polyline -> empty hex_sequence", (summary.get("hex_sequence", []) as Array).is_empty())
	_h.is_true("empty polyline -> empty affected_brigades", (summary.get("affected_brigades", []) as Array).is_empty())
	_h.is_true("empty polyline -> empty moves", (summary.get("moves", {}) as Dictionary).is_empty())


func _validate_no_relevant_brigades() -> void:
	_reload()
	var clean_hex_id := ""
	for hex in GameData.hexes:
		var has_red := false
		for bid in GameData.get_brigades_in_hex(hex.id):
			var b: Brigade = GameData.get_brigade(String(bid))
			if b != null and not b.destroyed and b.team == Brigade.Team.RED:
				has_red = true
				break
		if not has_red:
			clean_hex_id = hex.id
			break

	if clean_hex_id.is_empty():
		return

	var hex_entry := GameData.hex_lookup.get(clean_hex_id, null) as Hex
	if hex_entry == null:
		return

	var polyline: Array = [hex_entry.center]
	var summary: Dictionary = GameState.resolve_frontline_phase(polyline)
	var hex_sequence: Array = summary.get("hex_sequence", [])
	_h.is_true("hex_sequence non-empty even with no relevant brigades", not hex_sequence.is_empty())
	_h.is_true("affected_brigades empty when no Red brigades on hexes", (summary.get("affected_brigades", []) as Array).is_empty())
	_h.is_true("moves empty when no relevant brigades", (summary.get("moves", {}) as Dictionary).is_empty())


func _validate_determinism() -> void:
	_reload()

	var selected := _pick_test_hexes(3)
	if selected.size() < 3:
		return

	var polyline: Array = []
	for hex in selected:
		polyline.append(hex.center)

	_move_red_brigades(selected[0].id, 2)
	var first := JSON.stringify(GameState.resolve_frontline_phase(polyline))

	_reload()
	_move_red_brigades(selected[0].id, 2)
	var second := JSON.stringify(GameState.resolve_frontline_phase(polyline))

	_h.is_true("same input -> identical frontline summary", first == second)


