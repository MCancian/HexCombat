# Orchestrator Handoff — continue the TIV port via opencode subagents

**Audience:** the next Claude orchestrator session. Read `AGENTS.md` → `CLAUDE.md` → `ROADMAP.md`
→ `PLAN.md` first; this doc is the *active build plan* for finishing the TaiwanInvasionViewer
(TIV) port, the **opencode** implementer workflow, and the **per-sub-task retrospective loop** the
user asked for. The full per-sub-task breakdown lives in the approved plan file
`C:\Users\mdogg\.claude\plans\where-we-left-we-gentle-parnas.md` (written for pi — the *backlog* is
still correct; only the implementer CLI changed). Do not duplicate it here; point at it.

---

## 1. Where the port stands (verify before trusting)

Confirm with `git log --oneline -15` + a fresh `pwsh ./tools/run_all_tests.ps1` (must exit 0).

- **Wave 0 foundations — DONE:** Dice/RNG extensions (`randf`/`weighted_choice`/`weighted_choices`/
  `shuffle_indices`/`derive`), Theater model (`scripts/Theaters.gd` + `data/theaters.json`),
  Ship-type model (`scripts/model/ShipState.gd` + `data/ships.json`).
- **D4 IJFS A–F — DONE & committed:** models (`scripts/model/ijfs/`), loaders, data (`data/ijfs/`),
  and the six pure libs — `IjfsDetection`, `IjfsTargeting`, `IjfsStrike`, `IjfsFiringCapacity`,
  `IjfsEngagement`, `IjfsAdHealth`, `IjfsWarmup` — each with a GdUnit4 suite in `tests/ijfs/`
  (~238 cases, gate green).
- **D4-G — DONE (2026-06-26, committed).** `scripts/ijfs/IjfsEngine.gd` (`run_daily` 6-phase
  orchestration, returns ledgers dict — no file IO) + `scripts/ijfs/IjfsDailyState.gd` (in-memory
  state container) + `IjfsTarget.to_dict()` + `summarize_run` + `carry_to_next_day` continuity.
  5 GdUnit cases in `tests/ijfs/ijfs_engine_test.gd` (full-run / continuity / dedup / budget-routing,
  mirroring `test_ijfs_standalone.py`). Gate green at 124 GdUnit cases; golden invariant byte-stable.
- **D4-H — DONE (2026-06-26, committed).** `GameState.resolve_ijfs_turn(dice)` runs `IjfsEngine`
  each turn on an **independent** substream (golden byte-stable), storing `last_ijfs_summary` +
  `last_ijfs_writeback` (anti-ship destroyed/suppressed by Type; SAM destroyed/suppressed; maneuver-
  casualty port). Hooked after offload, before maneuver/combat. `EventBus.ijfs_resolved`; LLM `ijfs`
  observation block (schema + validator required-key + regenerated fixture);
  `tools/validate_headless_ijfs.gd` in the gate. **D4 (IJFS) milestone COMPLETE — pushed.**
- **D3-A — DONE (2026-06-26, committed).** `data/antiship/` (5 TIV configs verbatim + `minefields.json`),
  `scripts/model/AntishipSystem.gd` + `Minefield.gd`, `scripts/AntishipLoaders.gd` (grouping spec →
  650 systems aggregated by (TO,type_id)), `tools/validate_antiship_data.gd` in the gate. ships.json +
  ShipDef/ShipState reused from D0-C.
- **D3-B…F — NOT STARTED** ← resume here. **Before D3-B:** resolve the `PLAN.md` Open Question
  *"D4-H writeback (TO + ground-casualty) linkage"* — D3-B's firing plan wants anti-ship suppression
  per **(TO,Type)**, but the IJFS writeback is keyed by **Type only** (target data lacks `to_number`).
  Stamp `to_number` onto `data/ijfs/targets_master.json` (via `data/theaters.json` polygons by lat/lon)
  as part of D3-B so the join works.
- **Final integration** (turn-sequence wiring, LLM observation contract) — after D3.

