---
title: "0051: Destroyed coastal launchers get a last salvo away"
status: "Sketch"
created: "2026-07-27"
---

# Plan 0051: Destroyed coastal launchers get a last salvo away

## Goal

Wire up the TIV mechanic HexCombat ports but never runs: a Green coastal launcher destroyed by the
IJFS **this cycle** still gets a salvo away before it dies. Today the arithmetic exists in
`AntishipCalculator.build_firing_plan` and is fed nothing, so it contributes exactly zero on every
crossing of every game.

This is a **balance change**, not a wiring fix. It makes Green more lethal on the turns the IJFS is
hitting hardest. It ships OFF by default and needs a USER-dialed value plus a re-run of the accepted
crossing calibration before it is turned on.

## Read these first

| What | Where |
|---|---|
| The calculator that already implements it | `scripts/calc/AntishipCalculator.gd` → `build_firing_plan` |
| Who calls it with `{}` today | `scripts/calc/AntishipResolver.gd` → `resolve` (the `build_firing_plan(...)` call) and `_firing_inputs` |
| The only writer of the launcher rows | `scripts/transitions/AntishipTransitions.gd` (**do not write those fields anywhere else — the gate will fail you by file:line**) |
| The precedent to copy, end to end | plan 0028's `off_island_strike`: a default-0 block in `data/antiship/antiship_crossing_config.json` + registry knobs + byte-stable at default. Read `docs/plans/0028-sustained-followon-interdiction.md` and the `off_island_strike` block in that JSON, plus `AntishipResolver._append_off_island_strikes` for how such a block is consumed. |
| Field lifetimes + the establishment equation | header of `scripts/model/AntishipSystem.gd` |
| What may write what | `tools/mutation_authority_manifest.json` (the ONLY home — do not copy its lists into a header) |
| **The TIV oracle itself** | `~/Projects/TaiwanInvasionViewer/src/`. Three files decide this plan: `services/antiship_firing_plan.py` (the ported arithmetic), `serializers/antiship.py` (where TIV's percentages come from), `services/antiship_casualty_input_adapter.py` (what TIV counts as "destroyed"). Read them — the two judgement calls below are settled by them, not by argument. |

## Settled before you start — do not relitigate

- The mechanic is **per-cycle**, not cumulative. A launcher killed on IJFS day 1 does not keep firing
  for the rest of the campaign. See "Trap 1".
- Default value is **0**, so the golden gate stays byte-stable on the commit that adds it. Turning it
  on is a separate, USER-approved dial.
- Launcher losses are permanent (plan 0043). This plan does not touch that.
- `AntishipTransitions` stays the only writer of `AntishipSystem` fields.

## The two effects, and why only one of them is wanted

Wiring the `ijfs_destroyed` argument into `build_firing_plan` changes **two** things. Read this
section twice; it is the whole reason this is a plan and not a one-line change.

```gdscript
# scripts/calc/AntishipCalculator.gd, inside build_firing_plan
var truly_available := maxi(0, system.quantity)
var destroyed_count := ...                                  # <- fed {} today, so always 0
var initial_system_count := truly_available + destroyed_count
var intended_to_fire := int(float(initial_system_count) * fire_pct)
var available_firing := mini(intended_to_fire, truly_available)   # EFFECT 2 lives here
var destroyed_firing := int(float(destroyed_count) * destroyed_fire_pct)   # EFFECT 1
```

### Effect 1 — the mechanic you want

`destroyed_firing` becomes a separate firing row: dead launchers contributing a last salvo. It is
gated by `destroyed_fire_percentages`, which has **zero data plumbing today** — no JSON key, no
registry entry, only the function parameter and one unit test. Default 0 ⇒ adding the parameter alone
changes nothing.

### Effect 2 — a silent rollback of IJFS suppression. Do NOT ship this.

Because `initial_system_count` grows, `intended_to_fire` grows, and `available_firing` is only capped
at `truly_available`. Worked example, 10 survivors and 5 destroyed:

| `fire_pct` | today | if you feed `ijfs_destroyed` naively |
|---|---|---|
| 1.0 (unsuppressed) | 10 shots | 10 shots — `mini` caps it, no change |
| 0.6 (suppressed) | 6 shots | **9 shots** |

So it does nothing in the normal case and **partly undoes suppression exactly when suppression
bites** — which is the IJFS's entire purpose.

**This is a semantic mismatch, not a faithful port — verified against TIV source, not inferred.**

In TIV, `firing_percentages` is a **player fire-allocation ORDER**. It is built by
`format_fire_allocations(fire_allocations_by_to, ...)` in
`TaiwanInvasionViewer/src/serializers/antiship.py:193` from the fire-allocation map the player sets
per TO — "fire 60% of this TO's type-23 systems". It has nothing to do with suppression and nothing
to do with how many launchers survived. Against that quantity, `initial_system_count = survivors +
destroyed` is exactly right: you ordered 60% of your establishment out, and the survivors fill the
order as far as they can.

HexCombat has no fire-allocation order. `DEFAULT_FIRE_PCT` is a constant 100.0, and the only thing
that moves it is suppression. `AntishipResolver._firing_inputs` computes

```gdscript
var fire_pct := DEFAULT_FIRE_PCT * float(available - suppressed) / float(available)
```

— a **suppression fraction relative to SURVIVORS**. Same variable name, different quantity.
Multiplying a survivor-relative fraction by (survivors + dead) double-counts: expand it and you get
`survivors − suppressed` plus a spurious `dead × (survivors − suppressed) / survivors`.

If a later agent reads `build_firing_plan` beside the Python and "fixes" this back, they will
reintroduce the bug. That is why the divergence gets written down in the systems doc with this
reasoning, and why the regression test in the test list asserts `available_firing` specifically.

**Therefore: suppress effect 2.** The destroyed launchers' contribution must arrive ONLY through the
separate `destroyed_firing` row (effect 1). Concretely, `available_firing` must be computed from
`truly_available` alone. Record this divergence from TIV in `docs/systems/antiship-mine/antiship-mine.md` §11 with
the reasoning above — it is a deliberate, explained divergence, not a porting error.

## Trap 1 — cumulative vs per-cycle (the one that will bite you)

`IjfsWriteback.antiship_destroyed_by_type` is a **running campaign total**, not a per-turn delta.
`IjfsResolver.compute_writeback`'s header states this as an INVARIANT; do not change it.

TIV agrees with the plan, not with the cumulative reading: what it feeds this argument is built from
the CURRENT day's IJFS results (`build_ijfs_casualties_df(ijfs_results)`,
`TaiwanInvasionViewer/src/services/antiship_casualty_input_adapter.py:32`) and the column it keys on
is literally named **`Destroyed_This_Turn`** (same file, line 53). Per-cycle is the ported semantic;
cumulative is not.

