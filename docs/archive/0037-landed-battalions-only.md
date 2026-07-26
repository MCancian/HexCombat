---
title: "0037: Only landed battalions fight, eat, and are reported"
status: "Shipped"
created: "2026-07-25"
closed: "2026-07-25"
---

> **CLOSED 2026-07-25.** Shipped as planned, with three deviations, all deliberate:
>
> 1. **The landed rule lives on `Brigade`, not `CombatForces`.** `Brigade.landed_qty(battalion,
>    brigade_not_ashore)` and `Brigade.landed_battalion_count(brigade_not_ashore)` are the single
>    home; `CombatForces` and `TurnConductor` both delegate. Forced by the dependency ceiling —
>    routing the rule through `CombatForces`/`PendingBattalions` from `TurnConductor` pushed it to
>    ndeps=40 against a ceiling of 38 — but it is the better shape anyway: the rule is a property of
>    the brigade that owns `composition`, and there is now exactly one copy of the arithmetic.
> 2. **The assert is NOT in `apply_casualty`.** The plan's invariant is transiently false *by design*
>    mid-turn: `apply_crossing_casualties` deletes drowned battalions from their rosters while they
>    are still listed in `ship_reserve` (it maps ids via the pre-removal entries) and prunes the
>    reserve immediately after. The check is `TurnConductor.pending_pool_roster_violations`, asserted
>    at the settled end-of-turn boundary beside the existing runtime-index assert.
> 3. **`GameData.snapshot_state` takes the pools as a parameter.** Reading `GameState.data` from it
>    would invert the dependency — `GameData` is the CONTENT autoload and must not depend on runtime
>    state. `SelfPlayRunner` and `tools/validate_play_turn.gd` pass them in.
>
> **Re-baseline was smaller than predicted.** Two pins moved, not four:
> `validate_dos_consumption` (36 → 16 units; 2800 → 1600 t idle, 5600 → 3200 t moved) and
> `validate_cleanup` (`casualties=5, feba=-0.72` → `casualties=3, feba=-2.66`).
> `validate_golden_victory`, `validate_headless_turn` and `validate_air_insertion` did **not** move —
> confirming the plan's own cross-check that the change is confined to partially-landed formations.
> Direction verified: Red fights weaker early, which is the expected sign.
>
> **Probed rather than trusted:** after one offload turn the four Red amphibious brigades are ashore
> with 16 of 36 battalions — exactly their 4 Amphibious Infantry BNs each; every recon,
> mechanized-artillery, air-defence, support and service-support BN is still at sea. The 36 → 16 drop
> is the mechanic working, not over-subtraction.
>
> **Cost paid on the way:** patching `SelfPlayRunner` to call `GameState.data.pending_battalion_pools()`
> re-tripped the autoload-identifier trap — the script compiles in-game but not under a `-s` SceneTree
> tool, so `validate_headless_selfplay` failed to compile, never reached `quit()`, and hung the gate
> for two full runs. Fixed by using the file's own `_gs()` accessor. See
> `hexcombat-failure-archaeology`.
>
> **The 20-turn `scenario_default` re-measurement in "Verification" was NOT run** — re-running studies
> is an open USER decision (see `docs/DECISIONS.md` 2026-07-25), not an agent call.


# Plan 0037: Only landed battalions fight, eat, and are reported

**USER call 2026-07-25:** *"Only the battalions that have landed in a brigade should count for
combat. The LLMs should only account for those too."* Plus, asked separately, supply follows the same
rule — a battalion that is not on the island neither fights nor draws Taiwan-theater supply.

## The problem

A brigade's `hex_id` is set the moment its **first** battalion lands. Everything downstream then
treats the whole formation as present, because it reads `brigade.composition` — which is the roster
of battalions that exist, not the roster of battalions that are *here*. Plan 0034 fixed this for the
victory census only. Three systems still count phantoms:

| System | Code | Effect today |
|---|---|---|
| Ground combat | `CombatForces.maneuver_units` / `support_units` / `support_counts` (`scripts/CombatForces.gd:9`, `:24`, `:40`) | a brigade with 4 of 8 battalions ashore fights with 8 |
| Red supply | `TurnConductor.active_red_battalion_units` (`:556`) | all 8 consume DOS |
| LLM observation | `LLMGameAPI._brigade_observations` (`:269`) | reports `battalions: 8`; `_ship_reserve_observations` (`:298`) shows the sea queue but never `mainland_pool` |

This is **not** the ghost-landing family — those battalions were dead and still counted. These are
alive and elsewhere. It is wider in effect than the census bug: combat strength perturbs every
contested hex every turn, rather than only the terminal count.

## The rule