**Backlog order (dependency-checked):** `D4-G → D4-H → D3-A → {D3-B, D3-C, D3-D, D3-E} → D3-F →
final integration`. D3-B consumes D4-H's per-(TO,Type) destroyed/suppressed output; D3-F consumes
D0-C's ship layer via the `lost_at_sea` seam. Sub-task specs: approved plan §"Wave 1+ — D4" and
§"Wave N — D3". TIV oracle file/line refs: `ROADMAP.md` §D3/§D4.

---

## 2. The implementer: opencode (not pi)

pi is broken on this box (it spawns the `opencode` backend via `spawn('opencode')`, which can't
resolve the Windows `.cmd`/`.ps1` shim → `ENOENT`). Call `opencode` directly. Full usage is in
`CLAUDE.md` §"Using opencode". Quick reference:

```bash
# implement (read/write; build agent auto-allows its tools)
opencode run -m opencode/deepseek-v4-flash-free -s hexcombat-d4g "<self-contained brief>" -f scripts/ijfs/IjfsEngine.gd
# read-only review (explore subagent has no write tools)
opencode run -m opencode/deepseek-v4-flash-free --agent explore "<question>"
# continue the SAME session (keeps context — needed for the retrospective step below)
opencode run -m opencode/deepseek-v4-flash-free -s hexcombat-d4g "<follow-up>"   # or -c for last session
```

**Caveat:** `deepseek-v4-flash-free` is a small free model — weaker than a frontier implementer.
Keep briefs tight and self-contained, keep your verification bar high, and review every diff for
fidelity (formulas, constants, clamp bounds, RNG draw order) and scope drift. If a sub-task is too
intricate for the free model after a couple of focused attempts, implement it yourself and note
that in the retrospective.

---

## 3. The per-sub-task loop (with retrospective)

For **each** sub-task, run this loop. Steps 4 and 6b are the new parts the user requested.

1. **Plan.** Read the TIV oracle source for the sub-task *and its pytest* (the behavioral oracle).
   Write a self-contained brief: exact TIV source + line refs, target HexCombat files, the
   constants/formulas/RNG-order to preserve, the repo patterns to reuse, and the pytest cases to
   mirror. Tell opencode to follow `AGENTS.md`.
2. **Implement.** Dispatch to opencode in a named session (`-s hexcombat-<subtask>`).
3. **Report.** Have opencode report what it changed and how it self-checked.
4. **Retrospective — ask the implementer what it would do differently.** In the **same session**
   (so it still has full context), ask — *after* implementation and *after* it has seen the gate
   result:
   > "Knowing what you know now that it's implemented and gated: what would you do differently?
   > What surprised you, what's fragile or under-tested, what tech debt did you take on, and what
   > would make the *next* sub-task easier or safer? Be specific and concrete."
   Capture the answer. This is the implementer's lessons-learned, recorded *separately* from design
   decisions (see §4).
5. **Verify independently (orchestrator gates).** Never trust the report. Run, with captured
   stdout/stderr: `--import` (class cache) → the smoke test → the relevant `tools/validate_*.gd` →
   `pwsh ./tools/run_all_tests.ps1`. Confirm exit 0, the GdUnit4 case count grew, and the **ground
   combat golden invariant is byte-stable** (seed 20260624 → casualties=2, feba=0.76).
6. **Review — implementation *and* lessons.**
   a. **Diff review:** scope drift (exclude tooling/settings; never commit `.mcp.json`), fidelity
      to the TIV math/RNG order, faithful-port divergences justified (see §5).
   b. **Lessons review:** read the retrospective from step 4. Decide per item: *act now* (fold into
      this sub-task before committing), *act later* (turn into a backlog/Open-Question item), or
      *just record*. Apply the "act now" items.
7. **Record.** Append **design decisions** to `PLAN.md` → Decisions (existing append-only log) and
   the **retrospective + your triage** to `docs/RETROSPECTIVES.md` (see §4). Cross-link them.
8. **Commit on green.** One coherent commit per sub-task; end with the `Co-Authored-By` trailer.
   **Push at milestones** (D4 fully green; D3 fully green), not per micro-commit.

