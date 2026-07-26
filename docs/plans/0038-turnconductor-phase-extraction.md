---
title: "0038: TurnConductor phase extraction — buy back dependency headroom"
status: "In progress"
created: "2026-07-25"
---

# Plan 0038: TurnConductor phase extraction

## Progress

- **Step 1 — `ReinforcementPhases` — SHIPPED 2026-07-25.** Measured 38 → **28**; ceiling lowered to
  28 in the same commit. `GameState.gd` held at 29 of 29 (`ship_reserve_priority_order` moved with
  the offload group, so the new module dep was a swap, not an addition). Estimates in the table below
  were upper bounds and the move beat them: `HexState` and `SealiftState` left too, because their
  last references went with the moved functions.
  **One deviation:** `RosterMutations` (`apply_casualty`, `apply_crossing_casualties`,
  `pending_pool_roster_violations`) had to be extracted in the SAME commit. It is listed under "Not
  in scope" below as a cohesion-only change that buys no headroom — that measurement stands (it costs
  `TurnConductor` +1) — but it is a *prerequisite*, not an option: air insertion moved into
  `ReinforcementPhases` and still calls `apply_casualty`, which ground combat also calls, so leaving
  the seam in `TurnConductor` would have made the two modules a reference cycle. Splitting it into
  its own commit was impossible: alone it takes `TurnConductor` to 39 and breaches the ceiling.
- Steps 2 (`FiresPhases`) and 3 (`TurnClosure`) still to do, one commit each.

`scripts/resolvers/TurnConductor.gd` measures **ndeps = 38 against a ceiling of 38** (`tools/gd_metrics.py:44`).
Zero headroom. The next mechanic that adds a phase resolver breaks the gate, and
`gd_metrics.py:19-20` forbids the easy way out: *"bumping an existing ceiling to silence a real
regression defeats the point — fix the coupling instead."*

957 loc, 42 functions. This is the largest file in the project.

## What the 38 deps actually are (measured 2026-07-25)

| Group | Count | Members |
|---|---|---|
| Phase resolvers + state builders | **13** | AirInsertionResolver, AirInsertionStateBuilder, AntishipResolver, CleanupResolver, CombatResolver, FrontlineResolver, GameStateBuilder, IjfsResolver, InfrastructureResolver, MobilizationResolver, OffloadResolver, SealiftResolver, SupplyResolver |
| Model / value types | 25 | AirInsertionSummary, Battalion, Brigade, CombatResult, CombatRules, CombatSummary, CommitOrder, Dice, GameStateData, Hex, HexOwner, HexState, InfrastructureState, JlsfCargo, MobilizationSummary, MoveOrder, Movement, SealiftState, SeededDice, ShipDef, ShipState, TerrainType, Theaters, `autoload:EventBus`, `autoload:GameData` |

**A previously-considered extraction was measured and rejected.** Pulling the roster-mutation trio
(`apply_casualty`, `apply_crossing_casualties`, `pending_pool_roster_violations`) into its own module
was the intuitive first move. It buys **nothing — in fact it makes the breach worse**: those three
functions reference only `Brigade`, `GameData` and builtins, every one of which the remaining file
still needs, so no dep leaves; meanwhile `TurnConductor` gains a dep on the new module, taking it from
38 to **39** and breaking the ceiling immediately. It may still be worth doing for cohesion — it is
where two bug families have lived — but it must never be sold as a fix for the ceiling.
(Raised by `opencode/deepseek-v4-flash-free`, sharpened by `gem-explore`, verified by measurement.)

The ceiling is driven by the **resolver fan-out**, so only moving resolver ownership moves the number.

## The seam that makes this tractable

Each resolver dep is confined to one to five phase-wrapper functions:

| Dep | Functions that name it |
|---|---|
| `OffloadResolver` | `resolve_offload_turn` |
| `SupplyResolver` | `resolve_supply_turn` |
| `MobilizationResolver` | `resolve_mobilization_turn` |
| `AntishipResolver` | `resolve_antiship_turn` |
| `FrontlineResolver` | `resolve_frontline_phase` |
| `AirInsertionResolver` + `AirInsertionStateBuilder` | `resolve_air_insertion_turn`, `isolated_air_landed_brigades` |
| `SealiftResolver` | `resolve_offload_turn`, `resolve_antiship_turn`, `crossing_reserve_from_sent_cohorts`, `apply_crossing_hull_losses`, `resolve_sealift_turn` |
| `IjfsResolver` | `resolve_ijfs_turn`, `resolve_mobilization_turn`, `update_maneuver_posture`, `sync_maneuver_targets_to_oob`, `apply_ijfs_maneuver_casualties` |
| `CleanupResolver` | `resolve_cleanup_phase`, `taiwan_battalion_census` |
| `CombatResolver` | `resolve_combat_at`, `inject_supply_effectiveness` |
| `InfrastructureResolver` | `resolve_offload_turn`, `red_lodgement_hexes` |
| `GameStateBuilder` | `ensure_antiship_systems`, `rebuild_ijfs_state` |

**And the phase wrappers are not public API.** Every one is called exactly **once**, from the
`GameState` façade; no tool or test calls `TurnConductor.resolve_*_turn` directly — they all go
through `GameState`. So a wrapper can move to another file and `GameState` can delegate there
instead, with **zero** change to any caller outside `scripts/`. This is what makes the extraction
much cheaper than the file's size suggests.

