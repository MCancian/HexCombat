extends GdUnitTestSuite

# Mirrors ijfs_standalone engagement.py SEAD + free-shot. Uses the shared ScriptedDice helper;
# scripted randf() draws are its 3rd ctor arg. Draw order: SEAD loop (sorted by target_id) draws
# a destroy roll then a suppression roll on survival; return-fire/free-shot draw once per alive
# aircraft in squadron (force) order.

const AIR_CLASSES := {"classes": {"X": {"sead_eff": 1.0, "wvr": 0.0, "rcs": 0.0}}}


func _sam(id: String, sam_score: int) -> IjfsTarget:
	var t := IjfsTarget.new()
	t.target_id = id
	t.category = "Static SAMs"
	t.subcategory = "SAM"
	t.sam_score = sam_score
	return t


func _squadron(id: String, alive: int, role: String = "sead") -> IjfsSquadron:
	var sq := IjfsSquadron.new()
	sq.squadron_id = id
	sq.aircraft_class = "X"
	sq.role = role
	sq.initial = alive
	sq.alive = alive
	return sq


func test_sead_destroys_target_when_roll_below_p_destroy() -> void:
	# effective_power = 10*1*(1)*(1) = 10; sam_score 10 -> p_destroy = 10/20 = 0.5
	var target := _sam("t1", 10)
	var targets: Array[IjfsTarget] = [target]
	var force: Array[IjfsSquadron] = [_squadron("sq1", 10)]
	# destroy roll 0.4 (<=0.5). Destroyed target -> surviving_sam_score 0 -> no return-fire draws.
	var dice := ScriptedDice.new([], [], [0.4])
	var result := IjfsEngagement.resolve_sead_engagement(targets, force, AIR_CLASSES, dice)
	assert_int(result["engagement_log"].size()).is_equal(1)
	assert_float(result["engagement_log"][0]["p_destroy"]).is_equal_approx(0.5, 0.000001)
	assert_bool(result["engagement_log"][0]["destroyed"]).is_true()
	assert_str(target.sead_result).is_equal("destroyed")
	assert_bool(target.destroyed).is_true()
	assert_array(result["contest_log"]).is_empty()
	assert_int(dice._floats.size()).is_equal(0)


func test_sead_suppresses_survivor_and_excludes_it_from_return_fire() -> void:
	var target := _sam("t1", 10)
	var targets: Array[IjfsTarget] = [target]
	var force: Array[IjfsSquadron] = [_squadron("sq1", 10)]
	# survive (0.6 > 0.5); p_suppress = 0.5*0.4 = 0.2; supp roll 0.1 <= 0.2 -> suppressed.
	# suppressed target excluded from surviving_sam_score -> no return fire.
	var dice := ScriptedDice.new([], [], [0.6, 0.1])
	var result := IjfsEngagement.resolve_sead_engagement(targets, force, AIR_CLASSES, dice)
	assert_bool(result["engagement_log"][0]["destroyed"]).is_false()
	assert_bool(result["engagement_log"][0]["suppressed"]).is_true()
	assert_float(result["engagement_log"][0]["p_suppress"]).is_equal_approx(0.2, 0.000001)
	assert_str(target.sead_result).is_equal("suppressed")
	assert_bool(target.suppressed).is_true()
	assert_array(result["contest_log"]).is_empty()
	assert_int(dice._floats.size()).is_equal(0)


func test_unengaged_survivor_triggers_return_fire_losses() -> void:
	var target := _sam("t1", 10)
	var targets: Array[IjfsTarget] = [target]
	var sq := _squadron("sq1", 10)
	var force: Array[IjfsSquadron] = [sq]
	# survive (0.6), not suppressed (0.9 > 0.2) -> unengaged. surviving_sam_score = 10 > 0.
	# loss_rate = clamp(10*0.02)=0.2; rcs 0 -> rcs_survival 1.0; sq_loss_rate 0.2.
	# 10 aircraft draws: first two <=0.2 (losses), rest > 0.2.
	var floats: Array = [0.6, 0.9, 0.1, 0.1, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5]
	var dice := ScriptedDice.new([], [], floats)
	var result := IjfsEngagement.resolve_sead_engagement(targets, force, AIR_CLASSES, dice)
	assert_str(target.sead_result).is_equal("unengaged")
	assert_int(result["contest_log"].size()).is_equal(1)
	assert_int(result["contest_log"][0]["losses"]).is_equal(2)
	assert_str(result["contest_log"][0]["source"]).is_equal("sead_return_fire")
	assert_int(sq.alive).is_equal(8)
	assert_int(sq.losses_today).is_equal(2)
	assert_int(dice._floats.size()).is_equal(0)


func test_sead_disabled_sets_unengaged_and_draws_nothing() -> void:
	var target := _sam("t1", 10)
	var targets: Array[IjfsTarget] = [target]
	var force: Array[IjfsSquadron] = [_squadron("sq1", 10)]
	var dice := ScriptedDice.new([], [], [])
	var result := IjfsEngagement.resolve_sead_engagement(targets, force, AIR_CLASSES, dice, false)
	assert_array(result["engagement_log"]).is_empty()
	assert_str(target.sead_result).is_equal("unengaged")


func test_null_force_returns_empty_logs() -> void:
	var targets: Array[IjfsTarget] = [_sam("t1", 10)]
	var dice := ScriptedDice.new([], [], [])
	var result := IjfsEngagement.resolve_sead_engagement(targets, null, AIR_CLASSES, dice)
	assert_array(result["engagement_log"]).is_empty()
	assert_array(result["contest_log"]).is_empty()


func test_free_shot_attrition() -> void:
	var sq := _squadron("sq1", 10)
	var force: Array[IjfsSquadron] = [sq]
	# raw_sam_health 0.5 -> loss_rate clamp(0.5*0.05)=0.025; rcs 0 -> p_loss 0.025.
	# one aircraft draw <= 0.025 -> 1 loss.
	var floats: Array = [0.01, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5]
	var dice := ScriptedDice.new([], [], floats)
	var log := IjfsEngagement.apply_post_phase_2_free_shot(force, AIR_CLASSES, 0.5, dice)
	assert_int(log.size()).is_equal(1)
	assert_int(log[0]["losses"]).is_equal(1)
	assert_int(sq.alive).is_equal(9)
	assert_int(dice._floats.size()).is_equal(0)


func test_free_shot_skipped_when_no_sam_health() -> void:
	var sq := _squadron("sq1", 10)
	var force: Array[IjfsSquadron] = [sq]
	var dice := ScriptedDice.new([], [], [])
	var log := IjfsEngagement.apply_post_phase_2_free_shot(force, AIR_CLASSES, 0.0, dice)
	assert_array(log).is_empty()
	assert_int(sq.alive).is_equal(10)
