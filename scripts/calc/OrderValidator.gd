class_name OrderValidator
extends RefCounted

## Pure order legality for HexCombat's planning phase (plan 0014 P4; made pure and moved to
## scripts/calc/ by plan 0049). Every method answers "would this order be legal?" and NOTHING else —
## it appends to no buffer and holds no state. `OrderTransitions` is the only writer; it asks these
## questions and appends on accept, which is why a rejection cannot half-apply.
##
## The content store arrives as an ARGUMENT (`store: GameDataStore`), never as the `GameData`
## autoload. That is not style: `OrderTransitions` calls into here, and an authority that read an
## autoload — even transitively — would breach the house rule. Passing the store also makes every
## check testable against a store built from scratch.
##
## Rejections return a typed OrderResult (plan 0017): `OrderResult.reject(code, message)` on failure,
## `OrderResult.accept()` on success. Callers branch on `result.ok` and surface `result.code` /
## `result.message` (the LLM API feeds the message back to the agent). `eligible_commit_brigades`
## keeps its lone push_error — that guard is a programmer error (query fed a bad hex), not order
## validation.

const MoveOrderResource = preload("res://scripts/model/MoveOrder.gd")
const CommitOrderResource = preload("res://scripts/model/CommitOrder.gd")


## Build the MoveOrder an accepted request becomes. It is constructed here, with the rules that
## police it, and stays a local until the authority appends it.
static func move_order(brigade_id: String, target_hex: String, mode: String) -> MoveOrder:
	var order: MoveOrder = MoveOrderResource.new()
	order.brigade_id = brigade_id
	order.target_hex = target_hex
	order.mode = mode
	return order


static func commit_order(brigade_id: String, target_hex: String) -> CommitOrder:
	var order: CommitOrder = CommitOrderResource.new()
	order.brigade_id = brigade_id
	order.target_hex = target_hex
	return order


static func check_move_order(
	state: GameStateData, store: GameDataStore, team: Brigade.Team, order: MoveOrder
) -> OrderResult:
	if state.phase != GameStateData.Phase.PLANNING:
		return OrderResult.reject(OrderResult.Code.WRONG_PHASE, "Cannot add move order outside PLANNING phase")

	var brigade: Brigade = store.get_brigade(order.brigade_id)
	if brigade == null:
		return OrderResult.reject(OrderResult.Code.UNKNOWN_BRIGADE, "Move order references unknown brigade_id: %s" % order.brigade_id)
	if brigade.team != team:
		return OrderResult.reject(OrderResult.Code.TEAM_MISMATCH, "Move order team mismatch for %s: order=%s brigade=%s" % [order.brigade_id, Brigade.team_name(team), Brigade.team_name(brigade.team)])
	if order.target_hex not in store.hex_lookup:
		return OrderResult.reject(OrderResult.Code.UNKNOWN_HEX, "Move order references unknown target_hex: %s" % order.target_hex)
	if order.mode != Movement.MODE_TACTICAL and order.mode != Movement.MODE_ADMINISTRATIVE:
		return OrderResult.reject(OrderResult.Code.UNKNOWN_MODE, "Unknown movement mode: %s" % order.mode)

	var conflict := pending_order_conflict(state, team, order.brigade_id)
	if not conflict.ok:
		return conflict

	var allowance := Movement.move_allowance(brigade, order.mode)
	var reachable := store.find_reachable(brigade.hex_id, allowance)
	if order.target_hex not in reachable:
		return OrderResult.reject(OrderResult.Code.BEYOND_ALLOWANCE, "Move order target %s beyond %s allowance for %s" % [order.target_hex, order.mode, order.brigade_id])
	return OrderResult.accept()


