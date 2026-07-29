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
| `data/knobs/registry.json` | Curated registry of 23 outcome-relevant knobs |

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
