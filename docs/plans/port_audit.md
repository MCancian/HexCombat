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
| **Ground-casualty IJFS↔OOB linkage** | ✅ DONE 2026-06-29 (overnight 2b–2d) | **CLOSED.** `IjfsLoaders.build_maneuver_targets` generates per-battalion "Maneuver Units" IJFS targets from the ROC OOB (`{brigade_id}-MU-{n}`); wired into `_rebuild_ijfs_state` so they're struck; `_compute_ijfs_writeback` populates `maneuver_casualties`; `GameState._apply_ijfs_maneuver_casualties` removes the struck battalions from the OOB before ground combat. Tests: `ijfs_maneuver_targets_test.gd`, `ijfs_maneuver_consume_test.gd`. Golden unchanged. Remaining refinement (2c-ii): detection/lethality bias (mobility/posture/hardness). _Original notes:_ `maneuver_casualties` was *computed* (`GameState._compute_ijfs_writeback`, a port of `ijfs_maneuver_writeback_service`) and exposed via the LLM observation — but it is **not consumed**: nothing removes the struck battalions from the ground OOB, so IJFS air/missile kills don't reduce the brigades that fight. The remaining half is (a) the ID bridge so IJFS maneuver-target `battalion_id`/`brigade_id` match the PLA/ROC OOB, and (b) applying the casualties before ground combat. By contrast the anti-ship half of the writeback IS consumed (feeds the D3 firing plan). Design settled 2026-06-28 (Option B + detectability); needs `moved_last_turn`/`fought_last_turn` on `Brigade`. |
| **Per-hull escort magazines** (crossing interception/terminal defense deplete `hq10`/`hhq9`) | ADAPT | D3-B3 open question; needs a ship ammo/readiness subsystem HexCombat lacks. Count-based port matches all source pytests today. |
| **Per-ship-type mine neutralization likelihood** | REFINE | Current model uses a per-category table; source data varies within a category (LHD/LPD "Low" vs LST "High"). A `ShipDef` field would be more faithful. (RETROSPECTIVES 2026-06-29.) |
| **Flotilla composition nuances** (`create_flotillas.py`) | REFINE | HexCombat builds a sent fleet by capacity/screen; the source groups ships into flotillas with per-flotilla mine-encounter rolls. Only relevant if the missile pipeline is ported (flotillas are its unit of allocation). |
| **Terrain** | ADAPT | Deferred by design — TIV has no terrain data; a later ArcGIS-sourced phase (`ROADMAP.md` M6 note). |
| **Front-line polyline-draw UI (D5-D)** | PORT | The one remaining D5 piece; it's a **graphics** item → Track 5 (needs visual verification). |

## Found during the systems audit (2026-06-29)

| Item | Tag | Notes |
|---|---|---|
| **Supply-effectiveness → combat link** | ✅ DONE 2026-06-29 | `GameState._inject_supply_effectiveness` sets Red maneuver `supply_effectiveness` (1.0 while pool >0, else `GameData.red_out_of_supply_effectiveness`=0.5) before `resolve_map_attack`; mirrors TIV `_inject_supply_effectiveness`. Tests: `supply_combat_effectiveness_test.gd`. Golden unchanged (1-turn pool never exhausts). v1 binary; graded ramp = future refine. |
| **Front-line distribution granularity** | REFINE | `FrontLineService.distribute_units_along_hexes` distributes at **brigade level** and snaps to hex centers; TIV `distribute_battalions_along_line` works at battalion level with per-hex polygon clipping (`_get_polyline_coords_in_hex`) + support offset. Low priority — the front-line DRAW UI itself is deferred to Track 5 (graphics); refine the distribution when that UI lands. |
| **ShipLoadingModel: per-type transport weight** | REFINE | Every BN = 1.0 ship-equivalent; TIV uses `configurator.get_unit_transport_weight()` per type. Matters only for exact ship-manifest → D3 crossing calibration. Code-documented (`ShipLoadingModel.gd:14`). |
| **ShipLoadingModel: amphibious-vs-cargo ship eligibility** | REFINE | HexCombat: any carrier ships any BN; TIV splits amphibious vs cargo eligibility (`_ship_can_carry_battalion`). Same calibration caveat. |
| **Ground combat: unit strength table (12/17 types)** | DECISION | See `/DECISIONS.md` (Area 2). HexCombat differentiates maneuver strengths; TIV's runtime flattens to 1.0 (mapping bug). Awaiting user ratification. |
| **Ground combat: `feba_base_km` 2.0 vs 3.5** | DECISION | See `/DECISIONS.md` (Area 2). Recommend scenario-configurable default 3.5. |

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
