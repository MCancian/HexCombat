extends GdUnitTestSuite

# Plan 0060's RNG contract: the day derives ONE child stream for air-engagement rolls — package
# assembly, MANPADS, SAM return fire, anti-radiation salvos — and RETAINS it. Two failure modes it
# exists to prevent:
#
#   * re-deriving the same label per package, which hands every package an identical sequence;
#   * drawing package geometry off the main phase stream, where it would shift the strike, detection
#     and SEAD rolls that surround it.
#
# These use a REAL SeededDice, deliberately. ScriptedDice's `derive` returns `self` and shares its
# queues, so under it a child and its parent are the same stream by construction and the isolation
# this suite is about could not fail.

const LABEL := "ijfs_air_engagements"


func _floats(dice: Dice, count: int) -> Array:
	var out: Array = []
	for _i in range(count):
		out.append(dice.randf())
	return out


func test_deriving_the_child_does_not_advance_the_parent() -> void:
	var untouched := SeededDice.new(20260801)
	var expected := _floats(untouched, 5)

	var parent := SeededDice.new(20260801)
	parent.derive(LABEL)
	assert_array(_floats(parent, 5)).override_failure_message(
		"deriving the air-engagement stream must not consume a draw from the phase stream"
	).is_equal(expected)


func test_the_child_stream_is_independent_of_the_parent() -> void:
	var parent := SeededDice.new(20260801)
	var child := parent.derive(LABEL)
	assert_array(_floats(child, 8)).override_failure_message(
		"package geometry drawn off the child must not reproduce the phase stream"
	).is_not_equal(_floats(SeededDice.new(20260801), 8))


func test_retaining_one_child_gives_successive_packages_different_draws() -> void:
	# The bug the plan names: `derive(LABEL)` per package. Every package would then see the same
	# first four floats, so package composition would be identical all day.
	var parent := SeededDice.new(20260801)
	var re_derived_first := _floats(parent.derive(LABEL), 4)
	var re_derived_second := _floats(parent.derive(LABEL), 4)
	assert_array(re_derived_second).override_failure_message(
		"re-deriving the same label is the failure mode, and this pins that it really would repeat"
	).is_equal(re_derived_first)

	var retained := parent.derive(LABEL)
	var retained_first := _floats(retained, 4)
	var retained_second := _floats(retained, 4)
	assert_array(retained_second).override_failure_message(
		"one RETAINED child must keep advancing, so package two is not package one"
	).is_not_equal(retained_first)
	assert_array(retained_first).is_equal(re_derived_first)


func test_a_different_label_is_a_different_stream() -> void:
	var parent := SeededDice.new(20260801)
	assert_array(_floats(parent.derive(LABEL), 6)).override_failure_message(
		"the air-engagement label must not collide with the day label"
	).is_not_equal(_floats(parent.derive("ijfs:1:0"), 6))
