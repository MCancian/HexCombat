extends Dice
class_name ScriptedDice

var _rolls: Array = []
var _choices: Array = []


func _init(rolls: Array, choices: Array = []) -> void:
	_rolls = rolls.duplicate()
	_choices = choices.duplicate()


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
	if not raw_choice is Array:
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
