# Does an air path let Red route around the crossing? (plan 0032)

**Date:** 2026-07-24 · **Commit:** `d7475ac` · **Engine:** `red_airborne` scenario, 30 turns,
30 common seeds per cell · **Artifacts:** `reports/batches/airborne_bypass/`,
`reports/batches/airborne_vs_mobilized/`, `reports/sweeps/airborne_lift/`

## Question

The amphibious crossing is the PLA's binding chokepoint. Plan 0032 gives Red a second way in — fly
the PLAAF Airborne Corps onto the island under a per-turn lift cap. Does it change the outcome, or
is it a rounding error next to the ~81-battalion sea wave?

## Headline

**It erases the only defender-side lever that has ever moved the win rate.**

Against the plan-0029 configuration where 12 ROC reserve brigades phase in from mobilization — the
strongest defence measured to date, which had held Red to 83% — the air path takes Red back to 97%
and roughly halves the time to decision.

| Red policy | Red wins | Median decision turn | Red BN lost (ground) | Green BN lost (ground) |
|---|---|---|---|---|
| `selfplay_default` (no drops) | 25/30 — **83%** | 21 | 36.4 | 34.2 |
| `air_assault` (drops) | 29/30 — **97%** | 11 | 46.4 | 25.8 |

Both arms are the same scenario, same Green seat (`roc_defense`), same seeds, same ground play —
`air_assault` *is* `selfplay_default` plus the airborne doctrine. The only difference is the drops.
The no-drops arm reproduces plan 0029's 83.3% almost exactly, which is the cross-check that the
baseline is the configuration it claims to be.

Red pays for it: ground losses rise 36 → 46 battalions, because dropped formations fight isolated
until a corridor reaches them. It buys the win anyway.

## Lift quantity is not the constraint

Sweeping the per-turn airborne cap against the same mobilizing defender:

| Airborne BN/turn | Red win rate |
|---|---|
| 0 | 86.7% |
| 3 | 100.0% |
| 7 (dialled default) | 96.7% |
| 14 | 100.0% |

The response is a step, not a slope. Three battalions a turn is as decisive as fourteen; the spread
between 3, 7 and 14 is one game in thirty, i.e. seed noise. **What matters is that the corps exists
at all, not how fast it arrives.**

*Caveat on the 0 cell:* it grounds only the airborne class. The air-assault cap stays at 2 BN/turn,
so cell 0 is "almost no lift", not "no lift" — which is why it reads 86.7% rather than the 83% of
the true no-drops arm above. The comparison to make is the table in the previous section.

## Why it is this strong

Attrition after the standard 3-day pre-invasion warmup is small. Measured on seed 20260624, the
first drop costs 9.4% and the last 2.2%; 45 of 50 battalions were delivered for 2 lost. The model
prices insertion off Taiwan's surviving air defence (`0.75 × effective_ad_health`), and the IJFS
campaign has already driven that to ~0.24 by turn 1 and ~0.12 by turn 4. **By the time Red wants to
drop, the sky is effectively clear.**

Two consequences worth putting in front of the designer:

1. The permanent-airframe-loss rule — the mechanic's intended brake — barely engages. It only bites
   if Red drops *early*, into intact air defences, which no sensible policy does.
2. The supply-isolation rule does real work (it is why Red's ground losses rise) but does not
   prevent the win, because the `air_assault` doctrine deliberately drops near held ground.

## Open questions for the USER

- **Is a nearly-free corps the intended answer?** If airborne insertion should be a gamble rather
  than a sure thing, the lever is not the cap (it saturates) — it is either raising
  `max_attrition_at_full_ad`, decoupling attrition from AD health so the sky is never clear, or
  gating drops on something scarcer than airframes.
- **Should the 2 PLAA air assault brigades be added?** Still unbuilt; the OOB has 13 aviation
  brigades against the 15 the source gives, and only the corps' own air assault brigade feeds the
  rotary-wing cap.
- **A deep-drop doctrine is untested.** `air_assault` seizes ports and widens the lodgement. Whether
  a policy that drops on Taipei and accepts isolation does better or worse is unmeasured.

## Method notes

- Batch runner, one headless Godot process per game, artifact-based verdicts. Both batch reports
  carry a dirty-working-tree warning: the runs were made mid-implementation, before the final
  commit of the same code.
- **A silent-failure trap was hit and corrected during this study.** The first `airborne_vs_mobilized`
  run passed `--overrides` a file outside the project directory. The flatpak Godot sandbox cannot
  read those, and `DataOverrides` degraded to an empty map instead of failing — producing a batch
  that looked fine and was silently identical to the unoverridden run. Always confirm
  `record["overrides"]` is non-empty before believing an overridden batch.
