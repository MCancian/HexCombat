# Retrospectives — implementer lessons learned

Per-sub-task "what would you do differently, knowing what you know now" notes, captured **after**
implementation and gating (see `docs/ORCHESTRATOR_HANDOFF.md` §3 step 4), plus the orchestrator's
triage. This is **process/quality feedback** — design rationale lives in `PLAN.md` → Decisions.
Append-only; newest at the bottom of each section. Cross-link decisions as `PLAN.md <date>`.

## Entry format

```
## <date> — <sub-task id>: <title>   (implementer: opencode <model> | direct)

**What would you do differently (implementer):**
- <specific, concrete lesson — fragility, tech debt, surprise, what'd make the next task easier>

**Orchestrator triage:**
- <lesson> → act now | act later (→ PLAN.md Open Question / backlog) | record only — <note>
```

---

## 2026-06-26 — Tooling: pi → opencode implementer switch   (direct)

**What would you do differently:**
- pi (the previous implementer CLI) is unusable on this Windows box — it spawns the `opencode`
  backend via `spawn('opencode')` with no `shell:true`, which can't resolve the `.cmd`/`.ps1`
  shim and dies `ENOENT`. Calling `opencode run` directly works. Would have switched at first
  failure instead of diagnosing pi's internals.
- The free model `opencode/deepseek-v4-flash-free` is weaker than the prior GPT-5.5 implementer;
  briefs must be tighter and the orchestrator's diff review more careful.

**Orchestrator triage:**
- Switch to opencode → **acted now**: updated `CLAUDE.md`, `AGENTS.md`, `.claude/settings.json`
  (`Bash(opencode *)`), `docs/LLM_PLAYTESTING.md`. Historical pi references in dated logs left
  intact (append-only history). See `PLAN.md` Decisions (pending entry).

---

## D4-A…F port — carried-forward lessons (retro-logged 2026-06-26)

These were learned while porting the IJFS pure libs (mix of pi and direct); recorded here so the
next sub-tasks (D4-G/H, D3) don't relearn them.

**What would you do differently:**
- **ScriptedDice class_name collision.** An implementer declared a local `class ScriptedDice extends
  Dice`, colliding with the global `class_name ScriptedDice` → parse error. Always reuse
  `tests/helpers/ScriptedDice.gd`; brief the implementer on its ctor (`randf()` pops the 3rd arg
  `floats`; `choose_indices` pops the 2nd arg `choices`).
- **Cross-type comparison.** `value == ""` raises in GDScript when `value` is a bool/null (Python
  tolerates). Type-guard first (`if value is String:`). Bit `IjfsStrike._wildcard`.
- **Result-shape fidelity.** A test asserted `mobile_cap_applied` but the port returns
  `legacy_cap_applied`. Mirror the *source* key names exactly; grep the pytest for the asserted keys
  before writing the dict.
- **GdUnit assertion API.** `assert_object(dict).is_empty()/.is_same()` is invalid for dicts — use
  `assert_dict(...).is_empty()/.is_equal()`.
- **Fail-loud vs silent defaults.** Python `.get(key, 0)` hides missing config; the port fails loud
  on missing `firing_units`/`sorties`. Keep that — but brief the implementer so it doesn't
  "helpfully" re-add silent defaults.

**Orchestrator triage:**
- All → **record only / brief forward**: fold the relevant items into each sub-task brief. The
  ScriptedDice and key-shape items are the highest-value to repeat in every D3 brief.

---

## 2026-06-26 — D4-G: IJFS daily orchestration engine   (implementer: direct)

**What would you do differently (implementer = orchestrator, self-retro):**
- **Bypassed opencode deliberately.** D4-G is the integration layer — it threads a single `Dice`
  through six phases in a fixed draw order. Fidelity here is all-or-nothing and failures are subtle
  (a reordered phase still runs green on structural tests but silently diverges from the oracle).
  That's the worst possible task for the weak free model. Implementing directly was the right call;
  the cost was ~all of the session's reading budget spent pinning exact signatures first. Next time,
  front-load the signature sweep (grep `static func` across the libs in one pass) before writing any
  brief — I did, and it paid off.
- **GDScript Variant type-inference bites `:=`.** `var is_organic := mun != null and mun.category == …`
  failed to compile ("can't infer type") because `mun` is `Variant`. Any `:=` whose RHS touches a
  `Variant` member needs an explicit `: bool`/`: String`. Cost one compile cycle. Brief every future
  port: when porting Python duck-typed locals, annotate the type explicitly.
- **GdUnit captures engine `push_error`/`push_warning` as stack traces but does NOT fail the test.**
  The synthetic dedup test logged a line-158 trace (AD-health "no Moveable SAMs" warning + minimal-
  scenario strike noise) yet PASSED. I nearly misread the truncated first run as a failure. Always
  read the `Statistics:`/`Overall Summary` line, not the inline traces, to judge pass/fail.
- **Doc drift caught during verify:** PLAN.md still showed D4-F unchecked (it was committed in
  e20c582) and prior notes claimed "238 / 210 cases". The real GdUnit count is 124 (= `grep -c
  'func test_'`); the inflated numbers counted assertions. Trust `Overall Summary`, not prose.
- **`carry_to_next_day` is the fragile seam.** It hand-reproduces `loaders.load_targets`'s reload
  reset. If TIV ever changes which fields reset on reload, this silently diverges with no test
  linking the two. Under-tested: I assert suppression clears + destroyed persists, but not the full
  field-by-field parity against a real loader roundtrip.

**Orchestrator triage:**
- Bypass opencode for integration-heavy sub-tasks → **record only**: same call will apply to D4-H's
  RNG-sensitive writeback; revisit for D3-B…E (more mechanical, opencode-suitable).
- Variant `:=` annotation → **act now (done)** + **brief forward**: add to the standing D3 brief
  checklist alongside the ScriptedDice/key-shape items.
- GdUnit traces ≠ failures → **record only**: verification-reading guidance, already internalized.
- D4-F checkbox + case-count prose → **acted now**: ticked D4-F/D4-G in PLAN.md; corrected the
  count to 124 in the Decisions log.
- `carry_to_next_day` parity gap → **act later (→ backlog)**: when D4-H persists IJFS state on
  `GameState` across turns, add a continuity test that roundtrips through `IjfsLoaders` and asserts
  field-by-field parity with `carry_to_next_day`. Cross-link `PLAN.md 2026-06-26 D4-G`.

---

## 2026-06-26 — D4-H: IJFS GameState wiring + writeback   (implementer: direct)

**What would you do differently (self-retro):**
- **The RNG-isolation trap was the whole ballgame.** `ScriptedDice.derive()` returns `self` (shared
  queue), so naively doing `dice.derive("ijfs")` inside `resolve_turn` would have silently drained
  the scripted combat rolls in ~10 combat suites — green-looking until casualty asserts shifted. I
  caught it by checking how the combat tests call `resolve_turn` *before* wiring, not after a red
  gate. Lesson: whenever a new phase joins a shared `dice` pipeline, audit every caller's dice *type*
  first. The dice-type-aware branch (SeededDice→derive, else fresh SeededDice) is the durable fix.
- **The handoff's "(TO,Type)" spec outran the data.** The brief assumed targets carry a theater and
  battalion IDs; they don't. Rather than invent fake `to_number`s to satisfy the spec, I keyed the
  writeback by Type and logged an Open Question. Lesson: when porting a writeback, grep the *actual*
  data for the join keys before trusting the spec's shape.
