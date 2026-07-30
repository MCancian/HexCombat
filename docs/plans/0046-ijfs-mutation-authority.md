---
title: "0046: IJFS mutation authority"
status: "Ready"
created: "2026-07-26"
updated: "2026-07-30"
---

# Plan 0046: IJFS mutation authority

## Goal

Put persistent IJFS targets, munition inventory, squadron strength, MANPADS stocks and daily
carry-over behind one explicit IJFS mutation authority. Preserve the six-stage calculation pipeline
and every Dice draw while eliminating direct campaign-state mutation throughout `IjfsEngine`,
`IjfsStrike`, `IjfsEngagement`, `IjfsDetection`, `IjfsTargeting`, `IjfsManpads` and `IjfsResolver`.

## Settled constraints

- IJFS remains a persistent-entity model with daily ephemeral budgets; it is not converted into fleet-
  style closed buckets.
- Munition exhaustion is normal and causes a skipped attack, not an assertion failure.
- Destroyed targets remain destroyed; suppression is temporary according to existing carry-over rules.
- Green maneuver casualties are applied by `ForceTransitions`, not by IJFS editing brigade
  composition. **(Already true at HEAD — see the inventory below.)**
- Anti-ship writeback is cumulative for destruction and current-cycle for suppression; plan 0043's
  authority consumes it. **(Already true at HEAD.)**
- The warmup/day pipeline and RNG draw order are immutable during this architecture work.
- Untyped IJFS summary output remains deliberately untyped at the JSON boundary.

## Measured mutation surface (preflight, HEAD `55f2834`)

This section replaces the Sketch's prose description. Every line below was grepped and read; the
Sketch's version claimed writers that do not exist and missed constraints that do.

### `IjfsTarget` — runtime writers

| Where | Fields | Stage |
|---|---|---|
| `scripts/ijfs/IjfsDetection.gd:182-190` | `detected_this_turn`, `known_to_red`, `last_detected_day` | detection apply (both phases) |
| `scripts/ijfs/IjfsTargeting.gd:224` | `posture` | warmup posture override |
| `scripts/ijfs/IjfsTargeting.gd:267` | `intel_locked` | exquisite intel |
| `scripts/ijfs/IjfsStrike.gd:134-137` | `destroyed`, `known_to_red`, `suppressed`, `suppressed_this_turn` | strike destroy |
| `scripts/ijfs/IjfsStrike.gd:142-143` | `suppressed`, `suppressed_this_turn` | strike suppress |
| `scripts/ijfs/IjfsEngagement.gd:43` | `sead_result` (`"unengaged"` pre-pass over live SAMs) | SEAD |
| `scripts/ijfs/IjfsEngagement.gd:94-99` | `destroyed`, `suppressed`, `suppressed_this_turn`, `detected_this_turn`, `known_to_red`, `sead_result` | SEAD destroy |
| `scripts/ijfs/IjfsEngagement.gd:105-109` | `suppressed`, `suppressed_this_turn`, `sead_result` | SEAD suppress / miss |
| `scripts/ijfs/IjfsEngine.gd:395-397` | `suppressed`, `suppressed_this_turn`, `sead_result` | `carry_to_next_day` |
| `scripts/resolvers/IjfsResolver.gd:111` | `posture` | activity posture from force state |
| `scripts/resolvers/IjfsResolver.gd:187` | `destroyed` | maneuver-target retirement |
| `scripts/ijfs/IjfsManpads.gd:46,173,186` | `metadata["systems_remaining"]` | lazy seed, per-TO expend, island-wide expend |
| `scripts/resolvers/IjfsResolver.gd:140` | `metadata["systems_remaining"]` | MANPADS↔OOB cap |
| `scripts/resolvers/IjfsResolver.gd:152` | `IjfsDailyState.targets` (`append_array`) | mobilized-formation targets |

### `IjfsMunition` — runtime writers