> Waves: dependency-independent sub-tasks (e.g. D3-B…E once D3-A + D4-H are in) can run as separate
> concurrent opencode sessions; gate + commit + retrospect each as it returns.

---

## 4. What gets recorded, and where

Two distinct records — keep them separate so later review is clean:

- **`PLAN.md` → Decisions log** — *real design decisions*: a choice you (or the implementer) made
  that isn't forced by the source — a faithful-port divergence, a key/shape mapping, an ordering
  decision, an Open Question resolution. Append-only, dated, one entry per decision. This is the
  authoritative "why we did it this way" record for later review.
- **`docs/RETROSPECTIVES.md` → per-sub-task entries** — the *implementer's lessons learned* from
  step 4 ("what I'd do differently") **plus the orchestrator's triage** (act now / act later /
  record) from step 6b. This is process/quality feedback, not design rationale. Format and the
  seed entries are in that file.

If a retrospective surfaces a genuine design question, promote it to a `PLAN.md` Decision or Open
Question and cross-link (`see RETROSPECTIVES.md <date>/<subtask>`).

---

## 5. Guardrails (carry over from AGENTS.md — do not relax)

- **Faithful port.** Preserve formulas, constants, clamp bounds, RNG **draw order**, and result
  dict key shapes exactly. The settled strategy mirrors **formulas + draw order**, *not* numpy's
  PCG64 bitstream (not reproducible in Godot) — tests inject scripted draws.
- **Documented divergences (in-spirit, already used in D4):** Python tuple → GDScript Dictionary
  with stable source-parallel keys; type-guard before cross-type comparison (`bool == ""` raises in
  GDScript); fail-loud on missing config keys vs Python's silent `.get(...,0)`. Log any *new*
  divergence in the Decisions log.
- **Golden invariant.** Ground combat seed 20260624 → casualties=2, feba=0.76 must stay
  byte-stable. New phases use their own seeded streams and must not consume combat RNG.
- **Integration tests go in validators, not GdUnit.** Full-turn/turn-resolution assertions live in
  `tools/validate_*.gd` (`extends SceneTree`) to dodge the Godot 4.7 GdUnit teardown
  heap-corruption flake. Keep GdUnit for pure-lib units.
- **ScriptedDice.** Use the shared `tests/helpers/ScriptedDice.gd` (global `class_name`); never
  declare a local `class ScriptedDice` (class_name collision = parse error). `randf()` pops the
  3rd ctor arg (`floats`); `choose_indices` pops the 2nd (`choices`).
- **Commits.** Only the orchestrator commits. Never commit `.mcp.json`. Review every diff for scope
  drift before staging.

---

## 6. Immediate next action: D3-B (anti-ship calculator)

**D3-A is DONE** — the data layer + models + loader are in place: `AntishipLoaders.load_systems`
returns 650 `AntishipSystem` rows by (TO,type_id); `load_combat_catalog` / `load_crossing_config` /
`load_magazines` return the TIV config dicts; `load_minefields` returns 9 `Minefield`s. Validator:
`tools/validate_antiship_data.gd`.

**D3-B — `scripts/AntishipCalculator.gd`** (pure RefCounted lib; scope from the TIV oracle —
`antiship_firing_plan.py`, `antiship_crossing.py`, `antiship_launch_attrition.py`,
`antiship_magazine_service.py`, `contracts/antiship.py`):
- `build_firing_plan(systems, ijfs_results, fire_allocations_by_to, …)` — consumes the D4-H IJFS
  writeback (anti-ship destroyed/suppressed). **First:** stamp `to_number` onto
  `data/ijfs/targets_master.json` (from `data/theaters.json` polygons by lat/lon) so the IJFS
  writeback can key by (TO,Type) — currently it is Type-only (D4-H Open Question). Filter C2
  (type 99 / `special:"C2"`) from firing.