Feed that cumulative total into `build_firing_plan` and every launcher killed since turn 1 fires
again on every subsequent crossing, forever. That is not the mechanic; it is a large permanent buff
that would look like the mechanic in a one-turn test and only show up in a campaign.

**You need a per-cycle delta, and one does not exist in the tree today.** (`destroyed_this_turn` is
*launch* attrition, written by the authority AFTER the crossing — do not reuse it.)

Plan 0043 made producing the delta cheap: `AntishipTransitions.apply_ijfs_effects` already holds both
the old and the new cumulative for each row.

## Approach

Four commits, each ending gate-green. The **Traps** are interleaved next to the step they apply to
and are numbered in the order you will meet them, not in step order — read the trap immediately
before writing the step it sits beside. Traps 2 and 4 both live inside step 2; both were found by
review, and both are invisible to the unit tests.

### Step 1 — the per-cycle delta (no behaviour change)

1. Add to `scripts/model/AntishipSystem.gd`:
   ```gdscript
   @export var ijfs_destroyed_this_turn: int = 0
   ```
   Document it in the existing transient-counters comment: *launchers the IJFS destroyed in THIS
   cycle — the per-cycle delta of `ijfs_destroyed_cumulative`, kept because the cumulative total
   cannot answer "who died just now".*
2. Classify it in `tools/mutation_authority_manifest.json` as `"transient"` under the
   `AntishipSystem` owned model. **The gate fails on an unclassified field**, and the message will
   tell you exactly this.
