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

> **Open design calls so far** (`/DECISIONS.md`): Area 2 — (1) unit strength table differs from TIV on
> 12/17 types (recommend keep HexCombat's); (2) `feba_base_km` 2.0 vs TIV 3.5 (recommend configurable).
> Both await user ratification; not yet actioned.

## Areas

| # | Area | HexCombat | TIV oracle | Doc | Compare | Adjudicated |
|---|---|---|---|:--:|:--:|:--:|
| 1 | Hex grid & geometry | `HexMath`, `MapProjection`, `Hex`, `HexOwner` | `src/core/hex_grid.py` | ✅ | ✅ | ✅ |
| 2 | Ground combat (BOOTS) | `CombatCalculator`, `CombatForces`, `Movement`, `UnitStats`, `Brigade`/`Battalion` | `boots_calculator.py::resolve_map_attack` | ✅ | ✅ | ✅ |
| 3 | Amphibious offload (D1) | `OffloadCalculator`, `OffloadRates`, `ShipLoadingModel`, `BeachDef` | `services/offload*` | ✅ | ✅ | ✅ |
| 4 | Supply (D2 DOS) | `DosConsumption`, `SupplyState` | `services/red_dos_consumption.py` | ✅ | ✅ | ✅ |
| 5 | Anti-ship & mine (D3) | `Antiship*`, `MineWarfareService`, ship/mine models | TIV `antiship_crossing.py` + TaiwanDefenseRefactor `mine_warfare.py` | ✅ | ✅ | ✅ |
| 6 | IJFS (D4) | `scripts/ijfs/*` | `src/ijfs_standalone/*` | ✅ | ✅ | ✅ |
| 7 | Front-line / cleanup / victory (D5) | `FrontLineService`, `VictoryConditions`, `HexOwner` | `services/front_line_service.py`, `cleanup_*` | ✅ | ✅ | ✅ |
| 8 | Turn engine & data | `GameState`, `GameData`, `Dice`, `EventBus`, `Theaters` | `models/game_state.py` | ☐ | ☐ | ☐ |
| 9 | LLM API & self-play | `LLMGameAPI`, `SelfPlay*`, `TurnEventLog` | (HexCombat-original) | ☐ | ☐ | ☐ |
| 10 | View layer | `HexMap`, `GameController`, panels, symbols, `UnitManager` | (HexCombat-original UI) | ☐ | ☐ | ☐ |

## Log
<!-- one line per completed step: area#, step, outcome, commit -->
- Area 1 — documented (`docs/systems/hex-grid.md` + html) and compared. **Finding:** confirmed
  coordinate-system bug — `HexMath` treated offset (odd-r) coords as axial; neighbors matched geography
  23/308 vs odd-r 308/308. **Resolved (user call): FIXED** — odd-r neighbors + offset→cube distance;
  scenario beach-1 green + fixtures + LLM docs updated; golden re-baselined to `casualties=3,
  feba=-0.55`; full gate ALL PHASES GREEN. See `/DECISIONS.md` + `PLAN.md` Decisions (2026-06-29).
- Area 2 — documented (`docs/systems/ground-combat.md` + html) and compared vs
  `boots_calculator.py::resolve_map_attack`. **Core formula is a near-exact port** (clamps, FEBA,
  casualty rules all match). **Findings (2 design calls → `/DECISIONS.md`):** (1) unit strength table
  differs on 12/17 types — HexCombat differentiates, TIV's runtime flattens maneuver units to 1.0 (TIV
  mapping bug); HexCombat ported the intent; (2) `feba_base_km` 2.0 vs TIV 3.5. Minor notes (in the
  doc): RNG algorithm differs (numpy vs Dice → self-consistent only); `combat_detail` key shape. No
  code changed — both findings await user ratification.
- Area 3 — documented (`docs/systems/amphibious-offload.md` + html) and compared vs
  `offload_calculator.py` / `beach_throughput.py`. **✅ Faithful port** — verified `TONS_PER_BN=2200`,
  the pier/barge throughput formula, and the maneuver-BN whitelist all match TIV exactly; day-1
  redesign mirrored by 54 GdUnit tests. Only minor intentional `ShipLoadingModel` simplifications
  (per-type transport weight; amphibious-vs-cargo ship eligibility) diverge — already code-documented.
  No DECISIONS, no code change.
- Area 4 — documented (`docs/systems/supply-dos.md` + html) and compared vs `red_dos_consumption.py`.
  **✅ Faithful port** — constants (300/150/150), activity formula, mechanized hints, and the
  consumption-summary/net-delta (conservative ceil) all match TIV exactly. **One port gap (→
  `port_audit.md`):** `supply_effectiveness` is computed but fed to combat as a hardcoded 1.0
  (`CombatForces.gd:20`), so supply has no combat effect yet (TIV injects real values). No code change.
  NB: opencode agents default to the WRONG TIV path (outer dir) — pass the nested
  `…/TaiwanInvasionViewer/TaiwanInvasionViewer/…` path explicitly.
- Area 5 — documented (`docs/systems/antiship-mine.md` + html) and compared. **✅ Faithful ports from
  TWO source repos:** missile crossing/firing-plan/launch-attrition/magazine port TIV `antiship_*.py`
  stage-for-stage (verified); the geometric **mine model ports `TaiwanDefenseRefactor/mine_warfare.py`**
  (verified functions exist), NOT TIV's own sweep-based mine service — a deliberate cross-repo choice.
  Corrected the agent's draft (it had been mis-told the mine model was HexCombat-original). No new
  DECISIONS — count-based-vs-per-hull, per-category neutralization, magazine persistence already logged.
- Area 6 — documented (`docs/systems/ijfs.md` + html) and compared vs `src/ijfs_standalone/*`.
  **✅ Faithful port** — 10/11 stages are 1:1 (detection, targeting, engagement, strike Pk+resolution,
  firing capacity, AD health, warmup, loaders, daily state, run context); orchestrator independently
  confirmed pipeline order + strike-probability model. One adaptation (anti-ship targets from
  pre-built containers vs SQLite default_targets). **Port gap (→ `port_audit.md`):** ground
  (`maneuver_casualties`) writeback is computed but (a) empty at runtime — IJFS targets lack OOB
  battalion IDs — and (b) not consumed; IJFS air/missile kills don't reduce ground brigades. Anti-ship
  half IS wired. No new DECISIONS.
- Area 7 — documented (`docs/systems/frontline-cleanup-victory.md` + html) and compared. **✅ Front-line
  & cleanup are faithful ports** (polyline→hex 2km sampling, arc-length interpolation, ownership
  recompute all match `front_line_service.py`/`cleanup_hex_service.py`, verified). **Victory is
  HexCombat-original** (no TIV BOOTS equivalent; settled 2026-06-28). REFINE (→ `port_audit.md`):
  front-line distribution is brigade-level vs TIV battalion-level + per-hex clipping; tied to the
  deferred draw UI (Track 5). taiwan_hexes=null census caveat is known. No new DECISIONS.