- **Performance: IJFS now runs a full ~150-target pass on every `resolve_turn`.** That added ~6s to
  the suite (two GdUnit combat suites jumped to ~3.7s each). Acceptable now, but it's pure overhead
  in unit tests that don't care about IJFS. If the suite gets slow, gate IJFS behind a flag or cache
  the loaded `IjfsDailyState` statically across resets.
- **Integration coverage lives in a validator, not GdUnit** (per the teardown-flake rule), so the
  GdUnit count stayed at 124 — `tools/validate_headless_ijfs.gd` carries the day1/determinism/
  continuity/observation assertions. Right call, but it means the headline "what changed" isn't
  visible in the GdUnit number; the validator phase is where D4-H is actually tested.

**Orchestrator triage:**
- Dice-type isolation audit → **acted now** + **brief forward**: add "audit every `resolve_turn`
  caller's dice type before adding a phase" to the standing checklist; same caution applies to any
  future phase that joins the turn pipeline.
- Spec-vs-data join keys → **acted now**: keyed by Type + logged `PLAN.md` Open Question (D4-H
  writeback linkage) for D3 to resolve.
- IJFS per-turn cost → **act later (→ backlog)**: if gate runtime becomes a problem, cache the
  loaded IJFS data statically or make the phase opt-out for pure combat unit tests.
- Validator-not-GdUnit coverage → **record only**: expected per the project's testing rule.

---

## 2026-06-26 — D3-A: anti-ship data + models   (implementer: direct)

**What would you do differently (self-retro):**
- **Copy beats transcribe for tuning data.** The 5 TIV anti-ship configs are ~30KB of interdependent
  numbers (escort interception, lethality, ship profiles, magazines). Copying them verbatim into
  `data/antiship/` (then loading as Dictionaries) is the only safe move — hand-normalizing to
  snake_case like D1-A did for beaches would have been a transcription-bug minefield for zero benefit
  since D3-B consumes them as opaque config. Lesson: normalize *structural* data you'll model; copy
  *tuning* data you'll just read.
- **The grouping spec is the row source, not the catalog.** I almost modeled rows off
  `antiship_systems_consolidated.json` (the type catalog) before noticing its own note: "TOs block
  removed; row generation owned by defaults_loader + grouping spec." The real quantities live in
  `antiship_grouping_spec.json` as index-aligned `group_sizes[]`/`to_assignments[]`. Always read the
  data files' own `notes` array first — TIV documents its schema there.
- **Aggregation vs. container fidelity.** TIV keeps per-container rows ("Option B-lite"); I aggregated
  by (TO, type_id) because the firing plan keys on (TO, Type). This is a deliberate simplification —
  if D3-B ever needs per-container granularity (e.g. per-platform magazines), it'll have to re-read
  the grouping spec. Flagged in the Decisions log.
- **Data lacked beach names until I used the right key.** TIV `beaches.json` uses `Name_En` (not
  `Name_EN`); my first minefield export got blank names. Generating data via a script + immediately
  printing a sample caught it in one cycle — worth doing for every data port.

**Orchestrator triage:**
- Copy-vs-transcribe heuristic → **brief forward**: add to the D3 sub-task briefs (D3-C mine warfare
  will face the same choice).
- Read data `notes` first → **record only**: general data-port discipline.
- Aggregation simplification → **act later (→ watch)**: revisit only if D3-B needs per-container state.
- Verify generated data with a printed sample → **record only**: already standard practice here.

---

## 2026-06-26 — D3-B1: anti-ship magazine service (D3-B split)   (implementer: direct)

**What would you do differently (self-retro):**
- **Size the sub-task from the source, not the plan.** PLAN.md listed D3-B as one lib (firing plan +
  crossing + magazine). Reading the oracle showed ~2,100 lines with a hard dependency chain — the
  firing-plan pytests both require the magazine reservation context, so "firing plan first" was
  impossible. Re-deriving the real dependency order (magazine → firing plan → crossing) up front and
  splitting B1/B2/B3 saved a false start. Lesson: for big phases, read the pytests' imports first —
  they reveal the true coupling.
- **Port the pure core, drop the DB shell.** The magazine service interleaves pure reservation math
  with sqlite seed/load/persist. Only the pure part is the slice; copying the DB functions would have
  added untestable, irrelevant code. Clean cut at the conn boundary.
- **GDScript stability + integer-division gotchas, again.** Python's `sorted(key=-is_primary)` is
  stable; GDScript `sort_custom` is not — used an explicit primary-then-secondary partition. And the
  aircraft-pool cap is `count // mpl` (floor) — needs `@warning_ignore("integer_division")`. Both are
  recurring GDScript-port hazards now worth a standing checklist item.
- **Single source of truth for data.** Python keeps a `_DEFAULTS` constant "in sync with" the JSON;
  the GDScript port seeds straight from `antiship_magazine_defaults.json` (no duplicated constant),
  so there's nothing to drift. Better than the source here.

**Orchestrator triage:**
- Size-from-source + read-pytest-imports → **brief forward**: apply to D3-B2/B3 and any large port.
- Pure-core/DB-shell cut → **record only**: standard for this DB-free port.
- Stability + integer-division hazards → **act now (done)** + **brief forward**: add to the GDScript
  port checklist alongside ScriptedDice/Variant-`:=`/key-shape items.
- JSON-as-single-source → **record only**: keep doing it.

---

## 2026-06-27 — D3-B2: anti-ship firing plan   (direct)

**What would you do differently (self-retro):**
- **Read the pytest imports first — confirmed the B1 lesson paid off.** `test_antiship_firing_plan.py`
  imports `MagazineReservationContext` and exercises it in both cases, so the D3-B1-first split was
  the right call; B2 dropped straight onto the existing `AntishipMagazine`. Reading the two pytests
  before coding gave the exact, minimal behavior contract (shared-pool-once, full-volley-gates-before-
  row-split) and saved guessing at the larger calculator's surface.
- **The DataFrame `systems_expended` copy is a pandas artifact, not real semantics.** TIV's
  `build_firing_plan` returns a mutated-column copy purely so `resolve_launch_attrition` can write
  back by `row_idx`. Porting that literally would mean cloning every `AntishipSystem`. The faithful
  call is: `build_firing_plan` pure, `resolve_launch_attrition` mutates the rows in place by index.
  Lesson: distinguish source behavior from its pandas plumbing before porting.
- **Tuple-keyed dicts are a recurring port hazard.** Three of the inputs key on `(location, type)`
  tuples; GDScript Dictionaries silently misbehave with Array keys (reference identity), so a String
  encoding (`"<to>:<type>"`) is mandatory and must be applied consistently across every map plus the
  summary-ordering decode. Worth a standing checklist item next to ScriptedDice / integer-division.
- **Under-tested:** only single-row `(TO,type)` allocation is exercised through `build_firing_plan`
  (HexCombat pre-aggregates), so the multi-row largest-remainder path is covered by a *direct*
  `allocate_firing_to_rows` unit test only. If D3-D ever feeds un-aggregated rows, that path needs an
  integration test. Also: the launch-attrition summary's destroyed-only-key ordering relies on
  `_decode_key` assuming int type-keys — fine for current data, fragile if non-numeric types appear.

**Orchestrator triage:**
- Tuple-key → String-encoding hazard → **act now (done)** + **brief forward**: added to the GDScript
  port checklist (ScriptedDice / Variant-`:=` / integer-division / stability / **tuple-key encoding**).
