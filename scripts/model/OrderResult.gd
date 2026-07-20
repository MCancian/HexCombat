extends Resource
class_name OrderResult

## Typed outcome of an order-validation call (plan 0017). Replaces the pre-0017 push_error +
## void-return convention on OrderValidator.add_move_order / add_commit_order: callers can now
## branch on `ok` and read a machine-branchable `code` plus a human `message` (the same text the
## old push_error carried) for logs and LLM feedback. Follows the typed-Resource pattern of
## CombatResult / MineResult. `code` categories are shared across move and commit validation.

enum Code {
	OK,
	WRONG_PHASE,
	UNKNOWN_BRIGADE,
	TEAM_MISMATCH,
	UNKNOWN_HEX,
	UNKNOWN_MODE,
	BEYOND_ALLOWANCE,
	DESTROYED,
	ADMIN_MOVED,
	ALREADY_IN_HEX,
	NOT_ADJACENT,
	DUPLICATE_MOVE,
	DUPLICATE_COMMIT,
}

@export var ok: bool = true
@export var code: Code = Code.OK
@export var message: String = ""


static func accept() -> OrderResult:
	return OrderResult.new()


static func reject(reject_code: Code, reject_message: String) -> OrderResult:
	var result := OrderResult.new()
	result.ok = false
	result.code = reject_code
	result.message = reject_message
	return result
