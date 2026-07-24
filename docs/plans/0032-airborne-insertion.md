---
title: "0032: Airborne / air-assault insertion — a non-amphibious path that bypasses the crossing"
status: "Sketch"
created: "2026-07-24"
---

# Plan 0032: Airborne / air-assault insertion

## Design intent (USER 2026-07-24)

The amphibious crossing is the PLA's binding chokepoint — it is attritable, capacity-limited, and
(per [[0028-sustained-followon-interdiction]]) even the PLA's own JLSF logistics crowds combat power
out of it. This plan gives the PLA a **non-amphibious insertion path**: air-land air-assault and
airborne battalions directly, bypassing the sea crossing, at a per-turn cap and under attrition.

The OOB **already has the units** — `Air Assault Infantry Battalion` and the `Airborne` / `Air
Assault` categories (`UnitStats`, `pla_ground_forces.json`) with stats/tags. Today they have **no
insertion mechanic** and ride the beach/offload pipeline like everyone else. This plan adds the
mechanic, not the units.

### Decided design calls (USER 2026-07-24)

1. **Land on any hex.** No landing-zone restriction — but hexes **occupied by Green or contested**
   inflict **high attrition** on the inserting battalions. (Landing onto an empty/red hex is safe;
   landing onto/near the enemy is bloody.)
2. **Per-turn lift cap, per type:** **2 BN/turn air-assault**, **7 BN/turn airborne**. Both are
   subject to attrition on insertion.
3. **Attrition erodes the lift itself.** When attrition hits an inserting battalion, the unit **does
   not land** AND the **per-turn capacity is lowered** — i.e. losing lift on a contested drop
   permanently (airframes lost) reduces future throughput, not just that turn's delivery. *(Open
   sub-detail: permanent vs recovering cap — default to permanent airframe loss; confirm.)*
4. **No dependency on airbridge.** The `airbridge` infra kind is completely separate from this
   mechanic; airborne insertion does not require or interact with airbridges.

## How it extends what exists

- A new insertion path parallel to `SealiftResolver`'s crossing/offload: a per-turn airborne lift
  budget (two caps: air-assault, airborne) that places eligible units onto ordered target hexes.
- Reuse the unit-type tags already present (`air_assault`, `airborne`) to determine eligibility and
  which cap a unit draws from.
- Attrition model on insertion: a function of the target hex's occupancy/contested state (Green-held
  or contested → high loss); a lost BN is destroyed (not landed) and decrements the relevant cap.
- Likely a new small resolver (`hexcombat-add-phase-resolver` template) + a typed summary
  (`airborne_summary`) surfaced in the digest, so drops and lift attrition are observable.

## Open design sub-questions (for USER before build)

- **Attrition numbers**: loss probability / fraction on a contested vs Green-occupied vs adjacent-to-
  enemy hex; how much each loss lowers the cap (1 BN of cap per BN lost?); cap-recovery rule if any.
- **Who orders drops**: a policy behavior (self-play) and/or an LLM/`deploy`-style order; where do
  airborne units enter — a reserve pool phased like the follow-on, or the existing OOB?
- **Supply/holding**: once landed on an isolated hex, do airborne units get supply (DOS) or wither?
  Interaction with FEBA and ground combat the turn after landing.
- **Victory census**: landed airborne BNs count in the PLA census like any ground BN (assumed yes).

## Objectives

1. Airborne insertion resolver + two per-turn caps (2 air-assault, 7 airborne) + contested-hex
   attrition that both destroys the BN and decrements the cap; `airborne_summary` in the digest.
2. Golden byte-stable when no airborne orders are issued (mechanism default-off / no drops =
   today's behavior).
3. Sweep: cap sizes × attrition severity → does an air-insertion path change the crossing-bound
   outcome (bypass the chokepoint)? Deck-ready chart.

## Verification

- Golden byte-stable with no drops (the insertion path is inert unless ordered).
- GdUnit: a drop onto an empty red hex lands fully; a drop onto a Green/contested hex takes attrition
  and lowers the cap; caps enforced per turn per type.
- Full `run_all_tests` green.

## Dependencies / notes

- Independent of [[0031-graduated-port-suppression]] and [[0030-jlsf-first-class-cohort]] (no
  airbridge tie by USER call). Can sequence any time after 0030's observability floor.
- The PLA counterpart to the ROC-side [[0029-dynamic-roc-defense]] and port-throttle
  [[0031-graduated-port-suppression]] — a PLA lever to route *around* the contested crossing rather
  than force more through it.
