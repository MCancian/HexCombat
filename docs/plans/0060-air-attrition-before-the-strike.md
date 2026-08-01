---
title: "0060: Should air attrition happen before Red strikes, instead of after?"
status: "Sketch"
created: "2026-08-01"
---

# Plan 0060: air attrition before the strike

> **DESIGN COMPLETE — the USER design session was held 2026-08-01 and produced twelve rulings (R1-R12
> below). Nothing here is blocked on a design call any more.** What remains is implementation planning:
> re-scope and retitle this plan, sequence it against [[0059-sam-interception-and-rtb]], and fit R10's
> rate to the 10%/day calibration target.
>
> **Everything BELOW the rulings section is the pre-session document, kept for its evidence and its
> reasoning trail. Several of its claims were corrected by the session — see "Corrections" — and every
> number in it was measured at the OLD force (J-16D 48 / OOB 584) that R9 replaces. Do not quote it
> without checking the rulings first.**

## USER RULINGS — design session 2026-08-01

Twelve rulings. The plan's headline question — should MANPADS move before the strike — is answered by
R5, **by replacing the mechanic rather than reordering it**. Every ruling is stated as the rule an
implementer follows plus what it breaks.

**Land R9 and R11 first.** They change the force (J-16D 48 -> 10, OOB 584 -> 546) and a class name, and
every calibration downstream is fitted against the force they define.

### R1 — The warmup is a STANDOFF campaign: missiles only, no aircraft exposed

**Rule.** Set `prelanding.rules.munition_filter` to
`{"mode": "blacklist", "ids": ["attack_uav_small", "strike_aircraft_medium"]}` — the two `Organic`
munitions. `ad_attrition_enabled` and `sead_enabled` stay `false`. The pre-invasion campaign is
CRBM/SRBM/LACM work; Red's air force is not exposed before D-day, so its zero warmup losses become
correct by construction rather than an unmodelled gap.

**Why this and not the alternatives.** Measured, 10 seeds x 12 turns, scenario_default:

| stance | Red air lost/game | strikes, final warmup day | SAMs alive after warmup |
|---|---|---|---|
| 1 Sanctuary (previous behaviour) | 35.8 (6.1%) | 103.9 | 66.9 |
| 2 Contested, Red not yet doing SEAD | 77.0 (13.2%) | ~104 | ~67 |
| 3 Full air campaign, SEAD from day 1 | 38.9 (6.7%) | ~104 | low |
| **4 Standoff — CHOSEN** | 30.0 (5.1%) | **77.3** | 66.3 |
| 5 Standoff + defences live + SEAD | 41.5 (7.1%) | 44.0 | 0.0 |

**What it breaks.** Golden re-baseline (draw order moves). Red loses ~26% of warmup strike volume
(103.9 -> 77.3 executed strikes on the final warmup day), which reaches the ground war through the
warmup's maneuver-casualty writeback — re-run the crossing/campaign studies before comparing to any
prior number.

**Do NOT quote the loss-total column as the reason.** Campaign air losses hinge on how many SAMs
survive the turn-2 SEAD sweep — a small integer — so the gaps between 30.0, 35.8, 38.9 and 41.5 are
not resolvable at 10 seeds. Only stance 2's separation is signal. The decisive numbers here are the
strike-volume and exposure columns.

### R2 — `role_exposure_multipliers` means altitude/profile exposure

**Rule.** `isr 0.7 / sead 1.0 / strike 1.2` multiplies each attrition source's **per-airframe
`p_loss`**, alongside the existing RCS survival modifier. Applies to `IjfsEngagement._sead_return_fire`
and `apply_post_phase_2_free_shot`. `IjfsManpads.contest_squadrons` already implements a harsher binary
form of the same idea via `CONTESTED_ROLES` and is not double-modified.

**What it breaks.** Golden re-baseline. Until now the block was **dead data**: `IjfsLoaders` requires
`red_aircraft_attrition_and_sead` to exist but nothing reads any field in it, so the only role logic in
the model was MANPADS' include/exclude and the only per-aircraft modifier was RCS. Implementing it
makes Red's ISR fleet measurably more survivable than its strike fleet for the first time.

