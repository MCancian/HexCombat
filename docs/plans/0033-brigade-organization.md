---
title: "0033: Brigade organization — make the readiness track real"
status: "Sketch"
created: "2026-07-24"
---

# Plan 0033: Brigade organization

## Why now

The USER intends to build on organization (2026-07-24). Before anything is built on it, the field
has to stop being a half-wired stub — **as it stands it would misbehave the moment it is read.**

## What exists today (verified 2026-07-24)

`Brigade.gd` declares the track and `TurnConductor.apply_move_orders` decrements it:

| Constant | Value | Applied? |
|---|---|---|
| `MAX_ORGANIZATION` | 100.0 | as the starting value |
| `ADMIN_MOVE_ORG_COST` | 100.0 | **yes** — on every administrative move |
| `TACTICAL_MOVE_ORG_COST` | 25.0 | **yes** — on every tactical move |
| `COMBAT_ORG_COST_PER_TURN` | 10.0 | **no** — unreferenced |
| `ORG_RECOVERY_PER_TURN` | 10.0 | **no** — unreferenced |

Three problems, in order of severity:

1. **The track is monotonic.** Nothing anywhere restores organization — not `begin_next_turn`, not
   cleanup, not `reset_to_scenario` (which reloads brigades from source, i.e. only between games).
   One administrative move, or four tactical moves, zeroes a brigade **permanently**. Wire the value
   into combat as-is and every formation degrades to zero and stays there. `ORG_RECOVERY_PER_TURN`
   exists precisely to prevent this and is never called.
2. **Nothing reads it.** `organization` feeds no combat, movement, or eligibility decision. It is
   written and displayed only.
3. **The observation misdescribes it.** `LLMGameAPI.field_glossary` tells every agent it is a
   *"0-100 readiness value affected by movement and combat"*. Combat does not touch it, and an agent
   told a number matters will spend reasoning on it. For an AI-research instrument that is a
   correctness problem, not a cosmetic one.

## Design questions for the USER

These are genuine wargame-design calls, not technical forks:

1. **What does organization DO?** Candidates, not exclusive:
   - a combat-strength multiplier (like `supply_effectiveness`, which already has the plumbing);
   - a movement-allowance gate (below X, tactical only; below Y, no move);
   - a commit-eligibility gate (`moved_admin_this_turn` already does a crude version of this);
   - a retreat/rout trigger interacting with FEBA.
2. **Recovery rule.** Flat `+ORG_RECOVERY_PER_TURN` when a brigade neither moved nor fought (what the
   existing constant implies)? Faster in supply / on a held hex? Slower when isolated (this would
   compose with plan 0032's corridor rule)?
3. **Does combat cost organization**, and is it flat per turn engaged (the unused constant) or scaled
   by losses taken?
4. **Are the current costs right?** Admin = the entire bar is a strong claim: one road march and the
   formation is combat-ineffective until it rests.
5. **Both sides, or Red only?** Supply effectiveness is Red-only (Green has no DOS model). Organization
   is a natural place to model ROC fatigue too — or deliberately not.

## Objectives (shape, pending the answers above)

1. Close the monotonic-decay hole: a recovery rule, applied at a documented seam (cleanup is the
   natural one — it already latches per-turn activity flags).
2. Wire organization into whatever the USER's answer to Q1 is, through `CombatRules` if it is a combat
   modifier (the supply-effectiveness path is the template) or `Movement` if it is an allowance gate.
3. Make the observation honest: either the glossary describes what the field actually does, or the
   field is not published until it does something.
4. Knob-register the costs/recovery so they are sweepable, per `hexcombat-config-and-knobs`.

## Verification

- **This WILL move the golden.** Organization currently affects nothing; making it affect combat is a
  deliberate behaviour change and therefore a USER-aware re-baseline per `hexcombat-change-control`,
  not a refactor. Sequence the wiring commit so the re-baseline is isolated and reviewable.
- GdUnit: decay on each move mode, recovery when idle, the floor and ceiling clamps, and whatever
  gate/multiplier Q1 selects.
- A sweep on the recovery rate is the natural check that the track has any effect at all — if outcome
  distributions are flat across it, the mechanic is decorative and should be reconsidered.

## Dependencies / notes

- Independent of everything in flight. Touches `Brigade`, `TurnConductor.apply_move_orders`,
  `CombatRules`/`CombatResolver` (if a multiplier), `Movement` (if a gate), `LLMGameAPI`.
- The `moved_admin_this_turn` commit ban is an existing, cruder version of an organization gate; if
  organization becomes the gate, that flag may become redundant — check before duplicating the rule.
