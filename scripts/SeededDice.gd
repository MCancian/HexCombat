extends Dice
class_name SeededDice

var _seed: int
var _rng: RandomNumberGenerator


func _init(seed_value: int) -> void:
	_seed = seed_value
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


func randf() -> float:
	return _rng.randf()


func weighted_choice(weights: Array) -> int:
	if weights.is_empty():
		push_error("SeededDice.weighted_choice() requires non-empty weights")
		return 0

	var total := 0.0
	for raw_weight in weights:
		var weight := float(raw_weight)
		if weight < 0.0:
			push_error("SeededDice.weighted_choice() requires non-negative weights")
			return 0
		total += weight

	if total <= 0.0:
		push_error("SeededDice.weighted_choice() requires at least one positive weight")
		return 0

	var target := _rng.randf() * total
	var cumulative := 0.0
	for i in range(weights.size()):
		cumulative += float(weights[i])
		if target < cumulative:
			return i

	return weights.size() - 1


func weighted_choices(weights: Array, k: int) -> Array[int]:
	if k <= 0:
		return []

	var selected: Array[int] = []
	for i in range(k):
		selected.append(weighted_choice(weights))
	return selected


func shuffle_indices(n: int) -> Array[int]:
	if n < 0:
		push_error("SeededDice.shuffle_indices() requires n >= 0")
		return []

	var indices: Array[int] = []
	for i in range(n):
		indices.append(i)

	for i in range(n - 1, 0, -1):
		var swap_index := _rng.randi_range(0, i)
		var temp := indices[i]
		indices[i] = indices[swap_index]
		indices[swap_index] = temp

	return indices


func derive(label: String) -> Dice:
	var derived_seed := hash(str(_seed) + ":" + label)
	return SeededDice.new(derived_seed)
