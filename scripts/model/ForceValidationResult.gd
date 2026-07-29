class_name ForceValidationResult
extends Resource

@export var error: String = ""


static func refused(message: String) -> ForceValidationResult:
	var result := ForceValidationResult.new()
	result.error = message
	return result
