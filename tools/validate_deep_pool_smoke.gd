extends SceneTree

# Deep-pool coverage for the RESEARCH default (scenario_default.json) — the sustained-sealift
# scenario the rest of the gate does NOT exercise (it runs against scenario_golden.json). Explicitly
# loads scenario_default regardless of the gate's HEXCOMBAT_SCENARIO=golden selection, then checks:
#   1. the deep mainland pool auto-seeded (SealiftStateBuilder.resolve_followon_reserve),
#   2. sustained crossing — Red keeps arriving past the first wave (follow-on echelons embark),
#   3. determinism — same seed => identical terminal census (the reproducibility contract).
# Prints PASS:/FAIL: for the gate's Phase-3 verdict.
#
# Plan 0006: the run pushes every beach-sitting RED brigade one hex inland each turn. Under the
# beach occupancy valve (BeachDef.depth) a parked Day-1 assault closes its beach, so an
# empty-orders run plateaus by design and sustained crossing would be unobservable; moving inland
# clears the valve each turn, which is exactly the intended tempo loop this smoke must cover
# (land -> vacate -> next echelon lands).
#
# Plan 0006 C8: also assert landings CONTINUE past turn 10. The weight matrix once let a BN whose
# beach cost exceeded its locked beach's full per-day tons defer forever, deadlocking its cohort's
# hulls and freezing all sealift at ~turn 10 (fixed by day-N carry-over in OffloadCalculator);
# a 10-turn run could never see it.

const DEEP_SCENARIO := "res://data/scenarios/scenario_default.json"
const SEED := 20260624
const TURNS := 12
const LATE_LANDING_AFTER_TURN := 10

var GameData: Node = null
var GameState: Node = null
var _failures: Array[String] = []
var _late_landed := 0


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
	_check("sealift still landing after turn %d (no offload/cohort deadlock; %d BNs)"
		% [LATE_LANDING_AFTER_TURN, a["late_landed"]], a["late_landed"] > 0)
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
	_late_landed = 0
	var bus: Node = get_root().get_node("EventBus")
	bus.offload_resolved.connect(_on_offload_resolved)
	for _t in range(TURNS):
		var result: TurnResult = GameState.play_turn(_inland_move_orders(), [], dice)
		var cs: Dictionary = result.cleanup_summary
		red_final = int(cs.get("china_battalions_on_taiwan", -1))
		grn_final = int(cs.get("taiwan_battalions_on_taiwan", -1))
		if result.turn_number == 2:
			red_turn2 = red_final
		if result.game_over:
			break
		GameState.begin_next_turn()
	bus.offload_resolved.disconnect(_on_offload_resolved)
	return {"red_turn2": red_turn2, "red_final": red_final, "grn_final": grn_final,
		"late_landed": _late_landed}


# GDScript lambdas capture primitives by value, so the per-run counter lives on the script.
func _on_offload_resolved(manifest: Dictionary) -> void:
	if GameState.turn_number > LATE_LANDING_AFTER_TURN:
		_late_landed += int(manifest.get("bns_landed", 0))


# Deterministic "clear the beach" policy: every non-destroyed RED brigade standing on a beach hex
# moves to that hex's first sorted neighbor that is not itself a beach hex. Same rule as the
# catalog policy `inland_clear` (InlandClearPolicy) used by research runs; kept as a private
# order-dict copy here so this gate validator drives GameState.play_turn directly and stays
# self-contained.
func _inland_move_orders() -> Array:
	var beach_hexes: Dictionary = {}
	for beach_value in GameData.beaches.values():
		beach_hexes[String(beach_value.hex_id)] = true
	var orders: Array = []
	for brigade_value in GameData.brigades.values():
		var brigade: Brigade = brigade_value
		if brigade.team != Brigade.Team.RED or brigade.destroyed or brigade.hex_id.is_empty():
			continue
		if not beach_hexes.has(brigade.hex_id):
			continue
		var neighbors: Array = (GameData.neighbor_lookup.get(brigade.hex_id, []) as Array).duplicate()
		neighbors.sort()
		for neighbor_value in neighbors:
			var neighbor := String(neighbor_value)
			if not beach_hexes.has(neighbor):
				orders.append({"kind": "move", "brigade_id": brigade.id, "target_hex": neighbor})
				break
	return orders


func _check(label: String, ok: bool) -> void:
	if ok:
		print("  ok: %s" % label)
	else:
		_failures.append(label)
		print("  FAIL: %s" % label)
