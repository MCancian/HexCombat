---
title: "0060: Should air attrition happen before Red strikes, instead of after?"
status: "Sketch"
created: "2026-08-01"
---

# Plan 0060: air attrition before the strike

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