3. In `AntishipTransitions.apply_ijfs_effects`, set it from the delta before assigning the new
   cumulative — the old value is still in the field at that point:
   ```gdscript
   if ijfs_destroyed.has(key):
       var reported := int(ijfs_destroyed[key])
       system.ijfs_destroyed_this_turn = maxi(0, reported - system.ijfs_destroyed_cumulative)
       system.ijfs_destroyed_cumulative = _cumulative(
           system, "IJFS", system.ijfs_destroyed_cumulative, reported)
   ```
   **Note the `has(key)` guard is already there and is load-bearing** — an absent key means "no
   report", not "zero kills" (plan 0043). Leave it alone: a row with no report has a delta of 0 for
   this cycle, which the reset in the next step already gives you.
4. Clear it in `AntishipTransitions.reset_transient_flags` alongside the other per-turn counters.
5. Nothing reads it yet. **Gate must be green with zero pin movement.** Commit.

### Step 2 — feed the calculator (still no behaviour change)

Do these in order. The config must be reachable BEFORE you touch `_firing_inputs`.

1. **Hoist the config load.** In `AntishipResolver.resolve`, move the
   `var crossing_config := AntishipLoaders.load_crossing_config(CROSSING_PATH)` line ABOVE the
   `_firing_inputs(...)` call. It currently sits below it, so the config is not in scope where you
   need it. Loading a JSON file draws no dice and touches no state, so this is byte-stable — confirm
   with the gate, do not assume.
2. **Pass the block in.** Give `_firing_inputs` a second parameter for
   `crossing_config.get("destroyed_system_firing", {})`. Until step 3 adds the JSON block, that
   `.get` returns `{}` and every resolved percentage is 0 — which is exactly why step 2 changes
   nothing. **No loader change is needed:** `AntishipLoaders.load_crossing_config` returns the whole
   parsed body and only asserts a short required-key list; optional blocks like `off_island_strike`
   are simply read off the returned dict.
3. **Resolve the per-type percentage with a SMALL INLINE HELPER — do not reuse
   `AntishipCalculator._resolve_type_config`.** That function is declared `-> Dictionary` and
   `launch_attrition`'s per-type entries are dictionaries; your block's entries are floats, so
   calling it returns a float where a Dictionary is declared and crashes at runtime. Write the
   `_default` fallback out in three lines returning a `float`.
4. **Build two dictionaries in `_firing_inputs`** alongside `firing_percentages`, keyed identically
   with `AntishipCalculator.encode_key(to_number, type_id)`, and return them:
   `ijfs_destroyed[key] = system.ijfs_destroyed_this_turn` and `destroyed_fire_percentages[key] = …`.
   **Read Trap 2 and Trap 4 before writing this loop.**
5. In `AntishipResolver.resolve`, replace the two `{}` arguments in the `build_firing_plan(...)` call
   with `firing["ijfs_destroyed"]` and `firing["destroyed_fire_percentages"]`.
6. **Suppress effect 2** in `AntishipCalculator.build_firing_plan`: compute `available_firing` from
   `truly_available` only — take the percentage of `truly_available` rather than of
   `initial_system_count`. Leave `destroyed_firing` exactly as it is. Put the WHY (the
   survivor-relative `fire_pct`) in the function comment, or someone will "fix" it back.
7. **Gate green, zero pin movement.** Commit.