| Where | Field | Note |
|---|---|---|
| `scripts/ijfs/IjfsStrike.gd:124` | `inventory_remaining -= rounds` | the normal decrement |
| `scripts/ijfs/IjfsEngine.gd:218` | `inventory_remaining -= rounds` | MANPADS-intercepted round: spent, delivers nothing |

Both paths are guarded by the *same* sufficiency test (`inventory_remaining >= rounds`), evaluated
twice: at `IjfsEngine.gd:210` (`will_fly`) and again at `IjfsStrike.gd:111`.

**Both of those branches are unreachable in production**, because selection already refuses an
unaffordable pairing: `IjfsTargeting._rule_affordable:75` returns false when
`inventory_remaining < rounds_expended_per_engagement`, and **every** path that returns a non-null
`selected` runs through `_select_from_ordered_pairings:92`, which calls it — the doctrine-priority
branch, the doctrine-fallback branch and the no-doctrine branch alike
(`IjfsTargeting.gd:151,154,158`). Nothing decrements inventory between selection and either check.

Two consequences:

- `will_fly` is **defensive redundancy, not an RNG gate.** The actual conditional-draw gates for the
  MANPADS roll are munition vulnerability (`IjfsManpads.gd:61`), TO membership (`:63`) and ready stock
  (`:67`) — all three return `null` *before* consuming a die. Keep the call order exactly as it is for
  byte stability, but do not justify it as gating a draw.
- **`consume_munition` returning false cannot be reached through the engine**, so that contract must be
  pinned by a direct unit test of `IjfsTransitions`, not by an engine-level scenario. A test that tries
  to drive it through `run_daily` will silently test nothing.

### `IjfsSquadron` — runtime writers

| Where | Fields |
|---|---|
| `scripts/ijfs/IjfsEngagement.gd:147-148` | `alive`, `losses_today` (SEAD return fire) |
| `scripts/ijfs/IjfsEngagement.gd:182-183` | `alive`, `losses_today` (post-phase-2 free shot) |
| `scripts/ijfs/IjfsManpads.gd:152-153` | `alive`, `losses_today` (island-wide MANPADS contest) |

### Container writers (`IjfsDailyState`, `GameStateData`)

| Where | What | Kind |
|---|---|---|
| `scripts/builders/IjfsStateBuilder.gd:29,32,33,40,41` | `state.targets` (assign + `append_array`), `state.munitions`, `state.squadron_force`, `sam_score` enrichment | construction |
| `scripts/resolvers/IjfsResolver.gd:152` | `ijfs_state.targets.append_array` | runtime |
| `scripts/phases/FiresPhases.gd:22,40,42` | `state._ijfs_day`, `state.ijfs_state` | runtime |
| `scripts/GameState.gd:177-178` | `data.ijfs_state = null`, `data._ijfs_day = 0` (scenario reset) | runtime |
| `scripts/GameState.gd:83,86` | the forwarding **setters** for both fields | runtime |

The two `GameState` setters have **zero callers** — `tools/validate_mobilization.gd:169` and
`tools/validate_headless_ijfs.gd:43` only read. They are deleted, leaving getter-only properties, which
is precisely what `GameState.gd:93-100` already does for `antiship_systems`: *"A setter here would be a
public door around it."*

### Construction-only writers (`scripts/ijfs/IjfsLoaders.gd`)

Munitions `:199-205`, `:214-223`, `:483-490`; squadron rows `:387-393`; `sam_score` enrichment
`:412-414`; target rows `:433-450` and `:456-477`. All run inside `IjfsStateBuilder.build` before
anything holds the state — a `construction_writers` allowance, not a legacy writer. Note the two
`target.metadata = …` assignments at `:450` and `:477`, and that whole-model ownership means the
allowance must cover *every* field the loaders set, not only the interesting ones.

### Three Sketch premises the tree contradicts

