---
title: "0029: Dynamic ROC defense — the defender regenerates instead of only eroding"
status: "Sketch"
created: "2026-07-23"
---

# Plan 0029: Dynamic ROC defense

## Research question (USER 2026-07-23)

The Monte Carlo study ([[2026-07-23-monte-carlo-outcome-distribution]]) found the PLA wins 200/200
partly because **Green is a static attrition sink**: it starts at ~88 battalions and only ever loses
them (IJFS/CRBM strikes + ground combat), so the census race is Red-accumulates vs Green-erodes with
one sign. Can the ROC defense be made *dynamic* — mobilize reserves, reposition to threatened
sectors, and/or counterattack — so the defender can plateau or reverse the PLA below the victory
census, without an artificial campaign clock?

## Two tiers — very different cost

### Tier A — reserve mobilization / dynamic repositioning (no attacker-role change)

Green stays the defender but stops being a fixed laydown that only bleeds:

- **Reserve mobilization:** a pool of ROC battalions that come online over turns (like the PLA
  follow-on but defensive), feeding threatened sectors. Turns Green's curve from monotone-down into
  something that can hold a line.
- **Dynamic repositioning:** a Green policy that moves brigades toward the beachhead / contested
  front instead of garrisoning fixed hexes (the `garrison_draw` policy [[0021-garrison-draw-policy]]
  is the seed of this; `inland_clear` is its Red analogue).

Cost: mostly a **new/extended Green policy** + optionally a reserve-pool scenario field. No combat
engine change — Green still defends. This is the cheaper, higher-plausibility first step and likely
enough to make the census race two-sided.

### Tier B — ROC counterattack / counterlanding (deep — engine change)

Green actually *attacks* to retake hexes. This is a fundamental change: **attacker = Red is
hard-coded** in `CombatResolver.resolve_hex_combat` (`inject_supply_effectiveness(attacker_units,
Brigade.Team.RED, …)`), and the Red-only supply-pool asymmetry (`red_supply_pool` applies to the
attacker) assumes it. Un-hardcoding it is exactly **step 1 of [[0003-combat-summary-team-attribution]]**
(stamp `attacker_team`/`defender_team` on `CombatSummary`), followed by generalizing the supply
asymmetry and new resolver tests — a `hexcombat-add-phase-resolver`-scale effort. **Blocked on the
USER counterattack design call that 0003 already flags.**

## ⚠️ Feasibility / sequencing

- Do **Tier A first** — it's a policy (+ maybe a reserve field), testable and sweepable on its own,
  and answers "does a non-static defender flip the outcome?" cheaply.
- Only escalate to **Tier B** if Tier A is insufficient AND the USER wants Green to counterattack;
  Tier B starts by executing 0003's team-stamping step, then the mechanic.

## Tier A progress (2026-07-23)

**Repositioning shipped + measured — necessary but NOT sufficient.** Built `roc_defense`
(`scripts/RocDefensePolicy.gd`, registered in `PolicyCatalog`): every Green brigade steps toward the
nearest red/contested threat instead of the `selfplay_default` wander; holds pre-landing. Extracted
the shared id-geometry into `scripts/PolicyGeometry.gd` (repointed `GarrisonDrawPolicy` off its private
copies).

Result — `selfplay_default`(Red) vs `roc_defense`(Green), N=30, `scenario_default`: **Red still wins
30/30** (margin mean +6.2 vs the +8 wander baseline). It transforms the *battle* — Red present crashes
73→48, Green 65→42 — Green now actually fights and destroys far more Red, but **can't flip the
outcome**: every Red battalion it kills is refilled by the bottomless follow-on while Green's losses
are permanent, and moving Green raises its IJFS "active" detectability. **You cannot out-position an
infinite-reserve attacker.** Confirms the thread-1 thesis from the defender side: the decisive lever
is a defender *reservoir*, not positioning.