A battalion counts for combat, supply, and reporting when it is **ashore** — i.e. it is in its
brigade's `composition` and NOT in any pool returned by `GameStateData.pending_battalion_pools()`
(at sea, on the mainland awaiting a hull, or waiting to fly). One definition, already centralised by
plan 0034; this plan extends its reach from one consumer to four.

## Shape of the fix

1. **`PendingBattalions.by_brigade_and_type(pools) -> {brigade_id: {type: count}}`** — the existing
   `by_brigade` sums to a single number, which is enough for the census but not for combat, where
   *which* type is missing decides whether the loss is a maneuver or a support unit. Pool entries
   already carry `{id, type}`, so the type breakdown is exact, not apportioned.
   `by_brigade` then becomes a sum over `by_brigade_and_type` rather than a second independent
   count — two counting functions that must agree is exactly the drift this plan family exists to
   remove.
2. **`CombatForces`** takes that map and emits `qty - not_ashore[type]` units per battalion entry
   (clamped at 0). All three functions, `support_counts` included — it reads `battalion.qty`
   directly. **Injection seam:** `CombatResolver.resolve_at` has no parameter for this today, so
   decide explicitly rather than drifting — either widen `resolve_at`, or have
   `TurnConductor.resolve_combat_at` compute the map once per turn and hand it in. Prefer computing
   it once per turn: it is derived from state that does not change during the combat loop, and
   rebuilding it per hex would be both wasteful and a chance for two hexes to disagree.
3. **`active_red_battalion_units`** applies the same subtraction.
4. **`_brigade_observations`** reports landed battalions in `battalions`, and gains an explicit
   `battalions_not_ashore` so a seat can see the difference rather than infer it. Add a
   `mainland_pool` observation alongside `ship_reserve` so the queue behind the crossing is visible.
5. **`GameData.snapshot_state`** (`:842`) reports `battalions` per brigade and is written into every
   game record as `final_snapshot` (`SelfPlayRunner.gd:116`) — a research surface, so it must report
   landed too, or records will disagree with the census beside them.
6. **A debug-only assert in `apply_casualty`** that a casualty never drives a type's `qty` below its
   pool count. Cheap, and it is the tripwire for the mirror-image bug: if combat ever generated a
   unit for an at-sea battalion, this fix would silently delete that battalion from the roster while
   its pool entry survived.

## The invariant this must not break

`composition` is the roster; the pools name specific battalions of it. The load-bearing relation is:

```
landed(brigade, type) == composition.qty(type) − pool_count(brigade, type)
```

Combat casualties go through `TurnConductor.apply_casualty`, which shrinks `composition` by type and
does **not** touch the pools. That stays correct *because* combat can now only generate — and so only
kill — landed battalions: `qty` can never be driven below the pool count, so `landed` never goes
negative and the census's `maxi(0, …)` clamp never has to hide anything. **Verify this explicitly**;
if combat could kill more of a type than are ashore, it would silently delete at-sea battalions from
the roster while leaving their pool entries behind, which is the census bug's mirror image.

The other three composition-shrinking paths were traced 2026-07-25 and are all safe, for different
reasons — none needs changing, but none should be *assumed* safe by a future editor:

| Path | Why it is safe |
|---|---|
| `apply_crossing_casualties` (`TurnConductor.gd:861`) | removes drowned BNs from composition **and** `ship_reserve` — symmetric |
| air-insertion losses (`TurnConductor.gd:222`) | removes killed BNs from composition **and** the air pool — symmetric |
| `IjfsResolver.apply_maneuver_casualties` | Green/ROC only, and Green has no pools |

The type breakdown is exact rather than apportioned because pool entries inherit `battalion.type` at
construction, so a pool BN's type always names a real `composition` entry of the same brigade.

## Edge cases to settle in code, not by accident

- **A brigade with `hex_id` set but zero battalions ashore is a BLOCKER, not a curiosity.** Once
  `CombatForces` emits zero units for it, the brigade is still a *contributor* — it is in the hex and
  not `destroyed` — so the side reaches `CombatCalculator` with an empty unit list. That does not
  resolve to "no combat": `CombatCalculator.gd:144-148` floors degenerate zero strengths to
  `rules.combat_min_effective_strength`, so an empty side fights with **phantom strength** and the
  enemy takes real casualties from a formation that has nobody on the island. This is strictly worse
  than today's behaviour and would be introduced *by* this change.
  **Fix: `TurnConductor.combat_contributors_for` must require landed count > 0**, not just
  `not destroyed`. Keep `hex_id` (the brigade still holds ground for ownership purposes) but exclude
  it from combat and supply contributors — confirm that ownership reading is what the USER wants if
  it turns out to change who holds a hex.
- **The unscreened-support rule** (`CombatCalculator`: a side with only support units contributes 0.5
  each and takes losses) becomes reachable in a new way — a brigade whose maneuver battalions are all
  still at sea while its artillery landed. That is correct behaviour, but it is new behaviour, and
  worth a test so it is not mistaken for a regression later.