- DataFrame-copy-vs-semantics → **record only**: standard for this pandas→GDScript port; the pure
  build + in-place resolve split is the pattern for D3-B3/D3-C too.
- Multi-row allocation under-tested → **act later** (→ revisit in D3-D wiring): if GameState passes
  un-aggregated rows, add an integration case; today's aggregation makes it single-row.
- Gate teardown flake (`-1073741819` in random SceneTree validators) → **record only / watch**:
  pre-existing Godot 4.7 instability, not introduced here; all test cases pass every run and flagged
  validators pass deterministically in isolation. Same class as the 2026-06-24 GdUnit teardown flake.

---

## 2026-06-27 — D3-C: mine warfare (geometry-free)   (direct)

**What would you do differently (self-retro):**
- **Read the RNG seeding before estimating effort.** The handoff billed D3-C as "more mechanical /
  opencode-suitable," but the oracle uses Python's *string-seeded* Mersenne Twister twice (mine
  geometry + ship-type draw) — neither reproducible in Godot. That turns a "mechanical port" into a
  *scoping decision* (port the geometry with a different RNG, or drop it). Recognizing the danger
  radius spans the whole beach in the test configs (so dangerous==num_mines regardless of positions)
  is what made "drop the geometry" provably behavior-preserving for the mirrored cases. Lesson:
  grep the oracle for `random.Random(` / string seeds *first* — it decides portability and scope.
- **Let the existing model tell you the intended scope.** `Minefield.gd` (from D3-A) already carried
  exactly the simplified runtime fields (remaining/dangerous/swept/lane_cleared/ships_destroyed) and
  *none* of the geometry (Length/Width/Danger_Radius/Entry/Angle). The model was the spec — the
  geometry-free port was the pre-decided intent, not a fresh call.
- **Fragile/under-tested:** with the geometric filter gone, lethality is "1 unswept mine = 1 hull,"
  so the D3-A 100-mines/beach defaults could wipe a fleet if D3-D feeds them un-swept. The slice is
  correct but the *tuning* is untested and likely too lethal — explicitly flagged for D3-D. Also the
  same-day-rerun idempotency is genuinely gone (not just untested); if a future UI ever re-previews,
  it must re-resolve from saved state, not re-call this.

**Orchestrator triage:**
- grep-for-string-RNG-before-scoping → **brief forward**: add to the port checklist next to the
  tuple-key / integer-division / ScriptedDice items; it's the deciding factor for any DB/UI-heavy
  TIV service.
- Geometry-free lethality / tuning → **act later** (→ D3-D): when wiring `resolve_antiship_turn`,
  sanity-check ship losses vs. fleet size and tune sweeper supply / mine counts if a single turn
  annihilates the crossing fleet. Recorded in PLAN.md Decisions (balance note).
- Same-day-rerun dropped → **record only**: justified by the single-resolution action layer;
  re-evaluate only if a re-preview UI lands (Track C).

---

## 2026-06-27 — D3-B3: anti-ship crossing model (count-based)   (direct)

**What would you do differently (self-retro):**
- **Trace which functions the entrypoint actually calls before porting the whole file.** 941 lines,
  but `resolve_crossing_damage` calls the *per-hull* interception/damage variants — the count-based
  `_apply_interception`/`_apply_terminal_defense`/`_resolve_damage` are dead code kept from a prior
  iteration. Recognizing that the per-hull path needs a ship-ammo/readiness subsystem HexCombat
  lacks, *and* that the count-based twins reproduce every pytest assertion, collapsed a daunting port
  into a tractable one. Lesson: read the entrypoint's call graph first; a big file is often two code
  paths and you only need one.
- **Confirm the test assertions don't depend on the dropped layer.** The deciding evidence for
  "count-based is faithful" was checking each pytest: escort `attempts`/`success_prob` are set high
  enough that per-hull magazine limits never bind, and the damage assertions are structural
  (ranges/sums) or deterministic regardless of seed (e.g. neut=1.0 → exactly `capacity` sinks). Two
  cases (`damage_capped`, `damaged_rehit`) are fully seed-independent — worth designing the GDScript
  mirrors around those so they're not flaky under a different PRNG.
- **Keep the lib pure by injecting theater data.** `_reachable_tos` uses module-level
  ACTIVE_TOS/TO_ADJACENCY in TIV; reaching for HexCombat's `Theaters`/`GameData` autoload would have
  made the lib un-unit-testable. Passing `active_tos`/`to_adjacency` as defaulted params kept it a
  pure RefCounted and let the real-catalog test feed `theaters.json` directly.
- **Fragile/under-tested:** the per-hull escort-magazine depletion is genuinely gone (Open Question
  logged), so multi-day escort ammo attrition isn't modeled — escorts intercept at full strength
  every turn. Also, because RNG draw-order matches formulas but not Python's bitstream, the
  destroyed/damaged *split* values aren't asserted exactly (only that both occur) — a regression that
  shifted the split would pass. The deterministic-outcome cases + reconciliation invariants are the
  real guardrails.

**Orchestrator triage:**
- Call-graph-before-port → **brief forward**: standard for any large TIV service; add to the port
  checklist (read entrypoint → identify live path → check pytest coupling).
- Per-hull escort magazines deferred → **act later** (→ Open Question logged): additive swap if ship
  ammo is ever modeled; the count-based stage seams are isolated.
- RNG-bitstream divergence (split not exactly pinned) → **record only**: inherent to the
  formula+draw-order strategy (AGENTS.md); reconciliation invariants + deterministic cases cover it.
- Inject-theater-data-for-purity → **record only**: good pattern; reuse for any lib that would
  otherwise reach the GameData autoload.

---

## 2026-06-27 — D3-D: anti-ship GameState wiring + BN↔ship mapping + C2 suppression   (direct)

**What would you do differently (self-retro):**
- **Surface the balance question with a measurement, not a guess.** The crossing was catastrophic
  (33/36 BNs lost turn 1). The instinct was to treat it as a wiring bug; the right move was to confirm
  the reconciliation (BNs removed == bns_lost_at_sea == pending) was *correct* and surface it to the
  user as a **balance finding**, which kicked off the whole calibration dialogue. A tiny measurement
  script (`resolve_ijfs → resolve_antiship`, dump systems_fired + bns_lost + which TOs had C2
  suppressed) was worth more than any amount of staring at the firing loop.
- **Model the real granularity before tuning probabilities.** Two wrong turns chasing lethality: (a)
  expanding aircraft to 334 individual targets spread IJFS strikes too thin (41% suppressed) — TIV
  models them as 18 operating *bins*; restoring container granularity got it to ~72%; (b) raising
  aircraft `detectability_hiding` to "high" to push suppression — reverted, because strike *capacity*,
  not detection, was the limiter. Lesson: match the source's unit-of-account first; only then tune.
- **Find the structural cause of a mechanic's non-effect.** The C2 lever is correct and unit-tested,
  but it doesn't move the golden scenario because the IJFS suppresses TO4/TO5 C2 while the wave
  assaults TO3. That's not a bug — it's an emergent targeting gap. Worth stating explicitly in the
  Open Question so the next loop doesn't "fix" a working mechanic.
- **Fragile/under-tested:** per-turn magazines are rebuilt full each turn so they never bind (logged
  in the wiring comment) — cross-turn magazine state is unimplemented; the suppressed-systems "carry
  to next turn" is effectively re-derived from the IJFS writeback each turn rather than persisted on
  the systems; and the crossing lethality itself is unbalanced (Open Question). The reconciliation +
  determinism + C2-reduces-firing validators are the guardrails that *are* solid.

