# Permanent launch destruction — measured effect (plan 0043)

**Date:** 2026-07-27 · **Plan:** 0043 anti-ship mutation authority · **Verdict: no rebalance
indicated.**

## The question

Launchers destroyed during launch attrition used to come back on the next crossing: the firing plan
rebuilt `quantity` from `original_quantity` minus cumulative IJFS kills alone, which overwrote the
launch losses. The USER settled that they should stay destroyed. Plan 0043 makes that so, and the
plan's own instruction is to **report the direction and magnitude before considering any retune, and
not to automatically restore the old numbers**.

## Method

Common random numbers, one variable changed. The baseline was run from a `git worktree` at the
pre-change commit (`d4624b9`), so both arms are the same harness, same scenario, same seeds.

| | |
|---|---|
| Harness | `tools/run_selfplay_game.gd`, one record per game |
| Scenario | `scenario_default` |
| Matchup | `selfplay_default` both seats |
| Turn cap | 30 (games ended on victory at turns 16–22) |
| Seeds | 12 common seeds, `20260701`–`20260712` |
| Metrics | per-campaign sums over every resolved crossing: `systems_fired_count`, hulls destroyed (all ship types, crossing + mines), `bns_lost_at_sea` |

Crossings per campaign ranged 4–8, so the cross-crossing behaviour this plan changes is genuinely
exercised.

**A note on how NOT to measure this.** A first attempt drove `GameState.resolve_turn` in a bare loop
and read the terminal `quantity`. Both halves were wrong: without `begin_next_turn` every turn after
the first fails with *"Cannot resolve turn outside PLANNING phase"* (it looked like the campaign
contained exactly one crossing), and terminal `quantity` is not comparable across the change anyway,
because the old code decremented it by `attempted` during the crossing and restored it at the next
one. Use the real harness and compare campaign outcomes.

## Result

| seed | crossings | hulls lost (before → after) | BNs drowned | systems fired |
|---|---|---|---|---|
| 20260701 | 5 | 105 → 109 | 20 → 21 | 90 → 90 |
| 20260702 | 7 | 128 → 128 | 26 → 26 | 158 → 158 |
| 20260703 | 5 | 118 → 121 | 20 → 19 | 80 → 75 |
| 20260704 | 7 | 128 → 125 | 26 → 25 | 102 → 96 |
| 20260705 | 5 | 113 → 113 | 25 → 25 | 113 → 113 |
| 20260706 | 5 | 126 → 112 | 27 → 25 | 149 → 131 |
| 20260707 | 4 | 145 → 141 | 36 → 37 | 150 → 147 |
| 20260708 | 5 | 105 → 106 | 22 → 22 | 213 → 203 |
| 20260709 | 6 | 139 → 139 | 28 → 28 | 109 → 109 |
| 20260710 | 6 | 165 → 169 | 36 → 35 | 230 → 213 |
| 20260711 | 8 | 156 → 152 | 35 → 38 | 134 → 132 |
| 20260712 | 5 | 103 → 106 | 17 → 17 | 97 → 93 |

| metric | mean Δ | range | reading |
|---|---|---|---|
| Green systems fired | **−5.42** | −18 … 0 | falls in every seed that moves, **never rises** |
| Red hulls lost | −0.83 | −14 … +4 | noise around zero |
| Red BNs drowned | 0.00 | −2 … +3 | noise around zero |

9 of 12 seeds changed at all. The 3 that did not had no launch destruction left to carry into a
later crossing.

## Reading

The **direct** effect is exactly the mechanism and has a consistent sign: Green loses roughly five
shots per campaign — about 4% of the salvo — because launchers that died firing stay dead instead of
being restored each crossing. This is the only monotone quantity in the study, which is what you
would expect from a change that can only ever remove launchers.

The **downstream** effect is not detectable at n=12. Hull losses and drowned battalions scatter
around zero with ranges an order of magnitude wider than their means: past the firing step the
crossing re-derives its dice, so a campaign with slightly fewer missiles is a *different* campaign
rather than a uniformly gentler one. Neither the crossing-loss calibration (USER-accepted 32.9% mean
on the 81-BN sent-cohort wave, 2026-07-18) nor any pinned fingerprint moved: the full gate is ALL
PHASES GREEN with no re-baseline.

**Conclusion: ship the correction as-is.** It is a fidelity fix, not a balance lever, and there is
nothing here that would justify retuning IJFS or launch-attrition probabilities to recover the old
numbers. If a later plan makes campaigns cross substantially more often, the −5.4 shots/campaign
figure will grow and is worth re-measuring then.

## Reproducing

```bash
# after
godot --headless --path . -s res://tools/run_selfplay_game.gd -- \
  --seed=20260701 --turns=30 --policy=selfplay_default --out=reports/0043/after_20260701.json
# before: same command from a worktree at the pre-change commit
git worktree add --detach .baseline0043 d4624b9   # must live INSIDE the project dir;
                                                  # the flatpak Godot sandbox cannot read outside it
```

Records are byte-identical for deterministic policies, so a differing record IS the finding.