- **Air-landed brigades** already fight out of supply until a corridor reaches them (plan 0032). That
  is orthogonal — it scales effectiveness, whereas this decides who is present at all.

## Verification

- **The golden WILL move. That is the point, and it is a deliberate re-baseline** under
  `hexcombat-change-control`, not drift: this changes ported combat math on USER instruction. Expect
  `validate_headless_turn` (the scripted beach-1 fight), `validate_cleanup`, `validate_golden_victory`
  and `validate_air_insertion` to shift. Re-baseline in ONE commit, with the before/after numbers in
  the message, and say plainly which USER decision authorised it. `validate_golden_victory` will be
  on its **seventh** re-baseline — its header comment block records the previous six, all orthogonal
  to this one; append the reason there in the same style rather than replacing the history.
- **Regenerate the committed LLM example fixtures**, which nothing else will catch:
  `docs/examples/llm_observation_red_turn1.json` and `docs/examples/llm_result_after_turn.json` both
  embed per-brigade `battalions` counts. Left stale they become a fixture that documents the old,
  wrong number. `docs/examples/llm_action_response_move_end_turn.json` has no counts and is unaffected.
- **Expected NOT to move** (useful as a cross-check — if one of these fails, the change has leaked
  somewhere it should not): `validate_headless_selfplay` and `validate_play_turn` are equality/
  determinism checks whose two sides shift together; `validate_llm_api` is shape-not-value;
  `tests/combat_resolution_test.gd` builds brigades with no pools at all; `victory_present_census_test`
  already subtracts pools.
- **Sanity check the direction before accepting new pins:** this removes Red strength from the
  opening turns (Red is the side with pools; Green has none), so Red should do *worse* early. A
  re-baseline that makes Red stronger means the subtraction has the wrong sign somewhere.
- The scripted beach-1 golden fight uses pre-placed brigades with no reserve, so check whether it
  moves at all — if it does not, that is a useful confirmation the change is confined to
  partially-landed formations.
- New unit tests: a half-landed brigade fields half its maneuver units; a brigade whose maneuver
  battalions are all at sea triggers the unscreened-support path; `support_counts` subtracts by type;
  supply units match combat units for the same brigade.
- Re-measure the 20-turn `scenario_default` reference (seed 20260624, `selfplay_default` both seats)
  used for plan 0034: census was 57 → 49 there. This change should move the *trajectory*, not just
  the endpoint.

## Risks

- **Ported combat math.** Preserving TIV's math is a standing guardrail; this deliberately diverges
  on USER instruction, so it needs a `docs/DECISIONS.md` entry and a fidelity note in
  `docs/systems/ground-combat.md`, not just a code change.
- **Every prior study is affected again**, on top of the 0034 census correction — and this one bites
  harder, since it changes the fighting, not the counting. Do NOT re-run anything without the USER.
- Two commits: mechanism + consumers first (gate green, pins updated deliberately), observation
  contract second, so a contract-schema failure cannot be confused with a combat re-baseline.

## Explicitly OUT of scope (checked, don't re-raise)

- **IJFS maneuver targeting.** Raised as a blocker in review and **rejected on the code**:
  `IjfsLoaders.build_maneuver_targets(green_brigades, …)` (`:60`) is Green-only, and Green has no
  off-map pools — mobilizing ROC brigades are wholly off-map (`hex_id == ""`) and already excluded
  everywhere. Nothing to subtract. If Red ever becomes an IJFS target, revisit.
- **View-layer counts.** `GameData.get_unit_count_in_hex` (`:599`) is called only by `UnitManager`
  (`:37`), and `InfoPanel` reads composition for display. Neither feeds the sim or a seat's
  observation. Cosmetic drift only; leave them.

## Second-order effect to expect (not a defect)

Fixing supply **partially cancels** the combat change. Half a brigade eating means Red's DOS pool
drains more slowly, so Red stays in supply longer and its landed battalions fight at full
effectiveness for more turns (`red_out_of_supply_effectiveness` is 0.5 when the pool is exhausted).
The net direction should still be "Red weaker early" — it loses bodies immediately and gains
endurance only later — but do not expect the combat delta alone to predict the outcome, and say so
when reporting the re-baseline.

## Dependencies / notes

- Builds directly on plan 0034 (`docs/archive/0034-pending-battalion-pools.md`) — reuses
  `GameStateData.pending_battalion_pools()` as the single definition of "not ashore".
- Supersedes the two BACKLOG items logged 2026-07-25 from the 0034 review.
- The supply-side behaviour this changes is currently documented as deliberate in
  `docs/systems/air-insertion.md` §9 ("A partially-arrived brigade consumes full DOS") — that note
  must be rewritten, not left contradicting the code.
