extends Resource
class_name MoveOrder

@export var brigade_id: String = ""
@export var target_hex: String = ""
@export var mode: String = "tactical"  # "tactical" | "administrative"; validation is M4


## Whether this order is an ADMINISTRATIVE move (fast, but the brigade may not fight this turn). The
## predicate lives on the order rather than being spelled out at each call site — which is also what
## keeps `Movement` off TurnConductor's dependency budget.
func is_administrative() -> bool:
	return mode == Movement.MODE_ADMINISTRATIVE
