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
- **D3-B split into B1/B2/B3** (dependency order: magazine → firing plan → crossing; ~2,100 src lines):
  - **D3-B1 — DONE (2026-06-26, committed):** `scripts/AntishipMagazine.gd` (calculator-pure magazine
    reservation: `from_defaults`, `cap_launcher_count`, `reserve_full_volley`, `deduct_launcher_kills`)
    + `tests/antiship_magazine_test.gd` (9 cases). DB funcs not ported.
  - **D3-B2 — DONE (2026-06-27, committed):** `scripts/AntishipCalculator.gd` —
    `build_firing_plan` (single-row over pre-aggregated rows; C2 type-99 excluded; magazine
    `cap_launcher_count` + full-volley gate) + `allocate_firing_to_rows` (proportional largest-
    remainder) + `resolve_launch_attrition` (per-shot RNG draw order, in-place row mutation,
    systems-fired / launch-attrition summaries). `tests/antiship_firing_plan_test.gd` (9 cases incl.
    the two `test_antiship_firing_plan.py` mirrors). Tuple keys → `"<to>:<type>"` String encoding;
    launch-attrition config = crossing config's `launch_attrition` section. Golden byte-stable.
  - **D3-C — DONE (2026-06-27, committed):** `scripts/MineWarfareService.gd` (pure) —
    `resolve_ship_losses` (sweep → 1-mine-sinks-1-ship via `Dice.weighted_choice` → pool depletion
    across beaches ascending). **Geometry-free** simplified port (dropped the string-seeded-MT danger
    model + polygons + same-day-rerun baseline; see PLAN.md Decisions). `tests/mine_warfare_test.gd`
    (8 cases). Golden byte-stable. *Balance flag:* every unswept mine is lethal → 100-mine beaches
    are very lethal un-swept; tune in D3-D.
  - **D3-B3 — DONE (2026-06-27, committed):** `scripts/AntishipCrossing.gd` (pure) —
    `resolve_crossing_damage` (6-stage count-based pipeline: launches+pools+range-gating+partial-fire
    → in-flight → escort interception → weighted homing+decoy discrimination → terminal defense →
    fresh/damaged/sunk damage). `validate_combat_catalog`/`validate_crossing_config` ported.
    **Count-based** port — per-hull escort-magazine refinement deferred (Open Question; needs a ship
    ammo/readiness subsystem HexCombat lacks). Theater data injected to keep the lib pure.
    `tests/antiship_crossing_test.gd` (15 cases — full `test_antiship_crossing.py` mirror). Golden
    byte-stable. **D3-B (magazine + firing plan + crossing) COMPLETE.**
  - **D3-D — DONE (2026-06-27, committed). D3 (anti-ship & mine warfare) MILESTONE COMPLETE.**
    `GameState.resolve_antiship_turn(dice)` threads D3-B2 firing → D3-B3 crossing → D3-C mines (runs
    after `resolve_ijfs_turn`, before `resolve_offload_turn`). New `scripts/ShipLoadingModel.gd` maps
    BNs-at-sea → a sent fleet (min-lift greedy carrier fill + escort/decoy screen) and converts
    destroyed hulls → BNs lost at sea (fractional accumulator carried across turns), removing them from
    `ship_reserve` and feeding the D0-C `register_ship_losses` seam (D3-D absorbed the formerly-deferred
    D3-F BN-removal). IJFS suppression joins per **(TO,type)** via container-level dynamic targets
    (decision 1-A — resolves the D4-H TO-linkage Open Question); **C2 suppression** (type 99) costs a
    TO 30% of surviving anti-ship firing (`C2_SUPPRESSED_FIRE_MULTIPLIER`, no C2 destruction);
    bounded per-lane mine danger + first-transit lane clearing (decision 2-iii). LLM observation gains
    an `antiship` block (+schema/validator/fixture). `tools/validate_headless_antiship.gd`
    (reconciliation + determinism + C2-reduces-firing) in the gate. Golden 20260624 → casualties=2,
    feba=0.76 byte-stable. **Balance-flagged, not "tuned":** the crossing is catastrophically lethal
    (golden scenario loses 33/36 BNs into TO3, whose C2 the IJFS didn't suppress) — see PLAN.md Open
    Question "D3-D crossing lethality calibration". The ground-casualty half of the D4-H writeback Open
    Question is still open (no IJFS↔OOB ID bridge).
- **Final integration** (turn-sequence polish, full LLM observation contract) + **D5** (front-line /
  cleanup, scoped in PLAN.md) + **anti-ship balance calibration** — after D3. ← **resume here.**

**Backlog order (dependency-checked):** `D4-G → D4-H → D3-A → {D3-B, D3-C} → D3-D` — **all DONE
(D4 + D3 milestones complete, pushed)**. Remaining: **anti-ship balance calibration** (PLAN.md Open
Question "D3-D crossing lethality calibration" — a user/design call, not a port), **D5** (front-line
+ cleanup; sub-tasks D5-A/B/C scoped in PLAN.md), the **ground-casualty IJFS↔OOB linkage** (open half
of the D4-H Open Question), and **final integration / refactoring** polish. TIV oracle file/line refs:
`ROADMAP.md` §D3/§D4/§D5. (D3-D absorbed the formerly-separate D3-E/F BN-removal scope.)

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

## 6. Immediate next action (D3 + D4 milestones complete — pushed)

**All of D3 (anti-ship & mine warfare) and D4 (IJFS) are DONE, gated, and pushed.**

**Update 2026-06-28 — D5 headless ports + Track E façade DONE & pushed.** D5-A (`FrontLineService`),
D5-B (`resolve_frontline_phase`), D5-C (cleanup phase) are committed; the only D5 remainder is **D5-D**
(polyline-draw UI — needs visual verification, NOT autonomous-overnight-safe). The first **Track E**
(AI-readiness) seam also landed: `GameState.play_turn(red_orders, green_orders, dice) -> TurnResult` +
`GameData.snapshot_state()` (see `PLAN.md` Decisions 2026-06-28 / `RETROSPECTIVES.md 2026-06-28
play_turn-facade`), followed by the **per-turn structured event log** — `scripts/model/TurnEvent.gd` +
pure `scripts/TurnEventLog.gd` (`build(state) -> Array[TurnEvent]`) populating `TurnResult.events` in
`play_turn`; ordered `ijfs→antiship→move→commit→combat→frontline?→cleanup?`, derived non-invasively from
stored `last_*` state (golden byte-stable). See `PLAN.md`/`RETROSPECTIVES.md 2026-06-28 turn-event-log`.
The event log is now also **surfaced through `LLMGameAPI`**: `apply_agent_response`'s `end_turn` routes
through `play_turn` and threads `turn_result.to_dict()` (incl. the `events` log) into the action result under
a `turn_result` key; `tools/export_llm_result.gd` regenerates `docs/examples/llm_result_after_turn.json` (see
`PLAN.md`/`RETROSPECTIVES.md 2026-06-28 llm-event-surfacing`). **Next autonomous-safe unit:** add a
**`schemas/llm_action_result.schema.json`** JSON Schema for the action-result contract — the observation and
action_response already have schema files but the result does not (a contract-consistency gap); mirror the
existing `llm_observation.schema.json` pattern, cover the new `turn_result`/`events` shape, and wire it into
`tools/validate_llm_api.gd` (it already parses `EXAMPLE_PATHS`; add a conformance check of the committed
result fixture). Pure documentation/validation, zero golden risk. **— DONE 2026-06-28** (`schemas/
llm_action_result.schema.json` + `REQUIRED_RESULT_KEYS`/`_validate_result_schema_conformance` drift gate; see
`PLAN.md`/`RETROSPECTIVES.md 2026-06-28 llm-result-schema`). **This completes the Track-E AI-readiness arc**
(play_turn façade → event log → LLM surfacing → result schema).

The `GameData.validate_runtime_indexes()` hardening guard (REFACTOR_NOTES M5a) is **DONE 2026-06-28**
(read-only brigades ↔ brigades_by_hex bidirectional check + `tools/validate_runtime_indexes.gd` with a
negative corruption test; see `PLAN.md`/`RETROSPECTIVES.md 2026-06-28 runtime-index-guard`). Its top
follow-up — a debug-gated auto-assert in the mutators / end of `resolve_turn` — was **deliberately deferred**
(a new hot-path assert risks destabilizing currently-green tests on a benign transient desync; do it with
attention, not unattended).

The **headless AI-vs-AI self-play harness** (`tools/validate_headless_selfplay.gd`) is **DONE 2026-06-28** —
the Track-E capstone: a gated, deterministic 4-turn self-play game over the existing action API, asserting
full-game reproducibility + index health (cross-process determinism + 2× gate stability verified). See
`PLAN.md`/`RETROSPECTIVES.md 2026-06-28 selfplay-harness`.

The reusable **`SelfPlayRunner` + pluggable `SelfPlayPolicy`** extraction is **DONE 2026-06-28** (driver at the
LLMGameAPI adapter layer — NOT on GameState, to avoid inverting the dependency; the self-play validator now
delegates to it; golden validator untouched). See `PLAN.md`/`RETROSPECTIVES.md 2026-06-28 selfplay-runner`.

---

### ⏸ AUTONOMOUS LOOP STOPPED 2026-06-28 — clean handoff (safe backlog exhausted)

After 7 units this session (BOOTS port was already complete; this run added the full **Track-E AI-readiness
arc**: play_turn façade → snapshot_state → per-turn event log → LLM action-result surfacing → llm_action_result
schema → runtime-index guard → headless self-play harness → reusable runner/policy), **all green and pushed**,
the orchestrator loop **stopped deliberately**. Every remaining backlog item needs you or is unsafe to do
unattended with the free-model implementer:

- **Design calls (need you):** anti-ship **crossing-lethality calibration** (PLAN.md Open Question — the
  crossing is catastrophically lethal by design until tuned); **`game_over`/`winner` victory conditions** (new
  game-design, not a faithful TIV port); whether to wire the **debug-gated runtime-index auto-assert** into
  `set_brigade_hex`/`resolve_turn` (deliberate — it can surface latent benign desyncs and turn green tests red).
- **Blocked:** **D5-D** polyline-draw UI (needs human visual verification — not headless-verifiable); the
  **ground-casualty IJFS↔OOB linkage** (no shared ID bridge exists in the TIV source data — needs a design
  decision on how IJFS maneuver targets map to OOB brigades).
- **Risky for the free model (do with a stronger implementer / attention):** typed `HexState`/`CombatSummary`
  Resource migrations (touch many call sites across GameState/LLMGameAPI/validators — high golden-regression
  risk).
- **YAGNI until a consumer exists:** `SelfPlayRunner` per-turn hooks / a mid-game `resolve_turn(policy, seed)`
  entrypoint; a balance-sweep harness (also edges into the calibration design call); `export_turn_log` JSON
  game-log export.

**To resume:** pick a design call to settle (calibration or victory conditions are the highest-leverage), then
re-run `/loop`. The per-sub-task loop in §3 and all guardrails (§5) still apply. The full per-unit rationale +
retrospectives are in `PLAN.md` Decisions and `docs/RETROSPECTIVES.md` (2026-06-28 entries).

> **Note on the deeper AI-driver track (surfaced for the user — NOT autonomous):** a `game_over`/`winner`
> field requires defining **victory conditions**, which is new game-design, not a faithful TIV port — that is
> a design call for the user, not an overnight unit. A bulk `submit_and_resolve(red_orders, green_orders,
> seed)` endpoint (a thin `play_turn` wrapper) + a `current_player` observation field are safe later
> conveniences. After the result-schema unit, the autonomous Track-E backlog is largely exhausted; reassess
> whether to continue or hand off.

The remaining non-autonomous items (UI, design calls, data-blocked linkage) are unchanged below.

Pick the next unit from the post-D3 backlog (consult `ROADMAP.md` + `PLAN.md` so choices stay
forward-compatible). In rough priority order — settle the first with the user, it's a design call:

1. **Anti-ship crossing-lethality calibration** *(balance / design — surface to user first).* D3-D is
   wired and reconciles, but the crossing is catastrophically lethal (golden scenario loses 33/36 BNs
   into TO3, whose C2 the IJFS didn't suppress). The C2 lever (30% fire penalty) and aircraft
   suppression both work but don't bite the assaulted TO. Candidate levers (all additive on existing
   seams) are enumerated in **PLAN.md → Open Questions → "D3-D crossing lethality calibration"**: IJFS
   targeting weight on the assault-TO C2, `DEFAULT_ANTISHIP_FIRE_PCT`/`range_tier` tuning, cross-turn
   magazine state, or accepting a deadly unsupported crossing as intended. **Not a port — do not
   "fix" it autonomously; get the user's design call.**
2. **D5 — front-line + cleanup** (sub-tasks D5-A/B/C scoped in `PLAN.md`; TIV oracle in `ROADMAP.md`
   §D5). The next *port* work: `FrontLineService` (polyline → hex sequence, BN distribution), the
   polyline-draw UI, and the cleanup phase (residual attrition + isolation + ownership).
3. **Ground-casualty IJFS↔OOB linkage** — the still-open half of the D4-H writeback Open Question
   (`maneuver_casualties` is empty; needs an ID bridge between the IJFS target set and the PLA/ROC OOB).
4. **Final integration / refactoring** polish (see `docs/REFACTOR_NOTES.md`).

Use the per-sub-task loop in §3 throughout (plan → opencode → retrospective → independent gate →
review diff + lessons → record in PLAN.md Decisions + RETROSPECTIVES.md → commit; push at milestones).

> The historical scoping notes below (D3-A/B brief, D3-A deliverables) are kept as append-only record
> for the now-complete D3 sub-tasks; they are **not** the next action.

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
