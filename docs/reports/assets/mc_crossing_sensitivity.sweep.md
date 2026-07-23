# Sweep: mc_crossing_sensitivity
**Created:** 2026-07-23T20:24:30.669742+00:00
**Commit:** `7339378ae9d3f68832d4910c15d71b22443571e4`
**Scenario:** scenario_default
**Command:** `tools/run_sweep.py --name mc_crossing_sensitivity --knob data/ijfs/ijfs_scenario.json:intel_locked_antiship_strike_bonus --values 0.0,0.2,0.4,0.6,0.8 --matchup selfplay_default --scenario scenario_default --n 20 --turns 30 --parallel 6 --metrics crossing_loss_pct,red_win_rate`

## crossing_loss_pct
| intel_locked_antiship_strike_bonus | crossing_loss_pct |
|---|---|
| +0.00 | 37.2±14.1 |
| +0.20 | 33.2±8.9 |
| +0.40 | 22.1±7.5 |
| +0.60 | 20.4±6.9 |
| +0.80 | 20.8±8.1 |