**AMENDED 2026-08-01, same session (R6).** This ruling originally said MANPADS was NOT to be
role-multiplied, because `CONTESTED_ROLES` was already a harsher binary form of the same idea. R6
deletes that filter, so the multipliers now apply to the MANPADS mechanic too and are the ONLY role
differentiation in the model. All three attrition surfaces use one mechanism.

### R3 — Turn-2 annihilation of the SAM network is the BASE CASE

**Rule.** Today's behaviour stands as the default and must be reproducible exactly. Any survivability
work reproduces it at its knob's default value. This **disqualifies** re-scaling `sam_score` or adding
a durability term to `p_destroy`, since both change the base case by construction.

### R4 — Plan 0061 splits in two

Recorded in [[0061-resolution-dag]]; see its own rulings section.

### R5 — ONE MANPADS mechanic, not two — this plan's headline question, answered by replacement

**The question this plan opened with is resolved, but not by choosing an ordering.** The USER's call
is to collapse the two MANPADS mechanics into one.

Today there are two, doing different things with the same launcher stock:

| mechanic | when | effect | scope |
|---|---|---|---|
| `roll_strike_interception` | inside the strike phase, **before** each strike's own rolls | denies the munition; **never touches the aircraft** | per strike into a defended TO |
| `contest_squadrons` | after the whole post-AD strike phase | kills aircraft; never denies a munition | island-wide, every alive airframe |

**Rule.** Delete the island-wide contest. Extend interception so a MANPADS engagement can (a) abort the
mission — the existing "round denied" outcome — or (b) inflict attrition on the airframe, or both.
Because interception already runs *before* the strike resolves, the USER's "ideally before" is
satisfied for free on the strike side.

**Rule (timing).** Abort is the within-day effect; attrition is the next-day effect. `ctx.organic_budget`
is a snapshot taken at `IjfsEngine.gd:141`, before any strike resolves, so an airframe killed inside the
strike phase cannot shrink that same day's budget — but it does shrink every later day, since the budget
scales `alive/initial` over strike-role squadrons. **This is coherent and should be stated as the
design's own logic, not worked around:** the abort takes today's sortie away, the kill takes tomorrow's.

**What it breaks.**

- Golden re-baseline, and a much larger balance movement than any reordering. Losses stop being spread
  island-wide across ~500 airframes and concentrate where Red actually strikes.
- **Calibration is not a detail here.** Re-measured at R9's settled force (OOB 546): **139.1
  interception attempts per campaign** (49 / 27 / 24 / 27 / 10 / 1 by turn, then zero — MANPADS runs
  dry), producing **10.6 actual interceptions**. The island-wide contest being deleted kills **16.2**
  airframes a game. So to hold the current balance, either most interceptions must ALSO be kills — and
  10.6 interceptions cannot supply 16.2 kills, so that route is arithmetically closed — or attrition
  needs its own per-attempt roll at **p = 0.116**. **Attrition must therefore be a separate outcome of
  the engagement, not a rider on a successful interception.** That is an independent argument for R8's
  one-roll/three-outcome shape, arrived at from the numbers rather than from the idiom.
- **Attribution is the hard part, and it is a design question, not an implementation one.** Interception
  knows which *munition* was denied, not which *squadron* flew it. `red_firing_capacity` maps organic
  munitions to a `platform_type` (`aircraft` / `uav`) only. Worse, `owa_drone_small` — which carries
  `manpads_vulnerability: 1.0` and is the most-flown interceptable munition — is category
  `Inorganic-Slow` and **is flown by no squadron in `red_air_oob.json` at all**. So "shoot down the
  aircraft" has no referent for it. **Resolved by R7:** OWA drones are a separate expendable pool
  outside the OOB, so an intercepted drone is destroyed without decrementing any squadron.
- **The seam already exists and is unwired.** Every `red_firing_capacity` entry carries
  `attrition_link: null`, and `grep attrition_link --include=*.gd` returns nothing. That is the
  designed hook for exactly this mapping — second piece of dead scenario data this session found, after
  `role_exposure_multipliers`.