1. **"squadron `alive`, `losses_today`, and RTB state".** `IjfsSquadron.rtb_today` has **no runtime
   writer at all** — the only assignment in the tree is `IjfsLoaders.gd:392` (`= 0` at construction).
   It is reported in the `air_oob_after` ledger and never changes. The authority must NOT grow an
   RTB mutator; doing so would be inventing a mechanic under cover of a refactor.
2. **"daily reset/carry-over flags" for squadrons.** `carry_to_next_day` (`IjfsEngine.gd:390-397`)
   touches **targets only**. `losses_today` is never reset — it is a campaign-cumulative total
   wearing a per-day name, and it is visible in the `air_oob_after` ledger, so re-baselining it is a
   golden-touching behavior change. **Preserve exactly; do not "fix" the name's meaning here.**
   Logged to `docs/plans/BACKLOG.md` instead.
3. **"direct brigade composition mutation" (Sketch step 7) and the writeback boundary (step 8) are
   already done.** Plan 0044 moved the casualty application out: `IjfsResolver.apply_maneuver_casualties`
   (`scripts/resolvers/IjfsResolver.gd:196-197`) is a bare `push_error` stub with **zero callers**.
   `FiresPhases.gd:57` already routes maneuver casualties through `ForceTransitions`, `FiresPhases.gd:72`
   already routes anti-ship writeback through `AntishipTransitions`, and
   `IjfsResolver.compute_writeback` (`:219-231`) already builds the cumulative anti-ship totals from
   authoritative target state rather than from a per-day log. Steps 7 and 8 therefore shrink to
   *delete the dead stub* + *pin the existing seam with tests*.

### One constraint the Sketch does not state: `metadata` is aliased into the ledgers

`IjfsStrike.gd:153` and `IjfsManpads.gd:101` (both `strike_log` rows), `IjfsDetection.gd:208`
(`detection_log`) and `IjfsTarget.to_dict():52` (`target_status_after`) all put `target.metadata` — the
**live dictionary**, not a copy — into their rows. A later MANPADS expend therefore retroactively
changes rows already emitted this day, and the serialized ledger shows end-of-day stock. That is
current, pinned behavior.

Narrowing one thing: `manpads_intercept_log` rows (`IjfsManpads.roll_strike_interception:74-83`) carry
no `metadata` alias at all — they hold a scalar `systems_expended`. The four aliases above are the
complete set.

**Consequence for the typed-stock conversion:** a typed field alone silently changes ledger output
(the `systems_remaining` key would vanish from every MANPADS `metadata`). The typed field must be
authoritative *and* the authority must keep `metadata["systems_remaining"]` mirrored on every write,
so the aliasing keeps producing byte-identical ledgers. The mirror write lives in `IjfsTransitions`
and nowhere else, which is exactly what makes it safe.

## Aggregate boundary

`IjfsTransitions` at `scripts/transitions/IjfsTransitions.gd` owns persistent IJFS campaign state as
its exact sanctioned writer; no other file gains permission by sharing the directory.

Registered as aggregate `ijfs`:

- **`owned_models`** — `IjfsTarget`, `IjfsMunition`, `IjfsSquadron`. Owning the whole model means the
  manifest must classify every mutable field (`_schema_rules`, `E_UNCLASSIFIED_FIELD`), including the
  new typed MANPADS stock and `metadata`.
- **`hosted_fields`** — `IjfsDailyState.targets`, `.munitions` and `.squadron_force` (the three
  containers `IjfsDailyState.gd:7-8` documents as persisting across days), plus
  `GameStateData.ijfs_state` and `GameStateData._ijfs_day`.
- **`construction_writers`** — `scripts/ijfs/IjfsLoaders.gd` for the model rows, and
  `scripts/builders/IjfsStateBuilder.gd` for the three `IjfsDailyState` containers it assembles before
  anything holds the state.

### Why `metadata` is protected despite being a free-form Dictionary

Registering a generic field name risks the gate's `unresolved_receiver` name-backstop firing on
unrelated code. **Measured on the tree before deciding:** `metadata` is declared on exactly **one**
class in the repo (`scripts/model/ijfs/IjfsTarget.gd:24`), and all eight `.metadata` write sites have a
receiver the gate can type as `IjfsTarget`. There is nothing for the backstop to pollute.

