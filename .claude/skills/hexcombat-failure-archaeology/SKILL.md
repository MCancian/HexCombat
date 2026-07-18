---
name: hexcombat-failure-archaeology
description: The chronicle of HexCombat's major investigations, bugs, dead ends, and rejected fixes — each as symptom → root cause → evidence → status — so no agent re-fights a settled battle or re-proposes a rejected fix. Consult when a problem feels familiar, before proposing a fix in a subsystem with history, or when a doc/number contradicts the code.
---

# Failure archaeology

Settled battles. Primary sources: `docs/DECISIONS.md` (+ pre-2026-07-10 history in
`docs/archive/PLAN.md` → Decisions) and `docs/RETROSPECTIVES.md`
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
- **Amendment (2026-07-09):** a REAL reset leak did exist in a field that incident never
  checked — `GameData.hex_states` (ownership/FEBA) was only rebuilt by `load_hex_grid`, never by
  `reset_to_scenario`. Surfaced when the full-defense laydown made the 40-turn golden self-play's
  in-process second replay diverge (24/88 vs 25/90 — reproducible after fresh `--import`, stable
  across processes: the discriminating evidence vs. this entry's cache flake). Fixed by
  `GameData.reset_hex_states()`. The 2026-06-30 verdict stands for compositions/ship_reserve;
  its blanket "reset is already correct" did not.

### Fixture rot: `llm_result_after_turn.json` (2026-06-30)
- **Symptom:** committed example fixture silently 318/247 lines stale vs regeneration.
- **Root cause:** nothing regenerated-and-compared committed fixtures; the antiship balance work
  had drifted the contract.
- **Status:** fixed by refactor item 8 — the gate regenerates through the shared
  `tools/LLMFixtures.gd` builder and git-diffs `docs/examples/` (single source of truth so the
  gate can't drift from the exporters). **Recurred 2026-07-18** — see the next entry: the
  regeneration step itself was silently broken.

### Fixture drift gate was vacuous: exporters never wrote docs/examples (2026-07-18)
- **Symptom:** regenerating `llm_result_after_turn.json` on a clean HEAD produced a massively
  different file than the committed fixture, yet the gate's drift check had been green for days.
- **Root cause:** both gate scripts invoked `export_llm_*.gd` WITHOUT the `--` user-arg
  separator. Godot only surfaces args after `--` via `get_cmdline_user_args()`, so `--output`
  never reached the exporter, output fell back to `reports/llm_*.json`, and the git-diff check
  compared an untouched `docs/examples/` against itself — vacuous since f37170f.
- **Status:** fixed 2026-07-18 (e02abc7): separator added in both `run_all_tests.sh`/`.ps1`,
  fixture honestly re-baselined. Lesson: a NEW guard must be watched failing once before it is
  trusted; and any `-s script.gd` invocation that passes `--flags` needs the `--` separator.

### "2,500 Mobile SAMs destroyed on turn 2" is real, not double-counting (2026-07-10)
- **Symptom:** every game's turn-2 IJFS digest reports ~2,500 Mobile SAMs destroyed
  (`sead_destroyed` ≈ 2,506); looks like an engagement-log double-count.
- **Root cause:** NOT a counting bug. `targets_master.json` quantity-expands four Stinger MANPADS
  rows (500/1000/500/500) into ~2,500 individual Mobile-SAM instances; SEAD engages all
  non-destroyed SAM targets regardless of detection, and null `sam_score` → score 1 →
  `p_destroy ≈ 1`. Data + behavior verified identical in the TIV oracle
  (`ijfs_standalone/engagement.py`, TIV `targets_master.json`).
- **Evidence:** category instance counts from `data/ijfs/targets_master.json` (Mobile SAMs: 8
  rows → 2,550 instances); side-by-side oracle diff; both LLM games (seeds 20260710/20260711)
  reproduce 2,49x at turn 2 and ≤24 (the remainder) at turn 3.
- **Fenced off:** "fixing" the engagement-log counting or the digest sum — they are correct.
- **Status:** RESOLVED 2026-07-10 — USER chose to exclude MANPADS from SEAD and give them a real
  role: per-TO container bins, low-altitude strike interception + squadron contest, deterioration
  via usage/bombardment/ground losses (`IjfsManpads.gd`; docs/systems/ijfs.md → "MANPADS layer";
  Decisions log 2026-07-10). Golden pins re-baselined accordingly.

### Mine/crossing calibration: the lever that couldn't reach 25% (2026-06-28→29)
- **Symptom:** USER target ~25% crossing loss; the planned `intel_locked` strike-bonus lever
  topped out ~41% (band ~54→41%) because mines set a ~22% floor.
- **Root cause:** the geometry-free mine model made *every* mine dangerous — the wrong knob was
  being turned.
- **Evidence:** measured knob-band sweep (recorded in docs/archive/PLAN.md Open Questions "D3-D crossing
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

### Follow-on sealift lift-path: two silent capacity bugs (2026-07-12)
Found together while auditing why a deep-pool `roc_full_defense`/`scenario_default` reached a Red
`china_majority` faster than 25–30% crossing attrition should allow. Both live in the plan-0004
follow-on **embark** path (`SealiftResolver._embark_followon` → `ShipLoadingModel`), NOT the first
assault wave, so the golden default (no follow-on) never exercised either — they were invisible.
- **Bug 1 — `.contains("Amphibious")` substring trap.** `_gather_carriers_and_screen` gated follow-on
  lift with `ship_def.category.contains("Amphibious")`. The category set includes
  `"Civilian_Non_Amphibious"`, which *contains* that substring, so every non-amphibious civilian hull
  (Container/Fast_Transport/unmod RoRo/barges) counted as amphibious lift — the whole mainland pool
  crossed in ~one turn instead of metering across turns. **Evidence:** turn-1 embark loaded ~85 BNs
  vs a 36-BN first wave. **Fixed:** exact category membership, moved to `ShipDef.is_amphibious_lift()`
  (+ `sails()`/`is_carrier()`) with a regression test pinning `Civilian_Non_Amphibious` → not lift.
  Sister of the GDScript port-trap family above; the general lesson: **never substring-match a
  category enum** — the negation contains the positive.
- **Bug 2 — per-hull `floor(capacity)` zeroes sub-1.0 hulls.** `ShipLoadingModel.pack_bns_into_hulls`
  floored capacity **per hull**, so LCU/LSM (0.1), LST/Small_RoRo_Mod (0.25) each carried 0 BNs
  regardless of count — ~12.8 BN-equiv of dead-weight lift. Effective amphibious lift was 42, not the
  54.8 nominal. **Consequence:** once the cap-≥1.0 hulls were busy cycling (or, generalized, if they
  were *sunk*), only useless small craft were "ready" and follow-on embark went to 0 — a permanent
  sealift stall with dozens of hulls afloat. **Diverged from the sibling path:**
  `build_sent_snapshots` (first wave) aggregates fractional capacity via `ceil` across hulls, so the
  same fleet had two different lift capacities depending on which function asked. **Fixed:** aggregate
  `floor(ready * cap)` per type, matching the minimum-lift math (24 LCU → 2 BNs). Byte-stable for
  cap-1.0 hulls, so existing tests held.
- **Status:** both fixed (2026-07-12). No golden re-baseline was needed: rather than repin, the deep
  pool was made **opt-in** (`auto_seed_followon_pool`) and the golden gate was pointed at a frozen
  `scenario_golden.json` while `scenario_default` became the deep-pool research default (USER option
  B; see `docs/DECISIONS.md`). Also surfaced — not a bug, a modelling gap owned by **plan 0006**:
  offload is beaches-only with `current_day = global turn_number`, and an empty-orders *default* now
  overruns to a turn-17 win with no offload cap. Lesson: a lift/throughput abstraction that floors or
  substring-matches must be tested with the *awkward* inputs (sub-1.0 hulls, `Non_` enum members),
  not just the clean 1.0/amphibious ones.

### Sealift livelock: heavy BNs unlandable in one day froze all lift (2026-07-15)
Found by plan-0006 C8 **research runs** (40-turn ordered games on `scenario_default`), invisible
to every unit gate and to the 10-turn deep-pool smoke. Under `use_offload_weight_matrix`, a BN
whose day-N beach cost exceeds its locked beach's FULL per-day tons (Mechanized Artillery /
Field/Rocket Artillery 3300 t or Air Defense 2750 t × 2.0 civilian-hull multiplier = 6600/5500 t
vs a 4400 t/d beach) deferred `throughput_limited` **every turn forever**. Plan-0004 coupling
turned starvation into a global livelock: a cohort frees its hulls only when ALL its BNs drain,
so ~10 permanently-stuck BNs held every amphibious hull → embark = 0, the 864-BN mainland pool
never moved, queued JLSFs never sailed, ports never repaired — all sealift frozen from ~turn 10.
**Root cause:** the TIV oracle never starves — `build_offload_queue` offloads fractionally across
days; HexCombat's day-N was whole-BN-per-turn, a porting gap only reachable once C1–C6 made
per-BN costs exceed beach rates. **Fixed** (same day): day-N carry-over in `OffloadCalculator` —
the locked beach's leftover tons bank into `offload_progress_tons` on the bn dict (deferred
reason `offload_in_progress`) until progress covers the cost. Flat-cost path provably unchanged
(all flat costs/rates are multiples of 2200 ⇒ the partial branch can't fire) — golden stayed
byte-stable. Guard: `validate_deep_pool_smoke` now runs 12 turns and asserts landings continue
past turn 10 (pre-fix: 0). Lesson: **any per-item cost drawn from a per-turn budget needs a
carry-over or a proof that max(cost) ≤ min(budget)** — and end-to-end research runs longer than
the smoke horizon are part of a feature's verification, not an optional extra.