static func check_commit_order(
	state: GameStateData, store: GameDataStore, team: Brigade.Team, order: CommitOrder
) -> OrderResult:
	if state.phase != GameStateData.Phase.PLANNING:
		return OrderResult.reject(OrderResult.Code.WRONG_PHASE, "Cannot add commit order outside PLANNING phase")

	var brigade: Brigade = store.get_brigade(order.brigade_id)
	if brigade == null:
		return OrderResult.reject(OrderResult.Code.UNKNOWN_BRIGADE, "Commit order references unknown brigade_id: %s" % order.brigade_id)
	if brigade.team != team:
		return OrderResult.reject(OrderResult.Code.TEAM_MISMATCH, "Commit order team mismatch for %s: order=%s brigade=%s" % [order.brigade_id, Brigade.team_name(team), Brigade.team_name(brigade.team)])
	if brigade.destroyed:
		return OrderResult.reject(OrderResult.Code.DESTROYED, "Destroyed brigade cannot commit: %s" % order.brigade_id)
	if brigade.moved_admin_this_turn:
		return OrderResult.reject(OrderResult.Code.ADMIN_MOVED, "Administrative-moved brigade cannot commit: %s" % order.brigade_id)
	if order.target_hex not in store.hex_lookup:
		return OrderResult.reject(OrderResult.Code.UNKNOWN_HEX, "Commit order references unknown target_hex: %s" % order.target_hex)
	if brigade.hex_id == order.target_hex:
		return OrderResult.reject(OrderResult.Code.ALREADY_IN_HEX, "Commit order brigade is already in target hex: %s" % order.brigade_id)
	if brigade.hex_id not in store.get_neighbors(order.target_hex):
		return OrderResult.reject(OrderResult.Code.NOT_ADJACENT, "Commit order brigade %s is not adjacent to target_hex: %s" % [order.brigade_id, order.target_hex])

	return pending_order_conflict(state, team, order.brigade_id)


## Order one brigade of the PLAAF air corps to fly onto a hex this turn (plan 0032). Red-only.
##
## Unlike a move order there is no allowance or adjacency check — the whole point of the mechanic is
## that lift reaches anywhere, including hexes the enemy holds (a drop onto Green ground is paid for
## by the ground combat that follows in the same turn). What IS checked: the brigade actually flies,
## it still has battalions waiting, the hex exists and is passable, and — once the brigade has put
## its first packet down — that follow-up packets reinforce it where it stands, because a formation
## occupies one hex.
##
## How MUCH flies is not decided here: the per-class lift budget is spent at resolution, in order
## issue order, and an order that finds the budget already gone is reported in the phase summary
## rather than rejected now (the budget can be eroded by losses between planning and resolution).
static func check_air_insert_order(
	state: GameStateData, store: GameDataStore, team: Brigade.Team, brigade_id: String, target_hex: String
) -> OrderResult:
	if state.phase != GameStateData.Phase.PLANNING:
		return OrderResult.reject(OrderResult.Code.WRONG_PHASE, "Cannot add air insert order outside PLANNING phase")
	if team != Brigade.Team.RED:
		return OrderResult.reject(OrderResult.Code.TEAM_MISMATCH, "air_insert is a Red order")

	var brigade: Brigade = store.get_brigade(brigade_id)
	if brigade == null:
		return OrderResult.reject(OrderResult.Code.UNKNOWN_BRIGADE, "Air insert order references unknown brigade_id: %s" % brigade_id)
	if brigade.destroyed:
		return OrderResult.reject(OrderResult.Code.DESTROYED, "Destroyed brigade cannot be inserted: %s" % brigade_id)
	if not LiftClass.is_air_lifted(brigade):
		return OrderResult.reject(OrderResult.Code.NOT_AIR_LIFTED, "Brigade is not air-lifted: %s" % brigade_id)
	if target_hex not in store.hex_lookup:
		return OrderResult.reject(OrderResult.Code.UNKNOWN_HEX, "Air insert order references unknown target_hex: %s" % target_hex)

	var terrain: TerrainType = store.get_terrain(target_hex)
	if terrain == null or terrain.impassable:
		return OrderResult.reject(OrderResult.Code.IMPASSABLE_HEX, "Air insert target hex is impassable: %s" % target_hex)

	var air_state: AirInsertionState = state.air_insertion_state
	if air_state == null or air_state.entry_for(brigade_id).is_empty():
		return OrderResult.reject(OrderResult.Code.NO_LIFT_REMAINING, "Brigade has no battalions waiting to fly: %s" % brigade_id)
	if brigade.hex_id != "" and brigade.hex_id != target_hex:
		return OrderResult.reject(OrderResult.Code.BRIGADE_ALREADY_LANDED, "Brigade %s is already on %s; follow-up battalions must reinforce it there, not %s" % [brigade_id, brigade.hex_id, target_hex])

	for pending_value in state.air_insert_orders:
		var pending: Dictionary = pending_value
		if String(pending["brigade_id"]) == brigade_id:
			return OrderResult.reject(OrderResult.Code.DUPLICATE_AIR_INSERT, "Brigade already has a pending air insert order this turn: %s" % brigade_id)
	return OrderResult.accept()


