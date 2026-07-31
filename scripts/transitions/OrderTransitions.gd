class_name OrderTransitions
extends RefCounted

## THE mutation authority for the `order_buffers` aggregate (plan 0049). Living in
## scripts/transitions/ grants nothing by itself: authority is granted to this exact file by name in
## tools/mutation_authority_manifest.json, the only home for the protected-field and writer lists.
##
## Four request queues players fill during planning and the turn drains during resolution:
## `orders` (move), `commitments`, `air_insert_orders`, `jlsf_orders`. They belong together because
## the questions worth asking are about the SET — is anything accepted outside planning, does anything
## survive begin-next-turn — and an answer split across four files is not an answer.
##
## **This file is the only door.** Legality lives in `OrderValidator` (scripts/calc/), which appends
## nothing; every method here asks it first and appends only on accept, so a rejection cannot
## half-apply. The content store is PASSED IN and handed on, because an authority may not read a
## content autoload — not even through a calculator it calls.
##
## `apply_bulk_order` exists so the bulk/scripted path and the per-order path cannot drift: both the
## LLM action boundary and `GameState.play_turn` reach the same four methods through it. The external
## action `type` vocabulary and the internal order `kind` stay separate boundaries; this is where they
## meet.


## Per-turn clearing is split from scenario clearing deliberately. `clear_turn_buffers` empties only
## what a NEW TURN invalidates — the two ground-maneuver queues. `air_insert_orders` and `jlsf_orders`
## are consumed mid-resolution by the phases that read them, so a turn boundary finds them already
## empty; clearing them again here would hide a phase that had stopped consuming its queue.
static func clear_turn_buffers(state: GameStateData) -> void:
	for team in [Brigade.Team.RED, Brigade.Team.GREEN]:
		if state.orders.has(team):
			state.orders[team].clear()
		if state.commitments.has(team):
			state.commitments[team].clear()


## Scenario reset: every queue back to its empty shape, including the two per-team dictionaries whose
## KEYS the rest of the code assumes exist.
static func reset_buffers(state: GameStateData) -> void:
	state.orders = {
		Brigade.Team.RED: [],
		Brigade.Team.GREEN: [],
	}
	state.commitments = {
		Brigade.Team.RED: [],
		Brigade.Team.GREEN: [],
	}
	state.air_insert_orders = []
	state.jlsf_orders.clear()


# ── Order entry ─────────────────────────────────────────────────────────────────────────────────

## Factories for the two order resources, hosted here so a caller names ONE class to place an order
## rather than two — `MoveOrder`/`CommitOrder` reached only through a declared return type cost no
## dependency, which is what keeps `GameState` at its ceiling. Same reason `ForceTransitions` carries
## `ground_combat_casualty_request`.
static func move_order(brigade_id: String, target_hex: String, mode: String) -> MoveOrder:
	return OrderValidator.move_order(brigade_id, target_hex, mode)


static func commit_order(brigade_id: String, target_hex: String) -> CommitOrder:
	return OrderValidator.commit_order(brigade_id, target_hex)


static func add_move_order(
	state: GameStateData, store: GameDataStore, team: Brigade.Team, order: MoveOrder
) -> OrderResult:
	var verdict := OrderValidator.check_move_order(state, store, team, order)
	if not verdict.ok:
		return verdict
	state.orders[team].append(order)
	return verdict


static func add_commit_order(
	state: GameStateData, store: GameDataStore, team: Brigade.Team, order: CommitOrder
) -> OrderResult:
	var verdict := OrderValidator.check_commit_order(state, store, team, order)
	if not verdict.ok:
		return verdict
	state.commitments[team].append(order)
	return verdict


static func add_air_insert_order(
	state: GameStateData, store: GameDataStore, team: Brigade.Team, brigade_id: String, target_hex: String
) -> OrderResult:
	var verdict := OrderValidator.check_air_insert_order(state, store, team, brigade_id, target_hex)
	if not verdict.ok:
		return verdict
	state.air_insert_orders.append({"brigade_id": brigade_id, "target_hex": target_hex})
	return verdict


static func add_jlsf_order(
	state: GameStateData, store: GameDataStore, team: Brigade.Team, port_id: String
) -> OrderResult:
	var verdict := OrderValidator.check_jlsf_order(state, store, team, port_id)
	if not verdict.ok:
		return verdict
	state.jlsf_orders.append(port_id)
	return verdict


## Apply one order from a bulk spec ({kind, …}) — the scripted/LLM path. Unknown kinds are a caller
## error and rejected rather than silently dropped.
static func apply_bulk_order(
	state: GameStateData, store: GameDataStore, order: Dictionary, team: Brigade.Team
) -> OrderResult:
	var kind := String(order.get("kind", "move"))
	match kind:
		"move":
			return add_move_order(state, store, team, move_order(
				String(order["brigade_id"]), String(order["target_hex"]),
				String(order.get("mode", Movement.MODE_TACTICAL))))
		"commit":
			return add_commit_order(state, store, team, commit_order(
				String(order["brigade_id"]), String(order["target_hex"])))
		"deploy_jlsf":
			return add_jlsf_order(state, store, team, String(order.get("port_id", "")))
		"air_insert":
			return add_air_insert_order(
				state, store, team, String(order["brigade_id"]), String(order["target_hex"]))
	push_error("Unknown order kind: %s" % kind)
	return OrderResult.reject(OrderResult.Code.UNKNOWN_ORDER_KIND, "Unknown order kind: %s" % kind)


# ── Consumption by the phases that read a queue ─────────────────────────────────────────────────

## Both queues below are emptied by the phase that has just acted on them, mid-resolution, so the
## turn's events can still be built from what was ordered. Neither is a `clear_turn_buffers` job.

static func consume_air_insert_orders(state: GameStateData) -> void:
	state.air_insert_orders = []


static func consume_jlsf_orders(state: GameStateData) -> void:
	state.jlsf_orders.clear()


# ── Queries ─────────────────────────────────────────────────────────────────────────────────────
# Pure pass-throughs to the calculator. They live on the authority so a coordinator naming the order
# aggregate names ONE class, not two; they mutate nothing.

static func eligible_commit_brigades(
	state: GameStateData, store: GameDataStore, team: Brigade.Team, target_hex: String
) -> Array:
	return OrderValidator.eligible_commit_brigades(state, store, team, target_hex)


static func eligible_air_insert_brigades(state: GameStateData, store: GameDataStore) -> Array:
	return OrderValidator.eligible_air_insert_brigades(state, store)
