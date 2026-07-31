# Research Harness

## 1. Purpose

The research harness is the tooling layer that runs headless games, collects results,
and produces reports for the HexCombat wargame. It is not a game subsystem — it drives the
sim from outside. The LLM API and self-play runner are documented in
`docs/systems/llm-api-selfplay/llm-api-selfplay.md`; this module covers the batch/sweep/report
tools that consume game records.

## 2. Components

| Tool | Role |
|---|---|
| `tools/run_batch.py` | Scenario × matchup × seed matrix runner |
| `tools/run_selfplay_game.gd` | Single headless game (Godot entry point) |
| `tools/make_batch_report.gd` | Batch → `report.md` aggregation |
| `tools/make_game_narrative.gd` | Game record → turn-by-turn Markdown |
| `tools/run_sweep.py` | Knob sweep over batch cells |
| `tools/sweep_metrics.py` | Raw number extraction from game records |
| `tools/make_sweep_report.py` | Sweep display formatting |
| `tools/mc_summarize.py` | Batch → Monte Carlo summary JSON |
| `tools/mc_chart.py` | Summary JSON → deck SVG chart |
| `tools/research_knobs.py` | Knob-space ledger and sensitivity analysis |
| `scripts/KnobRegistry.gd` | Knob registry loader + record dump |
| `data/knobs/registry.json` | Curated registry of 55 outcome-relevant knobs |

## 3. Data flow

```
scenario + matchup + seeds
  → run_batch.py (parallel Godot processes)
    → run_selfplay_game.gd per game
      → v2 JSON game record
  → make_batch_report.gd → report.md
  → mc_summarize.py → summary.json → mc_chart.py → SVG
  → run_sweep.py (cell variants via DataOverrides)
    → sweep_metrics.py → make_sweep_report.py → sweep report
```

Full status: `docs/systems/research-harness/STATUS.md`.

## 4. State & authority

**This subsystem owns no protected runtime aggregate.** The harness drives whole games from the
outside — it launches processes, collects records, and aggregates them — and every mutation it causes
happens inside `resolve_turn`, through the ten authorities under `scripts/transitions/`. Nothing here
writes campaign state, and nothing here holds any.

The one thing it does depend on is the property that makes the records comparable at all: the same
commit, scenario, seat policies and seed must reproduce a record **byte-for-byte**. That is why every
record carries `commit`, `record_version` and `knobs_registry_version`, and why a batch may be resumed
from a checkpoint. The mutation-authority campaign (0042–0050) preserved it at every step: after the
0050 closeout, 40-turn `scenario_golden` and `scenario_default` records were byte-identical both across
separate processes and against the pre-change tree.

- **Manifest:** [tools/mutation_authority_manifest.json](../../../tools/mutation_authority_manifest.json).