**Next (needs a USER force-structure call):** give ROC its own reserve. Three models to choose from —
(a) new reserve OOB brigades (invents ROC reserve force structure), (b) hold some of the existing 32
brigades off-map and phase them in (redistributes the current force), (c) a battalion
regeneration/replacement rate (destroyed Green BNs reconstitute over turns — models mobilization
without inventing units). Each is a small injection mechanic + a sweepable rate/size knob; (c) is the
cleanest and most self-contained. **Surfaced to USER for the model + realistic numbers before building.**

## Tier A2 — mobilization phase-in (USER call 2026-07-24: model **(b)**)

USER chose **(b) phase in existing brigades**, and **deny-only** victory (no Green win arm — a
successful defense reads as "no decision inside the horizon" plus the census curve, not a win rate).

### Why (b) is more than a reshuffle

The ROC OOB already contains the answer: **12 of the 32 brigades are `nato_type: "reserve"`**
(BDE-911…943, 3 `Infantry Battalion (Reserve)` each = **36 of the 124 BNs, 29% of the force**).
Modelling those as *mobilizing* rather than *fielded at H-hour* invents nothing — it corrects a
laydown that currently assumes the entire reserve establishment is manned, equipped and standing on
its garrison hex on D-Day.

Total Green battalions are unchanged, so this is not free force. The lever is **exposure timing**:
an off-map mobilizing brigade is not an IJFS target and not in the victory census. Held-back
battalions sit out the front-loaded fires campaign (the CRBM/exquisite-intel warmup that does most
of its damage in the opening turns) and arrive intact afterwards, into a fight the `roc_defense`
policy then walks them toward. Green trades early census presence for late-arriving intact mass —
the first thing in this model that bends the Green curve upward.

### Mechanic

A **mobilization phase** in `resolve_turn`, placed immediately after amphibious offload and before
movement/commit — i.e. the Green reinforcement step sits at exactly the same seam as Red's
(offload), and units that arrive in resolution get orders on the *next* planning phase, same as
Red's landed brigades.

