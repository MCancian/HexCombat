extends SceneTree

# End-to-end coverage for the air insertion path (plan 0032) against the red_airborne scenario,
# which no other gate phase exercises. The pure logic is unit-tested in
# tests/air_insertion_{resolver,builder,order}_test.gd; what only a real game can show is the wiring:
#
#   1. Turning the mechanic on changes nothing until someone orders a drop — the corps sits off-map,
#      out of the census, and out of the sealift follow-on pool.
#   2. With the air_assault policy driving Red, battalions actually fly, land on hexes, and enter
#      the census — and the pool drains by exactly what flew.
#   3. No battalion is invented: census + still-waiting + killed-on-insertion is conserved.
#   4. The per-turn cap binds (a turn never lands more than the cap) and losses erode it permanently
#      (caps never rise).
#   5. Attrition tracks the air-defence picture: the first drop, into the strongest surviving air
#      defence, costs a higher rate than a late one.
#   6. Determinism: the same seed yields the same terminal census.
#
# Prints PASS:/FAIL: for the gate's verdict.

const SCENARIO := "res://data/scenarios/red_airborne.json"
const BASELINE_SCENARIO := "res://data/scenarios/scenario_default.json"
const SEED := 20260624
const TURNS := 14
const AIRBORNE_CAP := 7
const AIR_ASSAULT_CAP := 2
# 5 airborne brigades x 8 BN + 1 air assault brigade x 10 BN.
const CORPS_BATTALIONS := 50

var GameData: Node = null
var GameState: Node = null
var _h := ValidatorHarness.new("air insertion coverage")


func _initialize() -> void:
	print("=== PLAAF air insertion (red_airborne) ===")
	GameData = get_root().get_node("GameData")
	GameState = get_root().get_node("GameState")

	var idle := _play_once(SCENARIO, "noop")
	var flown := _play_once(SCENARIO, "air_assault")
	var repeat := _play_once(SCENARIO, "air_assault")
	var baseline := _play_once(BASELINE_SCENARIO, "noop")
	# air_assault IS selfplay_default plus the drops, so this pair differs only in the air path —
	# comparing against `noop` instead would credit air insertion with the ground movement too.
	var ground_only := _play_once(SCENARIO, "selfplay_default")

	_check("the corps starts off-map: %d battalions waiting to fly" % idle["pool_start"],
		idle["pool_start"] == CORPS_BATTALIONS)
	_check("an unordered corps never flies (landed=%d, red census %d vs scenario_default %d)" % [
		idle["landed_total"], idle["red_final"], baseline["red_final"]],
		idle["landed_total"] == 0 and idle["red_final"] == baseline["red_final"])
	_check("the corps stays out of the sealift pool (mainland %d == scenario_default %d)" % [
		idle["mainland_pool_start"], baseline["mainland_pool_start"]],
		idle["mainland_pool_start"] == baseline["mainland_pool_start"])

	_check("ordered drops actually fly (%d battalions landed over %d turns)" % [
		flown["landed_total"], TURNS], flown["landed_total"] > 0)
	_check("landed battalions reach hexes (%d distinct drop hexes)" % flown["drop_hexes"],
		flown["drop_hexes"] > 0)
	_check("the pool drains by exactly what flew (%d start - %d sent == %d left)" % [
		flown["pool_start"], flown["sent_total"], flown["pool_final"]],
		flown["pool_start"] - flown["sent_total"] == flown["pool_final"])
	_check("no battalion invented: landed + lost == sent (%d + %d == %d)" % [
		flown["landed_total"], flown["lost_total"], flown["sent_total"]],
		flown["landed_total"] + flown["lost_total"] == flown["sent_total"])
	_check("the air path adds to Red's census over the same ground play (%d vs %d)" % [
		flown["red_final"], ground_only["red_final"]],
		flown["red_final"] > ground_only["red_final"])

	_check("no turn lands more than the cap (max airborne %d <= %d, max air assault %d <= %d)" % [
		flown["max_airborne_sent"], AIRBORNE_CAP, flown["max_air_assault_sent"], AIR_ASSAULT_CAP],
		flown["max_airborne_sent"] <= AIRBORNE_CAP and flown["max_air_assault_sent"] <= AIR_ASSAULT_CAP)
	_check("caps never rise (final airborne %d <= initial %d)" % [
		flown["cap_airborne_final"], AIRBORNE_CAP],
		flown["cap_airborne_final"] <= AIRBORNE_CAP)
	_check("losses erode the lift by exactly one battalion each (%d lost -> caps down %d)" % [
		flown["lost_total"], flown["cap_erosion"]],
		flown["cap_erosion"] == mini(flown["lost_total"], AIRBORNE_CAP + AIR_ASSAULT_CAP))
	_check("attrition falls as the air defences are ground down (first %.3f >= last %.3f)" % [
		flown["first_rate"], flown["last_rate"]], flown["first_rate"] >= flown["last_rate"])

	_check("determinism: same seed -> identical terminal census (%d/%d == %d/%d)" % [
		flown["red_final"], flown["green_final"], repeat["red_final"], repeat["green_final"]],
		flown["red_final"] == repeat["red_final"] and flown["green_final"] == repeat["green_final"])

	if _h.failures.is_empty():
		print("PASS: the air path flies, is capped, bleeds lift, and conserves the force.")
		quit(0)
	else:
		print("FAIL: air insertion coverage found %d issue(s)." % _h.failures.size())
		quit(1)