### Trap 2 — the legacy fallback branch

`build_firing_plan` currently reads:

```gdscript
if not ijfs_destroyed.is_empty():
    destroyed_count = int(ijfs_destroyed.get(key, 0))
else:
    destroyed_count = maxi(0, system.destroyed_this_turn)
```

That `else` is a fallback for the empty dict we pass today. Once step 2 always passes a populated
dict it is dead — **but only if you emit an entry for every row**. If you emit entries only for rows
with kills, then on a quiet turn the dict is empty and the branch silently switches to reading
*launch* attrition instead of IJFS destruction. That is a different mechanic wearing the same name.

So: emit zeros, then **delete the `else` branch and the `destroyed_this_turn` read**, and make
`destroyed_count` unconditional. The calculator then reads no per-crossing state off the row at all,
which is the direction plan 0043 pushed it.

`tests/antiship_firing_plan_test.gd` → `test_destroyed_systems_fire_via_destroyed_fire_percentage`
depends on that fallback today (it sets `sys.destroyed_this_turn = 10` and passes `{}`). Rewrite it
to pass an explicit `{"3:5": 10}` — same expected numbers, now testing the path production uses.

### Trap 4 — the `available <= 0` filter, which silently kills the whole mechanic

**This is the one most likely to ship broken, because every unit test still passes.**

`AntishipResolver._firing_inputs` contains:

```gdscript
var available := maxi(0, system.quantity)
if available <= 0:
    continue                     # <- skips the row AND never records its TO
…
if not location_seen.has(system.to_number):
    location_seen[system.to_number] = true
    target_locations.append(system.to_number)
```

`build_firing_plan` iterates `for location in target_locations`, so a TO that appears in no entry is
never visited at all. Consequence: **a TO whose launchers are ALL destroyed contributes nothing** —
precisely the case the mechanic exists for. Partial destruction works (the TO gets in via its
survivors); total destruction silently does not.

Required:

- Record `ijfs_destroyed[key]`, `destroyed_fire_percentages[key]` and the TO in `target_locations`
  for **every non-C2 row**, whether or not it has survivors.
- **Guard the division.** `fire_pct` is `DEFAULT_FIRE_PCT * (available - suppressed) / available`;
  with `available == 0` that divides by zero and yields `inf`, which then poisons
  `intended_to_fire`. When `available == 0`, set `firing_percentages[key] = 0.0` explicitly and skip
  the arithmetic. Survivors firing is not the mechanic here — the dead row's contribution arrives
  only through `destroyed_firing`.
- Keep the C2 `continue` exactly as it is. C2 nodes are not firing systems.

This stays byte-stable at step 2: the extra rows produce `available_firing == 0` (no allocation
entry) and `destroyed_firing_plan[key] == 0`, and a zero entry there yields `total_firing == 0` and
`attempted_firing == 0`, so it reaches neither `systems_fired` nor `launch_attrition`. Verify that
claim with the gate rather than trusting this paragraph.

### Step 3 — the content knob, default 0

Copy the `off_island_strike` precedent exactly.

1. Add a block to `data/antiship/antiship_crossing_config.json`. **Key it PER SYSTEM TYPE**, which is
   both what TIV does (`format_destroyed_fire_percentages(destroyed_system_fire_percentages,
   target_locations)`, `TaiwanInvasionViewer/src/serializers/antiship.py:211` — a per-type map
   expanded across target locations) and how `launch_attrition` is already keyed in this same file:
   ```json
   "destroyed_system_firing": {
     "_comment": "TIV mechanic (plan 0051): a coastal launcher destroyed by the IJFS THIS cycle still gets a salvo away before it dies. Percentage of this cycle's destroyed launchers of that type that still fire. 0 = off, which is the shipped default and keeps the golden byte-stable. Keyed by type_id like launch_attrition, with a _default fallback; TIV expands the same per-type map across every target location.",
     "_default": 0.0
   }
   ```
