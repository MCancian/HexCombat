---
title: "0060: Localize MANPADS and SAM air attrition to engagements"
status: "Shipped"
created: "2026-08-01"
updated: "2026-08-01"
---

# Plan 0060: localize MANPADS and SAM air attrition to engagements

**SHIPPED 2026-08-01.** All five stages implemented, each reaching a full green gate with one named
golden cause. Facts landed in `docs/systems/ijfs/ijfs.md` (§2 file table, §3 pipeline, §4 formulas,
§8 data files, §9 authority, and the rewritten "MANPADS layer" section),
`docs/systems/ijfs/STATUS.md`, `tools/mutation_authority_manifest.json` and
`tools/validate_ijfs_data.gd`. Decision changelog: `docs/DECISIONS.md` 2026-08-01. Plan 0059 step 2
(`rtb_today`'s first runtime writer) is folded in and shipped here, so plan 0059 closes with it.

## What shipped, and the ONE thing that did not

Stage 1 (R9 + revised R11 + R1) · stage 2 (R2) · stage 3 (R5/R6/R7/R8/R12 + 0059 step 2) · stage 4
(revised R11 staged SEAD) · stage 5 (R10). Golden pins moved five times, each with its cause recorded
in the validator.

**CLOSURE REPORTED TO THE USER, NOT RESOLVED — R10's calibration checkpoint is unreachable.** R10
asks for "about 10% of the final 498-airframe OOB (~50 losses/day) against an intact IADS" and tells
the implementer to report a closure rather than force a fit. Measured, 6 seeds x 6 real turns through
`GameState.play_turn`:

| `sam_package_return_fire_factor` | turn-2 SAM kills | note |
|---|---|---|
| 0.02 | 0.8 | |
| 0.17 | 3.2 | **shipped** — the largest value keeping `p_loss` a real probability for every SAM/airframe pair |
| 0.20 | 3.2 | |
| 1.00 | 7.0 | every contact killing with near-certainty |

**The ceiling is ~7.5 losses on the first defended day, roughly 7x short of the checkpoint, and it is
STRUCTURAL rather than a knob being too low.** Three ruled constraints multiply:

1. R10 requires return fire to run only after the complete destroy/suppress pass. R11's staged SEAD
   leaves ~8.7 of 78 SAMs alive by then, so almost nothing is left to shoot back.
2. Each surviving SAM gets ONE roll per package and kills at most one airframe.
3. Most strike targets sit in no theatre at all, so no SAM can reach those packages.

The same closure applies to MANPADS: only ~6 eligible Maneuver-Unit package engagements exist per
turn (`strike_aircraft_medium` is capacity-limited to 7 packages/day), so at the shipped
`manpads_attrition_factor` 0.4 it produces ~1.5 kills/turn against the deleted island-wide contest's
15.6 per campaign. Widening the scope or allowing multiple kills per engagement would close the gap
and is exactly what R5 forbids.

**The USER's call, not the implementer's.** The reachable levers are all design changes: engage
return fire BEFORE the SEAD pass (contradicts R10), let a SAM engage more than one package member,
raise the anti-radiation and aircraft-SEAD effect so fewer SAMs die on the first defended day, or
accept that a 498-airframe force loses ~14 airframes per campaign rather than ~50 per day.

## Shipped values

| Knob | Value | Why |
|---|---|---|
| `manpads_attrition_factor` | 0.4 | keeps `p_kill + p_abort` well inside 1 for every class |
| `sam_package_return_fire_factor` | 0.17 | the largest value keeping `factor x sam_score x role_exposure x rcs_survival <= 1` for a Patriot against the least survivable airframe — above it the `sam_score` gradient saturates and stops meaning anything, which the engagement now ASSERTS rather than clamps |

## Progress

- **SHIPPED.** Every stage is implemented and gated. Transitional code: none.
- Pre-implementation review completed in two rounds. Round 1 forced the 498-airframe/anti-radiation
  inventory/package/TO redesign; round 2 reached reviewer quorum and its capacity-unit, SEAD-package,
  suppression, zero-survivor, RNG, Antelope-source, survivability-knob, and ledger findings are folded
  into the implementation contracts and final rulings below.

## Dependencies and implementation order

Required reading: `hexcombat-change-control`, `hexcombat-architecture-contract`,
`hexcombat-code-quality`, `hexcombat-validation-and-qa`, `hexcombat-config-and-knobs`, and
`hexcombat-docs-and-writing`. Coordinate the RTB field with
[[0059-sam-interception-and-rtb]] step 2; follow `.claude/REVIEWERS.md` for the plan/diff rounds.

Each stage reaches the full green gate before the next, so every golden movement has one named cause:

1. **R9 + revised R11 + R1:** J-16D 10; remove the 48 pseudo-airframe anti-radiation row; replace the
   60 Decoys with 60 Attack UCAVs; add the 192-missile anti-radiation inventory and standoff warmup.
   The final reusable OOB is 498. Build and validate the new SEAD data shape before changing combat.
2. **R2:** activate role-exposure multipliers on the current SAM/free-shot paths only; prove role and
   RCS modifiers compose rather than replace one another.
3. **Revised R5/R6/R7/R8/R12 + 0059 step 2:** delete the island-wide contest; narrow MANPADS to
   four-aircraft manned packages striking Maneuver Units; add typed package attribution, bounded RTB,
   and ledger migration. Do not fit final loss rates yet.
4. **Revised R11 aircraft-SEAD stage:** resolve twelve four-missile anti-radiation salvos, compute
   weighted IADS health, assign J-16Ds plus 0.25-effect strike backfill, and subtract
   `sead_assigned_today` before building strike packages.
5. **R10:** deploy all SAM instances by TO, move return fire to package engagements on a derived
   substream, then jointly fit SAM and MANPADS attrition against the final 498-airframe force.

R3 now permits the staged SEAD design to change turn-2 SAM survival; it is a measurement/reporting
requirement rather than a preservation constraint. R4 remains in plan 0061.

## Implementation contracts from plan review

- Add typed air-package / engagement-context objects rather than appending parameters to
  `roll_strike_interception` or the already-grandfathered `resolve_sead_engagement` signature. A typed
  strike-resolution context also absorbs phase/doctrine fields plus `survivors / 4.0`; do not append a
  tenth parameter to `IjfsStrike.resolve_strike`. Pay for any new `IjfsEngine` dependency by moving its
  air-OOB row builder out; do not raise dependency or parameter ceilings.
- `IjfsTransitions` remains the one IJFS writer. Add job-shaped operations for SEAD assignment and
  package abort/loss; do not split a second authority. Update the manifest rationale, add
  `sead_assigned_today`, remove `manpads_contest_log`, and refresh the real-claims pin.
- Validate every new JSON key and exact shape at load: `attrition_link`, `package_size`,
  `to_distribution`, anti-radiation inventory/capacity, and the 0.25 ordinary-aircraft SEAD factor.
  Unknown classes/TOs, empty links, bad sums, and probability bands above 1 fail loud.
- The low-level IJFS ledger is public through `GameState.resolve_ijfs_turn`. Define replacement event
  keys before deleting the old log, update `LLMGameAPI`/`GameNarrative`, regenerate fixtures, and run a
  repository-wide zero-reference check for `manpads_contest_log`, the old HARM class, and Decoys.
- Derive and retain one daily child stream for anti-radiation resolution, package assembly, and SAM
  return fire; never re-derive the same label per package. SAM hit/victim selection uses one draw and
  the same candidate/fractional-remainder transform as MANPADS. Prove isolation with real SeededDice;
  ScriptedDice deliberately shares queues across `derive` and cannot prove it.
- Dedicated tests cover: zero warmup anti-radiation expenditure; 48 missiles on each eligible day with
  at least 12 targets; exhaustion after four such days/no 49th salvo; slower depletion below 12 targets;
  weighted-score health; raw-headcount J-16D-first plus 0.25-effect backfill; TO totals; four-member
  package/airframe-sortie caps; mixed-class RCS; inclusive 1.0 draws; kill-then-degraded strike;
  all-four-ingress loss with no strike draws; abort-all-survivors; abort then free-shot; day reset;
  empty linked pools; and SAM destruction results independent of return-fire draw count.

> **DESIGN COMPLETE — the USER design session was held 2026-08-01 and produced twelve rulings (R1-R12),
> then two same-day follow-ups revised R3/R5/R6/R7/R8/R9/R10/R11/R12 after plan review. Nothing here is
> blocked on a design call any more.** What remains is implementation and measurement: sequence against
> [[0059-sam-interception-and-rtb]], measure package engagement volume, and jointly fit the final SAM
> and MANPADS rates against the 498-airframe force.
>
> **Everything BELOW the rulings section is the pre-session document, kept for its evidence and its
> reasoning trail. Several of its claims were corrected by the session — see "Corrections" — and every
> number in it was measured at the OLD force (J-16D 48 / OOB 584) that R9 replaces. Do not quote it
> without checking the rulings first.**

## USER RULINGS — design session 2026-08-01

Twelve rulings, with R3/R5/R6/R7/R8/R9/R10/R11/R12 carrying same-day USER follow-ups after plan review
exposed missing operation triggers, package geometry, SAM geography, and an expendable munition
misrepresented as reusable airframes. The plan's headline question —
should MANPADS move before the strike — is answered by R5, **by replacing the mechanic rather than
reordering it**. Every ruling below is the final rule an implementer follows plus what it breaks.

**Land R9 and revised R11 first.** Together they change J-16D 48 -> 10, remove the 48 expendable
pseudo-airframes, replace Decoys with Attack UCAVs at the same count, and establish the 498-airframe
force every downstream calibration uses.

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
`p_loss`**, alongside the existing RCS survival modifier. It applies to SAM return fire, the
post-phase-2 free shot, and the revised MANPADS kill probability for a linked reusable strike platform.
The deleted island-wide contest and its `CONTESTED_ROLES` filter provide no surviving role logic.

**What it breaks.** Golden re-baseline. Until now the block was **dead data**: `IjfsLoaders` requires
`red_aircraft_attrition_and_sead` to exist but nothing reads any field in it, so the only role logic in
the model was MANPADS' include/exclude and the only per-aircraft modifier was RCS. Implementing it
makes Red's ISR fleet measurably more survivable than its strike fleet for the first time.

**REVISED 2026-08-01 follow-up (R6/R10).** MANPADS uses the strike multiplier only. Per-engagement
SAM fire uses SEAD or strike according to the exposed package; ISR has no final SAM/MANPADS engagement
hook and uses its multiplier only if the post-phase-2 free shot is reachable. Subtract
`sead_assigned_today` when forming new strike/free-shot pools, but not from R10 return fire against the
already-formed SEAD package — those assigned aircraft are precisely the exposed victims. Subtract
`rtb_today` from every later pool so an aircraft already home cannot be killed. Role exposure and RCS are intentionally cumulative:
profile/altitude and signature are different survival advantages.

### R3 — Turn-2 SAM annihilation is no longer a preservation constraint

**REVISED USER RULING 2026-08-01 after plan review.** The staged anti-radiation volley in R11 resolves
before aircraft SEAD and is allowed to change which SAMs survive turn 2. Do not preserve, cap, or
recreate the old annihilation result by hidden scaling. Keep `sam_score` and the destroy/suppress
formula itself unchanged, then report the new turn-by-turn survival distribution across seeds. Golden
and target-level outcomes re-baseline deliberately.

### R4 — Plan 0061 splits in two

Recorded in [[0061-resolution-dag]]; see its own rulings section.

### R5 — ONE LOCAL MANPADS mechanic, only when Red strikes Maneuver Units

**REVISED USER RULING 2026-08-01, follow-up.** Delete the island-wide `contest_squadrons` pass. A
MANPADS engagement now exists only inside the existing pre-strike interception hook, and only when the
strike target's category is exactly `Maneuver Units`. MANPADS no longer taxes aircraft merely for being
in the campaign, and it does not protect SAM, radar, infrastructure, anti-ship, or other target
categories. The launcher must be in the struck target's TO and ready under the existing stock rules.

Only `strike_aircraft_medium` can trigger MANPADS: it is the only vulnerable munition with
Maneuver-Unit pairings, and the USER explicitly limited this threat to manned strikers. Populate its
`attrition_link` with the five manned strike classes and `package_size: 4`. Populate
`attack_uav_small` separately with the new `Attack UCAV` class and package size 4 for R10 SAM fire, but
mark it MANPADS-ineligible; do not add new Maneuver-Unit pairings merely to create exposure.

MANPADS kill probability is `threat_fraction * fitted_attrition_factor *
munition.manpads_vulnerability * role_exposure * rcs_survival`; abort probability remains the existing
interception formula. Both use the same vulnerability as a property of exposure but have separate base
factors. The loader hard-validates the attrition-link keys, class existence, nonempty pool, and package
size. Package eligibility is `alive - rtb_today - sead_assigned_today`; no path may select an aircraft
already unavailable today.
`owa_drone_small` deliberately keeps `attrition_link: null` under R7.

**Rule (timing).** Build `OrganicStrikeBudget` only after R11 books `sead_assigned_today`, using
`alive - sead_assigned_today - rtb_today`. The budget remains a package-count snapshot; each actual
package is assembled from currently available airframes immediately before ingress. A MANPADS kill
reduces that package now and the OOB tomorrow; a MANPADS abort returns every surviving package member,
denies today's strike, and excludes those airframes from later package assembly.

**Calibration correction.** The earlier 139.1-attempt / p≈0.116 argument counted MANPADS attempts
against every target category and is invalid under this narrower ruling. Re-measure eligible
Maneuver-Unit attempts at the final 498-airframe force before choosing the attrition factor. The
deleted island-wide contest's historical losses are a comparison, not a target; do not force a fit by widening
scope or allowing multiple kills per engagement: if one kill per eligible engagement cannot approach
that total at `p <= 1`, report the closure to the USER. Kill and abort remain mutually exclusive under
R8, so attrition is not a rider on a successful abort.

**Interaction with 0059.** MANPADS is an abort source only for linked reusable strike platforms and
gives `rtb_today` its first real writer. Fold in 0059 step 2: `IjfsTransitions` gains the bounded abort
operation, `carry_to_next_day` clears `rtb_today`, and the air-OOB ledger reports it. OWA interception
never writes `rtb_today`.

**Ledger/state migration.** `manpads_intercept_log` becomes the single MANPADS event stream. Each row
carries target/TO/munition, package members before and after, outcome, attributed losses, RTB count,
and whether the strike executed. Summary keys become explicit `attempts`, `kills`, `aborts`, and
`unaffected`; `interceptions = kills + aborts` remains as a compatibility total for narrative/API
consumers. `red_air_losses` sums kills only. Delete `manpads_contest_log` from `IjfsDailyState`, the
public ledger, summary math, mutation manifest, real-claims pin, tests, and system docs; regenerate the
LLM result fixture and update `GameNarrative`'s source wording.

**What it breaks.** Golden re-baseline and the low-level `resolve_ijfs_turn` ledger shape. It removes
both prior MANPADS surfaces (all-target interception and island-wide contest) in favor of one local
Maneuver-Unit-strike surface, concentrating losses on the platform actually exposed. It also
deliberately supersedes the original same-day R5 scope that tried to keep ISR and SEAD inside MANPADS
despite having no local operation to attach them to.

### R6 — MANPADS affects the exposed STRIKE platform, not every aircraft in the theater

**REVISED USER RULING 2026-08-01, follow-up.** Remove `IjfsManpads.CONTESTED_ROLES` together with the
contest itself; do not replace it with another role filter or all-role pool. Only a manned `strike_aircraft_medium` package can be killed or aborted. Attack UCAV, ISR, SEAD, and
inorganic munitions receive no MANPADS roll.
Their altitude/profile multipliers remain live for SAM return fire and the free shot under R2.

**Why.** The original all-role ruling had no local trigger for aggregate ISR or SEAD operations. An
island-wide pass would preserve the mechanic R5 deletes, while attaching ISR losses to unrelated
strikes or detections would be artificial. Local exposure is cleaner: the MANPADS threat is tied to the
Maneuver-Unit strike that actually entered its envelope.

**What it breaks.** This supersedes the original R6 all-aircraft scope and R12's MANPADS-on-SEAD
requirement. ISR/SEAD loss projections from the old contest are historical, not calibration targets.

### R7 — OWA drones remain an expendable munition pool outside the 498-airframe OOB

**Rule.** `owa_drone_small` stays a munition with `attrition_link: null`. It has no Maneuver-Unit
pairing, so under revised R5 it receives no MANPADS engagement at all; do not add a pairing merely to
make the old interception path reachable. It remains ordinary expended strike inventory and never
changes `red_air_losses`, `rtb_today`, or the squadron ledger.

This is separate from R11's new `anti_radiation_owa` inventory: both are expendable, but only the latter
runs in the dedicated pre-aircraft SEAD stage.

### R8 — Four-airframe packages; one mutually exclusive MANPADS outcome

**Rule (package assembly).** Every Organic strike log entry reserves exactly four available airframes
from its validated `attrition_link`. Use a typed package object carrying its four squadron references;
select without replacement on a dedicated derived substream so package composition does not borrow the
strike-resolution stream. Clamp the rare `randf() == 1.0` boundary to the last eligible index. If four
linked airframes are unavailable, the strike does not launch and records a named package-unavailable
skip before consuming capacity.

**Capacity units.** Existing `firing_units * sorties_per_unit_per_day` values are airframe-sortie seats,
not package counts. Divide by package size: full-health `strike_aircraft_medium` is
`floor(36 * 0.8 / 4) = 7` packages/day and `attack_uav_small` is `floor(40 * 2.0 / 4) = 20` packages/day.
Track seats/packages used so the same OOB may fly multiple daily sorties only within that authored
capacity; never interpret 80 UCAV seats as 80 four-ship attacks. A package cannot contain the same
airframe twice.

**Rule (ingress order).** R10 same-TO SAMs engage first, one at a time in stable target-id order, and
each successful SAM roll kills at most one package member. Stop once all four are dead. If the target
is a Maneuver Unit and at least one manned package member survives, MANPADS then consumes exactly one
draw:

- **killed:** one selected member dies; the survivors press the attack;
- **aborted:** every survivor returns, each source squadron books RTB, and the strike is denied;
- **unaffected:** the full surviving package presses.

Killed and unaffected packages with at least one survivor resolve the strike with final
destroy/suppress probabilities multiplied by `survivors / 4.0`. If SAM/MANPADS kills all four, record
an `ingress_destroyed` executed-sortie row (capacity spent, no delivery) and consume no strike
kill/suppression draws; this is distinct from a package that never launched. A MANPADS candidate is selected from the package, not the global OOB; use the
`floor(u*N)` / fractional-remainder transform for an unbiased candidate-specific outcome and clamp the
inclusive-1.0 boundary. Assert each candidate's kill+abort bands are at most 1.0. A killed aircraft can
never also be RTB, and all later attrition excludes booked RTB/SEAD-assigned airframes.

**What it breaks.** Gives `rtb_today` its first runtime writer and adds `sead_assigned_today` as a
second per-day availability ledger. Both are owned by `IjfsTransitions`, reset at the day boundary, and
serialized in `air_oob_after`; update the manifest rationale and replace the old no-writer
characterization test. This folds in 0059 step 2.

### R9 — J-16D is 10 airframes; revised R11 makes the final reusable OOB 498

**Ruled 2026-08-01.** `red_air_oob.json` carried J-16D at 2 squadrons x 24 = **48**. Twenty is China's
*entire* J-16D inventory and not all of it would be committed to this theatre, so the figure is **10**.
R9 alone produced the transitional 546-airframe force measured below. Revised R11 then removes the 48
expendable anti-radiation pseudo-airframes and renames the existing 60 Decoys as reusable Attack UCAVs
without changing their count. **The final baseline is 498: 420 strike / 10 dedicated SEAD / 68 ISR.**

The following 10-seed x 12-turn table is historical evidence for the J-16D decision, not a calibration
of the final R11/R10 design:

| J-16D | OOB total | SEAD fleet | Red air lost/game | share | sead_return | manpads | free shot | unsuppressed SAMs after turn 2 |
|---|---|---|---|---|---|---|---|---|
| **48** (historical) | 584 | 96 | 35.8 | 6.1% | 20.2 | 15.6 | 0.0 | 0.50 |
| **20** | 556 | 68 | 45.2 | 8.1% | 29.5 | 15.4 | 0.3 | 0.80 |
| **10** | 546 | 58 | 58.1 | **10.6%** | 41.6 | 16.2 | 0.3 | 1.10 |

**Two historical findings that motivated the follow-up (not claims about the final design):**

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
J-16D = 48 / OOB = 584 unless it says otherwise — treat those as historical.** Even the 546 column below
is now transitional evidence: it predates R11's removal of the expendable row, the new SEAD sequence,
and package-local attrition. No final-498 calibration exists yet.

| anchor | at OOB 584 (historical) | at OOB 546 (transitional) |
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

**Structural question resolved by revised R11.** The historically named `HARM` row was not an
airframe class at all. The USER reclassified it as 192 expendable missiles (48 four-missile salvos) in
the munition inventory, removing it from squadron `alive`/loss/RTB accounting.

**Squadron structure: 1 squadron x 10 — AGENT decision 2026-08-01, no USER call needed.** By inspection
the choice is RNG-neutral, which is not what was assumed when it was first flagged: every attrition loop
draws once per alive airframe (`_bernoulli_count(sq.alive, ...)`), and the per-airframe rate depends only
on the aircraft CLASS, so 1x10 and 2x5 consume the dice stream identically. `_expend_island_wide` is a
sequential lowest-id-first drain, so splitting one call of 10 into two of 5 leaves the same end state.
The only difference is log granularity — one `contest_log` row instead of two. 1x10 is chosen as the
simpler record of what is one real-world unit. **Verify the RNG-neutrality when implementing rather
than trusting this note**; it is an inspection result, not a measurement.

### R10 — SAM return fire becomes package-local and geographically explicit

**Ruled 2026-08-01.** Delete the pooled `_sead_return_fire` force tax. A SAM may attrit only an aircraft
actually assigned to the SEAD package or to a four-airframe Organic strike package in its TO.

**SAM deployment.** All 78 expanded SAM instances receive exactly one TO. The USER-set theater weights
are TO2 10% / TO3 50% / TO4 20% / TO5 20%. Because instances are indivisible, use the deterministic
8 / 39 / 16 / 15 split below; each source row carries an explicit `to_distribution` whose values sum
to its quantity, and the loader stamps `to_number` on every expanded instance:

| SAM source | TO2 | TO3 | TO4 | TO5 | total |
|---|---:|---:|---:|---:|---:|
| Mobile Antelope | 5 | 25 | 10 | 10 | 50 |
| Patriot PAC-3 | 1 | 4 | 2 | 2 | 9 |
| Tien Kung II | 1 | 3 | 1 | 1 | 6 |
| Tien Kung III | 1 | 3 | 1 | 1 | 6 |
| NASAMS | 0 | 2 | 1 | 0 | 3 |
| Static RIM-7/Skyguard | 0 | 2 | 1 | 1 | 4 |

Consolidate the four old TO-named Antelope source rows into one `sam_mobile_antelope` quantity-50 row
before applying its 5/25/10/10 distribution; otherwise the old source IDs would lie about geography.
This deliberately changes expanded target IDs/order, so pin the new stable IDs. Validate every per-row
sum and final TO total. No missing TO may silently mean island-wide, TO0, or immune.

**SEAD return fire.** Finish the complete sorted SAM destroy/suppress pass first. On a dedicated
derived `sam_return_fire` substream, each surviving unsuppressed SAM then gets one attrition-only roll
against the actual R11 aircraft-SEAD package. This keeps return-fire draws from shifting later SAM
outcomes. A hit selects one available package member proportional to its squadron representation and
kills at most one.

**Strike return fire.** Assemble the four-airframe package first. Before MANPADS or strike resolution,
every surviving unsuppressed SAM in the target's TO engages once in stable target-id order; each hit
kills at most one survivor and engagement stops when the package is empty. Both
`strike_aircraft_medium` and `attack_uav_small` have validated class-specific links, so SAM fire can
attrit manned packages and the renamed 60-airframe Attack UCAV pool without charging UCAV losses to
Decoys. A SAM may engage multiple distinct packages in one day; casualty count is nevertheless capped
by each package's four actual members.

**SAM event contract.** Keep the public `contest_log` key but replace its old per-squadron force-tax
rows with one row per SAM-package contact: SAM target ID/TO/score, package kind/ID, munition (null for
SEAD), member count before/after, victim squadron/class or null, p/roll, and losses 0/1. Summary retains
`contest_losses` as the sum. The end-of-day identity must prove total squadron shrinkage equals SAM
kills + MANPADS kills + free-shot kills.

**Probability.** Preserve SAM capability by using `p_loss = fitted_sam_return_factor * sam_score *
role_exposure * rcs_survival`, asserted in [0,1]. One uniform draw selects a package candidate and uses
its fractional remainder for the candidate-specific hit, matching R8 and avoiding a second victim draw. Fit the base factor from measured package engagements;
`0.7 losses per SAM-day` is an aggregate sanity ratio, not a per-roll probability.

**Calibration checkpoint.** Against an intact IADS, target about 10% of the final 498-airframe OOB
(~50 losses/day), but report the full role-specific curve: J-16D/SEAD backfill losses, manned strike
losses, Attack UCAV losses, SAM survival, strike volume, and crossing outcomes. The USER explicitly
allows the revised SEAD design to change turn-2 network survival, so the 10% figure is a checkpoint to
inspect rather than a reason to force the old annihilation result. Jointly fit this factor with the
MANPADS factor only after R11 and package geometry are live.

**What it breaks.** Golden and fixture re-baseline, new SAM deployment content, and a much larger draw
count. The structural gain is that losses scale with real SAM-package contacts while remaining bounded
by exposed package size, rather than taxing aircraft parked outside the engagement.

### R11 — anti-radiation OWA inventory resolves first, then aircraft are assigned to SEAD

**REVISED USER RULING 2026-08-01 after plan review.** The old 48-airframe `HARM` row represented
expendable one-way anti-radiation munitions and never belonged in squadron `alive`/RTB accounting.
Delete it from `red_air_oob.json`, `air_classes.json`, and the class allowlist. Add a dedicated
`anti_radiation_owa` munition with **192 missiles total**, **4 missiles per engagement**, and a daily
capacity of **48 missiles / 12 engagements** — 48 four-missile salvos across four full-capacity days.
It is not `owa_drone_small` and does not enter the ordinary strike phase.

**Stage A — expendable SEAD.** Before aircraft SEAD, choose up to 12 active (not destroyed or
suppressed) SAM emitters in descending `sam_score`, then stable `target_id`, one salvo per target. This
anti-radiation stage may home on active emitters regardless of `detected_this_turn`; detection gating
applies to the later aircraft stage, not to a weapon whose target signal is the emission itself. Each salvo has effective power 4 and uses
the existing target formula: `p_destroy = 4 / (4 + sam_score)`; on survival,
`p_suppress = p_destroy * 0.4`. Spend all four missiles whether the salvo destroys, suppresses, or
misses. This stage draws from its retained daily derived substream and writes target outcomes through
`IjfsTransitions`. Stage C skips both destroyed and currently suppressed Stage-A targets; it never
clears or overwrites their Stage-A result that day.

**Stage B — weighted IADS health.** After Stage A, compute
`remaining_unsuppressed_sam_score / initial_sam_score` over all Moveable, Static, and Mobile SAM
instances. Destroyed and currently suppressed systems contribute zero. This weighted score, not raw
instance count and not mobile-SAM-only health, drives aircraft assignment.

**Stage C — aircraft assignment with real effect.** The requirement is raw HEADCOUNT:
`ceil(0.25 * alive_strike_airframes * weighted_iads_health)`. At full health it is 105 aircraft;
alive J-16Ds fill 10 places first, then 95 ordinary strike-role airframes fill the rest. Allocate that
ordinary headcount proportionally across available manned strike and Attack UCAV squadrons by alive
strength, using largest-remainder rounding and stable squadron-id tie breaks. Each ordinary airframe
counts as one assigned head but contributes `sead_eff = 0.25`, so the full-health base power is
`10 + 95 * 0.25 = 33.75`, before WVR/RCS modifiers.

Run the ordinary aircraft-SEAD destroy/suppress pass against SAMs still active after Stage A, using
only the actual assigned package to compute summed SEAD power and package-average WVR/RCS. Activate
the already-ruled `sead_undetected_engagement` scenario scalar on this pass only: default 1.0 preserves
full engagement of undetected SAMs; lower sweep values multiply effective power against targets with
`detected_this_turn == false`. Assigned strike airframes are unavailable to Organic strikes that day
but remain exposed to R10 SEAD return fire. Record per-squadron `sead_assigned_today`, reset it with `rtb_today` at the next day boundary,
serialize both, and build R10's victim package from those same assigned references.

**Attack UCAV correction.** Rename the existing 60-airframe `Decoys` strike row/class to `Attack UCAV`
rather than adding force. Its attrition link exclusively backs `attack_uav_small`; the existing
`firing_units: 40` means 40 of the 60 establish 80 airframe-sortie seats/day, i.e. twenty four-UCAV
packages; losses scale those seats from the real 60-airframe pool. This avoids charging UCAV losses to a fictitious Decoy
class.

**What it breaks.** The reusable OOB drops from the transitional 546 to 498 and SEAD changes from one
aggregate 58-power sweep to a staged munition/assignment sequence. R3 explicitly allows the resulting
SAM-survival change. Rebaseline every IJFS/campaign golden and regenerate the air-OOB fixture; all old
546-force loss and interception anchors become historical.

### R12 — SEAD and ISR are outside MANPADS; SAM return fire remains separate

**REVISED USER RULING 2026-08-01, follow-up.** MANPADS neither kills nor aborts SEAD or ISR aircraft.
Do not add a per-SAM-target MANPADS hook, a detection-triggered hook, an all-role victim pool, or a
reduced daily contest. SEAD uses R11's explicit assigned package; ISR keeps its aggregate detection
shape.

R10's per-engagement SAM return fire applies to the assigned SEAD package and four-airframe Organic
strike packages in defended TOs. That is a different weapon/range model and must not be widened back into an island-wide force tax.
Thus this revision narrows MANPADS without undoing R10.

**Why.** A shoulder-launched threat belongs to the low-altitude Maneuver-Unit strike that exposed the
platform. The original R12 demanded SEAD MANPADS attrition but supplied no coherent local trigger; the
follow-up USER call chose reality and implementation clarity over preserving that scope.

### Follow-up closed 2026-08-01 — what is left is implementation and measurement, not design

The final rulings above include both follow-up rounds. Remaining unknowns are measurement outputs:

- Count four-airframe manned Maneuver-Unit packages and fit the MANPADS kill factor without trying to
  reproduce the deleted island-wide contest.
- Measure R11 anti-radiation expenditure, weighted IADS health, assigned SEAD composition, and SAM
  survival by turn.
- Jointly fit R10's score-scaled return factor and MANPADS attrition against the final 498-airframe
  force, using the 10% intact-IADS checkpoint plus role/campaign outcomes.

### Still open — nothing requiring a design call

- Package size/outcomes, MANPADS scope, anti-radiation inventory and salvo, SEAD allocation/effect,
  SAM deployment, weighted health, undetected-engagement knob, RTB/SEAD-assignment ownership, and R3's
  survival-change permission are all settled above. The superseded BACKLOG designs now point here and
  are not a second specification.

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

> **SUPERSEDED PRE-SESSION MEASUREMENT.** Its 54.2% / 253 / four-free-shot-loss headline was produced
> by the broken repeated-turn substream; the Corrections section above carries the valid historical
> measurement, and the final rulings replace both old MANPADS surfaces.

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
