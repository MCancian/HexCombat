class_name OrderValidator
extends RefCounted

## Static order validation for HexCombat's planning phase (plan 0014 P4). Every public method
## takes `state: GameStateData` as its first argument, reads the GameData content autoload for
## legality checks, and mutates `state.orders` / `state.commitments` in place. Reading GameData is
## allowed (universal read-only content source); this class never takes the GameState autoload
## singleton, which is what makes it unit-testable against a GameStateData built from scratch.
##
## Rejections return a typed OrderResult (plan 0017): `OrderResult.reject(code, message)` on failure,
## `OrderResult.accept()` on success. Callers branch on `result.ok` and surface `result.code` /
## `result.message` (the LLM API feeds the message back to the agent). `eligible_commit_brigades`
## keeps its lone push_error — that guard is a programmer error (query fed a bad hex), not order
## validation. GameState.gd's add_move_order/add_commit_order are one-line delegating wrappers.

const MoveOrderResource = preload("res://scripts/model/MoveOrder.gd")
const CommitOrderResource = preload("res://scripts/model/CommitOrder.gd")


static func add_move_order(state: GameStateData, team: Brigade.Team, brigade_id: String, target_hex: String, mode: String) -> OrderResult:
	if state.phase != GameStateData.Phase.PLANNING:
		return OrderResult.reject(OrderResult.Code.WRONG_PHASE, "Cannot add move order outside PLANNING phase")

	var brigade: Brigade = GameData.get_brigade(brigade_id)
	if brigade == null:
		return OrderResult.reject(OrderResult.Code.UNKNOWN_BRIGADE, "Move order references unknown brigade_id: %s" % brigade_id)
	if brigade.team != team:
		return OrderResult.reject(OrderResult.Code.TEAM_MISMATCH, "Move order team mismatch for %s: order=%s brigade=%s" % [brigade_id, team_to_string(team), team_to_string(brigade.team)])
	if target_hex not in GameData.hex_lookup:
		return OrderResult.reject(OrderResult.Code.UNKNOWN_HEX, "Move order references unknown target_hex: %s" % target_hex)
	if mode != Movement.MODE_TACTICAL and mode != Movement.MODE_ADMINISTRATIVE:
		return OrderResult.reject(OrderResult.Code.UNKNOWN_MODE, "Unknown movement mode: %s" % mode)

	var conflict := pending_order_conflict(state, team, brigade_id)
	if not conflict.ok:
		return conflict

	var allowance := Movement.move_allowance(brigade, mode)
	var reachable := GameData.find_reachable(brigade.hex_id, allowance)
	if target_hex not in reachable:
		return OrderResult.reject(OrderResult.Code.BEYOND_ALLOWANCE, "Move order target %s beyond %s allowance for %s" % [target_hex, mode, brigade_id])

	var order: MoveOrder = MoveOrderResource.new()
	order.brigade_id = brigade_id
	order.target_hex = target_hex
	order.mode = mode
	state.orders[team].append(order)
	return OrderResult.accept()


static func add_commit_order(state: GameStateData, team: Brigade.Team, brigade_id: String, target_hex: String) -> OrderResult:
	if state.phase != GameStateData.Phase.PLANNING:
		return OrderResult.reject(OrderResult.Code.WRONG_PHASE, "Cannot add commit order outside PLANNING phase")

	var brigade: Brigade = GameData.get_brigade(brigade_id)
	if brigade == null:
		return OrderResult.reject(OrderResult.Code.UNKNOWN_BRIGADE, "Commit order references unknown brigade_id: %s" % brigade_id)
	if brigade.team != team:
		return OrderResult.reject(OrderResult.Code.TEAM_MISMATCH, "Commit order team mismatch for %s: order=%s brigade=%s" % [brigade_id, team_to_string(team), team_to_string(brigade.team)])
	if brigade.destroyed:
		return OrderResult.reject(OrderResult.Code.DESTROYED, "Destroyed brigade cannot commit: %s" % brigade_id)
	if brigade.moved_admin_this_turn:
		return OrderResult.reject(OrderResult.Code.ADMIN_MOVED, "Administrative-moved brigade cannot commit: %s" % brigade_id)
	if target_hex not in GameData.hex_lookup:
		return OrderResult.reject(OrderResult.Code.UNKNOWN_HEX, "Commit order references unknown target_hex: %s" % target_hex)
	if brigade.hex_id == target_hex:
		return OrderResult.reject(OrderResult.Code.ALREADY_IN_HEX, "Commit order brigade is already in target hex: %s" % brigade_id)
	if brigade.hex_id not in GameData.get_neighbors(target_hex):
		return OrderResult.reject(OrderResult.Code.NOT_ADJACENT, "Commit order brigade %s is not adjacent to target_hex: %s" % [brigade_id, target_hex])

	var conflict := pending_order_conflict(state, team, brigade_id)
	if not conflict.ok:
		return conflict

	var order: CommitOrder = CommitOrderResource.new()
	order.brigade_id = brigade_id
	order.target_hex = target_hex
	state.commitments[team].append(order)
	return OrderResult.accept()


static func eligible_commit_brigades(state: GameStateData, team: Brigade.Team, target_hex: String) -> Array:
	if target_hex not in GameData.hex_lookup:
		push_error("Commit eligibility requested for unknown target_hex: %s" % target_hex)
		return []

	var eligible: Array = []
	for brigade_value in GameData.brigades.values():
		var brigade: Brigade = brigade_value
		if brigade.team != team or brigade.destroyed or brigade.moved_admin_this_turn:
			continue
		if brigade.hex_id == target_hex:
			continue
		if brigade.hex_id not in GameData.get_neighbors(target_hex):
			continue
		if not pending_order_conflict(state, team, brigade.id).ok:
			continue
		eligible.append(brigade.id)
	return eligible


## Single home for the "one order per brigade per turn" rule. Returns a rejecting OrderResult
## (DUPLICATE_MOVE / DUPLICATE_COMMIT, message centralized here) when the brigade already has a
## pending order this turn, else accept(). add_move_order / add_commit_order return the reject
## verbatim; eligible_commit_brigades filters on `.ok`.
static func pending_order_conflict(state: GameStateData, team: Brigade.Team, brigade_id: String) -> OrderResult:
	for pending_order in state.orders[team]:
		var typed_pending_order: MoveOrder = pending_order
		if typed_pending_order.brigade_id == brigade_id:
			return OrderResult.reject(OrderResult.Code.DUPLICATE_MOVE, "Brigade already has a pending move order this turn: %s" % brigade_id)
	for pending_commitment in state.commitments[team]:
		var typed_pending_commitment: CommitOrder = pending_commitment
		if typed_pending_commitment.brigade_id == brigade_id:
			return OrderResult.reject(OrderResult.Code.DUPLICATE_COMMIT, "Brigade already has a pending commit order this turn: %s" % brigade_id)
	return OrderResult.accept()


static func team_to_string(team: Brigade.Team) -> String:
	match team:
		Brigade.Team.GREEN:
			return "Green"
		_:
			return "Red"