## Shape of the fix

Move phase wrappers into cohesive modules, each owning its resolvers. `TurnConductor` keeps
`resolve_turn` (the ordering, which IS its job) and calls the modules.

Candidate split, in ascending risk:

1. **`ReinforcementPhases`** — `resolve_sealift_turn`, `resolve_offload_turn`,
   `resolve_mobilization_turn`, `resolve_air_insertion_turn` + their helpers. These four share a seam
   already: they are the "force arrives" group, they run consecutively, and plan 0032's air insertion
   was deliberately slotted beside them. Carries away `OffloadResolver`, `MobilizationResolver`,
   `AirInsertionResolver`, `AirInsertionStateBuilder`, `InfrastructureResolver` — **5 deps** — but
   **NOT `SealiftResolver`**, which `resolve_antiship_turn` still names until step 2.
2. **`FiresPhases`** — `resolve_antiship_turn`, `resolve_ijfs_turn` + the IJFS maneuver-casualty and
   posture helpers. Carries away `AntishipResolver`, `IjfsResolver`, and finally `SealiftResolver`
   (its last reference outside the reinforcement group) — **3 deps**.
3. **`TurnClosure`** — `resolve_cleanup_phase`, `taiwan_battalion_census`, `resolve_supply_turn`.
   Carries away `CleanupResolver` and `SupplyResolver` — **2 deps**. These are the end-of-turn
   accounting pair: supply bills who fought, cleanup censuses who is left.

`resolve_frontline_phase` / `FrontlineResolver` is deliberately in none of these: it is not part of
the turn pipeline (operator-drawn polyline, façade-only). Moving it is a separate, optional tidy.

Step 1 alone restores meaningful headroom. Do **not** do all three in one commit.

**Estimates are upper bounds — verify by measurement after each step.** A dep only leaves when its
LAST reference does, and `SealiftResolver`, `IjfsResolver` and `InfrastructureResolver` are each named
from more than one group. Run `python3 tools/gd_metrics.py . /dev/null --check-ceiling` after every
step rather than trusting the table.

## Design calls for the USER — none

This is pure internal restructuring with no rules change and no observable behaviour change. It
needs no design input. Flagged explicitly because the USER should not be asked about it.

## Verification

- **Byte-stability is the whole acceptance test.** `bash tools/run_all_tests.sh` must be
  ALL PHASES GREEN with **no pinned validator value moved**. If any pin moves, the extraction changed
  ordering or dice consumption and must be reverted, not re-baselined.
- `python3 tools/gd_metrics.py . /dev/null --check-ceiling` after each step; **lower the ceiling** in
  `DEP_CEILINGS` to the newly-measured value in the same commit, so the headroom bought is locked in
  rather than silently re-spent.
- The `GameState` façade's forwarding methods must keep their exact names and signatures — they are
  the external contract that tools and tests call.
- **Explicit step, not a hope:** `scripts/GameState.gd` is at ceiling 29 of 29. Delegating to a new
  module adds a dep *there* unless every wrapper `GameState` called moved wholesale, making it a swap.
  After each step, re-measure `GameState.gd` too. If it breaches, the fix is to move the remaining
  wrappers so the swap completes — **not** to raise its ceiling (`gd_metrics.py:19-20`). If that
  proves impossible, stop and write the `GameState` plan first.
- One extraction per commit (`hexcombat-change-control`: golden-touching work).

## Risks

- **`GameState.gd` has the same problem and it is not addressed here** (ceiling 29, measured 29 at
  `gd_metrics.py:36`). Its typed forwarding properties structurally accumulate deps — every new phase
  state adds one. This plan can make it *worse* by adding module deps. If it breaches, that is a
  separate plan, not a ceiling bump. Raised by `opencode/nemotron-3-ultra-free`.
- **`resolve_turn`'s ordering is load-bearing and readable in exactly one place.** The real order,
  read off `TurnConductor.resolve_turn` 2026-07-25, is: **IJFS → IJFS maneuver casualties → sealift →
  antiship → offload → mobilization → air insertion → movement → combat → supply → cleanup.** Note
  IJFS runs FIRST, supply runs LATE (after combat, so the bill covers who actually fought), and
  `resolve_frontline_phase` is **not in this pipeline at all** — it takes operator-drawn polyline
  coordinates and is called only from the `GameState` façade. Splitting the pipeline across modules
  can hide this. Mitigation: `resolve_turn` must keep the full ordered call list in its body — modules
  own the *how*, never the *when*.
- **Dice-stream identity.** Any phase that draws dice must draw them at the same point in the same
  order. This is what the golden pins protect; it is also why one extraction per commit matters.

## Not in scope

- The roster-mutation extraction (measured above to buy no headroom). If done, it is a separate,
  cohesion-motivated change.
- `GameState.gd`'s forwarding-property tax.
- Any behaviour change whatsoever.

## Dependencies / notes

- Measurements taken at commit `b76bac1`, 2026-07-25, from `tools/gd_metrics.py` output.
- Prompted by plan 0037, which hit the ceiling mid-implementation and had to reshape its design
  (the landed-battalion rule moved onto `Brigade`) to stay under it. That reshape was an improvement,
  but the next one may not be so lucky — the ceiling is now a live constraint on design, not a
  background check.
