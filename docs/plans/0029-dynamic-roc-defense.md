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
