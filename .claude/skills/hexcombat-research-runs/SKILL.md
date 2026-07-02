---
name: hexcombat-research-runs
description: Running HexCombat as a research instrument — Monte Carlo batches over seeds, parameter sensitivity sweeps, LLM players, and producing outcome reports with distributions and narratives. Use when the user asks for likely outcomes, a comparison between scenario variants, a sensitivity question, or AI-vs-AI games.
---

# Research runs (AI-vs-AI as an instrument)

> **Activation status:** the building blocks exist and are gated (headless self-play,
> deterministic seeds, TurnResult event logs, scenario knobs). The batch-runner/report layer is
> the active build track — until it lands, runs are composed from the blocks below; once it
> lands, replace this note with the concrete runner commands.

## The methodology (this is the contract, whatever the tooling)

1. **A result is a distribution.** One game = one anecdote. A claim ("Red usually wins",
   "mines matter more than DOS") requires N seeded runs (start N=30+ per condition; more if the
   comparison is close) reporting: win rates per side, terminal-turn distribution, casualty
   distributions (BNs by side; ships by type), and the census margin.
2. **Conditions differ by exactly one thing.** Scenario variant A vs B, or knob value X vs Y —
   same seed *set* across conditions (common random numbers) so differences are attributable.
3. **Everything reproducible:** report the commit hash, scenario file, seed list, and policy
   identity alongside the numbers. A result that can't be re-run is not a result.
4. **Narratives explain, statistics conclude.** For representative games (median + extreme
   outcomes), render the per-turn event log (`TurnResult.to_dict().events`: ijfs → antiship →
   move → combat → cleanup rollups) into a readable turn-by-turn account of *why* that outcome
   happened.

## Building blocks (all live today)

- **Scenario selection (B1):** `--scenario=<id-or-path>` user arg (after `--`) or
  `HEXCOMBAT_SCENARIO` env var per process — arg wins, no selection = default, selection
  survives `reset_to_scenario`. `ScenarioCatalog.list_scenario_paths()` enumerates the default +
  `data/scenarios/*.json`; `scenario_id()` gives the reporting identity;
  `GameData.scenario_path` records what a process actually loaded (stamp it into run records).
- `SelfPlayRunner.play_game(policy, turns, base_seed)` → `{final_snapshot, turn_digests,
  all_resolved, final_turn, index_violations}` — deterministic full games, headless.
- **Policy contract:** an object with `build_actions(observation) -> Array` (see
  `SelfPlayPolicy.gd` for the reference; instance-method Callables, not static).
- **LLM players** plug in at the same seam: a policy that sends the observation JSON to a model
  and parses the action JSON back (contract: `schemas/*.schema.json`,
  `docs/LLM_OBSERVATION_SCHEMA.md`). Determinism caveat: LLM decisions aren't seed-reproducible —
  log every observation/action pair so the *game* is replayable even though the *decider* isn't.
- Victory state: `game_over`/`winner` on GameState/TurnResult/observation; census in
  `_taiwan_battalion_census` terms (present battalions).
- Sweep pattern: `tools/sweep_antiship_crossing.gd` (fixed-seed grid + multi-seed means) — the
  shape to generalize, per `refactor_audit.md` item 7.
- Godot process-per-run is the parallelization unit (headless runs are cheap; separate processes
  also guarantee cross-process determinism, which is asserted by `validate_headless_selfplay.gd`).

## Report shape (deliverable to the user)

Markdown (+ optional HTML mirror) under `reports/`: research question → conditions table →
methods line (commit, scenario, seeds, N, policy) → headline distributions (tables; plots
optional) → sensitivity ranking if swept → 1–3 narrative vignettes → caveats (model limits:
no terrain, secondary-use divergences — pull from `docs/systems/` fidelity notes). Write for a
wargaming researcher, not a programmer.

## Cautions

- **Don't confuse policy strength with model claims.** A trivial policy losing is a statement
  about the policy, not the invasion. Report the policy identity prominently; compare policies
  under identical conditions before attributing outcomes to the scenario.
- Batch runs must not mutate committed state: scenarios read-only, outputs to `reports/`
  (git-ignored) — commit only the final report if the user wants it kept.
- Long batches: run in background, checkpoint per-game JSON as you go (a crashed batch should
  lose one game, not the night).