- **Scenario block** `green_mobilization` (`held_back_brigades: 0` default ⇒ nothing held ⇒
  byte-identical to today's laydown ⇒ golden safe):
  `{held_back_brigades, brigade_types:["reserve"], first_release_turn, release_interval_turns,
  brigades_per_release}`.
- **Selection** — eligible = placed Green brigades whose `nato_type` is in `brigade_types`, in
  `brigade_id` order; the first `held_back_brigades` of them start **off-map** (`hex_id == ""`,
  the same "not present" state Red's at-sea brigades already use, so census / IJFS targeting /
  legal-moves / observation all exclude them with no special-casing).
- **Release** — from `first_release_turn`, every `release_interval_turns`, `brigades_per_release`
  brigades arrive at their **real garrison hex** (the placement the scenario gave them). If that hex
  is RED/CONTESTED at release, the brigade arrives at the nearest non-enemy passable hex (BFS,
  id-sorted, bounded); if there is none it stays pending and retries next turn.
- **IJFS coupling** — maneuver targets are built for **on-map** Green brigades only; a released
  brigade's per-battalion targets are appended to the live IJFS state on arrival (append-only, so
  existing targets' detection continuity and ordering are untouched).

### Knobs (sweepable, `scenario:` prefix)

`green_mobilization.held_back_brigades` (0…12), `.first_release_turn`, `.release_interval_turns`,
`.brigades_per_release`. Default schedule: first release **turn 4**, **2 brigades every 2 turns** —
12 brigades fielded by turn 14 (turn = 1 day), matching a reserve mobilization that starts reporting
inside a week and produces formed units through D+14.

### Verification / measurement

GdUnit coverage for selection + release + displaced arrival; `tools/validate_mobilization.gd` as an
e2e (hold all 12, assert census dips then rises and every brigade arrives); golden byte-stable at
default 0. Then sweep `held_back_brigades` 0/4/8/12 with `roc_defense` in the Green seat and report
the census curves.

### Shipped 2026-07-24 — mechanic + measurement

**Mechanic shipped** (commit `7d1cc7b`, gate ALL PHASES GREEN): `green_mobilization` scenario block,
`MobilizationState`/`MobilizationSummary`, `MobilizationStateBuilder`/`MobilizationResolver`, a
mobilization phase between offload and movement, IJFS append-on-arrival, observation + record
surfacing, `tools/validate_mobilization.gd` + 16 GdUnit cases. Facts:
`docs/systems/roc-mobilization/roc-mobilization.md`. Default `held_back_brigades: 0` ⇒ inert, golden byte-stable.

**Measured** (30 seeds/cell, `selfplay_default` vs `roc_defense`, `scenario_default`, 30 turns —
full report: `docs/reports/2026-07-24-roc-mobilization-sweep.md`):

| held_back_brigades | 0 | 4 | 8 | 12 |
|---|---|---|---|---|
| Red win rate | **100%** | 93.3% | 90.0% | **83.3%** |
| mean turns to decision | 20.0 | 21.0 | 21.8 | 22.4 |

**The first defender-side lever to move the win rate off 100%** — and it does it without adding a
single battalion, purely by keeping 36 of the 124 BNs off-map (uncensused, unstrikable) through the
front-loaded fires campaign. Green's census curve stops being monotone: at held_back 12 it *rises*
t5→t8 (60→62) and plateaus to t14 where the baseline fell 89→53. 17% of seeds now survive the
horizon with the ROC ahead (mean −11.6).

It does **not** flip the median game: 83% are still PLA decisive, because the structural cause is
untouched — the bottomless `auto_seed_followon_pool` reservoir against a *finite* 36-BN injection.
The reserve buys turns, not victory.

Release timing (`first_release_turn` 2/4/8/12 at held_back 12) is nearly flat (90%→80%, inside the
noise at n=30) and its weak gradient favours *later* mobilization — a model boundary, not advice:
off-map is a sanctuary with no modelled cost, because the deny-only victory rule scores presence
only. See the report's caveat.

### Open after Tier A2

- **Mobilization × logistics throttle** (2-D): the decisive lever found so far is beach offload
  throughput (plan 0028); this sweep held it at default. Obvious next cell — does a finite defender
  reservoir flip the outcome once the attacker's buildup rate is capped?
- **Cost of staying unmobilized** (USER design call): today an off-map brigade cedes census and
  ground but is invulnerable, so the model mildly rewards withholding. A mobilization cost (ground
  control, political, or a readiness penalty on late arrivals) would close it.
- **Tier B** (Green counterattack) remains gated on 0003 + the USER counterattack call.

## Objectives

1. Tier A: reserve-mobilization pool and/or a repositioning Green policy; golden byte-stable when the
   defender behaves as today.
2. Tier A: sweep the reserve size / policy aggressiveness → does Green's curve flatten/cross the PLA
   census? Report + deck-ready crossing chart.
3. (gated on USER call + Tier A result) Tier B: un-hardcode attacker team (0003 step 1) → Green
   counterattack mechanic → tests.

## Verification

- Tier A: new GdUnit coverage for the reserve/policy; golden byte-stable at default; a sweep produces
  a sensitivity curve on the ROC census.
- Tier B: additive `attacker_team`/`defender_team` per 0003, golden re-baseline (allowed: additive
  field, math untouched at first); counterattack resolver tests.

## Dependencies / notes

- Pairs with [[0028-sustained-followon-interdiction]] — the two sides of "plateau the PLA within the
  horizon" (attrit the attacker's sustainment vs regenerate the defender). Independent.
- Tier B depends on [[0003-combat-summary-team-attribution]] (its team-stamping is Tier B's step 1)
  and is the concrete answer to 0003's open USER counterattack question.
- Green victory is currently not armed (victory is PLA-decisive-or-nothing); a Green *win* condition
  (vs merely "PLA culminates / no decision") is a separate USER call if Tier A/B should let ROC win
  outright rather than just deny.