2. Nothing to wire — step 2 already reads this block with `.get("destroyed_system_firing", {})` and
   resolves it per type. Adding the block simply gives that lookup something to find. Confirm the key
   name matches what step 2 reads, exactly.
3. Register it in `data/knobs/registry.json` so every game record carries it and it is sweepable:
   ```json
   {"id": "destroyed_system_fire_pct",
    "path": "data/antiship/antiship_crossing_config.json:destroyed_system_firing._default",
    "label": "Share of THIS cycle's IJFS-destroyed coastal launchers that still get a salvo away (plan 0051). 0 = off.",
    "group": "antiship", "sweepable": true}
   ```
   Bump `version` in that file if the registry validator requires it — `tools/validate_research_knobs.py`
   is the arbiter, run it.
4. **Gate green, no pin movement.** Commit. The mechanic now exists and is off.

### Step 4 — measure, then ask

1. Sweep the new knob over a range with everything else fixed:
   ```bash
   python3 tools/run_sweep.py --name destroyed_system_fire \
     --knob "data/antiship/antiship_crossing_config.json:destroyed_system_firing._default" \
     --values 0,10,25,50,100 --n 30
   ```
2. Because this changes Green lethality, also re-run the **accepted crossing calibration** and report
   whether the USER-accepted 32.9% mean loss on the 81-BN sent-cohort wave still holds:
   ```bash
   python3 tools/run_sweep.py --spec tools/sweeps/antiship_crossing.json
   ```
   That spec is `turns: 1`. **A one-turn sweep cannot see this mechanic properly** — it only fires
   when the IJFS has destroyed launchers in the same cycle as a crossing. Also run a multi-turn
   comparison with `--matchups selfplay_default` (see Trap 3).
3. Write `docs/reports/YYYY-MM-DD-destroyed-system-firing.md`: distributions, not anecdotes, per
   `hexcombat-research-runs` (N≥30 per condition, common seeds across conditions, commit hash).
4. **Stop and ask the USER for the value.** Do not pick one yourself — this is a balance dial, and
   the standing rule is that game-design calls are theirs.

### Trap 5 — the matchup decides whether you can see anything

Under the `noop` matchup a campaign contains exactly **one** crossing in 25 turns; under
`selfplay_default` it contains 4–8 (measured, plan 0043). The canned calibration sweeps use `noop`
because that is the semantics their dialed references were accepted under — so they are the right
tool for the calibration check and the **wrong** tool for measuring a cross-cycle mechanic. Use both,
and say which is which in the report.

## Tests and validation

Required, beyond the gate. **Note where each one sits**, because the trap in Trap 4 is invisible to
every unit test:

*Unit — `tests/antiship_firing_plan_test.gd` (calls `build_firing_plan` directly):*

- The rewritten fallback test (Trap 2): pass an explicit `ijfs_destroyed` instead of relying on
  `destroyed_this_turn`.
- A non-zero `destroyed_fire_percentages` produces the expected `destroyed_firing`, **and does not
  change `available_firing`**. That second assertion is effect 2 staying suppressed — it is the
  regression test for the central judgement of this plan, so write it explicitly rather than
  implying it.

*Unit — `tests/transitions/antiship_establishment_test.gd`:*

- The per-cycle delta: two IJFS reports of a GROWING cumulative total must give deltas of
  (first, second − first), not (first, second). Write it so it FAILS if someone feeds the cumulative
  — this is the only guard on Trap 1.
- The delta is cleared by `reset_transient_flags`.

*Integration — `tests/antiship_resolver_test.gd` (goes through `_firing_inputs`, which the unit
tests bypass entirely):*

- **A TO whose launchers are ALL destroyed still contributes fire.** Build a system with
  `quantity == 0` and `ijfs_destroyed_this_turn > 0`, set the knob non-zero, call
  `AntishipResolver.resolve`, and assert `summary.systems_fired_count > 0`. Without this test, the
  `available <= 0` filter (Trap 4) drops the row, every unit test still passes, and the mechanic
  ships doing nothing in exactly the case it was built for.