What protection here does *not* buy is the aliased case — `var m = target.metadata; m["x"] = 1` stays
invisible, exactly as the validator header says. That is precisely why the MANPADS stock moves onto a
typed field instead of staying in the dictionary; the `metadata` registration guards the direct writes
and the mirror, and the plan does not pretend it guards more.

**Fallback if the gate disagrees** (commit 4 is where this is discovered): move `IjfsTarget` from
`owned_models` to `hosted_fields`, which carries no exhaustiveness requirement, and list every field
except `metadata` — recording in the manifest why the exception exists.

### Fields the authority must reach that the state containers hide

`GameStateData.ijfs_state` / `_ijfs_day` are written today from three places (see the container-writer
table). Registering them without giving those places an authority call is the mistake that would strand
this plan at `migration` forever, so the authority gains three lifecycle operations —
`install_daily_state`, `reset_daily_state`, `advance_day` — and `FiresPhases` / `GameState` call them
instead of assigning. `FiresPhases.reset_ijfs_state` mirrors the existing
`FiresPhases.reset_antiship_establishment` pass-through exactly.

Not owned here:

- `IjfsPairing`, the scenario dictionary, doctrine/release rules: immutable content, loaded and
  overridden at build time only.
- Daily firing-capacity budgets (`IjfsFiringCapacity`): ephemeral calculators with their own
  `try_consume` API; they never touch campaign state.
- Per-run ledgers and AD-health snapshots on `IjfsDailyState`: rewritten wholesale by each
  `run_daily` and consumed as output. Registering them would centralize logging, not ownership.
- `GameStateData.last_ijfs_summary` / `last_ijfs_writeback`: phase-summary outputs, unregistered like
  every other phase's summary.
- Cross-aggregate writes: maneuver casualty receipts → `ForceTransitions`; anti-ship
  cumulative/suppression writeback → `AntishipTransitions`. Activity posture *reads* force state and
  writes only IJFS targets.

## Target calculation/application split

The engine keeps deterministic stage order and Dice. Each stage calls a narrowly named authority
method **at the exact current draw point** — calculate the rolled result, apply it immediately, so
later stage selection still sees updated state without changing draw order.

Authority operations (names reveal the domain event; there is deliberately no `set_target_field`):

- `apply_detection_results(targets, detected_ids, current_day)`
- `apply_warmup_posture_override(targets, posture)` / `apply_activity_posture(target, is_active)`
- `mark_intel_locked(target)`
- `apply_strike_destruction(target)` / `apply_strike_suppression(target)`
- `mark_sead_unengaged(target)` / `apply_sead_destruction(target)` / `apply_sead_suppression(target)`
- `consume_munition(munition, rounds) -> bool` (false = insufficient, the normal skip)
- `apply_squadron_losses(squadron, losses)`
- `manpads_remaining(target)` / `expend_manpads(target, count)` / `cap_manpads_stock(target, cap)`
- `retire_maneuver_target(target)` / `add_maneuver_targets(state, new_targets)`
- `carry_to_next_day(state)`
- lifecycle: `install_daily_state(state, built)` / `reset_daily_state(state)` / `advance_day(state, day)`

Validation the authority enforces: target ids resolvable and unique, `0 <= alive <= initial`,
non-negative inventory and stock, monotonic destruction (a destroyed target never resurrects, and
suppression reset never clears destruction).

## Model hardening

