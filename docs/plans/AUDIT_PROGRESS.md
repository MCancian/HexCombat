# Port-fidelity audit — orchestration tracker

Systematic, area-by-area audit of the HexCombat port against **TaiwanInvasionViewer** (TIV,
`C:\Users\mdogg\TaiwanInvasionViewer\TaiwanInvasionViewer`). Goal: every system is (1) documented
for machines (`docs/systems/<area>.md`, indexed from `AGENTS.md`), (2) documented for humans
(`docs/systems/html/<area>.html`), and (3) compared to its TIV oracle, with discrepancies either
fixed (obvious) or flagged in `/DECISIONS.md` (design calls).

## Per-area loop
1. **Document (opencode):** read HexCombat code → write `docs/systems/<area>.md` + `.../html/<area>.html`.
2. **Compare (opencode, read-only against TIV):** diff behavior vs. the TIV oracle → discrepancy list.
3. **Adjudicate (orchestrator):** independently verify against real source → fix obvious gaps, or
   add a `/DECISIONS.md` entry. Update STATUS/port_audit as needed. Commit.

## Areas

| # | Area | HexCombat | TIV oracle | Doc | Compare | Adjudicated |
|---|---|---|---|:--:|:--:|:--:|
| 1 | Hex grid & geometry | `HexMath`, `MapProjection`, `Hex`, `HexOwner` | `src/core/hex_grid.py` | ☐ | ☐ | ☐ |
| 2 | Ground combat (BOOTS) | `CombatCalculator`, `CombatForces`, `Movement`, `UnitStats`, `Brigade`/`Battalion` | `contracts/boots.py` + combat services | ☐ | ☐ | ☐ |
| 3 | Amphibious offload (D1) | `OffloadCalculator`, `OffloadRates`, `ShipLoadingModel`, `BeachDef` | `services/offload*` | ☐ | ☐ | ☐ |
| 4 | Supply (D2 DOS) | `DosConsumption`, `SupplyState` | `services/red_dos_*` | ☐ | ☐ | ☐ |
| 5 | Anti-ship & mine (D3) | `Antiship*`, `MineWarfareService`, ship/mine models | `services/antiship*`, `antiship/mine_warfare_service.py` | ☐ | ☐ | ☐ |
| 6 | IJFS (D4) | `scripts/ijfs/*` | `src/ijfs_standalone/*` | ☐ | ☐ | ☐ |
| 7 | Front-line / cleanup / victory (D5) | `FrontLineService`, `VictoryConditions`, `HexOwner` | `services/front_line_service.py`, `cleanup_*` | ☐ | ☐ | ☐ |
| 8 | Turn engine & data | `GameState`, `GameData`, `Dice`, `EventBus`, `Theaters` | `models/game_state.py` | ☐ | ☐ | ☐ |
| 9 | LLM API & self-play | `LLMGameAPI`, `SelfPlay*`, `TurnEventLog` | (HexCombat-original) | ☐ | ☐ | ☐ |
| 10 | View layer | `HexMap`, `GameController`, panels, symbols, `UnitManager` | (HexCombat-original UI) | ☐ | ☐ | ☐ |

## Log
<!-- one line per completed step: area#, step, outcome, commit -->
