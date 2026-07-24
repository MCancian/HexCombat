---
title: "0028: Sustained follow-on interdiction — make the crossing a running toll, not a one-shot"
status: "Sketch"
created: "2026-07-23"
---

# Plan 0028: Sustained follow-on interdiction

## Research question (USER 2026-07-23)

The Monte Carlo study ([[2026-07-23-monte-carlo-outcome-distribution]]) showed a PLA victory is
structurally inevitable: the follow-on draws on a bottomless mainland OOB and, once the amphibious
wave is ashore, only *offload throughput* constrains it (deck slide 7). One reason interdiction can't
flip the outcome: **it is a one-time toll at the initial assault, not a sustained campaign against the
follow-on shipping.** Can we make anti-ship / air interdiction *persist* against each follow-on
echelon so the reservoir pays a running cost — plausibly enough to plateau the PLA below the ROC
count without an artificial campaign clock?

## Evidence — interdiction is front-loaded (measured 2026-07-23)

Across 30 baseline games (`scenario_default`, `selfplay_default`, per-turn `antiship_summary`):

| | crossing BNs | lost at sea | loss rate |
|---|---|---|---|
| **Turn 1** (assault) | 2,430 (70% of all) | 799 (96% of all) | **33%** |
| **Turns 2+** (follow-on) | 1,057 | 32 | **3%** |

So the follow-on that crosses on later turns is essentially unopposed. This is *why* cranking
`exquisite_antiship_initial_count` 36→260 didn't flip anything — it only hits the turn-1 wave. Two
front-loading causes, both to confirm in a spike:

1. **Missiles deplete.** The exquisite-intel multi-day warmup fires a big turn-1 salvo (`ijfs`
   warmup); after that the anti-ship magazine isn't replenished/re-allocated against later crossings.
2. **Mines are swept once.** `available_minesweepers` clear a lane early (`lane_cleared: true`); the
   follow-on then transits the cleared lane at near-zero mine loss — mines don't re-seed.

## ⚠️ This is a mechanic, not a knob — feasibility FIRST

There is no "sustained fires" knob because the *capability* is absent. Do a spike before designing:

### Stage 1 — feasibility spike (gate for the rest)

- Confirm the two front-loading causes above from the code (`IjfsResolver`/`AntishipResolver` fire
  scheduling + magazine; `MineWarfareService` lane-clear persistence), and quantify each cause's
  share (turn off mines vs turn off missiles for the late waves).
- Determine the cheapest seam to inject a *per-turn* interdiction toll on the crossing follow-on
  (a per-turn anti-ship allocation, a re-seeding mine model, or a new air-interdiction-of-shipping
  pass). Which one is one-resolver-deep vs a cross-phase change?
- Determinism: the hierarchical `Dice` already derives an `antiship:<turn>` substream per turn, so a
  sustained per-turn toll should isolate cleanly — confirm; golden must stay byte-stable when off.

If a seam is cheap → proceed. If sustained interdiction requires re-plumbing the IJFS→antiship
writeback across phases → report cost to USER before building.

### Stage 2 — the sustained mechanism + a tuning knob (only if stage 1 passes)

- **Mechanism (design call, USER):** the most plausible is a *per-turn anti-ship interdiction budget*
  that fires on whatever is crossing that turn (a sustained analogue of the warmup salvo), and/or a
  mine model where the swept lane degrades / re-seeds over turns. Pick ONE to prototype first.
- **Knob:** e.g. `sustained_interdiction_per_turn` (fires/turn or loss-rate floor on the follow-on
  wave), registered in `data/knobs/registry.json` so it sweeps + records like any knob. Default OFF
  (or default = today's behaviour) so the golden is byte-stable.
- **Flip target:** sweep it and look for a monotone crossing where the follow-on's cumulative delivery
  plateaus below the ROC census — the same success shape as the offload-throughput curve.

## Progress — off-island fleet strikes shipped (2026-07-23)

USER direction: focus the sustained toll on **off-island** shooters (ROC submarines, allied/air) —
assets the PLA can't suppress the way it suppresses on-island coastal launchers. Built as a
default-off config lever:

- `data/antiship/antiship_crossing_config.json` → `off_island_strike.shooters[]` (`type` = a
  combat-catalog launcher id — `6` = `Harpoon_Sub_II` submarine, `3` = `Harpoon_Air_II`/`SLAM-ER`
  air; `systems_per_turn` = launchers firing each turn).
- `AntishipResolver._append_off_island_strikes` appends those as **location-less** firing rows every
  turn, after the on-island writeback/attrition. No `location` ⇒ `AntishipCrossing` skips the range
  gate (whole-strait reach) and they bypass per-TO IJFS suppression + depletion — so the follow-on
  keeps paying a toll after the on-island salvo is spent. Rows still run the full
  escort → terminal-defense gauntlet. Registry knobs `off_island_submarine_strikes` /
  `off_island_air_strikes`; default 0 ⇒ golden byte-stable. Test: `tests/off_island_strike_test.gd`.

**Finding (sweep `off_island_submarine_strikes` 0→64, N=15, `scenario_default`):** it works as a
sustained lever — late-turn (follow-on) drownings rise 1→18 BNs, total fleet drownings 26→54, and the
PLA margin compresses monotonically +9.1 → +3.1. **But it does not flip the outcome alone** (100% PLA
to 32/turn; 93% at 64): the follow-on reservoir is bottomless and the *binding* constraint is offload
*rate*, not sea attrition, so Red just sends more. Per USER ("a knob needn't flip alone") this is a
kept, first-class lever. **Antagonistic with the offload throttle** (a surprise): off-island 32 +
offload 1,600 gives *more* PLA wins (95%) than offload 1,600 alone (80%) — sinking ships at sea thins
the beach queue, so the binding offload throughput keeps pace better. The two are substitutes, not
complements.

**Still open (the mine/re-seed half of this plan):** mines are swept into a cleared lane once; a
re-seeding / degrading-lane model would be the *on-approach* sustained toll to pair with off-island
fires. Not built.

## Objectives

1. Stage-1 spike + written verdict (which cause dominates late-wave immunity; cheapest seam) → USER
   checkpoint.
2. (gated) Sustained interdiction mechanism + tuning knob; golden byte-stable when off.
3. (gated) Sweep → flip curve; report + a deck-ready crossing chart via `tools/mc_chart.py --crossing`.

## Verification

- Stage 1: a throwaway experiment lands late-wave loss-rate above baseline and the turn resolves with
  no index violations; golden untouched with the feature off.
- Stage 2–3: GdUnit coverage for the per-turn toll; golden byte-stable at the default; sweep yields a
  sensitivity crossing.

## Dependencies / notes

- Pairs with [[0029-dynamic-roc-defense]] — both aim to plateau the PLA *within* the horizon (no
  artificial clock), from the two sides (attrit the attacker's sustainment vs regenerate the
  defender). Independent; can sequence either first.
- Fidelity anchor: crossing lethality is USER-calibrated to 32.9% on the turn-1 sent cohort
  ([[0001-crossing-lethality-calibration]]); a sustained toll must NOT silently re-open that dial —
  keep the turn-1 assault semantics fixed and add the follow-on toll as a separate, defaulted-off lever.
