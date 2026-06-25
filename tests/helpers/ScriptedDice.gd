extends Dice
class_name ScriptedDice

var _rolls: Array = []
var _choices: Array = []
var _floats: Array = []
var _weighted: Array = []
var _shuffles: Array = []


func _init(rolls: Array, choices: Array = [], floats: Array = [], weighted: Array = [], shuffles: Array = []) -> void:
	_rolls = rolls.duplicate()
	_choices = choices.duplicate()
	_floats = floats.duplicate()
	_weighted = weighted.duplicate()
	_shuffles = shuffles.duplicate()


func roll_d100() -> int:
	if _rolls.is_empty():
		push_error("ScriptedDice.roll_d100() called with no scripted rolls remaining")
		return 1
	return int(_rolls.pop_front())


func choose_indices(population_size: int, count: int) -> Array[int]:
	if count <= 0:
		return []
	if _choices.is_empty():
		push_error("ScriptedDice.choose_indices() called with no scripted choices remaining")
		return []

	var raw_choice = _choices.pop_front()
	if not (raw_choice is Array):
		push_error("ScriptedDice choice entry must be an Array")
		return []

	var choice: Array = raw_choice
	if choice.size() != count:
		push_error("ScriptedDice choice size %d did not match requested count %d" % [choice.size(), count])

	var indices: Array[int] = []
	for raw_index in choice:
		var index := int(raw_index)
		if index < 0 or index >= population_size:
			push_error("ScriptedDice choice index %d outside population size %d" % [index, population_size])
		indices.append(index)
	return indices


func randf() -> float:
	if _floats.is_empty():
		push_error("ScriptedDice.randf() called with no scripted floats remaining")
		return 0.0
	return float(_floats.pop_front())


func weighted_choice(weights: Array) -> int:
	if weights.is_empty():
		push_error("ScriptedDice.weighted_choice() requires non-empty weights")
		return 0
	if _weighted.is_empty():
		push_error("ScriptedDice.weighted_choice() called with no scripted weighted choices remaining")
		return 0

	var index := int(_weighted.pop_front())
	if index < 0 or index >= weights.size():
		push_error("ScriptedDice weighted choice index %d outside weights size %d" % [index, weights.size()])
	return index


func weighted_choices(weights: Array, k: int) -> Array[int]:
	if k <= 0:
		return []

	var indices: Array[int] = []
	for i in range(k):
		indices.append(weighted_choice(weights))
	return indices


func shuffle_indices(n: int) -> Array[int]:
	if n < 0:
		push_error("ScriptedDice.shuffle_indices() requires n >= 0")
		return []
	if _shuffles.is_empty():
		push_error("ScriptedDice.shuffle_indices() called with no scripted shuffles remaining")
		return []

	var raw_shuffle = _shuffles.pop_front()
	if not (raw_shuffle is Array):
		push_error("ScriptedDice shuffle entry must be an Array")
		return []

	var raw_indices: Array = raw_shuffle
	if raw_indices.size() != n:
		push_error("ScriptedDice shuffle size %d did not match requested n %d" % [raw_indices.size(), n])

	var seen: Dictionary = {}
	var indices: Array[int] = []
	for raw_index in raw_indices:
		var index := int(raw_index)
		if index < 0 or index >= n:
			push_error("ScriptedDice shuffle index %d outside range 0..%d" % [index, n - 1])
		if seen.has(index):
			push_error("ScriptedDice shuffle index %d appeared more than once" % index)
		seen[index] = true
		indices.append(index)

	for i in range(n):
		if not seen.has(i):
			push_error("ScriptedDice shuffle missing index %d" % i)
	return indices


func derive(label: String) -> Dice:
	# Scripted sub-streams intentionally share this dice instance and its queues.
	return self
