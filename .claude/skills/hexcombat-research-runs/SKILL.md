---
name: hexcombat-research-runs
description: Running HexCombat as a research instrument — Monte Carlo batches over seeds, parameter sensitivity sweeps, LLM players, and producing outcome reports with distributions and narratives. Use when the user asks for likely outcomes, a comparison between scenario variants, a sensitivity question, or AI-vs-AI games.
---

# Research runs (AI-vs-AI as an instrument)

> **Activation status:** batch layer LIVE (B2, 2026-07-02). Run a batch:
> `pwsh -File tools/run_batch.ps1 -Name <study> -Scenarios default,<variant> -N 30 [-Turns 30]
> [-Policies selfplay_default] [-Parallel 4]` → per-game JSON records + `manifest.json` under
> `reports/batches/<study>/` (git-ignored). Checkpoint/resume: re-run the same command — games
> with an existing valid record are skipped. Re-run any single game byte-identically via the
> command line stamped in its manifest result row (or
> `godot --headless --path . -s res://tools/run_selfplay_game.gd -- --seed=S --scenario=X
> --policy=P --turns=T --out=file.json`). Verdicts are ARTIFACT-based (record exists + parses +
> all_resolved + no index_violations), never exit-code-based — the Godot teardown flake corrupts
> exit codes. Then aggregate:
> `godot --headless --path . -s res://tools/make_batch_report.gd -- --batch=<study>` →
> `reports/batches/<study>/report.md` (per-condition win rates, turn/census/margin
> distributions, loss means, methods + caveats; logic in `BatchReport.gd`, GdUnit-tested).
> Narrative vignettes:
> `godot --headless --path . -s res://tools/make_game_narrative.gd -- --batch=<study>
> --pick=median|longest|shortest` (or `--record=<file>`) → `<record>.narrative.md`, a
> turn-by-turn account rendered from the event log (`GameNarrative.gd`). Sensitivity sweeps:
> `pwsh -File tools/run_sweep.ps1 -Name <study> -Knob <dot.path> -Values a,b,c -N 30` —
> generates one-knob variants of the base scenario, batches them on a common seed set, and
> reports (condition rows are the sweep axis). Sweeps only cover scenario-FILE knobs; a knob
> living in a phase data file needs promoting to a scenario key first. **LLM-player adapter (B6)
> shipped and live-verified 2026-07-08** — policy id `llm_local` (`LLMPolicy`), sidecar
> `tools/llm_sidecar.py`, two-seat entrypoint `tools/run_selfplay_game.gd` with
> `--red-policy=llm_local --green-policy=llm_local` (`docs/STATUS.md` → "LLM players" has the
> full contract). Remaining gap: the batch runner (`run_batch.ps1`) still takes
> one `-Policies` value for both sides — per-seat policy assignment in a batch is not yet wired.
> Single-file HTML game reports: `python3 tools/make_game_bundle.py --record <record.json>
> --html` writes `<record>.game.html`, a shareable report with the viewer bundle baked in — works
> for LLM games (`run_selfplay_game.gd` output) and for self-play games run with `--log` (the JSONL
> replay/event log `make_game_bundle.py` reads alongside the record).

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
- `SelfPlayRunner.play_game(policy, turns, base_seed, stop_on_game_over := false)` →
  `{final_snapshot, turn_digests, all_resolved, final_turn, index_violations}` — deterministic
  full games, headless. Batch runs pass `stop_on_game_over = true` (decided games stop).
- **Policy contract:** an object with `build_actions(observation) -> Array` (see
  `SelfPlayPolicy.gd` for the reference; instance-method Callables, not static). Policies are
  registered by id in `PolicyCatalog` (unknown ids fail loud) — batch records stamp the
  `policy_id`, so a new policy = a `PolicyCatalog.create` branch + id.
- **Per-game record** (`tools/run_selfplay_game.gd`): commit, scenario id/path/name, policy_id,
  seed, turns played/requested, game_over/winner/victory_reason, terminal census, final
  snapshot, full turn_digests (the B4 narrative source). Deliberately timestamp-free so records
  are byte-reproducible; per-game stdout lands in a sibling `.log`.
- **LLM players** plug in at the same seam: a policy that sends the observation JSON to a model
  and parses the action JSON back (contract: `schemas/*.schema.json`,
  `docs/LLM_OBSERVATION_SCHEMA.md`). Determinism caveat: LLM decisions aren't seed-reproducible —
  log every observation/action pair so the *game* is replayable even though the *decider* isn't.
- Victory state: `game_over`/`winner` on GameState/TurnResult/observation; census in
  `_taiwan_battalion_census` terms (present battalions).
- Sweep pattern: `tools/sweep_antiship_crossing.gd` (fixed-seed grid + multi-seed means) — the
  shape to generalize, per `docs/archive/refactor_audit.md` item 7.
- Godot process-per-run is the parallelization unit (headless runs are cheap; separate processes
  also guarantee cross-process determinism, which is asserted by `validate_headless_selfplay.gd`).

## Report shape (deliverable to the user)

Markdown (+ optional HTML mirror) under `reports/`: research question → conditions table →
methods line (commit, scenario, seeds, N, policy) → headline distributions (tables; plots
optional) → sensitivity ranking if swept → 1–3 narrative vignettes → caveats (model limits and
secondary-use divergences — pull from `docs/systems/` fidelity notes). Write for a wargaming
researcher, not a programmer.

## Cautions

- **Don't confuse policy strength with model claims.** A trivial policy losing is a statement
  about the policy, not the invasion. Report the policy identity prominently; compare policies
  under identical conditions before attributing outcomes to the scenario.
- Batch runs must not mutate committed state: scenarios read-only, outputs to `reports/`
  (git-ignored) — commit only the final report if the user wants it kept.
- Long batches: run in background, checkpoint per-game JSON as you go (a crashed batch should
  lose one game, not the night).
