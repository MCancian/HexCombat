# Sweep: mc_offload_throughput
**Created:** 2026-07-23T22:42:50.964459+00:00
**Commit:** `8a2a046077cb375f798aab8699edaac5533d69b4`
**Scenario:** scenario_default
**Command:** `tools/run_sweep.py --name mc_offload_throughput --knob data/beaches.json:beaches[*].offload_rate --values 4400,3000,2200,1600,1200,900,600 --matchup selfplay_default --scenario scenario_default --n 20 --turns 30 --parallel 6 --metrics red_win_rate`

## red_win_rate
| offload_rate | red_win_rate |
|---|---|
| 4400 | 100.0% |
| 3000 | 100.0% |
| 2200 | 100.0% |
| 1600 | 80.0% |
| 1200 | 35.0% |
| 900 | 5.0% |
| 600 | 0.0% |

