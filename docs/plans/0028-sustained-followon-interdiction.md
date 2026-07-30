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

## Follow-up — ghost-landing census bug found + fixed (2026-07-24)

Investigating "how many off-island strikes flip the scenario" (extended sub-strike sweep to
0→2048/turn) surfaced a **correctness bug**: drowned crossing BNs were removed from `ship_reserve`
but left in `Brigade.composition`, so the victory census (`get_battalion_count - at_sea`) ghost-landed
a partially-landed brigade's drowned BNs (and combat over-counted its strength). Fixed
(`RosterMutations.apply_crossing_casualties`) — see `docs/DECISIONS.md` 2026-07-24 and
`docs/systems/amphibious-offload/amphibious-offload.md` §7 "Crossing losses are casualties". **Consequence: the flip
finding above (margin +9.1→+3.1, 93% PLA at 64/turn) and every prior census-based number over-stated
PLA strength and are being re-run against the fixed engine.**

### Corrected flip curve (fixed engine, N=20, `selfplay_default`, `scenario_default`)

Sub-strike sweep re-run on the fix. Off-island interdiction flips the scenario at a **~30–60× lower**
level than the buggy engine showed — the ghost-landing bug had been propping up the whole PLA
position (drowned BNs counted as present AND fighting):

| sub strikes/turn | 0 | 8 | 16 | 24 | 32 | 48 | 64 |
|---|---|---|---|---|---|---|---|
| **PLA win %** | 100 | 90 | 30 | 15 | 10 | 10 | 0 |

Knife-edge **~12–14/turn**, ≥85% ROC by ~24, reliable flip (0% PLA) by ~48–64 — vs the buggy 512
knife-edge / 1024 reliable. Within a plausible combined ROC-sub + allied-air + external-ASM
interdiction; the "structural inevitability" finding was partly a bug artifact. Specs:
`tools/sweeps/off_island_flip{,_fine}.json`. Deck-ready overlay chart:
`docs/reports/assets/off_island_flip_curve.svg` (from `tools/mc_chart.py --flip
docs/reports/assets/off_island_flip_curve.flip.json`, a new general multi-series flip mode).

### Q2 re-run on the fix — "Taipei port is a no-op" is overturned (2026-07-24)

Re-ran `off_island_flip_noport` on the fixed engine, **rescaled to the fine band** `[0,8,16,24,32,48,64]`
(the old `[0…2048]` grid saturates on the fix, so a port comparison there is measured entirely in the
reliable-flip regime — useless). With-port curve = the fine sweep above (`auto_jlsf` default `true`);
no-port = `auto_jlsf false` (seized ports don't auto-queue attritable JLSF lift):

| sub strikes/turn | 0 | 8 | 16 | 24 | 32 | 48 | 64 |
|---|---|---|---|---|---|---|---|
| **PLA win %, port intact** | 100 | 90 | 30 | 15 | 10 | 10 | 0 |
| **PLA win %, port neutralized** | 100 | 100 | 60 | 25 | 15 | 10 | 0 |

The buggy conclusion ("port is a no-op" — both curves flipped identically at ~512–1024) is **wrong**.
On the fix: at **zero** interdiction the port is a wash (both 100%), but in the contested band,
**denying the port (`auto_jlsf false`) *raises* PLA win %** (16: 60% vs 30%; 24: 25% vs 15%).

**Verified mechanism (traced, NOT the earlier hand-wave).** My first gloss — "the off-island shooters
sink the extra JLSF lift" — is **wrong**: matched cells show near-identical crossing drownings
(~35 vs ~35 BNs). Tracing a flip seed (20260629 @ 3000×32): turn 1 is identical (JLSF only fires once a
port is seized), but **port-intact ends with 18 *fewer* PLA combat BNs on Taiwan** (35 vs 53), losing
the `china_majority` it otherwise wins. Driver: `auto_jlsf` injects JLSF *logistics* cargo
(`jlsf_lift_bn_equiv`=4 BN-equiv/seized port) into the **same attritable crossing + capacity-limited
offload pipeline** as combat battalions (`JlsfCargo.queue_deployments` → `SealiftResolver` JLSF
pseudo-entries → offload). That cargo consumes scarce crossing/offload slots and repairs the port
(`InfrastructureResolver.tick` gates repair on `jlsf == ARRIVED`) but does **not** add to the combat
census — so within the 30-turn horizon it *crowds out* combat BNs and the port-repair payoff doesn't
recoup the displacement. This is a real **crowding-out/substitute** effect (same family as
off-island × offload), **not** the ghost-landing census bug — that bug *inflated* Red; here Red is
*lower* with the port active. **Balance-relevant for USER**: an emergent result that pushing logistics
through a contested crossing dilutes combat power; whether the port-repair payoff should dominate over
a longer horizon is a design call. (N=20/point; per-cell noise, but the direction is monotone and the
traced census gap is large.) Curves overlaid in the flip chart above.

### 2-D map — off-island strikes × beach throttle × port (2026-07-24)

USER asked for the two levers as heatmaps. Ran `off_island_offload_heat` (7 strikes × 7 offload × 2
port, 20 seeds = 1,960 games, ~20 min at `--parallel 28` on the 112-core box). Cells = PLA win %.
Charts: `docs/reports/assets/off_island_offload_heat.svg` (from `tools/mc_chart.py --heat`, fed by
`tools/make_heat_spec.py` which reuses `sweep_metrics.red_win_rate`; spec `.heat.json` alongside).

Two structural reads:

1. **Beach throttle dominates.** At offload ≤ ~1,600 t/day the entire grid is a PLA shutout (0%)
   *regardless of strikes* — the throttle culminates the invasion on its own (consistent with the
   ~1,330 t/day culmination in [[mc-offload-throughput]] / deck slide 7). Off-island strikes only bite
   in the contested high-throughput band (2,200–4,400), where they flip the outcome left→right.
2. **Denying the port helps the PLA here too.** Across the contested band, `port neutralized`
   is uniformly bluer (higher PLA win %) than `port intact` — e.g. offload 3,000 × 24 strikes: intact
   30% vs neutralized 45%; 3,000 × 32: intact 5% vs neutralized 40%. Same **crowding-out** mechanism as
   the Q2 trace above: `auto_jlsf`'s logistics cargo displaces combat BNs in the scarce crossing/offload
   pipeline, so the PLA lands fewer *combat* battalions within the horizon (not a sinking effect —
   drownings are equal; verified +18 combat BNs on a traced flip seed).

So the two interdiction levers are **substitutes, not complements** — throttling the beach is the
decisive constraint; and (counter-intuitively) the captured port's auto-JLSF logistics is a net
*liability* in the contested regime because it crowds combat power out of the crossing. Some per-cell
MC noise at N=20; the two patterns above are monotone across the grid.

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
