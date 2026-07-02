---
name: hexcombat-failure-archaeology
description: The chronicle of HexCombat's major investigations, bugs, dead ends, and rejected fixes — each as symptom → root cause → evidence → status — so no agent re-fights a settled battle or re-proposes a rejected fix. Consult when a problem feels familiar, before proposing a fix in a subsystem with history, or when a doc/number contradicts the code.
---

# Failure archaeology

Settled battles. Primary sources: `PLAN.md` → Decisions (why) and `docs/RETROSPECTIVES.md`
(lessons, dated entries). Newest lessons get APPENDED here when they close an investigation.

### Hex adjacency: offset coords treated as axial (2026-06-29)
- **Symptom:** none visible — combat/support aggregation quietly used wrong neighbors for weeks.
- **Root cause:** `HexMath` treated the grid's stored **odd-r offset** row/col as **axial**.
- **Evidence:** empirical sweep — prior axial neighbors matched great-circle geometry on 23/308
  interior hexes; odd-r matched 308/308.
- **Fenced off:** "defer the fix until after the audit" — rejected (USER call: fix immediately so
  the rest of the audit ran on correct adjacency, accepting a golden re-baseline).
- **Status:** fixed (parity-aware odd-r + offset→cube distance); golden re-baselined
  casualties 2→3; a scenario defender hex moved to a true neighbor. Lesson: never hand-roll hex
  math; all geometry via `HexMath`. Detail: `docs/systems/hex-grid.md`.

### Exquisite intel dead for the whole project (2026-06-28)
- **Symptom:** crossing losses measured ~67% with a key detection mechanism silently OFF; no
  error anywhere.
- **Root cause:** `resolve_ijfs_turn` ran `run_daily` with **no `warmup_context`**; every consumer
  read `wc.get(key, default)` so the absent config degraded to defaults invisibly.
- **Evidence:** wiring the full TIV warmup port dropped crossing loss 67%→50% with the golden
  byte-stable — proving the mechanism had been dormant, not weak.
- **Status:** fixed (faithful warmup port) + guarded (`WARMUP_CONTEXT_KEYS` allowlist assert,
  refactor item 1). **This incident is why the fail-loud/no-silent-defaults rule is absolute.**

### The census flake and the phantom reset fix (2026-06-30)
- **Symptom:** victory census nondeterministic across gate runs (20 vs 24).
- **Root cause:** **stale class cache** — the gate ran mid-edit before `--import` had picked up
  just-written files. NOT a state bug.
- **Evidence:** isolated re-runs + standalone validator + clean full re-run all gave a stable 20.
- **Fenced off:** the implementer's proposed `reset_to_scenario` state-bleed fix — evidence ruled
  it out; reset already rebuilds compositions and `ship_reserve` correctly.
- **Status:** closed. Rule: verify a determinism failure standalone (after re-import) before
  touching reset/state code.

### Fixture rot: `llm_result_after_turn.json` (2026-06-30)
- **Symptom:** committed example fixture silently 318/247 lines stale vs regeneration.
- **Root cause:** nothing regenerated-and-compared committed fixtures; the antiship balance work
  had drifted the contract.
- **Status:** fixed by refactor item 8 — `tools/validate_fixtures.gd` byte-compares every gate
  run through the shared `tools/LLMFixtures.gd` builder (single source of truth so the gate can't
  drift from the exporters).

### Mine/crossing calibration: the lever that couldn't reach 25% (2026-06-28→29)
- **Symptom:** USER target ~25% crossing loss; the planned `intel_locked` strike-bonus lever
  topped out ~41% (band ~54→41%) because mines set a ~22% floor.
- **Root cause:** the geometry-free mine model made *every* mine dangerous — the wrong knob was
  being turned.
