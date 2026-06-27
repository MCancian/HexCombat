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
