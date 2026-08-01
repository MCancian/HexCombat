extends RefCounted
class_name Dice


func roll_d100() -> int:
	push_error("Dice.roll_d100() must be overridden")
	return 1


func choose_indices(population_size: int, count: int) -> Array[int]:
	push_error("Dice.choose_indices() must be overridden")
	return []


func randf() -> float:
	push_error("Dice.randf() must be overridden")
	return 0.0


func weighted_choice(weights: Array) -> int:
	push_error("Dice.weighted_choice() must be overridden")
	return 0


func weighted_choices(weights: Array, k: int) -> Array[int]:
	push_error("Dice.weighted_choices() must be overridden")
	return []


func shuffle_indices(n: int) -> Array[int]:
	push_error("Dice.shuffle_indices() must be overridden")
	return []


func derive(label: String) -> Dice:
	push_error("Dice.derive() must be overridden")
	return self
