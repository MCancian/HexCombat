extends GdUnitTestSuite


func test_seeded_dice_new_methods_are_deterministic() -> void:
	var first := SeededDice.new(12345)
	var second := SeededDice.new(12345)

	assert_array(_mixed_sequence(first, 20)).is_equal(_mixed_sequence(second, 20))


func test_randf_is_in_half_open_unit_interval() -> void:
	var dice := SeededDice.new(777)
	for i in range(1000):
		var value := dice.randf()
		assert_bool(value >= 0.0).is_true()
		assert_bool(value < 1.0).is_true()


func test_weighted_choice_respects_zero_weights_and_covers_uniform_indices() -> void:
	var forced := SeededDice.new(42)
	for i in range(100):
		assert_int(forced.weighted_choice([0.0, 1.0, 0.0])).is_equal(1)

	var uniform := SeededDice.new(314159)
	var hits: Dictionary = {}
	for i in range(400):
		hits[uniform.weighted_choice([1.0, 1.0, 1.0, 1.0])] = true

	for i in range(4):
		assert_bool(hits.has(i)).is_true()


func test_shuffle_indices_returns_permutation_and_is_deterministic() -> void:
	var first := SeededDice.new(2468)
	var second := SeededDice.new(2468)
	var shuffled := first.shuffle_indices(20)
	var expected := _range_array(20)
	var sorted := shuffled.duplicate()
	sorted.sort()

	assert_array(sorted).is_equal(expected)
	assert_array(shuffled).is_equal(second.shuffle_indices(20))


func test_derive_is_reproducible_independent_and_does_not_advance_parent() -> void:
	var parent := SeededDice.new(9876)
	var control := SeededDice.new(9876)

	assert_float(parent.randf()).is_equal_approx(control.randf(), 0.0)

	var alpha_a := parent.derive("alpha")
	var alpha_b := SeededDice.new(9876).derive("alpha")
	var beta := parent.derive("beta")

	var alpha_sequence_a := _float_sequence(alpha_a, 5)
	var alpha_sequence_b := _float_sequence(alpha_b, 5)
	var beta_sequence := _float_sequence(beta, 5)

	assert_array(alpha_sequence_a).is_equal(alpha_sequence_b)
	assert_bool(alpha_sequence_a != beta_sequence).is_true()
	assert_float(parent.randf()).is_equal_approx(control.randf(), 0.0)


func test_scripted_dice_new_queues_return_values_in_order() -> void:
	var dice := ScriptedDice.new([], [], [0.25, 0.75], [2, 1, 0], [[2, 0, 1]])

	assert_float(dice.randf()).is_equal(0.25)
	assert_float(dice.randf()).is_equal(0.75)
	assert_int(dice.weighted_choice([1.0, 1.0, 1.0])).is_equal(2)
	assert_array(dice.weighted_choices([1.0, 1.0, 1.0], 2)).is_equal([1, 0])
	assert_array(dice.shuffle_indices(3)).is_equal([2, 0, 1])
	assert_bool(dice.derive("shared") == dice).is_true()


func test_scripted_dice_empty_new_queues_push_errors() -> void:
	var dice := ScriptedDice.new([])

	await assert_error(func() -> void:
		dice.randf()
	).is_push_error("ScriptedDice.randf() called with no scripted floats remaining")

	await assert_error(func() -> void:
		dice.weighted_choice([1.0])
	).is_push_error("ScriptedDice.weighted_choice() called with no scripted weighted choices remaining")

	await assert_error(func() -> void:
		dice.shuffle_indices(1)
	).is_push_error("ScriptedDice.shuffle_indices() called with no scripted shuffles remaining")


func _range_array(n: int) -> Array[int]:
	var values: Array[int] = []
	for i in range(n):
		values.append(i)
	return values


func _float_sequence(dice: Dice, count: int) -> Array:
	var values: Array = []
	for i in range(count):
		values.append(dice.randf())
	return values


func _mixed_sequence(dice: Dice, count: int) -> Array:
	var values: Array = []
	var weights := [1.0, 2.0, 3.0, 4.0]
	for i in range(count):
		values.append(dice.randf())
		values.append(dice.weighted_choice(weights))
		values.append(dice.shuffle_indices(8))
	return values
