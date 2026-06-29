# Port-leftover audit (Track 2)

What remains unported from the two source repos, each tagged **PORT** (worth doing), **ADAPT**
(needs a HexCombat subsystem first), **REFINE** (low-priority polish), or **SKIP** (intentionally not
ported — source-specific). Sources: TIV (BOOTS oracle; `ROADMAP.md` §D for refs) and
`TaiwanDefenseRefactor` (Python wargame; missile map in `docs/antiship_missile_pipeline_ref.md`).

## Candidate features

| Item | Tag | Notes |
|---|---|---|
| **Victory conditions** | PORT | Designed (`PLAN.md` → Victory conditions); being implemented in **Track 3a**. |
| **Anti-ship missile pipeline depth** (launches→allocate→leakers→missile_damage→second_attack) | ADAPT | The strike-coverage calibration lever (memory `antiship-strike-coverage-lever`). HexCombat's crossing is a count-based port; the per-missile/per-hull pipeline + JFPS pre-launch attrition is the upstream throughput model. Big; tie to a balance need, not speculative. Map: `docs/antiship_missile_pipeline_ref.md`. |
| **Ground-casualty IJFS↔OOB linkage** | ADAPT | Open half of the D4-H writeback — `maneuver_casualties` is empty; needs an ID bridge between IJFS maneuver targets and the PLA/ROC OOB. Design settled 2026-06-28 (Option B + detectability); needs `moved_last_turn`/`fought_last_turn` on `Brigade`. |
| **Per-hull escort magazines** (crossing interception/terminal defense deplete `hq10`/`hhq9`) | ADAPT | D3-B3 open question; needs a ship ammo/readiness subsystem HexCombat lacks. Count-based port matches all source pytests today. |
| **Per-ship-type mine neutralization likelihood** | REFINE | Current model uses a per-category table; source data varies within a category (LHD/LPD "Low" vs LST "High"). A `ShipDef` field would be more faithful. (RETROSPECTIVES 2026-06-29.) |
| **Flotilla composition nuances** (`create_flotillas.py`) | REFINE | HexCombat builds a sent fleet by capacity/screen; the source groups ships into flotillas with per-flotilla mine-encounter rolls. Only relevant if the missile pipeline is ported (flotillas are its unit of allocation). |
| **Terrain** | ADAPT | Deferred by design — TIV has no terrain data; a later ArcGIS-sourced phase (`ROADMAP.md` M6 note). |
| **Front-line polyline-draw UI (D5-D)** | PORT | The one remaining D5 piece; it's a **graphics** item → Track 5 (needs visual verification). |

## Intentionally skipped (source-specific — do NOT port)

- **TIV SQL/DB writeback** (`ijfs_writeback_service`, `target_system_writeback_service`, repo mutations,
  `Final_Attrition_Pct`/restore DB columns) — HexCombat recomputes state in-memory each turn.
- **Mine same-day re-preview baseline** (`last_resolved_day`/`*_day_start`) — a TIV web-UI idempotency
  concern; HexCombat resolves each turn once through the action layer.
- **Dashboards / visualizations / summaries / input glue** in TaiwanDefenseRefactor (`dashboard.py`,
  `visualizations.py`, `summaries.py`, `input.py`, `main.py`, `test_*`) — Streamlit/CSV UI, not sim.
- Assorted reporting-only derived columns noted across `PLAN.md` (e.g. `Final_Attrition_Pct`,
  per-battalion lat/lon spacing, support-BN HQ offset) — cosmetic/DB-shaped, no HexCombat consumer.

## Recommendation

Nothing here blocks the slice. The two **ADAPT** items with real gameplay weight — the **missile
pipeline** (strike-coverage lever) and the **ground-casualty IJFS↔OOB linkage** — are the next
substantive ports, but both should be driven by a concrete need (balance calibration; ground-fight
fidelity) rather than ported speculatively. Promote whichever the playtest (Track 3b) shows matters.
