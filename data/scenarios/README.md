# Scenario variants

One `.json` file per scenario variant; the **id** is the filename stem (`more_mines.json` →
`--scenario=more_mines` / `HEXCOMBAT_SCENARIO=more_mines`). The baseline stays at
`data/scenario_default.json` — it is a calibration artifact pinned by the golden gate; **never
edit it to make a variant** (variants are additive copies; see
`.claude/skills/hexcombat-scenario-authoring` for the recipe and
`.claude/skills/hexcombat-config-and-knobs` for every key).

Every file here is validated by `tools/validate_scenario_data.gd` (runs in the full gate) and is
enumerable by `ScenarioCatalog.list_scenario_paths()` for batch research runs. A variant's
`name`/`description` should state the research question it exists to answer.
