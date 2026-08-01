---
title: "0060: Should air attrition happen before Red strikes, instead of after?"
status: "Sketch"
created: "2026-08-01"
---

# Plan 0060: air attrition before the strike

> **BLOCKED — needs a detailed design session with the USER (their call, 2026-08-01). Do not
> implement, and do not "clarify" it by choosing an option.** This is a wargame-design decision about
> how an IJFS day is meant to read, on a mechanic ported from `ijfs_standalone` whose oracle is not on
> this box. Every option below changes Red's campaign strength, so an agent picking one is making a
> balance ruling the USER has reserved. The plan-review round does not substitute: reviewers can check
> whether the consequences are stated correctly, not which consequence is wanted.

## MEASURED 2026-08-01 — the question is not moot, and it is almost entirely about MANPADS

The cheapest item below was done first, because it was the one that could retire the plan. It did not.

**10 games × 12 IJFS days, scenario_default:**

| source | position | airframes lost |
|---|---|---|
| SEAD return fire | **before** the strike budget | 116 |
| MANPADS contest | **after** the strike | 133 |
| post-phase-2 free shot | **after** the strike | 4 |
| | **total** | **253** |

**54.2% of Red's air losses happen after the aircraft has already flown its mission.** So the effect
being argued about is a majority of all air attrition, not a rounding error.

Two things that change the shape of the decision:

1. **The free shot is negligible — 4 losses, 1.6% of the total.** That matters because the free shot is
   the hard case: its post-strike position is definitional, not incidental (see below). Since it barely
   fires, **the decision reduces almost entirely to MANPADS**, which is the one that is cleanly
   movable. The awkward half of the question is worth ~1.6% of air losses.
2. **The multi-day prelanding warmup produces ZERO air attrition** — turn 1 was 0/0/0 across all ten
   seeds. `IjfsResolver.build_warmup_context` reads `ad_attrition_enabled` from the scenario's
   prelanding rules and **defaults it to `false`**, so every air loss in a campaign comes from turn 2
   onward. Whether the warmup *should* attrit Red air is a separate USER question this plan did not set
   out to ask, and it may matter more than the ordering does.

**Method, so it can be rebuilt** (the throwaway script was deleted; `tools/` is inside the gate's
compile closure and must not accumulate scratch): drive `GameState.resolve_ijfs_turn` directly per
seed, summing the `losses` field of `contest_log` (SEAD return fire), `manpads_contest_log` and
`free_shot_log` from the returned ledgers.

**Two traps this measurement hit, for whoever redoes it at larger scale:**

- **Check the identity, do not trust the sum.** Summed log losses must equal
  `initial - alive` over the force. The first run reported a mismatch, which turned out to be a flaw in
  the *check* — `alive` was sampled before the lazily-built IJFS state existed, so the baseline was 0.
  Once fixed: 253 = 253, MATCH. Without that identity the count would have been believable and unproven.
- **Driving `resolve_ijfs_turn` in a loop does not advance the turn.** `advance_day` sets
  `_ijfs_day = turn_number`, and `turn_number` only moves when a real turn is played — measured,
  `_ijfs_day` stayed `1` for all twelve calls. Call 1 takes the warmup branch, calls 2-12 each resolve
  one plain day via `carry_to_next_day`, so distinct days DO resolve; but there is no ground combat and
  no target churn. **Treat the SHARE as the finding and the absolute numbers as indicative only.**

## What to bring to that session

The design calls are in "Design calls for the USER" below. What would make the session decide rather
than speculate is **evidence that does not exist yet**:

- **A sensitivity run over seeds, current order vs MANPADS-on-ingress**, reporting Red's landed combat
  strength and the crossing outcome — the two numbers the balance is actually judged on. The code
  change is small; this comparison IS the deliverable, and having it beforehand turns the session from
  an argument into a reading.
- **The per-turn air force curve** from [[0059-sam-interception-and-rtb]] step 1 (shipped): every turn
  record now carries the per-squadron OOB, so "how much air does Red have left by turn N" is now
  answerable and should be answered for both orderings.