**Why the typed conversion comes FIRST (lesson from plan 0045).** The gate resolves the RECEIVER'S
TYPE and only then asks whether that `(class, field)` pair is protected. A value inside a free-form
`Dictionary` — `metadata["systems_remaining"]` — names no type and is invisible no matter what the
manifest says (the validator's documented aliased-container blind spot). So:

1. A field cannot be enforced until it lives on a typed object. Register nothing that is still only
   inside `metadata`.
2. A file cannot be relocated (step 9) until its last untyped write is gone. **Audit the aliases each
   file is HANDED, not just the fields it names** — 0045's planner looked write-free and was not.

Concretely:

- Add `IjfsTarget.manpads_remaining: int = -1` (`-1` = not yet seeded from `systems_represented`),
  authoritative, with `metadata["systems_remaining"]` kept as a serialization mirror written only by
  `IjfsTransitions`. `to_dict()` output stays byte-identical.
- Do **not** add an initial-inventory field to `IjfsMunition`. The reference total is already in the
  content file and re-derivable; a second remaining-shaped number on the live model is exactly the
  `ShipState.sent_original` mistake 0045 deleted.
- Generated ids (`{class}__{role}__{NNN}` squadrons, `{source}#{n}` / `{brigade}-MU-{n}` targets) must
  be unique at construction. Changing their formats is out of scope.

## Commit sequence

Each commit ends with `bash tools/run_all_tests.sh` → **ALL PHASES GREEN**, and every commit through
step 9 is byte-stable: **no golden or fixture pin may move.**

1. **Characterization.** `ScriptedDice`-pinned tests for the stage outcomes this plan will re-route:
   warmup carry-over across days, munition exhaustion on both decrement paths, the MANPADS
   interception→inventory→ledger path, squadron loss accumulation, maneuver retirement and
   no-resurrection. Plus a draw-order assertion per stage. No production code changes.
2. **Parameter-ceiling paydown, here rather than separately.** `IjfsEngine._run_strike_phase` carries
   11 params against a hard cap of 5 (`tools/gd_metrics.py:111`), and `docs/plans/BACKLOG.md:62-65`
   flags the collision with this plan explicitly. Introduce `IjfsStrikePhaseContext`
   (`scripts/model/ijfs/`, the `AntishipResolutionContext` pattern) carrying `current_day`, `attacked`,
   `skip_reasons`, `capacity_budget`, `organic_budget`, `z_day`, `release_rules`, `munition_filter`;
   `Dice` and the per-call `phase` stay explicit. This also pays down `_append_final_skips` (6) and
   `_skip_log` (6), which take the same context — one byte-stability proof for three functions.
   **REMOVE** those three `PARAM_CEILINGS` entries rather than editing their numbers.
3. **Typed MANPADS stock.** `IjfsTarget.manpads_remaining` + mirror, per Model hardening. Uniqueness
   and bounds validation. `to_dict` byte-stable.
4. **Authority skeleton + inventory.** Create `scripts/transitions/IjfsTransitions.gd`, register the
   `ijfs` aggregate in `tools/mutation_authority_manifest.json` with `status: "migration"` and a
   `planned_authority`, listing every remaining direct writer as a `legacy_writer` with
   `removal_plan: "0046"`. Route both munition decrements through `consume_munition`. **This is the
   commit that tests the `metadata` registration decision** — if the name-backstop misfires, take the
   documented fallback rather than un-registering the field silently.
4b. **Lifecycle and containers.** Add `install_daily_state` / `reset_daily_state` / `advance_day`;
   delete `GameState.gd:83,86`'s callerless setters; route `GameState.gd:177-178` through a
   `FiresPhases.reset_ijfs_state` pass-through and `FiresPhases.gd:22,40,42` through the authority;
   register `IjfsStateBuilder.gd` as the construction writer for the three containers.
5. **Squadron authority.** Route the three loss sites through `apply_squadron_losses`. `rtb_today`
   gains no mutator (see premise 1).
6. **Target authority, one stage per commit.** Detection → posture/intel → strike → SEAD →
   carry-over → MANPADS expend/cap → maneuver retirement/addition. Each commit removes its
   `legacy_writer` entry. The MANPADS stage covers **both** stock writers — `IjfsManpads.gd:46,173,186`
   *and* `IjfsResolver.gd:140`'s OOB cap; splitting them would leave the typed field and the mirror
   describing different stocks.
7. **Delete the dead `apply_maneuver_casualties` stub** (`IjfsResolver.gd:196-197`, zero callers).
8. **Pin the writeback seam.** Tests proving anti-ship writeback stays cumulative across warmup days
   and composes with plan 0043's authority, and that maneuver casualties reach `ForceTransitions`
   exactly once per kill. No production change expected — if one is needed, that is a finding.
9. **Role placement.** Move `IjfsDailyState` → `scripts/model/` (persistent state, not a calculator;
   `class_name` is path-independent, so only the path, `.uid` and doc references change). Move the
   genuinely write-free helpers `IjfsAdHealth`, `IjfsWarmup`, `IjfsFiringCapacity` → `scripts/calc/`.
   **Open question for review, see below:** the stage files that now *call* the authority.
10. **Close the gate.** Flip the aggregate to `status: "enforced"`, remove the last legacy writers,
    and add deliberate-red fixtures under `tools/fixtures/mutation_authority/` proving direct, nested
    `metadata`, model-mutator, dynamic-`set()` and wrong-authority writes to target, munition,
    squadron and stock state all fail.

### Open question for the plan review (step 9)

The Sketch said to move IJFS algorithm files to `scripts/calc/` once they "return outcomes **or** call
the authority". That second clause contradicts the directory contract in `docs/STATUS.md`, whose
`scripts/calc/` claim is *"write-free calculation: returns outcomes, never applies them"* and whose
test is *"does it write NO campaign state at all"*. A file that calls `IjfsTransitions` applies state.

The stage files cannot stop calling the authority: mid-stage visibility is a stated risk — later
target selection depends on an earlier mutation, so lifting the calls to the resolver would change
draw order, which is forbidden.

**Proposed resolution (conservative):** `IjfsDailyState` → `model/`; `IjfsAdHealth` / `IjfsWarmup` /
`IjfsFiringCapacity` → `calc/`; the stage files stay in `scripts/ijfs/`, and `docs/STATUS.md`'s
"Where a file goes" table gains a row for it: *"a pipeline stage of one subsystem — computes and
applies at its own draw point, through the aggregate's authority"*. This keeps `calc/`'s claim true
rather than widening it to accommodate one subsystem.

## Tests and validation

Authority tests under `tests/transitions/ijfs_transitions_test.gd`:

- successful and insufficient munition consumption across **both** decrement paths; no negative
  inventory; rounds-expended reconciliation against the ledger. The insufficient case is a **direct
  unit test of the authority** — selection makes it unreachable through `run_daily`, so an
  engine-level attempt would pass while testing nothing;
- destroyed persistence, suppression carry-over/reset, and destruction surviving a suppression reset;
- multi-day warmup continuity, and continuity into the first normal turn;
- squadron losses bounded by `0 <= alive <= initial`, and `rtb_today` provably unwritten;
- MANPADS typed stock ↔ `metadata` mirror agreement after seed, expend, cap and serialize;
- maneuver target addition, retirement on casualties, and no resurrection;
- cumulative anti-ship writeback across days, composing with plan 0043;
- duplicate generated ids fail at build;
- `ScriptedDice` draw order unchanged at each stage.

Verification: full gate per commit; the IJFS GdUnit suites and `validate_headless_ijfs` /
`validate_headless_antiship`; the mutation-authority deliberate-red fixtures; and one multi-turn
game proving inventory, target and squadron continuity. **Run validators only through the gate** —
bare, they resolve the research default while the pins were taken under `HEXCOMBAT_SCENARIO=scenario_golden`.

## Out of scope

- IJFS probability, doctrine, capacity, release-rule, warmup or inventory balance changes.
- Changing target, squadron or battalion id formats.
- Making ephemeral firing-budget objects part of campaign state.
- Typing the full IJFS summary `Dictionary`.
- Launcher magazine or minefield persistence.
- **Giving `losses_today` per-day semantics, or `rtb_today` a mutator** — both are behavior changes
  wearing a refactor's clothes (premises 1-2). BACKLOG.

## Risks and stop conditions

- **RNG coupling.** Many conditional draws. Never batch or reorder outcomes to make the API cleaner.
  The real conditional-draw gates are `IjfsManpads.gd:61,63,67` (each returns before consuming a die),
  the strike's suppression roll firing only when the destroy roll missed (`IjfsStrike.gd:138`), and the
  SEAD suppression roll under the same rule (`IjfsEngagement.gd:100-103`).
- **Mid-stage visibility.** Apply at the same semantic point, not at end-of-day.
- **Metadata compatibility.** The mirror is the mechanism; if a consumer outside this repo needs the
  real migration, stop and surface it.
- **Performance.** No deep copy of IJFS state per strike; snapshot only what proves a delta.
- **Over-centralization.** `IjfsTransitions` may use focused helpers, but there is one sanctioned
  writer boundary and one manifest owner.

## Closeout homes

`docs/STATUS.md`; `docs/systems/ijfs/ijfs.md` + its `STATUS.md`; anti-ship/force cross-seam pointers
if behavior descriptions changed; `docs/systems/turn-engine/turn-engine.md` phase wiring; authority
code header and `hexcombat-architecture-contract`; `docs/DECISIONS.md`; `docs/systems/ijfs/RETRO.md`;
BACKLOG check-off for the param-ceiling item and the two new `losses_today`/`rtb_today` entries; plan
archived. Owning docs update their numbered **State & authority** section with aggregate, authority,
outcome/receipt types and the manifest link only.

## Plan review round (2026-07-30)

Fanned out with `tools/review_fanout.sh --freeze` (roles: Sol = fact-check the premises, agy = RNG
safety and what was missed, DeepSeek = bounded enumeration). Sol returned 5 findings (6.5 KB), agy 2
(3.0 KB); **DeepSeek flaked** — 15.7 KB of grep traces and zero findings, which is its measured shape
as a reviewer. The plan round needs one substantive read; it got two.

Every finding was verified against the tree before being applied — none were taken on trust.

| # | Finding | Disposition |
|---|---|---|
| Sol 1 / agy 1a-b | `GameState.gd:83,86,177-178` and `FiresPhases.gd:22,40,42` write the hosted `GameStateData` fields; registering them without authority operations strands the plan at `migration` | **Accepted.** Verified; the two setters have zero callers. New commit 4b + three lifecycle operations. |
| Sol 2 / agy 1c | `IjfsDailyState.munitions` and `.squadron_force` are documented as persisting across days and were unregistered | **Accepted.** Both added to `hosted_fields`. |
| Sol 3 | Construction inventory incomplete; target range missed `metadata` at `:450` | **Accepted.** Verified and corrected; found a second `target.metadata =` at `:477` that Sol also missed. |
| Sol 4 | `will_fly` is not an RNG gate — selection already rejects unaffordable pairings, so both insufficiency branches are unreachable | **Accepted, and it was my error.** Verified all three selection paths route through `_rule_affordable`. Changes how the insufficiency contract must be tested. |
| Sol 5 | The aliasing claim over-reached: `manpads_intercept_log` carries no `metadata` alias | **Accepted.** Claim narrowed to the four real alias sites. |
| agy 1d | The plan misses `IjfsResolver.gd:140`'s MANPADS write | **Already covered** — it is in the mutation table and commit 6. Made explicit rather than left implied. |
| agy 2 | Registering `metadata` risks aliased-container blindness and name-backstop pollution | **Half accepted.** Blindness is real and is the stated reason for the typed field. Pollution is **not** supported: measured, `metadata` is declared on one class and all eight write sites type-resolve. Decision recorded with the measurement and a documented fallback. |

## Dependencies

Requires 0042, 0043 and 0044 so the writeback has authoritative consumers; runs after 0045 to keep
the campaign strictly one aggregate at a time. All satisfied at HEAD `55f2834`.
