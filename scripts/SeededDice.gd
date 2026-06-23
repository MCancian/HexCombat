extends Dice
class_name SeededDice

var _rng: RandomNumberGenerator


func _init(seed_value: int) -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value


func roll_d100() -> int:
	return _rng.randi_range(1, 100)


func choose_indices(population_size: int, count: int) -> Array[int]:
	var select_count := clampi(count, 0, population_size)
	var indices: Array[int] = []
	for i in range(population_size):
		indices.append(i)

	var selected: Array[int] = []
	for i in range(select_count):
		var swap_index := _rng.randi_range(i, population_size - 1)
		var temp := indices[i]
		indices[i] = indices[swap_index]
		indices[swap_index] = temp
		selected.append(indices[i])

	return selected
