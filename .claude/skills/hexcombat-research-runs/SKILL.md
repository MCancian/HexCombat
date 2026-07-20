---
name: hexcombat-research-runs
description: Running HexCombat as a research instrument — Monte Carlo batches over seeds, parameter sensitivity sweeps, LLM players, and producing outcome reports with distributions and narratives. Use when the user asks for likely outcomes, a comparison between scenario variants, a sensitivity question, or AI-vs-AI games.
---

# Research runs (AI-vs-AI as an instrument)

> **Activation status:** batch layer LIVE (B7). Run a batch:
> `python3 tools/run_batch.py --name <study> --scenarios default,<variant>
> --matchups selfplay_default,llm_local:selfplay_default --n 30 [--turns 30] [--parallel 4]` →
> per-game JSON records + `manifest.json` + automatic `report.md` under
> `reports/batches/<study>/` (git-ignored). A bare matchup `p` means `p:p`; each condition is an
> explicit `red:green` pair, so conditions differ by exactly one thing under a common seed set.
> Checkpoint/resume: re-run the same command — only records that parse with `all_resolved` and no
> `index_violations` are skipped. Re-run any single deterministic game byte-identically via its
> manifest command line (or `godot --headless --path . -s res://tools/run_selfplay_game.gd --
> --seed=S --scenario=X --red-policy=R --green-policy=G --turns=T --out=file.json`). Verdicts are
> ARTIFACT-based, never exit-code-based — the Godot teardown flake corrupts exit codes. Use
> `--no-report` to suppress automatic aggregation; `llm_local` with parallel workers emits a
> warning, so use `--parallel 1` for live-model matchups.
> Narrative vignettes:
> `godot --headless --path . -s res://tools/make_game_narrative.gd -- --batch=<study>
> --pick=median|longest|shortest` (or `--record=<file>`) → `<record>.narrative.md`, a
> turn-by-turn account rendered from the event log (`GameNarrative.gd`). Sensitivity sweeps:
> `python3 tools/run_sweep.py --name <study> --knob <file:dot.path> --values a,b,c --n 30` —
> generates one-knob variants of the base scenario via the `DataOverrides` map, batches them on a common
> seed set, and reports. Any JSON knob in `data/` can be swept, not just scenario files. Canned
> sweeps: `python3 tools/run_sweep.py --spec tools/sweeps/<name>.json` (batch backend since plan
> 0012 — every cell is a parallel set of standard `run_batch.py` games; `sweep_metrics.py`
> extracts raw numbers from their records, `make_sweep_report.py` owns all formatting). Spec
> fields: `sweep_name`, `scenario` (existence enforced fail-loud), `matchup` (the canned
> calibration sweeps use `noop` — pure engine dynamics, the semantics their dialed references
> were accepted under), `turns`, optional `run_past_game_over`, `knobs`, `grid`, `seeds`,
> `metrics`, optional `extra_cells` — e.g. the antiship mines-only floor, now the
> `disable_antiship_systems` grouping-spec override.
> Typo'd override paths fail loud (`DataOverrides.unapplied()`); reports match cells by override
> content, not filename; stale cell files are cleared per run. The antiship instrument includes
> sealift (mandatory post-plan-0004; wave = sent cohort, ~81 BNs). **LLM-player adapter (B6)
> shipped and live-verified 2026-07-08** — policy id `llm_local` (`LLMPolicy`), sidecar
> `tools/llm_sidecar.py`, two-seat entrypoint `tools/run_selfplay_game.gd` with
> `--red-policy=llm_local --green-policy=llm_local` (`docs/STATUS.md` → "LLM players" has the
> full contract).
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
  registered by id in `PolicyCatalog` (unknown ids fail loud) — batch records stamp
  `red_policy_id` and `green_policy_id`, so a new policy = a `PolicyCatalog.create` branch + id.
- **Per-game record** (`tools/run_selfplay_game.gd`): v2 record with commit, scenario
  id/path/name, explicit Red/Green policy ids, seed, turns played/requested,
  game_over/winner/victory_reason, terminal census, final snapshot, full turn_digests (the B4
  narrative source). Deliberately timestamp-free so deterministic-seat records are
  byte-reproducible; per-game stdout lands in a sibling `.log`.
- **LLM players** plug in at the same seam: a policy that sends the observation JSON to a model
  and parses the action JSON back (contract: `schemas/*.schema.json`,
  `docs/LLM_OBSERVATION_SCHEMA.md`). Determinism caveat: LLM decisions aren't seed-reproducible —
  log every observation/action pair so the *game* is replayable even though the *decider* isn't.
- Victory state: `game_over`/`winner` on GameState/TurnResult/observation; census in
  `_taiwan_battalion_census` terms (present battalions).
- Sweep pattern: `tools/run_sweep.py` orchestration (fixed-seed grid + multi-seed means; every
  cell a parallel `run_batch.py` job set over standard game records) — generalized per plan
  0011, unified on the batch backend per plan 0012.
- Godot process-per-run is the parallelization unit (headless runs are cheap; separate processes
  also guarantee cross-process determinism, which is asserted by `validate_headless_selfplay.gd`).
- **Knob vector + cross-sweep analysis (plan 0018):** every record carries `record["knobs"]` — the
  full resolved value of every registry knob (`data/knobs/registry.json`; see
  `hexcombat-config-and-knobs`), so records from *different* sweeps are comparable. Two views over
  a `reports/` tree via `tools/research_knobs.py`:
  `ledger --records reports/` → one row per distinct knob-vector (game count, sources, outcome
  summary; held-constant knobs listed once) = "what have we explored?";
  `sensitivity --records reports/ --metric red_win_rate|census_margin` → ranks each *varying* knob
  by the spread it induces on the metric, with per-value sample counts (`n=`) and a thin-bin warning
  when a value is backed by <3 games (so noise doesn't masquerade as signal), plus a confounding
  caveat when >1 knob co-varies (cleanest is a single-knob sweep) = "which knobs move outcomes most?".
  LLM runs also record
  `llm_model` + `llm_prompt_hash` (capture-only) so a prompt/model change is never invisible.

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
