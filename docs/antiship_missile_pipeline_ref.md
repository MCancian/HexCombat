# Anti-ship missile pipeline — reference map (TaiwanDefenseRefactor)

Reference for the **deferred** anti-ship strike-coverage calibration lever (see
`docs/archive/PLAN.md` → Open Question "D3-D crossing lethality calibration" (live plan:
`docs/archive/0001-crossing-lethality-calibration.md`), and memory
`antiship-strike-coverage-lever`). Source: `C:\Users\mdogg\My Drive\Projects\TaiwanDefenseRefactor`
(external Python wargame). Surveyed 2026-06-29 (opencode, via `-f`). **Not ported** — map only.

| Stage | File | Purpose | Key constants |
|---|---|---|---|
| 0 | `JFPS_attrition.py` | Pre-launch attrition per platform (binomial) → surviving quantities | `JFPS_attrition` % per platform (`platforms.json`); `attrition_factor = min(num_days/3, 1.0)` |
| 1 | `launches.py` | Surviving platforms fire loaded munitions (alt-munition fallback), then post-fire attrition | `launch_probability=0.5`; `post_fire_susceptibility` per platform |
| 2 | `allocate_attacks.py` | Group launches by platform category, chunk into max groups, assign each to a random non-neutralized flotilla/SAG | `max_platforms`: Aircraft 12, Corvettes 4, Mobile Launchers 4, Fixed Sites 1 |
| 3 | `leakers.py` | Per group: SAG interception (per-missile binomial), then homing + terminal defense per ship | interception attempts 8 (Type-055)/6 (Type-052D); success 0.7/0.6; targeting_weights L1/M2/H3; discrimination L0.2/M0.5/H0.8; terminal_defense base 0.7 (±susceptibility/capability adj); `sag_defense_likelihood_factor=0.5`; `max_targeting_attempts=3`; `missile_group_size=4` |
| 4 | `missile_damage.py` | Per hit ship: roll neutralization, else degrade capability levels | `Neutralization_Likelihoods`: High 0.8 / Medium 0.5 / Low 0.2 / None 0.0; `degrade_level()` High→Medium→Low→None |
| 5 | `second_attack_result.py` | Wrapper re-running allocate→leakers→damage on `second_launches.json` | none of its own |

Config oracle: `output/config.json` (`leakers`, `launches`, `max_platforms`, `JFPS` blocks).
Ship data: `output/platforms.json`, `escorts.json` (SAG/`sags.csv`), `amphibs.json`, `decoys.json`,
`munitions.json`. Flotilla composition: `create_flotillas.py`.

> Relevance to the deferred lever: HexCombat's crossing (`AntishipCrossing`) is a **count-based** port
> of the leakers/terminal-defense stages; the binding calibration constraint is IJFS **strike
> coverage** upstream (how many launchers fire), governed by `launches.py`-equivalent firing capacity.
