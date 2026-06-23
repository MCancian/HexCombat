extends RefCounted
class_name Dice


func roll_d100() -> int:
	push_error("Dice.roll_d100() must be overridden")
	return 1


func choose_indices(population_size: int, count: int) -> Array[int]:
	push_error("Dice.choose_indices() must be overridden")
	return []
