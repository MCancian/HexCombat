---
title: "0061: Model a resolution day as an explicit DAG, with a substream per node"
status: "Sketch"
created: "2026-08-01"
---

# Plan 0061: the resolution DAG

> **BLOCKED — this is the USER's architectural direction (2026-08-01), stated at sketch level and not
> yet specified. It needs the same design session as [[0060-air-attrition-before-the-strike]], and the
> reading below needs the USER's confirmation before anyone builds anything.**

## What the USER asked for

> "We'll need to make a dag for this calculator and fold it into a larger campaign to make days for all
> of the calculators."

**My reading, which needs confirming:** the IJFS engine resolves a "day" as a hard-coded sequence of
six steps whose ordering is implicit and whose dependencies are undocumented. Model that day instead as
an explicit **directed acyclic graph** — each node a resolution step, each edge a real dependency
("MANPADS reads target state that the strike phase mutates", "the strike budget reads the force that
SEAD return fire attrits"). Then generalise: give every resolver/calculator the same explicit day
structure, under one campaign, so the whole turn is composed of ordered graphs rather than of function
call order.

**What I am NOT sure of and should be told:** whether "all of the calculators" means the `scripts/calc/`
role specifically (the pure calculators), or every phase resolver, or the whole turn pipeline.
The scope differs by an order of magnitude between those readings.

## Why this is worth doing, and it is not the tidiness argument

The IJFS day today is six steps sharing **one `dice` stream** (`IjfsEngine.run_daily` passes the same
`dice` to the pre-AD strike, SEAD engagement, detection phase 2, the post-AD strike, MANPADS and the
free shot). That single fact is what makes [[0060-air-attrition-before-the-strike]] expensive: moving
any step shifts every later draw, so a pure ordering experiment costs a full golden re-baseline and a
study re-run, and the RNG movement is indistinguishable from the balance movement you actually wanted
to measure.

**A substream per node dissolves that.** `Dice.derive(label)` already exists and the codebase already
uses it at coarser scope — `combat:<turn>:<hex>` (`TurnConductor`), `antiship:<turn>` (`FiresPhases`),
`ijfs:<turn>:<day>` (`IjfsResolver`), `air_insertion:<turn>` (`AirInsertionResolver`). Extending it to
step granularity is a proven pattern here, not an invention. Once each node draws from its own labelled
substream, **reordering nodes stops changing what any other node rolls**, and an ordering change costs
only the balance delta it genuinely causes.

That is the payoff, and it is mechanical rather than aesthetic: it converts ordering from an
expensive, entangled question into a cheap, isolated one. Every future question of this shape — and
0060 is only the first — gets cheaper.

**Contrast with the idea that was measured down.** A typed turn-resolution outcome was proposed and
declined on 2026-08-01 (see `docs/plans/BACKLOG.md`, standing limits) because 5 of 11 phase-report
fields are read between turns and could not move, so it would have added a mechanism beside the one it
failed to replace — a refactor with no mechanical payoff. **This proposal is the opposite case:** it
has a payoff that shows up as reduced cost on real future work. Do not read the earlier rejection as
precedent against this.

## Known costs, stated up front

- **One-time golden re-baseline.** Splitting one stream into per-node substreams changes every draw
  once. That is unavoidable and is the price of never paying it again for an ordering change.
- **A DAG must not become a scheduler.** The value here is *explicit, checkable dependencies* and
  isolated randomness. A general execution engine that topologically sorts at runtime would be a much
  larger and riskier thing, and nothing measured so far argues for it. Prefer a declared graph that is
  *validated* against a still-explicit call order — the gate can then fail when a step reads something
  no edge declares.
- **The edges have to be discovered, not asserted.** The dependency claims in 0060 were only found by
  reading (`IjfsManpads.contest_squadrons` counts ready systems off `state.targets`; the free shot
  scales off `taiwan_ad_health_after`). A DAG whose edges are guessed would be worse than no DAG,
  because it would look authoritative. The enumeration commissioned for 0060 is the start of this
  inventory and should be reused.

## Sequencing

1. **0060's design session first.** It decides whether the ordering should change at all; this plan
   decides how cheaply such decisions can be made in future. If the USER rules that the order stays as
   it is, this plan's payoff shrinks to legibility and should be re-argued on those terms.
2. **IJFS is the right first calculator** — it is the one with six ordered steps, a measured ordering
   question, and an existing per-day substream to extend.
3. Generalise only after one graph exists and has earned its keep.

## Open questions for the design session

1. Scope of "all of the calculators" — `scripts/calc/` only, every phase resolver, or the whole turn?
2. Is the DAG **declared and validated**, or **executed**? (This plan recommends declared-and-validated.)
3. Does a node's substream label include the turn and day, as the existing labels do, or something
   finer? Determinism across a campaign depends on the label scheme being stable.
4. Does this subsume the "days" concept for phases that do not currently have days, or do only IJFS-like
   multi-step phases get one?
