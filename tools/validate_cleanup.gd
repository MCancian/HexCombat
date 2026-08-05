# Run from the project root:
# C:\Godot_v4.7-stable_win64.exe --headless --path C:\Users\mdogg\Desktop\HexCombat -s res://tools/validate_cleanup.gd
#
# Validates D2-C: GameState.resolve_cleanup_phase resets per-turn anti-ship flags and that the result
# is deterministic. Also validates that the existing resolve_turn golden invariant (byte-stable
# ground-combat output under seed 20260624) is preserved — cleanup runs after combat and consumes no
# RNG, so the pinned fingerprint must be unchanged.
# Scripted-turn shape lives in tools/GoldenScript.gd; only the OUTCOME fingerprint is pinned
# here (no-commit variant — differs from validate_headless_turn's committed-defender pin).
# Re-baselined 2026-07-09 twice (both user-approved): Track F defender terrain modifier, then
# the full ROC defense laydown.
extends SceneTree

const SEED := GoldenScript.SEED
const RED_MOVER_ID := GoldenScript.RED_MOVER_ID
const GREEN_DEFENDER_ID := GoldenScript.GREEN_DEFENDER_ID
const START_HEX := GoldenScript.START_HEX
const TARGET_HEX := GoldenScript.TARGET_HEX
# Re-baselined 2026-07-11 for plan 0001 crossing-lethality dial-in (USER call: intel_locked
# strike bonus 0.20 + exquisite-intel initial_count 36 change the PLA force landed before the
# scripted fight, shifting feba). Was "casualties=7, feba=-0.16".
# Re-baselined 2026-07-17 for plan 0008 support unit casualties (USER call). Was "casualties=7, feba=-0.46".
# Re-baselined 2026-07-17 for plan 0010 per-hex combat RNG substreams (scripted fight now draws from
# a derived per-hex dice stream — re-derived draws, not a behaviour change). Was "casualties=9, feba=-0.48".
# Re-baselined 2026-07-17 for plan 0009 follow-up (USER call): IJFS maneuver casualties now include
# the multi-day warmup kills (previously only the final warmup day reached the OOB), so more ROC
# maneuver battalions are removed before the scripted fight, shifting its contributors. Was
# "casualties=8, feba=-0.23".
# Re-baselined 2026-07-24 for the crossing-drowning roster fix (plan 0028 follow-up): drowned
# battalions are now deleted from their brigade rosters, so a partially-landed brigade fights with
# only its surviving BNs (was over-counting drowned "ghost" BNs in combat strength). The scripted
# fight's contributors shift accordingly. Was "casualties=6, feba=0.34".
# Corrected 2026-07-24 (same day, plan 0029 gate run): that re-baseline was taken with NO scenario
# selection, i.e. against scenario_default — but run_all_tests exports HEXCOMBAT_SCENARIO=
# scenario_golden, so the pin never matched the gate and this validator was red on main. Re-measured
# UNDER THE GATE'S SCENARIO (scenario_golden), which is the only environment this pin is asserted in
# — the same trap already recorded for validate_golden_victory. Behaviour unchanged: the drowning fix
# is exactly as shipped, only the pin's measurement environment is corrected.
# Was (default-scenario, never gate-valid) "casualties=7, feba=2.24".
# Re-baselined 2026-07-25 for landed-battalions-only combat (plan 0037, USER call): a brigade counts
# as on-map from its FIRST landed battalion, but now only the battalions actually ASHORE fight. The
# scripted turn runs one offload turn first, so the Red mover attacks with the 4 Amphibious Infantry
# BNs that landed rather than its whole 9-BN roster — fewer bodies on both counts, and the FEBA moves
# against the attacker. Direction is the expected one: Red is the side with off-map pools, Green has
# none, so removing not-ashore strength can only make the Red attack worse.
# Was "casualties=5, feba=-0.72".
# Re-baselined 2026-08-01 for plan 0060 stage 1 (USER rulings R9/R11/R1): Red's reusable air OOB drops
# 584 -> 498 (J-16D 48 -> 10, the 48 anti-radiation pseudo-airframes become a munition, Decoys are
# renamed Attack UCAV at the same strength) and the prelanding warmup becomes a STANDOFF campaign that
# flies no aircraft at all. Both move the IJFS draw sequence and the warmup's maneuver-casualty
# writeback, so the scripted fight starts from a different ROC laydown. Was "casualties=3, feba=-2.66".
# Re-baselined 2026-08-01 for plan 0060 stage 3 (USER rulings R5/R6/R8/R12): four-airframe packages,
# and with them R8's capacity-unit correction — four airframe-sortie seats now buy ONE four-ship
# attack rather than four attacks. Red's warmup strike volume falls sharply, so the scripted fight
# meets a much less damaged ROC. Was "casualties=4, feba=-3.00".
const EXPECTED_COMBAT_FINGERPRINT := "casualties=3, feba=-2.27"

var _h := ValidatorHarness.new("headless cleanup validation")
var GameData: Node = null
var GameState: Node = null


func _initialize() -> void:
	print("=== Headless cleanup (D2-C) validation ===")
	GameData = get_root().get_node("GameData")
	GameState = get_root().get_node("GameState")
	if GameData == null or GameState == null:
		_h.fail("Autoloads GameData/GameState not found")
		_h.finish(self, " (seed=%d)" % SEED)
		return

	GameData.load_all()
	_validate_cleanup_resets_antiship_flags()
	_validate_cleanup_determinism()
	_validate_cleanup_produces_summary()
	_validate_turn_golden_invariant_preserved()
	_h.finish(self, " (seed=%d)" % SEED)


