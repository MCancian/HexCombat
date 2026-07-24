---
title: "0031: Graduated port suppression — the captured port is a contested capacity, not a binary"
status: "Sketch"
created: "2026-07-24"
---

# Plan 0031: Graduated port suppression

## Design intent (USER 2026-07-24)

This session's 2-D map ([[0028-sustained-followon-interdiction]] "2-D map") showed **beach/port
throughput is the decisive lever** — below ~1,600 t/day the PLA never wins, regardless of
interdiction. Today that lever is static (a fixed `offload_rate`) and the captured Taipei port is
effectively binary (seized → repairs → operational). This plan makes the port's throughput a
**contested, continuous capacity** that the ROC actively suppresses and the PLA actively repairs —
turning the decisive throttle into a playable tug-of-war.

### Decided design calls (USER 2026-07-24)

1. **Continuous scale.** Port capacity is a fraction `C ∈ [0, 1]` (0–100 % of the port's max
   throughput), NOT the discrete `degraded/operational` rungs. Effective port throughput =
   `C × max_port_rate`.
2. **Default start state = 0 % throughput.** A freshly captured port delivers nothing until the PLA
   repairs it up.
3. **Repair is JLSF-driven.** PLA raises `C` by running JLSF to the port (ties to the existing
   JLSF-gated repair clock and to [[0030-jlsf-first-class-cohort]]). Repair rate per JLSF arrival is
   a knob.
4. **Two ROC suppression inputs, both lowering `C`:**
   - **Off-island dedicated fires budget** — a knob (fires/turn) applied straight to the port,
     un-suppressable by the PLA (the off-island analogue of [[0028-sustained-followon-interdiction]]'s
     off-island strikes).
   - **On-island strike budget = HIMARS units, subject to IJFS.** ROC HIMARS launchers contribute
     suppression but are themselves detectable/killable through the PLA IJFS kill chain
     ([[hexcombat-wargame-domain-reference]]) — so the PLA can degrade the on-island half by hunting
     HIMARS, exactly as it suppresses on-island coastal launchers today.
5. **ROC-only.** This is a defender mechanic (deny the captured port). The PLA's only lever on `C` is
   JLSF repair.

### Net dynamic

`C_next = clamp(C + jlsf_repair − off_island_fires − himars_surviving_fires, 0, 1)`, evaluated each
turn. Port throughput each turn = `C × max_rate`. The PLA pours JLSF to lift `C`; the ROC spends
off-island fires (fixed) + HIMARS (attritable via IJFS) to hold it down. Whether the port ever comes
online is the contest.

## How it extends what exists

- `InfrastructureState` already has a status ladder (`seized/degraded/operational`) and a JLSF
  sub-state; `InfrastructureResolver.tick` already gates repair on `jlsf == ARRIVED` and Red-held.
  Add a continuous `capacity` field to the port node; drive throughput off it in
  `red_offload_nodes` instead of the discrete `OPERATIONAL_PORT/DEGRADED_PORT` branch.
- **Step 0 of this plan (absorbed from BACKLOG, USER 2026-07-24):** `offload_operational_port_rate`
  is a hardcoded `OffloadRates.OPERATIONAL_PORT` constant, NOT loaded through `DataOverrides`, so port
  throughput is not tunable/sweepable. First wire `offload_rates.json` through `GameData._read_json`
  so `max_port_rate` is a real knob; then build the continuous capacity on top.
- HIMARS: a ROC on-island launcher type fed into the existing IJFS target pool so it is
  detectable/attritable; its surviving count each turn scales the on-island suppression.

## Open design sub-questions (for USER before build)

- **Numbers**: max port throughput (t/day at C=1), JLSF repair per arrival, off-island fires/turn,
  per-HIMARS suppression, HIMARS count/survivability. (Sweepable knobs — can be dialed after a
  feasibility run, but need plausible starting values.)
- **HIMARS suppression vs port capacity units**: do fires reduce `C` by a flat amount per shot, or
  probabilistically? Sticky (permanent until re-repaired) — yes, implied by the tug-of-war, confirm.
- **Airbridge parity**: does the same continuous-capacity + suppression model apply to seized
  `airbridge` nodes, or ports only for now?

## Objectives

0. **Prereq (absorbed from BACKLOG):** load `offload_rates.json` through `GameData._read_json` /
   `DataOverrides` so `max_port_rate` is a real, sweepable knob (today it is a hardcoded constant).
1. Continuous port `capacity` state + JLSF-driven repair + throughput read (throughput =
   `capacity × max_port_rate`). **Default start 0 % (USER 2026-07-24)** — a captured port delivers
   nothing until repaired. This is a deliberate behavior change from today's free auto-repair, so the
   golden is **re-baselined** (see Verification), NOT held byte-stable.
2. Off-island fires knob + HIMARS-on-island suppression (HIMARS in the IJFS target pool).
3. Sweep: off-island fires × HIMARS × JLSF-repair → does the port stay suppressed below the
   culmination throughput? Deck-ready chart (`mc_chart.py --flip`/`--heat`); refresh deck slides 6/7
   for the new baseline.

## Verification

- **Deliberate golden re-baseline (USER 2026-07-24):** 0 %-start is the default, so the captured-port
  outcome changes and `validate_golden_victory` is re-baselined under the new behavior (per
  `hexcombat-change-control`'s re-baseline rules); the 200-seed baseline distribution and deck slides
  6/7 are refreshed to match. **No compatibility flag** — today's free auto-repair is retired.
- GdUnit for the capacity tick (repair up, fires down, clamp, HIMARS attrition feeding suppression).
- A sweep produces a sensitivity crossing on port throughput / PLA win rate.

## Dependencies / notes

- Depends on [[0030-jlsf-first-class-cohort]] for legible JLSF flow (repair is JLSF-driven).
- The `offload_operational_port_rate` DataOverrides wiring is Objective 0 of this plan (absorbed from
  BACKLOG, USER 2026-07-24).
- Operationalizes the decisive lever from [[0028-sustained-followon-interdiction]]; pairs with the
  defender-reservoir thread in [[0029-dynamic-roc-defense]] (both are ROC ways to plateau the PLA).
- Default 0 % start throughput changes the baseline outcome vs today (the port currently comes online
  for free); the golden re-baseline + 200-seed/deck-slide-6-7 refresh is the **accepted plan**
  (USER 2026-07-24), not an open risk.
