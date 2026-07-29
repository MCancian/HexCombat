# ROC Mobilization — Status

**ROC mobilization phase-in (plan 0029 Tier A2, USER call)** — a scenario may hold a
slice of the **existing** ROC force off-map "in mobilization" and phase it in over the opening
turns, instead of standing the whole OOB (including its 12 reserve infantry brigades, 36 of 124
BNs) on its garrison hexes at H-hour. Scenario block `green_mobilization`
(`held_back_brigades` — **0 by default, so nothing changes and golden stays byte-stable** —
`brigade_types`, `first_release_turn`, `release_interval_turns`, `brigades_per_release`; all four
are `scenario:`-prefixed registry knobs). Held brigades are `hex_id == ""`, the same not-present
state Red's at-sea brigades use, so the census, legal moves and IJFS targeting exclude them; on
release they arrive at their real garrison hex (or the nearest non-enemy passable hex, else defer)
and their maneuver targets are appended to the live IJFS state. The phase runs between amphibious
offload and movement — the same seam as Red's reinforcement — and consumes no dice. Total force is
unchanged; the lever is exposure timing (off-map battalions sit out the front-loaded fires
campaign). Coverage: `tools/validate_mobilization.gd` + `tests/mobilization_*_test.gd`.
Detail: `docs/systems/roc-mobilization/roc-mobilization.md`. **Measured (30 seeds/cell,
`selfplay_default` vs `roc_defense`, `scenario_default`, 30 turns):** holding 0/4/8/12 reserve
brigades back takes the Red win rate 100% → 93.3% → 90.0% → **83.3%** and pushes mean decision
from turn 20.0 to 22.4 — the first defender-side lever to move the win rate off 100%, with no
extra force. Green's census curve stops being monotone (rises t5→t8, plateaus to t14 where the
baseline fell 89→53); 17% of seeds survive the horizon with the ROC ahead. It does **not** flip
the median game: a finite 36-BN reserve cannot beat the bottomless follow-on pool. Release timing
is nearly flat and its weak "later is better" gradient is a model artifact (off-map is a sanctuary
with no modelled cost). Report: `docs/reports/2026-07-24-roc-mobilization-sweep.md`.