- **SEAD aborts have nowhere to attach yet.** The USER wants MANPADS to be able to degrade SEAD as well
  as strike. But `resolve_sead_engagement` has no per-round loop — it is one aggregate
  `effective_power` computed from summed `sead_eff` across alive airframes. A SEAD abort must therefore
  reduce that power (or the alive count feeding it), which is a different shape from denying a round.
  Needs its own design pass.

**Recommended shape for the abort/kill split, needs the USER's nod.** Mirror the SAM outcome idiom the
codebase already uses — a target is destroyed / suppressed / unengaged. Give an engaged aircraft the
same three: **killed / aborted / unaffected**, from one roll rather than two. Plan
[[0059-sam-interception-and-rtb]] noted precisely this asymmetry ("a SAM target has three outcomes; an
aircraft has two") and this closes it.

**Interaction with 0059.** This ruling makes MANPADS an abort source, which settles part of 0059's open
"which sources abort" question in the affirmative for MANPADS, and gives `rtb_today` its first real
writer. 0059 step 2 and this ruling should be planned together or they will collide in the same code.

**Scope note.** With R5 this plan is no longer "should attrition be reordered" — it is "replace the
MANPADS pair with one mechanic". Re-scope and retitle it when work actually starts.

### R6 — MANPADS affects ALL aircraft, differentiated by role exposure rather than by a filter

**Rule.** Delete `IjfsManpads.CONTESTED_ROLES` entirely. Every role — ISR included — can be engaged, with
R2's `isr 0.7 / sead 1.0 / strike 1.2` doing the differentiation. One mechanism, no include/exclude list.

**What it breaks.** Golden re-baseline. It also overrides the standing comment in `IjfsManpads`
("low-altitude attack profiles; ISR flies high"), which was the physical justification for excluding
ISR — that premise is now retired and the code comment must be rewritten rather than left contradicting
the behaviour. **Note the multiplier is a modest discount, not immunity:** 0.7 leaves ISR 70% as
exposed as a SEAD aircraft to a shoulder-launched IR missile. If the intent is "ISR is largely out of
reach of MANPADS specifically", 0.7 is too generous and MANPADS wants its own ISR exposure value.
Flagged, not decided.

Detection is unaffected either way: `aircraft_isr_raw_score` clamps at 1.0 and Red's ISR sum is 56.4, so
ISR losses do not move phase-2 detection until the fleet is >98% destroyed.

### R7 — OWA drones are a separate expendable pool, NOT part of the 584-airframe OOB

**Rule.** `owa_drone_small` stays a munition, not an airframe. A MANPADS engagement against it denies
the round and destroys the drone; **nothing decrements from `red_air_oob.json`**. Red's air order of
battle stays at 584 and continues to mean manned aircraft plus reusable UAVs only.

**What it breaks.** Nothing today — it ratifies the current data model rather than changing it, and it
dissolves R5's attribution problem for the most-flown interceptable munition. Note the consequence for
reporting: an OWA drone shot down must NOT appear in `red_air_losses` or the per-squadron OOB ledger, or
the 584 identity that every measurement in this session was checked against stops holding.

### R8 — One roll, three outcomes

**Rule.** A MANPADS engagement resolves in a single draw to exactly one of **killed / aborted /
unaffected**, mirroring the destroyed / suppressed / unengaged idiom `IjfsEngagement._engage_sam_target`
already uses for SAM targets. Not two independent rolls.

**What it breaks.** Closes the asymmetry [[0059-sam-interception-and-rtb]] named — "a SAM target has
three outcomes; an aircraft has two" — and gives `rtb_today` its first writer. 0059 step 2 and this
must be planned together; they edit the same code.

### R9 — J-16D is 10 airframes, not 48. THIS IS THE NEW BASELINE FORCE.

**Ruled 2026-08-01.** `red_air_oob.json` carried J-16D at 2 squadrons x 24 = **48**. Twenty is China's
*entire* J-16D inventory and not all of it would be committed to this theatre, so the figure is **10**.
Red's OOB becomes **546** (420 strike / 58 SEAD / 68 ISR). Measured, 10 seeds x 12 turns:

| J-16D | OOB total | SEAD fleet | Red air lost/game | share | sead_return | manpads | free shot | unsuppressed SAMs after turn 2 |
|---|---|---|---|---|---|---|---|---|
| **48** (today) | 584 | 96 | 35.8 | 6.1% | 20.2 | 15.6 | 0.0 | 0.50 |
| **20** | 556 | 68 | 45.2 | 8.1% | 29.5 | 15.4 | 0.3 | 0.80 |
| **10** | 546 | 58 | 58.1 | **10.6%** | 41.6 | 16.2 | 0.3 | 1.10 |

**Two findings that matter more than the number itself:**

1. **The turn-2 annihilation is insensitive to SEAD strength; only its PRICE is sensitive.** Cutting the
   SEAD fleet by 40% (96 -> 58) still leaves 1.9 of 78 SAMs alive after turn 2 — R3's base case holds
   unchanged. But Red's air losses rise 62% (35.8 -> 58.1). This is the return-fire knife-edge
   documented in `docs/plans/BACKLOG.md` behaving exactly as predicted: `loss_rate =
   surviving_sam_score * 0.02`, so doubling the unsuppressed survivors (0.50 -> 1.10) doubles the bill
   (20.2 -> 41.6). **Any future change to SEAD strength is a high-gearing lever on Red air losses and a
   near-zero lever on whether the network dies.**
2. **It nearly fixes the SEAD-allocation problem by itself.** With J-16D at 10 the pool is 478, the 25%
   requirement is 119.5, the manned half after OWA substitution is 59.75 — against a SEAD fleet of 58.
   The rule finally binds, but by **1.75 airframes**: mathematically yes, practically nil. Reading (B)
   or a rate above ~25% is still needed for it to mean anything. At J-16D = 20 it does not bind at all.

**What it breaks.** Golden re-baseline. **Every number elsewhere in this document was measured at
J-16D = 48 / OOB = 584 unless it says otherwise — treat those as historical.** The load-bearing anchors
were re-measured at the settled force and are restated here; R5's calibration block carries the new
figures:

| anchor | at OOB 584 (historical) | **at OOB 546 (baseline)** |
|---|---|---|
| Red air lost / game | 35.8 (6.1%) | **58.1 (10.6%)** |
| by source: sead_return / manpads / free | 20.2 / 15.6 / 0.0 | **41.6 / 16.2 / 0.3** |
| post-strike share of losses | 43.6% | **28.4%** |
| MANPADS interception attempts / campaign | ~127 | **139.1** (49/27/24/27/10/1 by turn, then 0) |
| actual interceptions / campaign | ~19 | **10.6** |
| `owa_drone_small` strike sorties / campaign | — | **100.7** (inventory 1200, capacity 180/day) |

**Note the direction of the post-strike share.** It FALLS from 43.6% to 28.4%, because a weaker SEAD
fleet leaves more SAMs alive and return fire — which is already correctly placed before the strike —
grows to dominate. The ordering question this plan opened with gets smaller still at the settled force.

**Structural question this raises, not yet answered.** With J-16D at 10, the `HARM` class — 1 squadron
x 48, `kind: unmanned`, the only other entry with `sead_eff: 1` — supplies **48 of 58**, i.e. 83% of
Red's entire SEAD capability. If the J-16D figure was wrong, this one deserves the same scrutiny:
"HARM" is a missile designation being used as an airframe class, and it is now doing almost all the
work. **USER call needed.**

**Squadron structure: 1 squadron x 10 — AGENT decision 2026-08-01, no USER call needed.** By inspection
the choice is RNG-neutral, which is not what was assumed when it was first flagged: every attrition loop
draws once per alive airframe (`_bernoulli_count(sq.alive, ...)`), and the per-airframe rate depends only
on the aircraft CLASS, so 1x10 and 2x5 consume the dice stream identically. `_expend_island_wide` is a
sequential lowest-id-first drain, so splitting one call of 10 into two of 5 leaves the same end state.
The only difference is log granularity — one `contest_log` row instead of two. 1x10 is chosen as the
simpler record of what is one real-world unit. **Verify the RNG-neutrality when implementing rather
than trusting this note**; it is an inspection result, not a measurement.

### R10 — SAM return fire becomes PER-ENGAGEMENT, not a per-force tax

**Ruled 2026-08-01.** Today `_sead_return_fire` sums the surviving SAM score once, derives one rate, and
draws against **every alive airframe in Red's inventory** — an aircraft parked in China runs the same
risk as one over Taipei. That is what produces the knife-edge (rate clamps at 1.0 against an intact
network, so the whole air force dies in a day).

**Rule.** Return fire attaches to engagements, not to the force. The hook already exists: SEAD has a
per-target loop (`_engage_sam_target`, called for each SAM in `_sorted_by_id(targets)`), so a SAM that
survives its engagement and is not suppressed draws there, against the package that engaged it —
instead of every SAM's score being pooled into one island-wide tax.

**Why this is the right shape and not just the expensive one.** It makes SAM return fire structurally
identical to R5's MANPADS mechanic: both become per-engagement rolls keyed to something that actually
happened. And **it dissolves the knife-edge by construction** rather than capping it — total losses
scale with the NUMBER of surviving SAMs engaged, each shot bounded, so there is no clamp to saturate.
The cap and the saturating-curve options were rejected as papering over the structure.

**FULL TIER, ruled 2026-08-01: strike sorties into defended TOs also draw SAM fire.** Not just the SEAD
package. A SAM engages whatever enters its envelope, and strike sorties already carry a `to_number`
exactly as MANPADS interception does — so a strike into a TO with surviving unsuppressed SAMs draws a
SAM engagement in the same place MANPADS interception is rolled. **SAM fire and MANPADS fire become the
same shape at the same hook**, differing only in which launchers are in range and the role-exposure
multiplier applied.

**CALIBRATION TARGET, ruled 2026-08-01: 10% of Red's air force per day against an INTACT IADS.**
At OOB 546 that is ~55 airframes on the worst day, against 78 unsuppressed SAM targets — roughly
**0.7 airframes per surviving SAM per day**. Fit the per-engagement rate to that, then let it fall
naturally as the network is rolled back.

**Do not port the current rate and expect 10%.** Today's turn 2 costs 41.6 airframes, which is 7.6% of
546 and looks close to target — but it is produced by ~1.1 surviving SAMs taxing the ENTIRE force. Under
R10 the same turn has up to 78 SAMs each drawing against the aircraft that actually engaged them, which
is far more fire from a far smaller per-shot rate. The two numbers are not comparable and the rate must
be fitted, not carried over.

**What it breaks.** Golden re-baseline, the largest single behavioural change in this document, and it
supersedes the "reshape return fire before touching the survivability knob" precondition recorded in
`docs/plans/BACKLOG.md` — R10 IS that reshape. Note the campaign-level consequence of the target: 10%
per day sustained against an intact network would cost Red ~72% of its air force over twelve days. That
is only reachable if the network STAYS intact, which is precisely what the mobile-SAM survivability
knob controls — so R10 and that knob must be calibrated together, not separately.

### R11 — `HARM` is anti-radiation loitering munitions; rename it, keep the count

**Ruled 2026-08-01.** The 48-airframe `HARM` entry stays at 48 and keeps `sead_eff: 1`; it represents
anti-radiation loitering munitions / UAVs, not a manned type. **Rename the class to say so** — "HARM" is
a US missile designation standing in as an aircraft class, and after R9 this entry supplies 48 of 58
SEAD airframes, 83% of Red's SEAD capability. A name that misdescribes the single most load-bearing
entry in the air OOB is a legibility defect.

**What it breaks.** `aircraft_class` is a key into `data/ijfs/air_classes.json` and appears in
`contest_log` / `air_oob_after` rows, so a rename touches both data files plus any fixture carrying the
string. Behaviour is unchanged if the count and stats hold — this should be a byte-stable rename apart
from the string itself. **Verify that**; if the golden moves, something else was keyed on the name.

### R12 — MANPADS does NOT abort SEAD sorties; attrition only

**Ruled 2026-08-01.** SEAD aircraft stay in scope for MANPADS **kills** (per R6, which put all roles in
scope), but there is no within-day abort effect on SEAD. SEAD keeps its aggregate-power shape — no
per-sortie loop is added for it — so under R5's split it gets the tomorrow-effect (fewer airframes ->
less `sead_eff`) and no today-effect.

