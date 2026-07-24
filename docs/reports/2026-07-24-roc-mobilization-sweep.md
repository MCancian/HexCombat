# ROC mobilization phase-in — the first defender-side lever that moves the win rate

**Date:** 2026-07-24 · **Author:** Agent (Opus 5) · **Commit:** `5b4d396`

Plan 0029 Tier A2. Companion to [Tier A1](../plans/0029-dynamic-roc-defense.md) (the `roc_defense`
repositioning policy, which transformed the battle but left Red at 30/30) and to the
[Monte Carlo baseline](2026-07-23-monte-carlo-outcome-distribution.md) (PLA 200/200).

## Research question

The census race has had one sign: Red accumulates, Green only erodes. If the ROC's reserve
establishment is modelled as **mobilizing** rather than standing on its garrison hexes at H-hour —
so a slice of the force is off-map, outside the census and outside IJFS targeting, until it forms
up — does the defender's curve flatten, and does that change the outcome?

## Conditions

| | |
|---|---|
| Scenario | `scenario_default` (full 32-brigade ROC laydown, deep PLA follow-on pool) |
| Matchup | Red `selfplay_default` vs Green `roc_defense` (the Tier A1 concentrating defender) |
| Horizon | 30 turns (turn = 1 day) |
| Seeds | 30 common seeds per cell (20260624–20260653) |
| Swept | `green_mobilization.held_back_brigades` ∈ {0, 4, 8, 12}; then `first_release_turn` ∈ {2, 4, 8, 12} at held_back = 12 |
| Schedule | default: 2 brigades every 2 turns from `first_release_turn` (all 12 fielded by turn 14) |
| Victory | unchanged, deny-only: Red wins the moment its present census strictly exceeds Green's; Green can only "win" by eliminating Red entirely (never observed), so a defended game reads as **undecided at the horizon** |

Specs: `tools/sweeps/roc_mobilization.json`, `tools/sweeps/roc_mobilization_timing.json`.
Cell 0 is the Tier A1 reference condition.

## Result 1 — the win rate finally moves

| held_back_brigades | Red win rate | mean turns to decision | undecided games | their final margin |
|---|---|---|---|---|
| 0 (pre-0029 laydown) | **100.0%** | 20.0 | 0 | — |
| 4 | 93.3% | 21.0 | 2 | −12.5 (ROC ahead) |
| 8 | 90.0% | 21.8 | 3 | −16.7 (ROC ahead) |
| 12 (whole reserve) | **83.3%** | 22.4 | 5 | −11.6 (ROC ahead) |

Monotone in the knob. This is the **first defender-side change in the project to move the Red win
rate off 100%** — beach capacity, anti-ship lethality and repositioning all left it flat.

The mechanism is not extra force (total ROC battalions are identical in every cell — the knob only
decides how many start off-map). It is **exposure timing**: the PLA fires campaign is front-loaded
(the exquisite-intel warmup plus the opening CRBM volleys), and battalions that are not on the
island cannot be struck. Held-back brigades arrive intact into a fight that `roc_defense` then walks
them toward.

## Result 2 — Green's curve stops being monotone

Mean census by turn, R/G, over games still running (n in parentheses — late turns are
survivor-biased, since decided games drop out):

| cell | t1 | t3 | t5 | t8 | t10 | t14 | t18 | t22 | t30 |
|---|---|---|---|---|---|---|---|---|---|
| held_back 0 | 17/106 (30) | 17/97 | 22/89 | 27/78 | 25/68 | 28/53 | 34/41 (27) | 33/34 (6) | — |
| held_back 8 | 18/82 (30) | 18/76 | 22/74 | **26/75** | 24/73 | 25/58 | 34/46 (28) | 37/44 (12) | 31/48 (3) |
| held_back 12 | 18/69 (30) | 18/62 | 24/60 | **28/62** | 25/59 | 25/57 | 34/46 (28) | 34/41 (14) | 23/34 (5) |

The baseline is the pure attrition sink: 106 → 53 by turn 14, decided by ~turn 20. With the reserve
mobilizing, Green **rises** between turns 5 and 8 (mobilization inflow exceeds losses) and then
holds roughly flat to turn 14 — a plateau where there had only ever been a slope. Decision is pushed
~2.4 turns later on average, and in the games that survive the opening, Green is *ahead* and staying
ahead (t30: 48 vs 31 at held_back 8).

## Result 3 — release timing is a weak, and suspicious, lever

At held_back = 12:

| first_release_turn | Red win rate | mean turns to decision | mean final margin |
|---|---|---|---|
| 2 | 90.0% | 21.6 | +3.2 |
| 4 | 83.3% | 22.4 | +4.3 |
| 8 | 83.3% | 22.8 | +3.0 |
| 12 | 80.0% | 21.9 | −0.3 |

Differences of 1–2 games at n = 30 are inside the noise, but the direction is consistent and it
points at a **model boundary, not a recommendation**: in this engine an off-map brigade is a
sanctuary — it cannot be struck and costs nothing to leave unmobilized, because Green's presence
buys nothing the victory rule scores. Real reserves left unmobilized cede ground and political
control. Treat "mobilize later" as an artifact of the deny-only victory rule, and read the
`first_release_turn` axis as *insensitivity* (the mass matters, the tempo barely does), not as
advice. Closing that hole is a scenario/victory-design question for the USER — see the plan's open
items.

## What this does and does not show

- **Does**: a defender modelled with a mobilization pipeline is no longer a one-sign attrition sink;
  17% of seeds now survive the horizon with the ROC ahead, and every seed takes longer to decide.
- **Does not**: flip the median game. 83% of seeds are still a PLA decisive win, because the
  structural cause is untouched — the PLA follow-on auto-seeds from the entire mainland OOB
  (`auto_seed_followon_pool`, a bottomless reservoir) and no campaign clock caps the buildup. The
  reserve is a *finite* 36-battalion injection against an infinite one; it buys turns, not victory.
- **Combination untested**: this sweep holds the logistics levers at default. The decisive lever
  found so far is beach offload throughput (plan 0028 / deck slide 7); mobilization × throttled
  throughput is the obvious next 2-D cell and is not run here.

## Reproduction

```bash
python3 tools/run_sweep.py --spec tools/sweeps/roc_mobilization.json --parallel 8
python3 tools/run_sweep.py --spec tools/sweeps/roc_mobilization_timing.json --parallel 8
```

Reports land in `reports/sweeps/roc_mobilization{,_timing}/report.md`; the per-cell game records
under `cells/*/games/` carry the full knob vector, so the census-by-turn tables above are
recomputable from them (`turn_digests[].cleanup_summary`).
