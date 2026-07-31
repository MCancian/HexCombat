# Supply / DOS — Status

**D2 Red DOS Supply System (`SupplyBill`, `SupplyState`, `SupplyTransitions`, `TurnClosure`)**:
- **Supply Pool (DOS)**: Red forces consume Day-of-Supply (DOS) rations from a global pool (`red_dos_start`, default 100 in default scenario).
- **Consumption Rate**: Landed PLA battalions consume supply each turn based on unit activity (movement, combat commitment).
- **Out-of-Supply Penalty**: When the Red DOS supply pool is exhausted (≤ 0), Red ground combat effectiveness is degraded by `red_out_of_supply_effectiveness` (default 0.5, configurable per scenario).
- **Resolver & Phase Integration**: `TurnClosure.resolve_supply_turn` bills the day through `SupplyBill.for_turn` (write-free) and applies it through `SupplyTransitions.apply_daily_bill`, the supply aggregate's authority (plan 0049). The supply effectiveness multiplier is injected into combat resolution via `CombatResolver.inject_supply_effectiveness`, threaded by `TurnConductor`.
- **Landed Battalions Only (Plan 0037)**: Supply consumption counts only battalions actually landed ashore (`Brigade.landed_qty`), matching the ground combat fighting strength bill.
