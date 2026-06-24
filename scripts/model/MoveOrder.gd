extends Resource
class_name MoveOrder

@export var brigade_id: String = ""
@export var target_hex: String = ""
@export var mode: String = "tactical"  # "tactical" | "administrative"; validation is M4