**Why.** R5 collapsed MANPADS into a per-strike mechanic, and SEAD is not a strike: it consumes no
munitions and has no per-sortie hook. Giving it aborts would have required a third MANPADS touchpoint,
partly undoing the "one mechanic" ruling. This keeps R5 intact.

**What it breaks.** Nothing structurally. Note the interaction with R10: R10 adds a per-target loop for
return fire, which is a SAM mechanic, not a MANPADS one — R12 does not license reusing it for MANPADS
aborts against SEAD.

### Session closed 2026-08-01 — what is left is implementation planning, not design

Twelve rulings above. The remaining unknowns are all things measurement answers, not the USER:

- **Fitting R10's per-engagement rate to the 10%/day target.** A sensitivity run, not a decision.
- **Re-measuring every anchor after R9 + R11 land**, since the force and a class name both move.
- **Sequencing.** R10 (return fire) and the mobile-SAM survivability knob calibrate together. R5/R8
  (one MANPADS mechanic) collides with [[0059-sam-interception-and-rtb]] step 2 and must be planned
  with it. R9 and R11 are data changes that should land FIRST, because every calibration downstream is
  fitted against the force they define.

### Still open — nothing requiring a design call

- **Nothing is blocked on a USER design call.** The SEAD-allocation mechanic is fully specified
  (reading (B), priority fill, k = 4) in `docs/plans/BACKLOG.md`; the mobile-SAM survivability knob is
  specified in the same file and calibrates jointly with R10.