- **Evidence:** measured knob-band sweep (recorded in PLAN.md Open Questions "D3-D crossing
  lethality calibration"); knob map `docs/antiship_lethality_knobs.html`.
- **Fenced off:** continuing to force the strike bonus toward 25% (deferred as a lever, memory:
  strike-coverage); re-tuning the geometry-free model.
- **Status:** USER redirected to porting the **geometric danger model + decoy-sponge transit**
  (TaiwanDefenseRefactor `mine_warfare.py`): baseline mean loss 54%→32.4%, and the intel lever
  bites again via emergent coupling (killing launchers preserves the decoy screen). Final dial-in
  to exactly ~25% left as a USER call. Documented divergences from the source (decoys sponge ≥1
  mine; Dice not numpy) in the Decisions entry.

### RNG isolation trap: `ScriptedDice.derive()` returns self (2026-06-26)
- **Symptom (near-miss):** wiring IJFS into `resolve_turn` with `dice.derive("ijfs")` would have
  silently drained scripted combat rolls across ~10 suites — green-looking until casualty asserts
  shifted.
- **Root cause:** the test double's `derive()` shares one queue; real `SeededDice.derive()` forks.
- **Evidence:** caught by auditing every `resolve_turn` caller's dice *type* before wiring.
- **Status:** durable fix = dice-type-aware branch. Rule: any new phase joining the shared dice
  pipeline → audit caller dice types first.

### Godot 4.7 headless teardown crash (recurring, environmental)
- **Symptom:** nonzero/crash exit codes (0xC0000005 et al.) after all tests printed PASS.
- **Root cause:** engine bug — SceneTree shutdown after many back-to-back headless scripts.
- **Status:** permanently gated around — `run_all_tests.ps1` judges by OUTPUT, downgrading
  crash-exits with clean output to warnings. Don't re-litigate; don't chase the exit codes;
  don't weaken output-based verdicts either.

### pi CLI ENOENT (2026-06-26)
- **Symptom:** the prior implementer CLI `pi` died instantly on this box.
- **Root cause:** it spawns `opencode` via `spawn('opencode')` without `shell:true`; Windows
  can't resolve the `.cmd` shim.
- **Status:** abandoned — call `opencode run` directly. (Since 2026-07-02 the frontier agent
  implements directly anyway; opencode = mechanical chores only.)

### Map projection stretch (2026-06-24)
- **Symptom:** flat/wide hexes, ~2.75× horizontal stretch, markers off-screen north.
- **Root cause:** independent per-axis scaling in `MapProjection` instead of a uniform
  `cos(mean_lat)`-corrected fit.
- **Status:** fixed; verified by screenshot. Lesson: geographic projections need uniform scale;
  verify view-layer work visually, never by gate-green alone.

### Scoping corrections the oracle forced (pattern, 2026-06-27+)
- **D5-C cleanup:** ROADMAP said "residual attrition + isolation checks"; the TIV source shows
  cleanup is a pure end-of-turn system reset — and the only non-redundant HexCombat work was
  resetting anti-ship per-turn flags (a latent accumulation bug found *by* the scoping read).
- **D4-H writeback:** the brief's "(TO,Type)" join keys didn't exist in the data; keyed by Type
  and logged the gap rather than inventing fake IDs.
- **Lesson:** read the source/data before implementing a plan's description of it; plans drift,
  oracles don't. Grep the actual data for join keys before trusting a spec.

### GDScript-vs-Python port traps (collected, 2026-06-26)
Recurring compile/behavior traps when porting Python: `:=` cannot infer from `Variant` members
(annotate explicitly); `value == ""` raises on non-String (type-guard first); GdUnit needs
`assert_dict()` not `assert_object()` for dicts; GdUnit prints `push_error` stack traces without
failing the test (judge by `Statistics:`/`Overall Summary` only); mirror source dict key names
exactly (grep the pytest's asserted keys); don't let a "helpful" port re-add Python's silent
`.get(key, 0)` defaults.

### Historical case-count inflation (2026-06-26)
Prose in planning docs claimed "238/210 cases" when the real GdUnit count was 124 — assertions
were counted as cases. Rule: trust `grep -c 'func test_'` and the GdUnit `Overall Summary`, never
prose counts (including in THIS documentation).
