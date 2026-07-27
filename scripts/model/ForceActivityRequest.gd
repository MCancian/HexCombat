class_name ForceActivityRequest
extends Resource

enum Operation {
	MOVE_TACTICAL,
	MOVE_ADMIN,
	FOUGHT,
	LATCH_PRIOR_FROM_CURRENT,
	RESET_TURN_FLAGS,
}

@export var operation: Operation = Operation.FOUGHT


static func make(p_operation: Operation) -> ForceActivityRequest:
	var request := ForceActivityRequest.new()
	request.operation = p_operation
	return request