- `resolve_crossing_damage(crossing_result, dice)` — the 7-stage missile model (launch attrition →
  groups of 4 → escort interception → decoy discrimination → weighted homing → terminal defense →
  neutralization) using `antiship_crossing_config.json` + `ship_profiles`.
- `apply_magazine_expenditure(...)` — finite shared magazines from `antiship_magazine_defaults.json`.
- **RNG:** inject `Dice`; mirror the source draw order exactly; mirror the TIV pytests
  (`test_antiship_firing_plan.py`, `test_antiship_crossing.py`, `test_antiship_magazine_service.py`)
  in `tests/antiship_calculator_test.gd`.
- D3-C (mine warfare) and D3-B are independent given D3-A; D3-D wires `resolve_antiship_turn` into
  `GameState` (apply ship losses → `pending_lost_at_sea` via the D0-C `register_ship_losses` seam).

D3-B…E are dependency-independent once D3-A lands — they can run as concurrent opencode sessions
(gate + commit + retrospect each). D3-B/D are RNG-sensitive (firing plan / ship-loss); D3-A/C are
more mechanical and opencode-suitable. Use the per-sub-task loop in §3 throughout.

### D3-A scoping notes (gathered 2026-06-26 — start here)

**Already exists (from D0-C — do NOT recreate):** `data/ships.json` (27 entries) +
`scripts/model/ShipDef.gd` / `ShipState.gd` / `IndividualShip.gd`; `GameState.fleet` (name→ShipState,
built by `_rebuild_fleet`); the `pending_lost_at_sea` / `register_ship_losses` seam (reporting-only,
BN-removal deferred to D3-F). So D3-A's *new* work is the **anti-ship systems + minefield** data/models,
not ships.

**TIV data oracle** (at `…/TaiwanInvasionViewer/TaiwanInvasionViewer/defaults/`, NOT `src/defaults/`):
- `antiship_systems_consolidated.json` (6KB) — Green weapon-system **type catalog** (id, name,
  detectability, description) + per-TO quantities. **CAVEAT:** several platform groups are
  `"deprecated": true` (split into finer types per the "2026 OOB update" — e.g. group 1 → types
  19/20/21/22; group 4 → 23/24). Port the **non-deprecated current types**; record which you dropped.
- `antiship_crossing_config.json` (5.7KB) — crossing-damage params (munition stages: launched →
  failed-in-flight → intercepted → leakers → hits/decoy/wasted; per-ship-type destroy/damage). Feeds D3-B.
- `antiship_combat_catalog.json` (6.3KB) — combat params per system/munition. Feeds D3-B.
- `antiship_magazine_defaults.json` (4.9KB) — magazine counts (D3-B `apply_magazine_expenditure`).
- `antiship_grouping_spec.json` (12KB) — TO/type grouping spec.
- Contracts: `src/contracts/antiship.py` (read — TypedDicts/dataclasses: `FiringAllocationRow`,
  `LaunchAttritionSummaryRow`, `AntishipCrossingSummary`, `AntishipMinefieldBeachSummary`, etc.).

**Proposed D3-A deliverables:** `data/antiship/antiship_systems.json` (+ crossing/magazine configs as
needed), `scripts/model/AntishipSystem.gd` (to, type, type_name, quantity, original_quantity,
destroyed, fired, expended, destroyed_this_turn, active — mirror `AntishipSystemEntry`),
`scripts/model/Minefield.gd` (beach_id, name, dangerous_mines, remaining_mines, lane_cleared,
minesweepers_assigned, lat/lng/advance_direction — mirror `AntishipMinefieldBeachSummary`),
`scripts/AntishipLoaders.gd` (or extend `GameData`), `tools/validate_antiship_data.gd`. Keep the TO
(theater) key consistent with `data/theaters.json` so D3-B can join IJFS suppression per (TO,Type) and
the D4-H Open Question resolves naturally.

**TO-mapping (D4-H Open Question):** likely defer the *actual IJFS-target `to_number` stamping* to
D3-B (where it's consumed) — but settle the **key convention** (TO = `theaters.json` `to_number`) in
D3-A so models/data agree from the start.