**Orchestrator triage:**
- Measurement-over-guess for balance → **brief forward**: when a wired phase produces an extreme
  outcome, first prove reconciliation, then measure and surface — don't assume wiring bug.
- Container granularity (TIV operating bins) → **acted now**: reworked aircraft + all platform groups
  to per-container IJFS targets (decision 1-A); committed. Detectability tweak reverted.
- Crossing lethality unbalanced → **act later** (→ Open Question "D3-D crossing lethality
  calibration"): surfaced to the user; the candidate levers (assault-TO C2 targeting, fire-%/range,
  cross-turn magazines) are design calls for the next loop / the user.
- Cross-turn magazine state + persisted suppression flag → **act later** (→ noted in `GameState`
  wiring comment + Open Questions): additive once a persistent per-turn anti-ship state seam exists.

---

## 2026-06-27 — D3-D balance: multi-day IJFS + screen targeting   (implementer: opencode deepseek-v4-flash-free)

Two self-contained briefs (Part A: screen-preferential homing in `AntishipCrossing`; Part B:
multi-day pre-invasion IJFS + cumulative writeback in `GameState`). Part A given as goal+constraints;
Part B given as exact before/after code blocks (intricate, RNG/validator-sensitive). Both came back
matching spec on the first pass; orchestrator verified the gate independently (the implementer's
"pre-existing GdUnit crash" claim was the real Godot 4.7 teardown flake — confirmed by isolation runs).

**What would you do differently (implementer):**
- `PRE_INVASION_IJFS_DAYS = 4` and `screen_target_preference = 3.0` are tuning knobs that live in
  source / a config key, not in scenario data — a designer can't vary the campaign length per scenario
  without editing code, and the validators don't exercise the data path.
- The cumulative anti-ship writeback now depends on `IjfsEngine.carry_to_next_day` preserving
  `target.destroyed`, but no test asserted it — a regression there would silently zero out attrition.
- `_compute_ijfs_writeback(ledgers)` reads `ijfs_state.targets` as a side effect while its signature
  advertises only `ledgers` — a contract smell; rename/repass or split the anti-ship scan out.
- In-place mutation of the persistent `antiship_systems` array means a read-only validator that calls
  `resolve_antiship_turn` mutates state the real game would later read.
- The `original_quantity - killed` decrement is correct **only** because the writeback reports a
  cumulative TOTAL; a future switch to incremental deltas would silently double-charge losses.

