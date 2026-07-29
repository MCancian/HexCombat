# Research Harness — Status

**Scenario selection (research harness B1)** — any headless process picks its scenario via the
`--scenario=<id-or-path>` user arg or `HEXCOMBAT_SCENARIO` env var (`ScenarioCatalog`; arg wins,
no selection = `data/scenarios/scenario_default.json` so all pins hold). Variant files live in
`data/scenarios/` (id = filename stem, enumerated by `ScenarioCatalog.list_scenario_paths()`);
the selection survives `GameState.reset_to_scenario()`; `validate_scenario_data.gd` checks every
scenario generically + the default's pinned shape.

**Batch runner (research harness B2/B7)** — `python3 tools/run_batch.py --name <study>
--scenarios default,<variant> --matchups red:green,... --n 30` plays a scenario × matchup ×
common-seed matrix, one headless Godot process per game, up to `--parallel` at a time. A bare
matchup policy means the same policy in both seats. Each game (`tools/run_selfplay_game.gd`)
writes a timestamp-free, byte-reproducible (for deterministic seats) v2 JSON record with
explicit Red/Green policy identities to `reports/batches/<study>/games/`; verdicts are
artifact-based; re-running resumes only valid records; `manifest.json` stamps matchups,
commit, and per-game re-run command lines. The runner writes `report.md` automatically
(`--no-report` suppresses it). The runner warns when a live-model matchup uses more than one
worker; use `--parallel 1`.

**Outcome reports (research harness B3)** — `tools/make_batch_report.gd -- --batch=<study>`
aggregates a batch's records into `report.md`: per-condition (scenario × Red policy × Green
policy) win rates, turn/census/margin distributions, per-game loss means, a methods line
(commit, mixed-commit and dirty-tree warnings), and standing caveats (including LLM
non-determinism). Aggregation/rendering is pure `BatchReport` statics (GdUnit-tested).

**Narrative renderer (research harness B4)** — `tools/make_game_narrative.gd`
(`--record=<file>` or `--batch=<study> --pick=median|longest|shortest`) renders a game
record's event log into a turn-by-turn Markdown account (IJFS strikes + air-defense
degradation, the crossing, maneuver/commitments, per-hex ground combat with FEBA movement,
end-of-turn census, outcome). Pure `GameNarrative` statics (GdUnit-tested).

**Knob sweeps (research harness B5)** — `python3 tools/run_sweep.py --spec tools/sweeps/<spec>.json` or `python3 tools/run_sweep.py --name <study> --knob <file:dot.path> --values a,b,c` generates cell variants
(via `DataOverrides` map), batches them over a common seed set, and reports per-value
outcome rows. One backend since plan 0012: every cell is a parallel `run_batch.py` job set of
standard `run_selfplay_game.gd` games; `sweep_metrics.py` extracts raw numbers from the game
records (turn digests + terminal census) and `make_sweep_report.py` owns all display
formatting. The canned calibration specs run `matchup: noop` (pure engine dynamics — the
measurement semantics their dialed reference tables were accepted under; per-seed parity with
the retired in-process cell runner verified). Any JSON knob in `data/` can be swept.
A spec's `scenario` id must resolve to a file before any game runs; typo'd override paths fail
loud via `DataOverrides.unapplied()` in the selfplay entrypoint; reports match cells by
override content, not filename. **The
antiship crossing instrument changed:** the harness now runs sealift between IJFS
and the crossing (mandatory since plan 0004 — without it no cohort is "sent" and losses read
zero), and the wave is the sent cohort (~81 BNs incl. follow-on echelons), not the 36-BN ship
reserve. The plan-0001 dial (ic=36, bonus=0.20) reads **32.9%** mean crossing loss on the new wave
semantics — USER accepted (supersedes the ~25%-of-36-BN target; table:
`reports/sweeps/antiship_crossing/report.md`).

**Research knob tracking (plan 0018)** — a curated registry `data/knobs/registry.json` (23
outcome-relevant knobs, IJFS warmup → beach capacity) drives a full resolved-knob dump into every
game record (`record["knobs"]`, via pure `scripts/KnobRegistry.gd`), so records from any sweep
share one knob-space and are directly comparable. LLM games also record `llm_model` +
`llm_prompt_hash` (the sidecar hashes its system prompt) so a prompt/model change is never
invisible. `python3 tools/research_knobs.py ledger --records reports/` renders the explored-space
table (one row per distinct knob-vector, held-constant knobs listed once);
`... sensitivity --records reports/ --metric red_win_rate|census_margin` ranks which varying knobs
move outcomes most (confounding caveat when >1 co-varies). Registry integrity + path resolution
gated by `tools/validate_knob_registry.gd`; the analysis tools by `tools/validate_research_knobs.py`.
`DataOverrides` addresses arrays (`name[*]`/`name[]` = all elements, `name[N]` = one), so array
knobs are first-class sweepable too — e.g. `--knob "data/beaches.json:beaches[*].capacity_battalions"`
scales every beach at once; `KnobRegistry._extract` shares the grammar for the record dump.

**Monte Carlo outcome distribution (deck slide 6)** — `tools/mc_summarize.py` aggregates a
`run_batch.py` batch into a committable, timestamp-free summary JSON (outcome counts, win rates,
and the victory-margin / battalions-ashore / turns-to-decision distributions with histogram bins);
`tools/mc_chart.py` renders that summary into a deck-themed self-contained inline `<svg>` (no
fabricated numbers — the chart is a pure function of the batch). Both are stdlib-only standalone
tools, not wired into the gate. Headline result (200 seeds, `selfplay_default` both seats,
`scenario_default`, commit 7339378): **PLA wins 200/200 but by a stochastic margin** (min +1,
median +6, mean +8, max +28); single-knob sweeps of beach capacity (1→4) and anti-ship lethality
(0→0.8) leave the win rate flat at 100% — the laydown is structurally Red-favored, the RNG sets the
margin not the winner. Report + committed data: `docs/reports/2026-07-23-monte-carlo-outcome-distribution.md`
(+ `docs/reports/assets/mc_outcome_distribution.{summary.json,svg}`). The slide's `#mc-distribution`
container holds the generated SVG (`data-status="ready"`). **Follow-up (structural cause + the flip
lever):** the 100% win rate is structural — the PLA follow-on auto-seeds from the entire mainland OOB
(`auto_seed_followon_pool`, a bottomless reservoir) and no campaign clock caps the buildup, so a
logistics-throttled trickle still out-accumulates the defender. The plausible flip lever is **beach
offload throughput**: sweeping `data/beaches.json:beaches[*].offload_rate` gives a clean monotone
crossing — the invasion culminates below ~1,330 t/day (deck **slide 7** "Where the Invasion
Culminates" + `tools/mc_chart.py --crossing`; spec `tools/sweeps/mc_offload_throughput.json`). Fixed
a registry bug in the process: `offload_beach_base_rate` pointed at the phantom `offload_rates.json`
(never loaded at runtime — throughput is `OffloadRates` constants; the JSON is only a validation
mirror), so its sweep silently no-op'd; repointed to the real `beaches[*].offload_rate`, and marked
`offload_operational_port_rate` `sweepable:false` (dump-only code constant). Still open:
`combat_{defender,attacker}_advantage_ratio` are registry knobs recorded but inert (don't reach
`CombatResolver`).
