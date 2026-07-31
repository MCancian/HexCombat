class_name SupplyTransitions
extends RefCounted

## THE mutation authority for the `supply` aggregate (plan 0049). Living in scripts/transitions/
## grants nothing by itself: authority is granted to this exact file by name in
## tools/mutation_authority_manifest.json, the only home for the protected-field and writer lists.
##
## The aggregate is small and entirely about one number: `SupplyState.current_dos_tons` is the Red
## theater pool, and `day_history` is its append-only audit ledger. `SupplyBill` (scripts/calc/)
## decides who eats and how much; this file is the only thing that spends the pool.
##
## **The balance is DERIVED, never accepted.** `apply_daily_bill` takes the consumption row and works
## out the new pool itself. That is not defensive style, it is what makes the ledger's central
## property — every row starts at the previous row's close, and the last row agrees with the
## authoritative balance — true by CONSTRUCTION rather than by a guard someone can argue with. There
## is deliberately no way to hand this authority a `pool_after`, so a row that disagrees with the
## balance is unexpressible, and no second running total exists to drift (procedure doc §6).
##
## By the same technique there is no `set_pool` and no way to append a row without applying it: the
## only expressible operations are a scenario reset and a billed day, so the pool cannot rise during
## a campaign.


## The one key this authority READS off a consumption row, and the two it STAMPS onto the ledger row.
const CONSUMED_KEY := "red_dos_consumed_tons"
const POOL_BEFORE_KEY := "pool_before"
const POOL_AFTER_KEY := "pool_after"


# ── Aggregate lifecycle ─────────────────────────────────────────────────────────────────────────

## Replace the supply state with a fresh pool from the (possibly changed) scenario's starting DOS.
## This is a scenario RESET of live state, not construction of unpublished state, which is why it
## routes through the authority instead of GameState assigning the builder's result itself — the same
## division `InfrastructureTransitions.rebuild_infrastructure` and
## `AirInsertionTransitions.rebuild_air_insertion_state` draw. `SupplyStateBuilder` still fills the
## FRESH object and keeps its construction allowance.
static func rebuild_supply_state(state: GameStateData, red_dos_start: float) -> void:
	state.supply_state = SupplyStateBuilder.build(red_dos_start)


# ── The day's DOS bill ──────────────────────────────────────────────────────────────────────────

## Spend one day's consumption against the pool and append the audit row.
##
## `consumption` is the row `SupplyBill`/`DosConsumption` produced; its `red_dos_consumed_tons` is the
## ONLY input that moves the balance. The three keys stamped below are appended in this exact order
## (`applied`, `pool_before`, `pool_after`) because the row is serialized straight into `day_history`
## and `EventBus.supply_updated`, so its insertion order is a public shape.
##
## The ledger row is a COPY, and so is the return value. `consumption` is a Dictionary the caller
## still holds, so stamping and appending it directly would leave the caller aliasing a committed
## history row: reusing one row object for a second bill would rewrite the first, and mutating the
## returned report afterwards would silently rewrite history. Neither is reachable from today's one
## caller, but "a row that disagrees with the balance is unexpressible" is the whole claim of this
## authority, and it is not true of a row anyone else can still write to. Copying in and out costs
## one duplicate per game-day and makes the claim hold literally. (Found in diff review.)
##
## Returns the completed row, or an empty Dictionary if the bill was refused — the caller must not
## treat an empty return as a billed day.
static func apply_daily_bill(supply_state: SupplyState, consumption: Dictionary) -> Dictionary:
	if supply_state == null:
		push_error("SupplyTransitions.apply_daily_bill: no supply state")
		return {}
	if not consumption.has(CONSUMED_KEY):
		push_error("SupplyTransitions.apply_daily_bill: row has no '%s'" % CONSUMED_KEY)
		return {}
	# The three stamped keys are this authority's to write. A row that already carries a balance was
	# not produced by DosConsumption, and accepting it would both defeat the derive-don't-accept rule
	# and leave the stamped keys in the wrong serialized position (reassignment does not move an
	# existing key). `applied` is deliberately NOT checked: DosConsumption emits it as its FIRST key,
	# set to false, and flipping it in place is what keeps the row's key order byte-stable.
	for stamped_key in [POOL_BEFORE_KEY, POOL_AFTER_KEY]:
		if consumption.has(stamped_key):
			push_error("SupplyTransitions.apply_daily_bill: row already carries '%s'" % stamped_key)
			return {}

	var consumed := float(consumption[CONSUMED_KEY])
	if not is_finite(consumed) or consumed < 0.0:
		push_error("SupplyTransitions.apply_daily_bill: invalid consumption %f" % consumed)
		return {}

	var pool_before := supply_state.current_dos_tons
	supply_state.current_dos_tons = maxf(0.0, pool_before - consumed)

	var row := consumption.duplicate(true)
	row["applied"] = true
	row[POOL_BEFORE_KEY] = pool_before
	row[POOL_AFTER_KEY] = supply_state.current_dos_tons
	# Combat-effectiveness injection from supply exhaustion happens at the combat call site
	# (CombatResolver.inject_supply_effectiveness via TurnConductor), not here.
	supply_state.day_history.append(row)
	return row.duplicate(true)
