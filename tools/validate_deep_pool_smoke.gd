extends SceneTree

# Deep-pool coverage for the RESEARCH default (scenario_default.json) — the sustained-sealift
# scenario the rest of the gate does NOT exercise (it runs against scenario_golden.json). Explicitly
# loads scenario_default regardless of the gate's HEXCOMBAT_SCENARIO=golden selection, then checks:
#   1. the deep mainland pool auto-seeded (SealiftStateBuilder.resolve_followon_reserve),
#   2. sustained crossing — Red keeps arriving past the first wave (follow-on echelons embark),
#   3. determinism — same seed => identical terminal census (the reproducibility contract).
# Prints PASS:/FAIL: for the gate's Phase-3 verdict.

const DEEP_SCENARIO := "res://data/scenario_default.json"
const SEED := 20260624
const TURNS := 10

var GameData: Node = null
var GameState: Node = null
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Deep-pool research-default coverage (scenario_default) ===")
	GameData = get_root().get_node("GameData")
	GameState = get_root().get_node("GameState")
	GameData.load_all(DEEP_SCENARIO)

	# 1. Deep pool auto-seeded.
	GameState.reset_to_scenario()
	var pool_bns := 0
	for entry in GameState.sealift_state.mainland_pool:
		pool_bns += (entry.get("bns", []) as Array).size()
	_check("deep mainland pool auto-seeded (>100 BN)", pool_bns > 100)

	# 2 + 3. Two identical runs; sustained crossing within a run.
	var a := _play()
	var b := _play()
	_check("sustained crossing past first wave (red grows turn 2 -> %d)" % TURNS,
		a["red_final"] > a["red_turn2"])
	_check("determinism: same seed -> identical terminal census (%d/%d == %d/%d)"
		% [a["red_final"], a["grn_final"], b["red_final"], b["grn_final"]],
		a["red_final"] == b["red_final"] and a["grn_final"] == b["grn_final"])

	if _failures.is_empty():
		print("PASS: deep-pool default auto-seeds, sustains crossing, and is deterministic.")
		quit(0)
	else:
		for f in _failures:
			push_error(f)
		print("FAIL: deep-pool coverage found %d issue(s)." % _failures.size())
		quit(1)


func _play() -> Dictionary:
	GameData.load_all(DEEP_SCENARIO)
	GameState.reset_to_scenario()
	var dice := SeededDice.new(SEED)
	var red_turn2 := 0
	var red_final := 0
	var grn_final := 0
	for _t in range(TURNS):
		var result: TurnResult = GameState.play_turn([], [], dice)
		var cs: Dictionary = result.cleanup_summary
		red_final = int(cs.get("china_battalions_on_taiwan", -1))
		grn_final = int(cs.get("taiwan_battalions_on_taiwan", -1))
		if result.turn_number == 2:
			red_turn2 = red_final
		if result.game_over:
			break
		GameState.begin_next_turn()
	return {"red_turn2": red_turn2, "red_final": red_final, "grn_final": grn_final}


func _check(label: String, ok: bool) -> void:
	if ok:
		print("  ok: %s" % label)
	else:
		_failures.append(label)
		print("  FAIL: %s" % label)