## Deploy a JLSF package through a port/airbridge (plan 0006). Until plan 0049 this order had NO
## validation API at all — `GameState._apply_order` appended the raw port id — so it was the one order
## accepted outside PLANNING and with an id naming nothing. Both are checked here now.
##
## A DUPLICATE port id is deliberately still legal, but only to PRESERVE EXISTING BEHAVIOUR — the old
## bulk dispatcher appended anything, and rejecting a duplicate would be a behaviour change this plan
## is not entitled to make. It is NOT load-bearing: diff review disproved the first draft's claim that
## it was. `JlsfCargo.queue_deployments` calls `InfrastructureTransitions.queue_jlsf` per occurrence,
## and the second call returns false because the marker is already set, so two buffered orders emit
## exactly ONE pool entry — the same result one buffered order would give. Whether duplicates SHOULD
## be rejected is an open design question for the USER, not a mechanic that depends on them.
static func check_jlsf_order(
	state: GameStateData, store: GameDataStore, team: Brigade.Team, port_id: String
) -> OrderResult:
	if state.phase != GameStateData.Phase.PLANNING:
		return OrderResult.reject(OrderResult.Code.WRONG_PHASE, "Cannot add deploy_jlsf order outside PLANNING phase")
	if team != Brigade.Team.RED:
		return OrderResult.reject(OrderResult.Code.TEAM_MISMATCH, "deploy_jlsf is a Red order")
	if not store.infrastructure.has(port_id):
		return OrderResult.reject(OrderResult.Code.UNKNOWN_INFRASTRUCTURE, "unknown infrastructure id '%s'" % port_id)
	return OrderResult.accept()


## Brigades that could legally receive an air_insert order right now. Mirrors
## eligible_commit_brigades' role for the LLM contract; the logic itself lives on AirInsertionState
## so the observation can build the same list without reaching the GameData singleton.
static func eligible_air_insert_brigades(state: GameStateData, store: GameDataStore) -> Array:
	if state.air_insertion_state == null:
		return []
	return state.air_insertion_state.eligible_orders(store.brigades, state.air_insert_orders)


static func eligible_commit_brigades(
	state: GameStateData, store: GameDataStore, team: Brigade.Team, target_hex: String
) -> Array:
	if target_hex not in store.hex_lookup:
		push_error("Commit eligibility requested for unknown target_hex: %s" % target_hex)
		return []

	var eligible: Array = []
	for brigade_value in store.brigades.values():
		var brigade: Brigade = brigade_value
		if brigade.team != team or brigade.destroyed or brigade.moved_admin_this_turn:
			continue
		if brigade.hex_id == target_hex:
			continue
		if brigade.hex_id not in store.get_neighbors(target_hex):
			continue
		if not pending_order_conflict(state, team, brigade.id).ok:
			continue
		eligible.append(brigade.id)
	return eligible


## Single home for the "one order per brigade per turn" rule. Returns a rejecting OrderResult
## (DUPLICATE_MOVE / DUPLICATE_COMMIT, message centralized here) when the brigade already has a
## pending order this turn, else accept(). check_move_order / check_commit_order return the reject
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