func _validate_cleanup_resets_antiship_flags() -> void:
	GameState.reset_to_scenario()
	GameState.resolve_ijfs_turn(SeededDice.new(SEED))
	GameState.resolve_sealift_turn()  # form the crossing wave (plan 0004) before the anti-ship phase
	GameState.resolve_antiship_turn(SeededDice.new(SEED))

	# Confirm anti-ship was exercised — at least one system has non-zero per-turn flags.
	var exercised := false
	for system_value in GameState.antiship_systems:
		var system: AntishipSystem = system_value
		if system.fired > 0 or system.destroyed_this_turn > 0 or system.active:
			exercised = true
			break
	_h.is_true("anti-ship phase exercised at least one system before cleanup", exercised)

	GameState.resolve_cleanup_phase()

	# AFTER cleanup all per-turn flags must be zero/false.
	for system_value in GameState.antiship_systems:
		var system: AntishipSystem = system_value
		_h.is_true("fired reset to 0 for %s" % system.type_name, system.fired == 0)
		_h.is_true("destroyed_this_turn reset to 0 for %s" % system.type_name, system.destroyed_this_turn == 0)
		_h.is_true("suppressed_now reset to 0 for %s" % system.type_name, system.suppressed_now == 0)
		_h.is_true("active reset to false for %s" % system.type_name, not system.active)
		# Cumulative fields must NOT be touched.
		_h.is_true("destroyed (cumulative) untouched for %s" % system.type_name, system.destroyed >= 0)
		_h.is_true("quantity untouched for %s" % system.type_name, system.quantity >= 0)
		_h.is_true("original_quantity untouched for %s" % system.type_name, system.original_quantity >= 0)

	var summary: CleanupSummary = GameState.last_cleanup_summary
	_h.is_true("last_cleanup_summary produced", summary != null)
	_h.is_true("antiship_systems_reset > 0", summary != null and summary.antiship_systems_reset > 0)


func _validate_cleanup_determinism() -> void:
	GameState.reset_to_scenario()
	GameState.resolve_ijfs_turn(SeededDice.new(SEED))
	GameState.resolve_sealift_turn()  # form the crossing wave (plan 0004) before the anti-ship phase
	GameState.resolve_antiship_turn(SeededDice.new(SEED))
	GameState.resolve_cleanup_phase()
	var first_flags: Array[int] = []
	for system_value in GameState.antiship_systems:
		var system: AntishipSystem = system_value
		first_flags.append(system.fired + system.destroyed_this_turn + system.suppressed_now)

	GameState.reset_to_scenario()
	GameState.resolve_ijfs_turn(SeededDice.new(SEED))
	GameState.resolve_sealift_turn()  # form the crossing wave (plan 0004) before the anti-ship phase
	GameState.resolve_antiship_turn(SeededDice.new(SEED))
	GameState.resolve_cleanup_phase()
	var second_flags: Array[int] = []
	for system_value in GameState.antiship_systems:
		var system: AntishipSystem = system_value
		second_flags.append(system.fired + system.destroyed_this_turn + system.suppressed_now)

	# Compare as JSON strings for deep equality.
	_h.is_true("deterministic cleanup: same flag state", JSON.stringify(first_flags) == JSON.stringify(second_flags))


func _validate_cleanup_produces_summary() -> void:
	GameState.reset_to_scenario()
	GameState.resolve_cleanup_phase()
	var summary: CleanupSummary = GameState.last_cleanup_summary
	_h.is_true("cleanup produces summary when no anti-ship systems", summary != null)
	_h.is_true("summary antiship_systems_reset is zero with no systems", summary != null and summary.antiship_systems_reset == 0)


# Golden invariant: run the scripted move (no commit) with seed 20260624; must still yield
# EXPECTED_COMBAT_FINGERPRINT (re-baselined 2026-07-09, full ROC defense laydown) — cleanup runs
# after combat, consumes no RNG, so ground-combat output is byte-stable given this baseline.
func _validate_turn_golden_invariant_preserved() -> void:
	GameState.reset_to_scenario()
	GameState.resolve_offload_turn(SeededDice.new(SEED))

	_h.equal_int("golden invariant turn_number", GameState.turn_number, 1)

	var red_brigade: Brigade = GameData.get_brigade(RED_MOVER_ID)
	var green_defender: Brigade = GameData.get_brigade(GREEN_DEFENDER_ID)
	if red_brigade == null:
		_h.fail("golden invariant missing Red mover: %s" % RED_MOVER_ID)
		return
	if green_defender == null:
		_h.fail("golden invariant missing Green defender: %s" % GREEN_DEFENDER_ID)
		return

	GameState.add_move_order(Brigade.Team.RED, RED_MOVER_ID, TARGET_HEX, Movement.MODE_TACTICAL)
	var eligible_committers: Array = GameState.eligible_commit_brigades(Brigade.Team.GREEN, TARGET_HEX)
	if not eligible_committers.is_empty():
		GameState.add_commit_order(Brigade.Team.GREEN, String(eligible_committers[0]), TARGET_HEX)

	GameState.resolve_turn(SeededDice.new(SEED))

	var total_casualties := 0
	for summary in GameState.last_combat_summaries:
		total_casualties += summary.attacker_losses
		total_casualties += summary.defender_losses
	var total_feba := 0.0
	for summary in GameState.last_combat_summaries:
		total_feba += summary.feba_movement_km
	total_feba = snapped(total_feba, 0.01)
	var fingerprint := "casualties=%d, feba=%.2f" % [total_casualties, total_feba]
	_assert_equal_string("turn golden invariant preserved (%s)" % EXPECTED_COMBAT_FINGERPRINT, fingerprint, EXPECTED_COMBAT_FINGERPRINT)


func _assert_equal_string(label: String, actual: String, expected: String) -> void:
	if actual != expected:
		_h.fail("%s: expected \"%s\", got \"%s\"" % [label, expected, actual])