### Corrections to the measurements below, from the same session

1. **The 54.2% figure is wrong; the corrected split is 43.6%.** The original instrument left
   `turn_number` at 1, so `_derive_day_dice` produced the label `ijfs:1:0` for **all eleven**
   post-warmup days — every day redrew the identical substream. Re-measured advancing `turn_number`:
   SEAD return fire 20.2/game (**turn 2 only**), MANPADS 15.6 (turns 2-6), free shot **0.0 — it never
   fires**, total 35.8 of 584 (6.1%), identity-checked against force shrinkage.
2. **The free shot is not merely small, it is unreachable.** It is gated on `raw_sam_health > 0`, and
   `raw_sam_health` is 0.000 from turn 3 onward. Question 1 of "Design calls for the USER" below is
   therefore moot: there is nothing to move.
3. **SEAD return fire is already correctly placed.** The pre-AD strike phase excludes `Organic`
   munitions (`IjfsTargeting._filter_by_phase`, `pre_ad_recompute`), so aircraft deliver ordnance in
   the post-AD phase ONLY. Return fire runs before that. The claim that its victims "already flew their
   mission" is false — it applies to MANPADS alone.
4. **The warmup is not a missile-only campaign** (which is what R1 now makes it). Before R1, 45.9 of
   103.9 executed strikes on the final warmup day were aircraft-delivered, and warmup SAM kills split
   roughly evenly between missiles and aircraft.

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

**And a third, from the dependency trace in [[0061-resolution-dag]]: air attrition changes DETECTION,
not just striking.** `IjfsEngagement._sead_return_fire` iterates every squadron with no role filter, so
ISR airframes are shot down alongside strike and SEAD ones, and phase-2 aircraft detection then computes
its ISR score from the survivors. Moving attrition earlier therefore degrades Red's *sensing* a step
later, on top of the two effects this plan already names. That edge is second-order, was not accounted
for here, and should be on the table before any ordering is chosen. The full 18-edge inventory is in
0061; the two that matter most to this plan are D→E and D→F, which are the "more shooters alive" claim
made specific.

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