- A TO with survivors AND destroyed launchers contributes both, and its survivors' shot count is
  unchanged from the knob-off run.

*Measurement, not argument:* set the knob to 100, run one seeded game, and confirm
`systems_fired_count` rises on turns where the IJFS destroyed launchers and is unchanged on turns
where it did not.

Every step must end **ALL PHASES GREEN** (`bash tools/run_all_tests.sh`, verdict by marker lines,
never exit codes). Run single validators with the gate's environment
(`HEXCOMBAT_SCENARIO=scenario_golden`) or their pins will not match. Steps 1–3 must move **no pinned
fingerprint**; if one moves, you have shipped a behaviour change by accident — find it before
continuing.

## Out of scope

- Changing `IjfsWriteback` to carry deltas instead of cumulative totals. The cumulative invariant is
  load-bearing elsewhere; derive the delta in the authority instead.
- Persistent launcher magazines (`AntishipMagazine`) — still deferred.
- Any change to permanent launch destruction (plan 0043).
- Re-tuning IJFS or launch-attrition probabilities to offset whatever this does. Report first.

## Risks and stop conditions

- **Trap 4 shipped by accident** is the likeliest failure: the mechanic quietly does nothing for a
  fully-destroyed TO, every unit test passes, and the sweep in step 4 then reports "no effect" for
  the wrong reason — which would get the mechanic wrongly written off as inert. The integration test
  is the only guard; do not skip it because the unit tests are green.
- **Trap 1 shipped by accident** is the most damaging: it would look correct in unit tests and only
  show as a Green buff in long campaigns. The dedicated delta test is the guard.
- **Effect 2 shipped by accident** partly cancels IJFS suppression. The `available_firing` regression
  test is the guard.
- If the calibration moves materially at value 0, **stop** — something in steps 1–3 was not
  byte-stable and the plan's premise is broken.
- If measurement shows the mechanic cannot move outcomes at any value (as happened with permanent
  launch destruction in plan 0043), say so plainly and let the USER decide whether to ship it OFF as
  a modelling nicety or drop it.

## Closeout homes

`docs/STATUS.md` (D3 bullet), `docs/systems/antiship-mine/antiship-mine.md` (§9 turn flow + §11 the deliberate
`fire_pct` divergence), `hexcombat-config-and-knobs` (the new knob), `docs/DECISIONS.md` (USER call +
measured consequence), report under `docs/reports/`, plan archived.

## Review record (2026-07-27, pre-implementation)

Reviewed by the agy explore wrapper; the tier-3 reviewer failed with a streaming error (a known flake).
All six of the plan's factual premises were confirmed against the tree. Three blockers came back and
are folded in above:

1. **Step ordering was unbuildable** — step 2 needed a config value that step 3 had not loaded yet.
   The config hoist moved into step 2.
2. **The `available <= 0` filter** in `_firing_inputs` drops a fully-destroyed TO from
   `target_locations` entirely, so the mechanic would silently do nothing in its headline case while
   every unit test passed. Now Trap 4, with an integration test that fails without the fix.
3. **`_resolve_type_config` cannot be reused** for this block — it is declared `-> Dictionary` and
   the block's entries are floats, so reusing it crashes at runtime. Step 2.3 now says write the
   fallback inline.

The load-bearing judgement — that effect 2 is a semantic mismatch rather than a faithful port — was
independently checked against TIV source afterwards and is cited in place. Do not re-derive it from
the Python alone; the Python is right for TIV's inputs and wrong for ours.

## Dependencies

Requires plan 0043 (shipped) — the authority and the cumulative fields the delta is derived from.
Independent of plans 0044–0050. **Must not land in the same window as another Green-lethality change**
or neither measurement is attributable.
