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
