class_name MapTransitions
extends RefCounted

## THE mutation authority for the `map` aggregate (plan 0047) — the exact and only production writer
## of `HexState.hex_owner`, `HexState.feba_km`, and the `GameDataStore.hex_states` container. Living
## in scripts/transitions/ grants nothing by itself: authority is granted to this exact file by name
## in tools/mutation_authority_manifest.json, which is also the only home for the field and writer
## lists. Do not copy them here.
##
## Hex DEFINITIONS, geometry and terrain are immutable content owned by `GameData`; only `HexState` is
## runtime state, and only it is claimed here. This authority does not move brigades — it READS the
## placement index the force authority owns, to derive who holds what.
##
## **There is deliberately no `set_owner`.** Ownership is DERIVED from occupancy, never asserted: the
## invariant is enforced by there being no way to express a violation, the same technique
## `IjfsTransitions` uses to make destruction monotonic. The only caller that ever wanted such a setter
## was a scripted validator, now driven through real domain operations instead. That also disposes of
## a question this plan could not answer: whether such a setter should start validating its owner
## string. Today's `GameData.set_hex_owner` silently accepted anything, so tightening it would have
## been a behaviour change; deleting it makes the question moot rather than deciding it quietly.
##
## The aggregate ships with **zero allowances** — construction of `hex_states` routes through here too.
## That is stricter than the `infrastructure` aggregate next door, deliberately: infrastructure
## construction fills a local, unpublished object, whereas hex construction writes straight into a
## globally reachable autoload container.


# ── Grid lifecycle ──────────────────────────────────────────────────────────────────────────────

## Empty the runtime hex state. Kept SEPARATE from initialize_hex_states on purpose: `load_hex_grid`
## clears BEFORE it reads the grid JSON and returns early on a parse failure, so a failed load leaves
## the map empty. Initialising only after a successful parse would let a repeated failed load silently
## retain the previous map.
static func clear_hex_states(data_store: GameDataStore) -> void:
	data_store.hex_states.clear()


## Give every parsed hex a default state, in the order the ids arrive (the grid's own order).
static func initialize_hex_states(data_store: GameDataStore, hex_ids: Array) -> void:
	for hex_id_value in hex_ids:
		data_store.hex_states[String(hex_id_value)] = HexState.new()


## Restore every hex to the HexState defaults (GREEN owner, feba 0) WITHOUT re-parsing the grid JSON.
## Combat and the frontline mutate HexState in place across a play-through, so a scenario reset that
## skips this leaks run 1's ownership/FEBA map into run 2 — measured 2026-07-09, when an in-process
## replay of the 40-turn golden diverged 24/88 -> 25/90 on the second run.
static func reset_hex_states(data_store: GameDataStore) -> void:
	for hex_id_value in data_store.hex_states.keys():
		data_store.hex_states[hex_id_value] = HexState.new()


# ── Ownership ───────────────────────────────────────────────────────────────────────────────────

## Recompute ownership from who is standing where.
##
## INVARIANT: a hex emptied of brigades KEEPS its last owner. That is expressed here as ITERATING the
## occupied hexes the calculator returned — never as looking every hex up in the result with a default
## — because omission is only equivalent to the old missing `else` branch if omitted hexes are never
## visited. It is load-bearing for plan 0006: infrastructure seizure persists after Red moves inland.
##
## The iteration source stays `hex_lookup` rather than the placement index, exactly as before. Walking
## `brigades_by_hex` would be faster but would change what happens when the index holds a hex
## `hex_states` does not, and this plan does not buy behaviour changes with performance.
static func recompute_ownership(data_store: GameDataStore) -> void:
	var occupancy := HexOwnershipCalculator.occupancy_from_placements(
		data_store, data_store.hex_lookup.keys())
	var owners := HexOwnershipCalculator.owners_from_occupancy(occupancy)
	for hex_id_value in owners.keys():
		var hex_state := _hex_state(data_store, String(hex_id_value), "recompute_ownership")
		if hex_state == null:
			continue
		hex_state.hex_owner = String(owners[hex_id_value])


# ── FEBA ────────────────────────────────────────────────────────────────────────────────────────

## Move the front line in one hex by `delta_km` (Red-positive), accumulating on what is already there.
static func apply_feba_delta(data_store: GameDataStore, hex_id: String, delta_km: float) -> void:
	var hex_state := _hex_state(data_store, hex_id, "apply_feba_delta")
	if hex_state == null:
		return
	hex_state.feba_km = hex_state.feba_km + delta_km


## Reset one hex's front line to zero — what a retreat does to the ground it gave up.
static func clear_feba(data_store: GameDataStore, hex_id: String) -> void:
	var hex_state := _hex_state(data_store, hex_id, "clear_feba")
	if hex_state == null:
		return
	hex_state.feba_km = 0.0


# ── Internals ───────────────────────────────────────────────────────────────────────────────────

## Resolve one hex's runtime state, reporting rather than crashing when it is absent. Unreachable on
## every path that exists today — `hex_states` is populated from the same loop as `hex_lookup` and
## nothing removes a key — so this guard exists to fail loudly if a future change breaks that pairing.
static func _hex_state(data_store: GameDataStore, hex_id: String, operation: String) -> HexState:
	var state_value: Variant = data_store.hex_states.get(hex_id)
	if not (state_value is HexState):
		push_error("MapTransitions.%s: no HexState for hex '%s'" % [operation, hex_id])
		return null
	return state_value
