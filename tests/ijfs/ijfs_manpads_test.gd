extends GdUnitTestSuite

# MANPADS layer (2026-07-10 USER design call, deliberate TIV-oracle divergence): per-TO container
# bins contest low-altitude air ops (strike interception + squadron contest) and deteriorate via
# usage, bombardment (normal strike path — not tested here), and TO ground losses
# (IjfsResolver.sync_manpads_to_oob). Uses the shared ScriptedDice helper.

const AIR_CLASSES := {"classes": {"4th Gen": {"rcs": 0, "wvr": 0, "isr_value": 0, "sead_eff": 2}}}


func _bin(id: String, to_number: int, systems: int, destroyed := false, suppressed := false) -> IjfsTarget:
	var t := IjfsTarget.new()
	t.target_id = id
	t.category = IjfsManpads.CATEGORY
	t.metadata = {"to_number": to_number, "systems_represented": systems}
	t.destroyed = destroyed
	t.suppressed = suppressed
	return t


func _maneuver(id: String, to_number: int, destroyed := false) -> IjfsTarget:
	var t := IjfsTarget.new()
	t.target_id = id
	t.category = "Maneuver Units"
	t.metadata = {"to_number": to_number}
	t.destroyed = destroyed
	return t


func _strike_target(id: String, to_number: int) -> IjfsTarget:
	var t := IjfsTarget.new()
	t.target_id = id
	t.category = "Maneuver Units"
	t.metadata = {"to_number": to_number}
	return t


func _munition(vulnerability: float) -> IjfsMunition:
	var m := IjfsMunition.new()
	m.munition_id = "attack_uav_small"
	m.manpads_vulnerability = vulnerability
	return m


func _squadron(id: String, role: String, alive: int) -> IjfsSquadron:
	var sq := IjfsSquadron.new()
	sq.squadron_id = id
	sq.aircraft_class = "4th Gen"
	sq.role = role
	sq.initial = alive
	sq.alive = alive
	return sq


func test_ready_systems_excludes_dead_suppressed_and_seeds_remaining() -> void:
	var targets: Array[IjfsTarget] = [
		_bin("m1", 2, 50),
		_bin("m2", 2, 50, true),         # destroyed -> 0
		_bin("m3", 3, 50, false, true),  # suppressed -> 0 threat
	]
	var by_to := IjfsManpads.ready_systems_by_to(targets)
	assert_int(by_to["total"]).is_equal(50)
	assert_int(by_to["2"]).is_equal(50)
	assert_bool(by_to.has("3")).is_false()
	# systems_remaining was lazily seeded from systems_represented
	assert_int(int(targets[0].metadata["systems_remaining"])).is_equal(50)


func test_interception_rolls_expends_and_reports() -> void:
	var bins: Array[IjfsTarget] = [_bin("m1", 2, 500)]
	# threat = 500/500 = 1.0; p = 1.0 * 0.15 * 1.0 = 0.15; roll 0.1 <= 0.15 -> intercepted
	var dice := ScriptedDice.new([], [], [0.1])
	var entry: Variant = IjfsManpads.roll_strike_interception(_strike_target("t1", 2), _munition(1.0), bins, dice)
	assert_bool(entry["intercepted"]).is_true()
	assert_float(entry["p_intercept"]).is_equal_approx(0.15, 0.000001)
	# usage drain: attempt fired regardless of outcome
	assert_int(int(bins[0].metadata["systems_remaining"])).is_equal(500 - IjfsManpads.EXPEND_PER_INTERCEPT)


func test_interception_skips_without_consuming_dice() -> void:
	var dice := ScriptedDice.new([], [], [])
	# invulnerable munition -> null, no draw
	assert_that(IjfsManpads.roll_strike_interception(
		_strike_target("t1", 2), _munition(0.0), [_bin("m1", 2, 50)] as Array[IjfsTarget], dice)).is_null()
	# no ready launchers in the strike's TO -> null, no draw
	assert_that(IjfsManpads.roll_strike_interception(
		_strike_target("t2", 4), _munition(1.0), [_bin("m1", 2, 50)] as Array[IjfsTarget], dice)).is_null()


func test_contest_engages_only_low_altitude_roles() -> void:
	var bins: Array[IjfsTarget] = [_bin("m1", 2, 500)]
	var force := [
		_squadron("sead1", "sead", 2),
		_squadron("strike1", "strike", 1),
		_squadron("isr1", "isr", 3),      # high-altitude: never engaged
		_squadron("bench", "unused", 5),
	]
	# threat 1.0 -> p_loss = 0.01 per aircraft; draws: 2 (sead) + 1 (strike) = 3
	var dice := ScriptedDice.new([], [], [0.005, 0.5, 0.5])
	var log := IjfsManpads.contest_squadrons(bins, force, AIR_CLASSES, dice)
	assert_int(log.size()).is_equal(2)
	assert_int(log[0]["losses"]).is_equal(1)  # sead1: roll 0.005 <= 0.01
	assert_int(log[1]["losses"]).is_equal(0)
	assert_str(log[0]["source"]).is_equal("manpads")
	assert_int((force[0] as IjfsSquadron).alive).is_equal(1)
	assert_int((force[2] as IjfsSquadron).alive).is_equal(3)
	# usage: 3 engaged aircraft x EXPEND_PER_CONTEST_AIRCRAFT
	assert_int(int(bins[0].metadata["systems_remaining"])).is_equal(
		500 - 3 * IjfsManpads.EXPEND_PER_CONTEST_AIRCRAFT)
	assert_int(dice._floats.size()).is_equal(0)


func test_expend_drains_bins_deterministically() -> void:
	var bins: Array[IjfsTarget] = [_bin("m2", 2, 50), _bin("m1", 2, 50)]
	IjfsManpads.expend(bins, 2, 60)
	# lowest target_id first: m1 drained to 0, m2 pays the remaining 10
	assert_int(int(bins[1].metadata["systems_remaining"])).is_equal(0)
	assert_int(int(bins[0].metadata["systems_remaining"])).is_equal(40)


func test_sync_manpads_to_oob_caps_by_to_survival() -> void:
	var state := IjfsDailyState.new()
	state.targets = [
		_maneuver("mu1", 2), _maneuver("mu2", 2, true),  # TO2: 1/2 alive
		_maneuver("mu3", 3),                             # TO3: 1/1 alive
		_bin("mp2", 2, 50),
		_bin("mp3", 3, 50),
	]
	IjfsResolver.sync_manpads_to_oob(state)
	assert_int(int(state.targets[3].metadata["systems_remaining"])).is_equal(25)
	assert_int(int(state.targets[4].metadata["systems_remaining"])).is_equal(50)
	# monotonic: usage already below the cap stays put
	state.targets[3].metadata["systems_remaining"] = 10
	IjfsResolver.sync_manpads_to_oob(state)
	assert_int(int(state.targets[3].metadata["systems_remaining"])).is_equal(10)


func test_intercepted_strike_log_is_summary_compatible() -> void:
	var pairing := IjfsPairing.new()
	pairing.pairing_id = "p1"
	pairing.munition_id = "attack_uav_small"
	pairing.rounds_expended_per_engagement = 1
	var entry := IjfsManpads.intercepted_strike_log(_strike_target("t1", 2), pairing, 3, "post_ad_recompute", null, null)
	assert_bool(entry["attack_executed"]).is_true()
	assert_bool(entry["destroyed"]).is_false()
	assert_bool(entry["suppressed"]).is_false()
	assert_bool(entry["intercepted_by_manpads"]).is_true()
	assert_int(entry["rounds_expended"]).is_equal(1)
