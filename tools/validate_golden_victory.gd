# Track 3b — end-to-end golden self-play test. Plays the golden scenario (seed 20260624) forward
# from PLANNING with empty orders (offload / anti-ship / combat / cleanup all run automatically)
# and pins the deterministic MAX_TURNS outcome. This exercises the full pipeline: offload landing
# -> on-Taiwan census -> VictoryConditions. Run by the gate (tools/validate_*.gd).
#
# NOTE: since the full ROC defense laydown (2026-07-09, 32 Green brigades) the default scenario
# CANNOT terminate under empty orders — the census red-win can never fire, and two of the four
# landed brigades sit on uncontested beaches so china never attrites to 0. The pinned outcome is
# therefore the turn-40 stalemate census. Victory FIRING (both win paths + arming) is covered by
# tests/victory_conditions_test.gd; the winner ⇔ census consistency check below stays armed in
# case a future rebalance makes the run terminal again — that would move the pins and must be a
# deliberate re-baseline.
extends SceneTree

const SEED := GoldenScript.SEED
const MAX_TURNS := 40
# Golden pins for the empty-orders self-play at MAX_TURNS (re-baselined 2026-07-11 for plan 0001
# crossing-lethality dial-in, USER call: intel_locked strike bonus 0.20 + exquisite-intel
# initial_count 36 lower crossing losses than the old default, landing more PLA battalions; see
# docs/archive/0001-crossing-lethality-calibration.md and docs/DECISIONS.md).
# Re-baselined 2026-07-17 for Plan 0008: support unit casualties (USER call). Was 25/89.
# Re-baselined 2026-07-17 for Plan 0010: per-hex combat RNG substreams (each contested hex now
# draws from its own derived dice stream, re-deriving all combat draws — equally valid, not a
# behaviour change). Was 27/94.
# Re-baselined 2026-07-17 for Plan 0009: CRBM heavy-volley maneuver attrition knob (USER call).
# The crbm_maneuver_strike_bonus (0.15, starting value) now lets CRBM strikes kill ROC maneuver
# battalions before ground combat, so 4 more ROC battalions die and PLA nets one more ashore. Was 25/92.
# Re-baselined 2026-07-17 for Plan 0009 follow-up (USER call): IJFS maneuver casualties now include
# the multi-day warmup kills (previously only the final warmup day reached the OOB), so far more ROC
# maneuver battalions die in the pre-invasion campaign. Was 26/88.
# Re-baselined 2026-07-24 for the crossing-drowning roster fix (plan 0028 follow-up): battalions
# that drown in the crossing are now deleted from their brigade rosters, so the victory census no
# longer ghost-lands drowned BNs of a partially-landed brigade (the census counted
# get_battalion_count - at_sea, and drowned BNs had left at_sea but not the roster). China's count
# drops; Taiwan is unchanged (Green never crosses). Was china=25.
# Re-baselined 2026-08-01 for plan 0060 stage 1 (USER rulings R9/R11/R1): the reusable air OOB drops
# 584 -> 498 and the prelanding warmup becomes a missile-only standoff campaign, so Red flies ~26%
# fewer warmup strikes and the pre-invasion maneuver-casualty writeback lands differently.
# Was china=12 / taiwan=76.
# Re-baselined 2026-08-01 for plan 0060 stage 2 (USER ruling R2): role_exposure_multipliers stopped
# being dead data. Every per-airframe loss probability now carries altitude/profile exposure
# (isr 0.7 / sead 1.0 / strike 1.2) on top of the RCS survival modifier, so Red's strike fleet dies
# faster and its ISR fleet slower than the day before. Was china=11 / taiwan=77.
# Re-baselined 2026-08-01 for plan 0060 stage 3 (USER rulings R5/R6/R8/R12): an Organic strike became
# a FOUR-AIRFRAME PACKAGE. The dominant term is R8's capacity-unit correction — the authored
# firing_units x sorties numbers were always airframe-sortie SEATS, and four seats now buy one
# four-ship attack instead of four attacks — so Red's Organic strike volume falls by about 4x and far
# fewer ROC maneuver battalions die in the warmup. Was china=11 / taiwan=79.
const EXPECTED_GAME_OVER := false
const EXPECTED_CHINA := 16
const EXPECTED_TAIWAN := 103

var _failures: Array[String] = []
var GameData: Node = null
var GameState: Node = null


func _initialize() -> void:
	print("=== Golden end-to-end victory validation ===")
	GameData = get_root().get_node("GameData")
	GameState = get_root().get_node("GameState")
	GameData.load_all()

	var first := _play_to_terminal()
	var second := _play_to_terminal()

	_assert_true("game_over matches golden pin (expected %s, got %s)" % [EXPECTED_GAME_OVER, first["game_over"]],
		first["game_over"] == EXPECTED_GAME_OVER)
	_assert_true("census matches golden pin (expected %d/%d, got %d/%d)" % [EXPECTED_CHINA, EXPECTED_TAIWAN, first["china"], first["taiwan"]],
		first["china"] == EXPECTED_CHINA and first["taiwan"] == EXPECTED_TAIWAN)
	# Winner must be consistent with the final on-Taiwan census (armed only if a rebalance ever
	# makes the run terminal — that also trips the game_over pin above and forces a re-baseline).
	if first["winner"] == "red":
		_assert_true("red win => china (%d) > taiwan (%d)" % [first["china"], first["taiwan"]],
			first["china"] > first["taiwan"])
	elif first["winner"] == "green":
		_assert_true("green win => china battalions == 0 (got %d)" % first["china"], first["china"] == 0)
	_assert_true("census counts are non-negative", first["china"] >= 0 and first["taiwan"] >= 0)

	# Determinism: same seed -> identical terminal turn, winner, and census.
	_assert_true("same seed -> same terminal turn (%d == %d)" % [first["turn"], second["turn"]],
		first["turn"] == second["turn"])
	_assert_true("same seed -> same winner (%s == %s)" % [first["winner"], second["winner"]],
		first["winner"] == second["winner"])
	_assert_true("same seed -> same census (%d/%d == %d/%d)" % [first["china"], first["taiwan"], second["china"], second["taiwan"]],
		first["china"] == second["china"] and first["taiwan"] == second["taiwan"])

	print("Terminal: turn=%d winner=%s china=%d taiwan=%d" % [first["turn"], first["winner"], first["china"], first["taiwan"]])
	_finish()


func _play_to_terminal() -> Dictionary:
	GameState.reset_to_scenario()
	var dice := SeededDice.new(SEED)
	var last := {"game_over": false, "winner": "", "china": -1, "taiwan": -1, "turn": 0}
	for _t in range(MAX_TURNS):
		var result = GameState.play_turn([], [], dice)
		var cs: Dictionary = result.cleanup_summary
		last = {
			"game_over": result.game_over,
			"winner": result.winner,
			"china": int(cs.get("china_battalions_on_taiwan", -1)),
			"taiwan": int(cs.get("taiwan_battalions_on_taiwan", -1)),
			"turn": result.turn_number,
		}
		if result.game_over:
			break
		GameState.begin_next_turn()
	return last


func _assert_true(label: String, value: bool) -> void:
	if not value:
		_failures.append(label)
		push_error(label)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: golden end-to-end victory validation succeeded (seed=%d)" % SEED)
		quit(0)
		return
	print("FAIL: golden end-to-end victory validation found %d issue(s):" % _failures.size())
	for f in _failures:
		print("  - %s" % f)
	quit(1)
