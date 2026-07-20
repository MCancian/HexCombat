---
title: "0021: garrison_draw — a Green force-draw policy + swept draw_fraction knob"
status: "Ready"
created: "2026-07-20"
---

# Plan 0021: `garrison_draw` — how much can Green strip its other theaters?

## Research question (USER 2026-07-20)

How far can Green (ROC) pull forces out of its non-landing theaters to reinforce the beachhead
before it backfires? Sweep the drawn fraction — **0% / 50% / 80%** of other-TO brigades — and read
the effect on the outcome. This is the *measurement* half of a two-sided study; the Red
counter-pressure (exploiting a stripped theater by opening a new beach) is [[0022-red-beach-switching]].

## Why a scripted policy, not the LLM (settled 2026-07-20)

The study needs the drawn fraction to be an **exact, reproducible knob** so the sensitivity tool can
attribute an outcome shift to it and nothing else (research contract: "conditions differ by exactly
one thing"). An LLM seat can't hit a precise 0/50/80% and isn't seed-reproducible. So this is a new
**deterministic scripted policy** in the `selfplay_default` family, not a prompt. (Watching an LLM
Green *choose* how much to draw is a valid follow-up, not this.)

## Design

New policy id `garrison_draw` registered in `PolicyCatalog` (`create` branch + `known_ids`),
implementing the standard `build_actions(observation) -> Array`. Behavior each turn:

1. Identify the **landing theater(s)** — the TO(s) where Red is ashore/contesting (derive from the
   observation's hex ownership + Red brigade positions; beaches map to TOs via `beach_to_to`).
2. Partition Green brigades into *in-landing-TO* vs *other-TO* (brigade `to_number` from `GameData`).
3. Deterministically select `draw_fraction` of the other-TO brigades (see design call #1) and, each
   turn, march each selected brigade one hex toward the landing beachhead (existing pathfinder /
   `find_reachable`, pick the reachable hex minimizing distance to the landing). Non-selected
   other-TO brigades hold in place. In-landing-TO brigades: hold/defend (design call #4).

Deterministic given the observation, so games stay seed-reproducible (same discipline as
`InlandClearPolicy`, including the "GameData is empty at policy construction — load beach/TO data on
first `build_actions`, not in `_init`" gotcha; tests inject synthetic data via `_init`).

### The knob (this is what makes it sweepable + recorded)

`draw_fraction` lives in **`data/policies/garrison_draw.json`** (`{ "draw_fraction": 0.0,
"selection_rule": "..." }`) — a data file so it is `DataOverrides`-sweepable and dumps into every
record via the knob registry. Add a registry entry
`data/policies/garrison_draw.json:draw_fraction` (sweepable, group `policy`). The policy reads it
from `GameData` on first use. (Rationale for a `data/policies/` home over a scenario field: it is a
policy parameter, not scenario content — keep the concerns separate; "everything tunable comes from
`data/*.json`".)

## Design calls for USER (recommended defaults in **bold**)

1. **Which fraction of brigades?** Selection must be deterministic. Options: **(a) the `draw_fraction`
   nearest the landing** (militarily sensible — closest reinforcements move first), (b) stable by
   brigade id (most neutral), (c) by battalion strength (heaviest first). *Recommend (a).*
2. **What "draw" does:** **march the selected brigades toward the landing hex** each turn (the point
   is reinforcement) vs. merely leave the home TO. *Recommend march-toward-landing.*
3. **Rounding** of `draw_fraction × N`: **round to nearest**, min 0. *Recommend round.*
4. **Non-drawn / in-TO brigades:** **hold in place (pass)** vs. local defense maneuver. *Recommend
   hold* (keeps the knob's effect clean — only the drawn brigades move).
5. **Red opponent for the study (study-design, not policy):** run Green `garrison_draw` against Red
   **`inland_clear`** (sustained beachhead — gives Green a multi-turn threat to reinforce against)
   vs. `selfplay_default`. *Recommend `inland_clear`* on the `roc_full_defense` scenario (all 32 ROC
   brigades placed across real garrison TOs — the only scenario where "other theaters" is meaningful).

## Objectives / steps (each its own commit, gated)

1. `data/policies/garrison_draw.json` + registry entry + validator stays green.
2. `scripts/GarrisonDrawPolicy.gd` + `PolicyCatalog` registration.
3. GdUnit test with injected synthetic observation + GameData (selection rule honored at 0/0.5/0.8;
   determinism; non-drawn hold). Follow `InlandClearPolicy`'s test pattern.
4. A real sweep: `run_sweep.py --scenario roc_full_defense --matchup inland_clear:garrison_draw
   --knob "data/policies/garrison_draw.json:draw_fraction" --values 0.0,0.5,0.8 --n 30`, then
   `research_knobs.py sensitivity` over the records → the deliverable.

## Verification

- `bash tools/run_all_tests.sh` ALL PHASES GREEN — golden byte-stable (new opt-in policy + data
  file; nothing existing changes).
- The sweep runs and the sensitivity report shows `draw_fraction`'s effect with per-value n and the
  census/win-rate distribution.

## Closeout targets

`docs/systems/` (a short note on the policy if warranted); `hexcombat-research-runs` (register the
new policy id + the study recipe); `hexcombat-config-and-knobs` (the new knob); DECISIONS; STATUS
(new policy in the players table); archive.