- ~~**How many airframes currently die AFTER striking**~~ — **DONE 2026-08-01, see above: 54.2%.**
  The plan is not moot and the session is warranted.

Bring the two questions the measurement raised, which are arguably bigger than the one this plan
opened with: whether the free shot is worth moving at all given it accounts for 1.6% of air losses,
and whether the prelanding warmup should attrit Red air at all, since today it does not.

## Motivation (USER question 2026-08-01, out of plan 0059)

Identifying the third air-attrition source for [[0059-sam-interception-and-rtb]] exposed the phase
order in `IjfsEngine.run_daily`:

```
SEAD engagement (return fire hits squadrons)
  -> OrganicStrikeBudget computed from the surviving force   <-- the ONLY consumer of availability
  -> detection phase 2
  -> strike phase
  -> MANPADS island-wide contest
  -> post-phase-2 free shot
```

Two of the three attrition sources fire **after** the strike is already flown. So an aircraft killed by
MANPADS or the free shot still completed its mission that day, and a return-to-base abort drawn there
would be mechanically inert. The USER asked whether the sources could move before the firing.

## The answer is yes, and it is NOT a neutral reordering

This is the finding that makes it a plan rather than a chore. Moving attrition earlier is a **Red nerf
on two independent axes at once**, and they compound:

1. **Killed aircraft stop striking.** Today they die after delivering. Moved earlier, every airframe
   lost is a strike not flown — the strike budget is computed from the survivors.
2. **More shooters are alive to do the killing.** Both later sources read target state that the strike
   phase has already degraded. `IjfsManpads.contest_squadrons` counts ready systems from
   `state.targets`, and the free shot scales off `taiwan_ad_health_after`. Run before the strike, they
   see an undamaged air-defence network and therefore kill more.

So the change is not "the same attrition, sooner". It is more attrition, applied to aircraft that then
do not strike. Whether that is *right* is a wargame-design question about how the IJFS day is meant to
read, and it belongs to the USER.

## The free shot may not be movable at all

`IjfsEngagement.apply_post_phase_2_free_shot` is a port of `ijfs_standalone/engagement.py` and its
post-strike position is **definitional, not incidental**: the name encodes it, and its loss rate is
driven by `raw_sam_health` taken from `taiwan_ad_health_after` — the health that remains *once the
strike package has worked*. It models surviving SAMs taking a parting shot at a departing package.
Moved before the strike it would need a different health input (`taiwan_ad_health_after_sead` exists)
and would stop being the same mechanic. **Treat "move the free shot" as redefining it, not relocating
it** — and note the Python oracle is not on this box, so upstream cannot be consulted directly.

MANPADS is the genuinely movable one: an island-wide low-altitude contest has no intrinsic reason to
happen after the strike, and ingress-side engagement is arguably the more realistic reading.

## Design calls for the USER

1. **Which sources move?** MANPADS only (defensible, bounded), or MANPADS + a redefined free shot?
2. **Does the ingress/egress split matter?** A middle option nobody has costed: MANPADS contests on
   *ingress* (before the strike) and the free shot stays on *egress* (after) — which is both the
   realistic reading and the smallest change.
3. **How much Red weakening is acceptable?** This lands directly on the crossing/campaign balance that
   several studies are calibrated against. A sensitivity run should precede the decision, not follow it.

## Verification

- **Golden re-baseline is certain**, on both counts: draw order moves (every subsequent roll shifts)
  and outcomes change. It needs the USER's explicit call per `hexcombat-change-control`, plus a
  re-run of the crossing/campaign studies before any prior number is treated as comparable.
- A before/after sensitivity comparison over seeds is the actual deliverable here — the code change is
  small, the balance consequence is the work.

## Relationship to 0059

**0060 is not a prerequisite for 0059, and 0059 must not wait for it.** But the two interact: if
attrition moves before the strike, a return-to-base abort becomes meaningful in every source, and
0059's open "which sources abort" call collapses to "all of them". If 0060 does not happen, 0059
should draw aborts on SEAD return fire alone, since that is the only source whose outcome the strike
budget can still see. Sequence 0059 first; it is additive and reviewed, and it also gives 0060 the
per-squadron record needed to *measure* the nerf.