**Orchestrator triage:**
- No test for the cumulative writeback → **acted now**: added `_validate_cumulative_ijfs_attrition`
  to `validate_headless_antiship.gd` (writeback destroyed reconciles with an independent recount of
  destroyed containers' `systems_represented`, and is > 0). Catches the carry_to_next_day regression.
- "TOTAL not per-turn delta" invariant + side-effect read → **acted now**: invariant comments added
  at `_compute_ijfs_writeback` and the decrement site, noting the read of `ijfs_state` is deliberate
  (cumulative state spans multiple `run_daily` days).
- In-place `antiship_systems` mutation → **record only**: the idempotent `original_quantity - killed`
  rewrite makes `resolve_antiship_turn` self-resetting w.r.t. IJFS kills each call, so the validator-
  corrupts-game-state concern is largely mitigated; a full `_rebuild_antiship_systems()` reset is a
  later cleanup if a non-resetting caller appears.
- Knobs in source/config not scenario data → **act later** (→ Open Question "D3-D crossing lethality
  calibration"): move `PRE_INVASION_IJFS_DAYS` + `screen_target_preference` into scenario/config when
  the crossing is tuned for real; until then the const + config key are the tuning surface.

---

## 2026-06-27 — D5-A: FrontLineService (polyline → hex sequence)   (implementer: opencode deepseek-v4-flash-free; refactor: 2nd opencode session)

Port brief (pure lib + tests, end with a retrospective) → orchestrator triage → a 2nd opencode
subagent implemented the one approved refactor. Both gated independently by the orchestrator.

**What would you do differently (implementer):**
- `find_hexes_for_polyline` baked the polyline sampling into the hex-lookup loop; D5-B (wiring) and
  D5-C (draw UI) both need the raw sampled points, so the sampling should be its own helper.
- `point_to_hex` is an O(N) haversine scan rebuilt every call — fine at game tick, but a redrawn
  polyline × hundreds of centers is many calls; a spatial index / parallel packed arrays would cut it.
- `distribute_units_along_hexes` silently tolerates duplicate `unit_ids` / non-deduped `hex_sequence`
  and extreme N≫M ratios; a guard would surface bad callers.
- Linear lat/lon interpolation during sampling (faithful to TIV) makes `sample_interval_km` only
  approximate in real km at higher latitudes — fine for the game, worth a caller note.
- The flat `Array[{id,lat,lon}]` hex-center shape diverges from GameData's `Hex` Resources, so D5-B
  needs a translation adapter — keep it in GameState; do NOT make the lib depend on GameData.

**Orchestrator triage:**
- Extract `sample_polyline` → **acted now (2nd subagent)**: added `sample_polyline(coords, interval)`
  returning the ordered sampled `Vector2`s; `find_hexes_for_polyline` now consumes it with a
  regression test proving identical output. Helps D5-B/C reuse the sampling.
- O(N) `point_to_hex` micro-opt → **rejected / record only**: premature optimization; the scan is
  trivial at game tick and a spatial index adds complexity with no measured need.
- `distribute_units_along_hexes` ratio/dupe warning → **rejected / record only**: the threshold is
  arbitrary and would be noisy; empty inputs are already handled; dupe-free input is a caller contract.
- Linear-interp sampling caveat + flat-hex adapter → **record only / brief forward to D5-B**: faithful
  port; the GameData→flat-hex adapter is D5-B's job and must stay out of the pure lib.

---

## 2026-06-27 — D5-B: front-line GameState wiring   (implementer: opencode deepseek-v4-flash-free)

Wiring brief (GameState method + adapter + EventBus signal + headless validator, end with a
retrospective). Orchestrator gated independently (validator + full gate green, golden byte-stable).

**What would you do differently (implementer):**
- `_frontline_hex_centers()` rebuilds the 455-entry centers array every call; fine once-per-turn but a
  D5-D drag-preview that calls it per frame would want it pre-built (hexes are static after load).
- Red-only repositioning is hardcoded (`Brigade.Team.RED`); intentional and faithful to TIV's
  single-side filter, but undocumented it reads like a bug — and if Green ever draws lines it needs a
  team parameter.
- Turn integration (D5-D) must decide *when* the front-line fires in the resolve_turn sequence; since
  it's a player-drawn polyline it has to be a PLANNING-phase action stored on GameState and executed at
  the right point, not auto-sequenced — a new data structure the wiring doesn't yet have.

**Orchestrator triage:**
- Red-only asymmetry → **acted now (inline, orchestrator)**: added a comment documenting the
  intentional single-side filter + the `team`-parameter extension point. Too small to commission a 2nd
  subagent.
- Pre-cache `_frontline_hex_centers()` → **rejected / deferred (→ D5-D)**: the phase runs once per
  turn, not per frame; pre-caching adds state to keep in sync for no current benefit. Revisit only if
  D5-D adds a live drag-preview loop.
- PLANNING-phase action plumbing for turn integration → **record only / brief forward to D5-D**: real
  and correct, but it's D5-D's scope (UI + turn sequencing), not this headless wiring step.

---

## 2026-06-27 — D5-C: cleanup phase (end-of-turn system reset)   (implementer: opencode deepseek-v4-flash-free)

Port brief (GameState method + EventBus signal + validator + resolve_turn hook, end with a
retrospective). Orchestrator corrected the ROADMAP's mis-scoping first (cleanup is a flag reset, not
attrition/isolation), gated independently (validator + gate green, golden byte-stable), fixed a
"D2-C"→"D5-C" header typo inline.

**What would you do differently (implementer):**
- The hook position (between `resolve_supply_turn` and `phase = Phase.END`) is positional/brittle — a
  `Phase.CLEANUP` enum state with explicit `phase_changed` emissions would make the ordering contract
  visible rather than implicit.
- Cleanup resets only anti-ship flags; nothing guards a future contributor to `antiship_systems` who
  forgets to extend the reset (the validator checks the current fields but can't know about new ones).
- End-of-turn resets are now split across three sites (`begin_next_turn` = brigade flags + turn
  advance; `resolve_cleanup_phase` = anti-ship flags; `carry_to_next_day` = IJFS per-day flags); one
  canonical reset point would be cleaner.

**Orchestrator triage:**
- `Phase.CLEANUP` enum state → **rejected / record only**: the positional hook works and is commented;
  adding a phase state touches the phase machine + observation `phase` strings for low value.
- Merge brigade-flag reset into cleanup for one canonical point → **rejected / record only**: the
  implementer itself flagged the risk — `begin_next_turn` runs in PLANNING and also does
  `turn_number += 1` / buffer-clearing; merging would drag that into cleanup. Real churn, real risk,
  little benefit while the reset set is this small. Revisit only if end-of-turn resets grow.
- Guard against forgotten future resets → **record only**: the validator already asserts the cumulative
  fields are NOT touched; a "new field" guard isn't expressible without reflection.

---

## 2026-06-28 — play_turn-facade: headless turn façade + state snapshot   (implementer: opencode deepseek-v4-flash-free)

Track E AI-readiness seam (the deferred `GameState.play_turn(...) -> TurnResult` + `GameData.snapshot_state()`
flagged across `REFACTOR_NOTES.md` M3/M5c/M6). Brief: typed `TurnResult` Resource + a pure orchestration
façade over `resolve_turn` + a deterministic snapshot + a validator proving byte-identical behavior to the
hand-rolled `validate_headless_turn` sequence. Gated independently (validator PASS; full gate ALL PHASES
GREEN; golden 20260624 → casualties=2, feba=0.76 byte-stable). The implementer also pre-applied its own
point #6 (unknown-`kind` `push_error` fallthrough) before reporting.

**What would you do differently (implementer):**
1. `TurnResult` is a flat mirror of the `last_*` fields with untyped `Array`/`Dictionary` payloads
   (`combat_summaries`, `ijfs_writeback`); the next seam (per-turn structured event log) would be easier if
   it carried a typed `Array[TurnEvent]` instead of opaque dicts.
2. `play_turn` shouldn't auto-advance (correct) — but every caller must remember `begin_next_turn()`; a
   `play_full_turn_and_advance()` convenience belongs on `LLMGameAPI`, not `GameState`.
3. `snapshot_state()` is GameData-only; a `GameState.snapshot()` superset (turn_number, orders, ship_reserve,
   `last_*`) would be the right shape for resumable/journaled games.
4. The validator is a single datapoint (one seed/scenario); a second hex/brigade combo or varied order count
   would harden it.
5. No error-path test — `play_turn` returns `null` outside PLANNING / on bad input, but that contract was
   untested; an AI driver calling it in the wrong phase would get a silent null.
6. `_apply_order` defaulted unknown `kind` to "move" (a typo'd kind would silently move) — fixed to a
   `push_error` fallthrough in-session.

**Orchestrator triage:**
- #5 error-path test → **ACTED NOW (inline):** the contract is the whole point of a fail-loud façade and the
  test is ~4 lines. Added a wrong-phase `play_turn([],[],…)` → assert `null` case to `validate_play_turn.gd`
  (the prior `play_turn` leaves the machine in `Phase.END`; the emitted `push_error` is harmless — the gate
  only fails validators on the two-word "SCRIPT ERROR"). Re-gated green. Did it inline rather than via a 2nd
  opencode session — below the threshold where the free model adds value and SceneTree assertion structure is
  easy to botch (per CLAUDE.md "implement it yourself" for too-small tasks).
- #1 typed per-turn event log → **PROMOTED to the next backlog unit** (`PLAN.md` Decisions 2026-06-28 +
  ORCHESTRATOR_HANDOFF §6). It's the natural next Track E step and `TurnResult.to_dict()` is already the
  serialization bridge it will extend.
- #2 `play_full_turn_and_advance()` on `LLMGameAPI` → **record / act later:** real convenience, fold into the
  AI-driver loop when it lands; keeping `GameState` minimal is correct now.
- #3 GameState-superset snapshot → **record / act later (persistence track):** not needed until save/replay;
  the GameData-only snapshot is exactly right for the current byte-comparison gate.
- #4 second validator datapoint → **record only:** snapshot-equality against the gate-trusted oracle is
  already a strong proof; revisit if `play_turn`'s order-iteration logic grows.
- #6 unknown-`kind` guard → **already applied by the implementer** (verified in the diff).

---

## 2026-06-28 — turn-event-log: per-turn structured event log (TurnEvent)   (implementer: opencode deepseek-v4-flash-free)

Second Track E AI-readiness seam (REFACTOR_NOTES.md M5b/M6 + the play_turn retrospective's #1). Brief:
typed `TurnEvent` Resource + a pure `TurnEventLog.build(state) -> Array[TurnEvent]` deriving an ordered
turn trace from the data `resolve_turn` already stores, populated into `TurnResult.events` by `play_turn`.
Explicit constraint: non-invasive (read stored state only) so the golden invariant stays byte-stable.
Gated independently (validator PASS; full gate ALL PHASES GREEN; golden 20260624 → casualties=2, feba=0.76
byte-stable).

**What would you do differently (implementer):**
1. `kind` as String vs typed enum — String is fine at the JSON/AI serialization boundary; refactor to an
   enum only when the event log becomes a first-class persistence format with a second consumer.
2. One combat rollup event vs per-casualty/per-FEBA/per-ownership sub-events — rollup is correct for the AI
   observation surface; `data` already nests `combat_detail` with the full casualty breakdown, so finer
   granularity is derivable without splitting. Premature to split now.
3. Deriving move/commit from the buffered orders is intentionally fragile — it forces consumption of
   `result.events` before `begin_next_turn()` clears the buffers; a future path that advances first would
   silently drop the moves. Alternative (snapshot orders into TurnResult during play_turn) duplicates state.
4. Surface the event log through `LLMGameAPI` next — appending `"events"` to the observation/action result
   gives LLM agents a structured turn trace without parsing combat summaries; `TurnEvent.to_dict()` makes it
   trivial. Highest-impact next step.
5. For save/replay journaling: add `to_line()`/`from_line()` (flat + JSON-encoded `data`) and a per-event
   `turn_number` so a flat multi-turn journal reconstructs without the TurnResult wrapper.

**Orchestrator triage:**
- #3 ordering dependency → **ACTED NOW (inline):** the dependency is fully contained inside `play_turn`
  (it builds the log immediately after `resolve_turn`, before any advance), so it's not externally
  exposed — but added a docstring to `TurnEventLog.build` documenting that move/commit read the still-buffered
  orders and the call must precede `begin_next_turn` if ever moved. Comment-only; re-ran the validator (PASS).
- #4 surface through `LLMGameAPI` → **PROMOTED to the next backlog unit** (`PLAN.md` Decisions 2026-06-28 +
  ORCHESTRATOR_HANDOFF §6). Natural next Track E step; `to_dict()` is the ready serialization bridge.
- #1 enum `kind` → **record only:** keep String at the boundary; revisit on a second consumer.
- #2 per-casualty sub-events → **record only:** rollup + nested `combat_detail` is sufficient; split only if a
  granular replay/attribution consumer appears.
- #5 `to_line`/`from_line` + per-event `turn_number` → **record / act later (persistence track):** cheap and
  genuinely useful for flat journals, but premature without a save/replay consumer.

---

## 2026-06-28 — llm-event-surfacing: surface event log + TurnResult through LLMGameAPI   (implementer: opencode deepseek-v4-flash-free)

Third Track E AI-readiness seam (the event-log retrospective's #4). Brief: route apply_agent_response's
end_turn through play_turn, thread turn_result.to_dict() into the action result, add an export tool +
regenerate the result fixture, extend the validator. Pure wiring over already-tested seams (play_turn /
TurnResult / TurnEventLog). Gated independently (validate_llm_api PASS; full gate ALL PHASES GREEN; golden
20260624 → casualties=2, feba=0.76 byte-stable; committed fixture confirmed byte-identical to a fresh
tool regeneration).

**What would you do differently (implementer):**
1. `turn_result` in the action result is the right home — observation = current/forward state, turn_result =
   transient "what happened"; separate keys keep semantics clean and avoid bloating the observation.
2. There should be a `hexcombat.llm_action_result` JSON Schema file (the observation + action_response already
   have schemas under res://schemas/); the result now has a structured `turn_result` worth self-documenting.
3. Regenerating the 1300-line fixture by hand-running a tool is fragile — most of the diff is hex-list noise.
   The validator already applies in-memory; the committed fixture is only human-readable documentation. Could
   commit a small hand-trimmed example instead, or generate in CI rather than commit the full blob.
4. Next AI-driver conveniences: a `current_player` observation field, a `game_over`+`winner` field, and a bulk
   `submit_and_resolve(red_orders, green_orders, seed)` endpoint (play_turn already takes bulk arrays).

**Orchestrator triage:**
- #2 result schema file → **PROMOTED to the next backlog unit** (`PLAN.md` Decisions 2026-06-28 +
  ORCHESTRATOR_HANDOFF §6). Real contract-consistency gap, cleanly bounded, mirrors the existing observation
  schema pattern, zero golden risk. Did NOT rush it inline — a faithful schema is its own unit of work.
- #1 turn_result home → **record only** (confirms the design).
- #3 fixture fragility → **record only:** the fixture is tool-generated + byte-verified and the validator
  already gates via in-memory application; the committed blob is documentation. Removing/trimming it is a
  separate doc-artifact decision, not a defect. Logged as a known tradeoff.
- #4 AI-driver conveniences → **split:** `game_over`/`winner` requires defining VICTORY CONDITIONS, which is
  new game-design, NOT a faithful TIV port — that must go to the user as a design call, not an autonomous
  unit. `submit_and_resolve` is a thin play_turn wrapper + `current_player` is a small observation add; both
  recorded as later low-risk conveniences once the schema unit lands.

---

## 2026-06-28 — llm-result-schema: llm_action_result JSON Schema + schema-driven key gate   (implementer: opencode deepseek-v4-flash-free)

Fourth Track E AI-readiness seam (the llm-event-surfacing retrospective's #2). Brief: add the missing
schemas/llm_action_result.schema.json + a schema-driven key conformance check in the validator. Documentation
+ validation only; zero game-logic change. Gated independently (validate_llm_api PASS; full gate ALL PHASES
GREEN — flake-free this run; golden 20260624 → casualties=2, feba=0.76 byte-stable).

**What would you do differently (implementer):**
1. No real JSON-Schema validation engine — the schemas are parse-checked JSON but never actually validate
   documents; GDScript re-lists required keys. Vendoring a GDScript JSON-Schema validator (or a Python
   jsonschema test harness) would catch type/structural drift, not just key absence.
2. Duplicated key lists (REQUIRED_RESULT_KEYS mirrors the schema's `required`) are a DRY/drift risk; the
   sorted-set cross-check mitigates it but the validator could instead parse the schema's `required` at runtime
   and use it directly, eliminating the constant.
3. `additionalProperties:true` is too loose for an LLM contract — unknown top-level fields are silently valid;
   a stricter top-level (all fields enumerated, sub-objects loose) + a Python schema regression suite would
   catch real drift.

**Orchestrator triage:**
- #1 real schema engine → **record / later:** genuine value but it's a library/design decision (which engine,
  GDScript vs a Python test harness) and a unit of its own, not an inline fix.
- #2 parse schema `required` at runtime instead of a constant → **record only (rejected as inline change):**
  the cross-check between REQUIRED_RESULT_KEYS and the schema's `required` is the DELIBERATE drift guard —
  collapsing them to one source removes the very thing being checked; the duplication is intentional and
  matches the existing REQUIRED_OBSERVATION_KEYS pattern.
- #3 additionalProperties looseness → **record only:** consistent with the existing observation/action_response
  schemas; tightening all three is a broader contract decision, out of scope for this consistency-fill unit.
- **Arc note:** this closes the Track-E AI-readiness arc (play_turn → event log → LLM surfacing → result
  schema). Next autonomous-safe candidate is the `GameData.validate_runtime_indexes()` hardening guard
  (REFACTOR_NOTES M5a); `game_over`/`winner` victory conditions remain a user design call.

---

## 2026-06-28 — runtime-index-guard: GameData.validate_runtime_indexes() invariant guard   (implementer: opencode deepseek-v4-flash-free)

Data-layer hardening (REFACTOR_NOTES M5a). Brief: a read-only bidirectional brigades ↔ brigades_by_hex
consistency check returning Array[String] + a validator with a negative corruption test. Pure read-only; no
game-logic change. Gated independently (validator PASS incl. the __ghost__ negative test; full gate ALL
PHASES GREEN — flake-free; golden 20260624 → casualties=2, feba=0.76 byte-stable).

**What would you do differently (implementer):**
1. Run it automatically — a debug/PROFILE_BUILD-gated assert in set_brigade_hex/_add_brigade_to_hex (the only
   desync vectors) and at the end of resolve_turn (catches combat-path breakage), not just the one validator.
   O(N) per move is sub-ms at 143 brigades; worth it in debug builds, stripped in release.
2. Guard other indexes: hex_states vs hex_lookup coverage (low drift today — same populate loop), fleet vs
   ship_defs (ShipState.validate() already exists), ship_reserve brigade refs after destroy mutations.
3. Array[String] is right for the gate; add a sibling assert_runtime_indexes() that push_errors each violation
   for inline debug use (stack trace per violation) without coupling the two use cases.
4. Extract a reusable pattern: every container type gets validate_invariants() -> Array[String], GameData
   aggregates via validate_data_layer() gated by project settings — analogous to ShipState.validate().

**Orchestrator triage:**
- #1 auto-run assert → **RECORDED as the top follow-up; deliberately NOT acted on inline.** The value is real
  (continuous protection of the golden path), but injecting a new hot-path assert into resolve_turn/
  set_brigade_hex could turn currently-green GdUnit/validator suites red on any pre-existing benign transient
  desync — an unacceptable destabilization risk for an unattended overnight run. It's the right change to make
  deliberately, with attention to which gated scenarios it touches, not autonomously at 5am.
- #2 other-index guards → **record:** several are low-drift today (hex_states shares the populate loop; fleet
  has ShipState.validate()); fold into a validate_data_layer() aggregation when a third index needs guarding.
- #3 assert wrapper → **record** (pairs with #1).
- #4 reusable validate_invariants() pattern → **record:** good direction; extract once a third container needs
  it (YAGNI until then).

---

## 2026-06-28 — selfplay-harness: headless AI-vs-AI self-play regression gate   (implementer: opencode deepseek-v4-flash-free)

Track-E capstone. Brief: a gated validator that plays 4 turns through LLMGameAPI with a deterministic policy
and asserts full-game reproducibility + index health. Drives only existing tested APIs; no game-logic change.
Gated independently and THOROUGHLY (the riskiest unit so far): validator deterministic across two separate
Godot processes; full gate run TWICE → ALL PHASES GREEN both, golden 20260624 → casualties=2, feba=0.76
byte-stable both. The trivial policy drives combat in all 4 turns.

**What would you do differently (implementer):**
1. A gated multi-turn self-play validator is a good regression gasket (the per-turn determinism check is
   stronger than a single-turn test), but the trivial "first adjacent hex" policy doesn't stress admin moves,
   commitments, zero-org brigades, or stacking. A fuzzier (still deterministic) policy would be higher-value.
2. Extract the policy into a reusable `tools/policies/<name>.gd` (`static build_actions(observation)->Array`)
   so the validator is policy-agnostic and real agents/stress profiles plug in.
3. Add a `GameState.play_game(policy, turns, seed) -> {snapshot,digests,violations}` headless-driver
   entrypoint — the load_all/reset/loop bootstrap is now duplicated across three validators; DRY it.
4. Add `export_turn_log(game_result)` writing deterministic JSON-per-turn to reports/ for review — TurnResult.events
   already has the right structure, just needs a serialization helper.

**Orchestrator triage:**
- #3 `GameState.play_game(...)` entrypoint + #2 reusable policy helper → **PROMOTED to the next unit**
  (`PLAN.md` Decisions 2026-06-28 + ORCHESTRATOR_HANDOFF §6). Genuine DRY + the pluggable-policy seam a real
  agent-vs-agent mode needs. Scope note for the follow-up: add `play_game` + refactor the self-play validator
  to use it, but LEAVE `validate_headless_turn.gd` (the golden validator) untouched to avoid perturbing the
  golden assertion.
- #1 fuzzier policy → **record:** a deterministic-but-varied policy (occasional admin/stacking) would harden
  coverage; fold into the reusable-policy helper.
- #4 export_turn_log → **record (save/replay track):** pairs with the event log; defer until a replay/instrument
  consumer exists.
- **Arc note:** this caps the Track-E AI-readiness arc. After the `play_game` extraction the autonomous backlog
  is design-calls (calibration, victory conditions), blocked (UI, IJFS↔OOB linkage), or risky typed-model
  migrations — at which point the right move is a clean handoff, not manufactured work.

---

## 2026-06-28 — selfplay-runner: reusable runner + pluggable policy extraction   (implementer: opencode deepseek-v4-flash-free)

The agent-vs-agent foundation follow-up flagged by the selfplay-harness retrospective. Brief: extract the
self-play loop into scripts/SelfPlayRunner.gd + scripts/SelfPlayPolicy.gd and rewire the validator to use
them, LEAVING the golden validator untouched. Pure refactor; behavior preserved. Gated independently
(validator PASS twice cross-process, identical "combat in 4 turns"; full gate ALL PHASES GREEN — clean run;
golden 20260624 → casualties=2, feba=0.76 byte-stable).

**What would you do differently (implementer):**
1. The policy/runner split is at the right layer — runner at the LLMGameAPI adapter level keeps the dependency
   direction correct (GameState ← LLMGameAPI ← SelfPlayRunner); a real agent just implements
   build_actions(obs)->Array.
2. Expose hooks — a `resolve_turn(policy, seed)` mid-game entrypoint (caller owns the loop, can inspect state
   / detect early termination) on top of the fixed-horizon play_game.
3. Callable is the right plugin mechanism (idiomatic; no GDScript interface enforcement anyway); the gotcha is
   it must be a bound instance-method Callable, which is what we used.
4. A balance-sweep harness would want: the resolve_turn entrypoint, a stats accumulator (or just aggregate the
   returned turn_digests over N games across a seed range), parallel execution at scale, and an observation
   perturbation hook to inject balance tweaks while reusing the game flow.

**Orchestrator triage:**
- #1, #3 → **record (confirm the design):** the adapter-layer placement was an explicit orchestrator decision
  diverging from the retrospective's "GameState.play_game" precisely to avoid inverting GameState's
  dependencies (logged in PLAN.md Decisions 2026-06-28).
- #2 mid-game resolve_turn entrypoint + #4 balance-sweep machinery → **record as YAGNI-until-consumer:** real
  and sensible, but there is no balance-sweep / real-AI consumer yet, and a balance harness edges into the
  crossing-lethality CALIBRATION the user reserved as a design call. Building speculative hooks/sweep tooling
  unattended is exactly the "manufactured/risky work" the handoff guidance says to avoid.
- **Stop point:** this was the last clearly-safe, valuable, non-design autonomous unit with a real consumer.
  The orchestrator loop is stopping here with a clean handoff (ORCHESTRATOR_HANDOFF §6) — the remaining backlog
  is user design-calls, blocked items, YAGNI-without-consumer, or risky typed-model migrations.

## 2026-06-28 — D3-D: wire prelanding warmup (activate exquisite intel)   (implementer: opencode deepseek-v4-flash-free)

**What would you do differently (implementer):**
- `resolve_ijfs_turn` was the right seam (only caller of `run_daily`); a dedicated
  `_run_prelanding_warmup()` would own the same branch — not worth extracting at this size. The
  `_build_warmup_context` helper is the right factoring.
- `prelanding.days` (3) vs the old `PRE_INVASION_IJFS_DAYS` (4) caused no surprise — warmup-day count now
  comes from the scenario JSON; the const survives only as a fallback.
- **Main fragility: the `warmup_context` dict shape.** Every key is read via `dict.get(key)` inside
  `IjfsEngine.run_daily`, so a misspelled key silently yields `null` → that piece of warmup config goes
  dead with no error. This is *exactly* the class of bug that left exquisite intel dormant (the whole
  context was simply never passed). Plain dicts mirror the Python source's own fragility.

**Orchestrator triage:**
- Verified independently: golden `casualties=2 feba=0.76` byte-stable, anti-ship PASS, gate 204/204,
  crossing loss 67%→50.0% (probe). Diff scoped to `GameState.gd` only; RNG isolation (derived ijfs
  substream) intact. → **acted now** (committed).
- warmup_context dict-shape fragility → **record + act later**: a typed `WarmupContext` Resource (or a
  one-line key-allowlist assert in `run_daily`) would make silent dead-config impossible. Not blocking
  (the config is now exercised and the 50% result proves it's live), but it's the highest-value
  hardening for this subsystem — queued in `ORCHESTRATOR_HANDOFF.md` as a future cleanup. Cross-ref
  `PLAN.md 2026-06-28 — D3-D wire warmup`.
- Vestigial `PRE_INVASION_IJFS_DAYS` const (now only a fallback) → **record only**: harmless; leave as
  the missing-config fallback rather than churn it.

## 2026-06-29 — mine-geometry: geometric danger model + decoy-sponge transit   (implementer: direct)

**What I'd do differently / what surprised me (orchestrator, implemented directly — the geometry/RNG
was too sensitive for the free-model implementer):**
- **Measure before building was the win.** A throwaway 2-D sweep (`tools/sweep_antiship_crossing.gd`)
  falsified the planned strike-bonus path (whole band ~54%→~41%; mine floor ~22%) *before* any code,
  which is what redirected the work to mines. Keep leading calibration tasks with a measurement harness.
- **The biggest surprise was the unit bug in my own first harness:** I divided BNs-lost by SHIP hulls
  (`sent_by_type`, 148) instead of the BN wave (`ship_reserve`, 36) — off by ~4×. Caught it because the
  baseline didn't reproduce the committed 50%. Lesson: always reproduce a known reference number before
  trusting a new measurement instrument.
- **Emergent coupling I didn't expect:** the decoy-sponge made the IJFS intel lever matter *again*
  (killing launchers → more screen survives the crossing → more sponges at the minefield → fewer amphibs
  mined). The mine and missile subsystems are now coupled through the shared surviving fleet pool.
- **Fragility / tech debt:** (1) neutralization likelihood is a per-CATEGORY table, but the source data
  shows it varies *within* a category (LHD/LPD "Low" vs LST "High" though both Military_Amphibious) — a
  per-ship-type field on `ShipDef` would be more faithful and is the obvious refinement if mines need
  finer tuning. (2) The decoy-continue inner loop is unbounded by design (bounded only by
  `remaining_dangerous`); fine because dangerous counts are small, but worth a guard if geometry is ever
  cranked. (3) Geometry draws 2·num_mines randf per beach (200 at default) purely to count — cheap, but
  positions are discarded, so a closed-form expected-count could replace the loop if perf ever matters.

**Orchestrator triage:**
- Verified independently: 13/13 mine unit cases, `validate_headless_antiship` PASS (determinism +
  reconciliation), golden `casualties=2/feba=0.76` byte-stable, full gate green (30 suites). Diff scoped
  to the mine subsystem + data + the PLAN/ref docs; no stray files, no `.mcp.json`. → **acted now**
  (committing).
- Per-ship-type neutralization likelihood → **act later**: queue as a refinement (`ShipDef` field) if the
  user wants finer mine tuning; the category table is a sufficient, tunable default now. Cross-ref
  `PLAN.md 2026-06-29 — Mine warfare`.
- Final dial-in toward exactly ~25% → **surface to user**: the model is green at ~32% baseline mean; which
  knob (mine geometry/decoy mix vs the now-working intel lever) and the exact target is a design call.

## 2026-06-29 — victory-conditions: end-of-cleanup census + e2e golden test   (implementer: opencode for the pure checker; direct for integration)

**What surprised me / what I'd do differently:**
- **The data gap was the real story.** "On Taiwan main-island land hexes" sounds simple but the hex grid
  has **no land/sea/island flag** (geometry only; terrain is a deferred ArcGIS phase). Rather than
  fabricate a coastline, I made the census key on a `taiwan_hexes` config (null = all placed hexes) — a
  graceful default that's exact for the golden scenario and a clean hook for future land data. Lesson:
  when a design references data that doesn't exist, build the mechanism + a config seam, don't invent the
  data.
- **The arm-vs-sea-start interaction only showed up in the e2e run.** `unconditional` (the design
  default) declares a China loss on turn 1 because the PLA starts at sea (0 ashore). The exploratory
  multi-turn harness caught it immediately; the unit tests never would have. Lesson: an end-to-end
  playthrough harness earns its keep — it surfaces phase-interaction bugs unit tests can't see. The fix
  (golden scenario armed `after_first_landing`) is exactly what the design provided for.
- **opencode was a clean fit for the pure checker** (`VictoryConditions.evaluate`): self-contained, no
  RNG, no golden risk, fully specified by a table of cases. It produced correct code + a 9-case suite
  first try, zero scope drift. The integration (golden-sensitive, multi-file) I kept for myself.
- **Census fidelity tech debt:** the census counts OOB `get_battalion_count()`, not present strength, so
  sea losses over-count China. Robust for the golden outcome but should count survivors eventually.

**Orchestrator triage:**
- Verified: 9/9 victory unit cases, `validate_golden_victory` PASS (deterministic terminal + winner⇔
  census), golden `casualties=2/feba=0.76` byte-stable, full gate green (32 GdUnit suites). opencode diff
  scoped to the 2 intended files. → **acted now** (committing 3a + 3b together).
- Census OOB over-count → **act later**: count present/surviving battalions; logged in
  `docs/plans/refactor_audit.md`. Cross-ref `PLAN.md 2026-06-29 — Victory conditions`.
- Main-island land-hex data → **blocked on terrain phase**: `taiwan_hexes` knob is the hook; documented.

---

## 2026-06-29 — Port audit Area 1: hex-grid coordinate bug   (orchestrator + opencode deepseek-v4-flash-free for the doc)

**What would you do differently:**
- The opencode doc agent flagged a plausible-sounding "open question" about distance consistency, but
  the actual bug (odd-r coords read as axial) was only nailed by an **empirical** check — converting
  the real grid to geography and counting neighbor matches (23/308 vs 308/308). Lesson: for port
  fidelity, *measure against the source's behavior*, don't reason from code shape alone.
- The bug had propagated into hand-authored scenario data and ~10 test fixtures (the
  `hex_44_16`/`hex_43_17` pair), which all encoded the wrong adjacency. Re-baselining meant chasing
  every fixture keyed to that pair. Lesson: a single foundational geometry bug fans out widely;
  fix-and-re-baseline is cheaper the earlier it's caught.

**Orchestrator triage:**
- Empirical-verification habit → act now (done) — kept a haversine check script approach; will reuse
  for later geometry/data-derived areas.
- Coordinate convention is now documented in `HexMath.gd` + `docs/systems/hex-grid.md` so the next
  agent won't reintroduce axial assumptions → record only.
- Most fixtures cluster on one scenario pair; consider a shared test-fixture constant for the
  golden beach-1 pair instead of duplicating literals across ~10 files → act later (refactor backlog).

---

## 2026-06-29 — Overnight loop item 1: supply→combat wiring   (orchestrator; opencode arg-limit hit)

**What would you do differently:**
- The opencode implementer call failed with "Argument list too long" — on this Windows box a long
  prompt passed as a CLI positional arg exceeds the exe argument limit, and the background task still
  exits 0 (silent failure). Lesson for the loop: pass long implementer plans via a file with `-f`
  (write the plan to a scratch .md, `opencode run -f plan.md "implement the attached plan"`), or keep
  the inline prompt short. The orchestrator implemented item 1 directly instead — faster than retrying.
- Design call recorded in PLAN.md before coding (pool→per-unit effectiveness): binary-at-exhaustion
  with a scenario knob. Clean, but a graded ramp (effectiveness scales with pool adequacy vs a required-
  tons baseline) would be more faithful to TIV's continuous 0..1 — left as a future refine.

**Orchestrator triage:**
- opencode arg-length → act now: future overnight iterations use `-f` file attachment for plans.
- Graded supply ramp → record only (future REFINE; binary v1 is sufficient and gated).
