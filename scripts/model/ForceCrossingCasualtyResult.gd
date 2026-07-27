class_name ForceCrossingCasualtyResult
extends Resource

@export var success: bool = false
@export var receipts: Array[ForceCasualtyReceipt] = []
@export var error: String = ""


static func ok(p_receipts: Array[ForceCasualtyReceipt]) -> ForceCrossingCasualtyResult:
	var result := ForceCrossingCasualtyResult.new()
	result.success = true
	result.receipts = p_receipts
	return result


static func refused(message: String) -> ForceCrossingCasualtyResult:
	var result := ForceCrossingCasualtyResult.new()
	result.success = false
	result.error = message
	if not message.is_empty():
		push_error(message)
	return result