func _play_once(scenario: String, red_policy_id: String) -> Dictionary:
	GameData.load_all(scenario)
	GameState.reset_to_scenario()

	var air_state: AirInsertionState = GameState.air_insertion_state
	var out := {
		"pool_start": air_state.pending_battalions() if air_state != null else 0,
		"mainland_pool_start": GameState.sealift_state.mainland_pool.size() if GameState.sealift_state != null else 0,
		"landed_total": 0, "lost_total": 0, "sent_total": 0,
		"max_airborne_sent": 0, "max_air_assault_sent": 0,
		"first_rate": 0.0, "last_rate": 0.0,
	}
	var red_policy: Object = PolicyCatalog.create(red_policy_id)
	var drop_hexes: Dictionary = {}
	var dice := SeededDice.new(SEED)
	var red_final := 0
	var green_final := 0
	var seen_rate := false

	for _turn_index in range(TURNS):
		var actions: Array = red_policy.build_actions(LLMGameAPI.observation("Red"))
		var result: TurnResult = GameState.play_turn(_orders_from_actions(actions), [], dice)
		var summary: Dictionary = result.air_insertion_summary
		out["landed_total"] = int(out["landed_total"]) + int(summary.get("battalions_landed", 0))
		out["lost_total"] = int(out["lost_total"]) + int(summary.get("battalions_lost", 0))

		var sent_by_class: Dictionary = {}
		for drop_value in summary.get("drops", []):
			var drop: Dictionary = drop_value
			out["sent_total"] = int(out["sent_total"]) + int(drop["sent"])
			var lift_class := String(drop["lift_class"])
			sent_by_class[lift_class] = int(sent_by_class.get(lift_class, 0)) + int(drop["sent"])
			if int(drop["landed"]) > 0:
				drop_hexes[String(drop["hex_id"])] = true
			if not seen_rate:
				out["first_rate"] = float(drop["attrition_rate"])
				seen_rate = true
			out["last_rate"] = float(drop["attrition_rate"])
		out["max_airborne_sent"] = maxi(int(out["max_airborne_sent"]), int(sent_by_class.get(LiftClass.AIRBORNE, 0)))
		out["max_air_assault_sent"] = maxi(int(out["max_air_assault_sent"]), int(sent_by_class.get(LiftClass.AIR_ASSAULT, 0)))

		var cleanup: Dictionary = result.cleanup_summary
		red_final = int(cleanup.get("china_battalions_on_taiwan", -1))
		green_final = int(cleanup.get("taiwan_battalions_on_taiwan", -1))
		if result.game_over:
			break
		GameState.begin_next_turn()

	air_state = GameState.air_insertion_state
	out["pool_final"] = air_state.pending_battalions() if air_state != null else 0
	out["cap_airborne_final"] = int(air_state.caps.get(LiftClass.AIRBORNE, 0)) if air_state != null else 0
	out["cap_erosion"] = _cap_erosion(air_state)
	out["drop_hexes"] = drop_hexes.size()
	out["red_final"] = red_final
	out["green_final"] = green_final
	return out


func _cap_erosion(air_state: AirInsertionState) -> int:
	if air_state == null:
		return 0
	var erosion := 0
	for lift_class in air_state.initial_caps.keys():
		erosion += int(air_state.initial_caps[lift_class]) - int(air_state.caps.get(lift_class, 0))
	return erosion


## Translate policy actions into the bulk-order specs GameState.play_turn takes.
func _orders_from_actions(actions: Array) -> Array:
	var orders: Array = []
	for action_value in actions:
		var action: Dictionary = action_value
		match String(action.get("type", "")):
			"move":
				orders.append({
					"kind": "move", "brigade_id": String(action["brigade_id"]),
					"target_hex": String(action["target_hex"]),
					"mode": String(action.get("mode", Movement.MODE_TACTICAL)),
				})
			"commit":
				orders.append({
					"kind": "commit", "brigade_id": String(action["brigade_id"]),
					"target_hex": String(action["target_hex"]),
				})
			"air_insert":
				orders.append({
					"kind": "air_insert", "brigade_id": String(action["brigade_id"]),
					"target_hex": String(action["target_hex"]),
				})
	return orders


func _check(label: String, ok: bool) -> void:
	if ok:
		print("  ok: %s" % label)
	else:
		_h.fail(label)
		print("  FAIL: %s" % label)
