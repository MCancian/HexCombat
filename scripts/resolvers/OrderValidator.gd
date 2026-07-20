class_name OrderValidator
extends RefCounted

## Static order validation for HexCombat's planning phase (plan 0014 P4). Every public method
## takes `state: GameStateData` as its first argument, reads the GameData content autoload for
## legality checks, and mutates `state.orders` / `state.commitments` in place. Reading GameData is
## allowed (universal read-only content source); this class never takes the GameState autoload
## singleton, which is what makes it unit-testable against a GameStateData built from scratch.
##
## Preserves push_error rejection semantics EXACTLY as GameState carried them pre-refactor —
## changing rejection to a typed Result/enum is plan 0017's job, not this one; the GdUnit tests
## still assert `assert_error().is_push_error(...)`. GameState.gd's add_move_order/add_commit_order/
## eligible_commit_brigades are now one-line delegating wrappers to these.

const MoveOrderResource = preload("res://scripts/model/MoveOrder.gd")
const CommitOrderResource = preload("res://scripts/model/CommitOrder.gd")


static func add_move_order(state: GameStateData, team: Brigade.Team, brigade_id: String, target_hex: String, mode: String) -> void:
	if state.phase != GameStateData.Phase.PLANNING:
		push_error("Cannot add move order outside PLANNING phase")
		return

	var brigade: Brigade = GameData.get_brigade(brigade_id)
	if brigade == null:
		push_error("Move order references unknown brigade_id: %s" % brigade_id)
		return
	if brigade.team != team:
		push_error("Move order team mismatch for %s: order=%s brigade=%s" % [brigade_id, team_to_string(team), team_to_string(brigade.team)])
		return
	if target_hex not in GameData.hex_lookup:
		push_error("Move order references unknown target_hex: %s" % target_hex)
		return
	if mode != Movement.MODE_TACTICAL and mode != Movement.MODE_ADMINISTRATIVE:
		push_error("Unknown movement mode: %s" % mode)
		return

	for pending_order in state.orders[team]:
		var typed_pending_order: MoveOrder = pending_order
		if typed_pending_order.brigade_id == brigade_id:
			push_error("Brigade already has a pending move order this turn: %s" % brigade_id)
			return
	for pending_commitment in state.commitments[team]:
		var typed_pending_commitment: CommitOrder = pending_commitment
		if typed_pending_commitment.brigade_id == brigade_id:
			push_error("Brigade already has a pending commit order this turn: %s" % brigade_id)
			return

	var allowance := Movement.move_allowance(brigade, mode)
	var reachable := GameData.find_reachable(brigade.hex_id, allowance)
	if target_hex not in reachable:
		push_error("Move order target %s beyond %s allowance for %s" % [target_hex, mode, brigade_id])
		return

	var order: MoveOrder = MoveOrderResource.new()
	order.brigade_id = brigade_id
	order.target_hex = target_hex
	order.mode = mode
	state.orders[team].append(order)


static func add_commit_order(state: GameStateData, team: Brigade.Team, brigade_id: String, target_hex: String) -> void:
	if state.phase != GameStateData.Phase.PLANNING:
		push_error("Cannot add commit order outside PLANNING phase")
		return

	var brigade: Brigade = GameData.get_brigade(brigade_id)
	if brigade == null:
		push_error("Commit order references unknown brigade_id: %s" % brigade_id)
		return
	if brigade.team != team:
		push_error("Commit order team mismatch for %s: order=%s brigade=%s" % [brigade_id, team_to_string(team), team_to_string(brigade.team)])
		return
	if brigade.destroyed:
		push_error("Destroyed brigade cannot commit: %s" % brigade_id)
		return
	if brigade.moved_admin_this_turn:
		push_error("Administrative-moved brigade cannot commit: %s" % brigade_id)
		return
	if target_hex not in GameData.hex_lookup:
		push_error("Commit order references unknown target_hex: %s" % target_hex)
		return
	if brigade.hex_id == target_hex:
		push_error("Commit order brigade is already in target hex: %s" % brigade_id)
		return
	if brigade.hex_id not in GameData.get_neighbors(target_hex):
		push_error("Commit order brigade %s is not adjacent to target_hex: %s" % [brigade_id, target_hex])
		return

	for pending_order in state.orders[team]:
		var typed_pending_order: MoveOrder = pending_order
		if typed_pending_order.brigade_id == brigade_id:
			push_error("Brigade already has a pending move order this turn: %s" % brigade_id)
			return
	for pending_commitment in state.commitments[team]:
		var typed_pending_commitment: CommitOrder = pending_commitment
		if typed_pending_commitment.brigade_id == brigade_id:
			push_error("Brigade already has a pending commit order this turn: %s" % brigade_id)
			return

	var order: CommitOrder = CommitOrderResource.new()
	order.brigade_id = brigade_id
	order.target_hex = target_hex
	state.commitments[team].append(order)


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
		if brigade_has_pending_order(state, team, brigade.id):
			continue
		eligible.append(brigade.id)
	return eligible


static func brigade_has_pending_order(state: GameStateData, team: Brigade.Team, brigade_id: String) -> bool:
	for pending_order in state.orders[team]:
		var typed_pending_order: MoveOrder = pending_order
		if typed_pending_order.brigade_id == brigade_id:
			return true
	for pending_commitment in state.commitments[team]:
		var typed_pending_commitment: CommitOrder = pending_commitment
		if typed_pending_commitment.brigade_id == brigade_id:
			return true
	return false


static func team_to_string(team: Brigade.Team) -> String:
	match team:
		Brigade.Team.GREEN:
			return "Green"
		_:
			return "Red"
