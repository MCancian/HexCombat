---
status: Shipped
shipped: 2026-07-22
landed_in: docs/DECISIONS.md
---
# 0013 — One home for scenario files (`data/scenarios/`)

**Goal:** Move `data/scenarios/scenario_default.json` and `data/scenarios/scenario_golden.json` into
`data/scenarios/`, so every scenario lives in `SCENARIOS_DIR` and `ScenarioCatalog` loses its
special cases.

## Context & Motivation

The two founding scenarios predate `ScenarioCatalog` (research-harness B1) and live in `data/`
root; variants added since live in `data/scenarios/`. The split forces special-casing that has
already caused one real incident:

- `ScenarioCatalog.resolve_path` needs a dedicated branch so the id `scenario_default` doesn't
  resolve to the nonexistent `data/scenarios/scenario_default.json` (added 2026-07-18 after a
  sweep silently ran with an empty ship reserve off exactly that bad resolution — see DECISIONS
  2026-07-18 review fixes).
- `list_scenario_paths` prepends `DEFAULT_SCENARIO_PATH` instead of just globbing one directory.
- The gate selects the golden fixture by full path (`HEXCOMBAT_SCENARIO=res://data/scenarios/scenario_golden.json`
  in `tools/run_all_tests.sh` / `.ps1`) rather than by id.

One directory = id↔path resolution is a single rule (`SCENARIOS_DIR/<id>.json`), enumeration is
one glob, and no future id can silently miss its file.

## Design

1. `git mv data/scenarios/scenario_default.json data/scenarios/scenario_default.json` (same for
   `scenario_golden.json`).
2. `ScenarioCatalog`: point `DEFAULT_SCENARIO_PATH` at the new location; delete the
   `scenario_default`-id special branch (bare-id rule now covers it); simplify
   `list_scenario_paths` to a pure glob with the default sorted first (or simply first-by-name —
   decide by what the validator pins).
3. Gates: switch `HEXCOMBAT_SCENARIO` exports to the id form (`scenario_golden`) — ids are
   location-independent, so a future move can't break the gate again.
4. Sweep chain needs no change (specs already select by id).

## Reference inventory (grep before executing — this list is 2026-07-18)

- Code: `scripts/ScenarioCatalog.gd` (const + special cases), `scripts/GameData.gd`
  (fallback comment/path), `tools/validate_deep_pool_smoke.gd`, `tools/validate_terrain_data.gd`,
  `tests/scenario_catalog_test.gd` (path assertions).
- Harness: `tools/run_all_tests.sh`, `tools/run_all_tests.ps1` (`HEXCOMBAT_SCENARIO` export).
- Docs: `data/scenarios/README.md`, `docs/STATUS.md`, `docs/systems/*.md`, skills
  (`hexcombat-config-and-knobs`, `hexcombat-scenario-authoring`, `hexcombat-validation-and-qa`);
  sweep manifests under `reports/` are generated artifacts — ignore.
- Godot `.uid`/import metadata: none (plain JSON, not imported resources).

## Risks & Validation

- **Golden byte-identity is the whole risk.** The move must change zero behavior: same files,
  new paths. Full gate (both boxes' scripts touched) must stay ALL PHASES GREEN with **no
  re-baseline** — any pin drift means a reference was missed, never a legitimate change.
- Stale-path references that only bite at runtime (validators that hardcode the old path) —
  the reference inventory + a final `grep -rn "data/scenario_default\|data/scenario_golden"`
  (excluding `docs/archive/`, `reports/`) must come back empty.
- Windows box parity: `.ps1` gate edit can't be exercised from the Linux box — flag for a
  Windows-side gate run at next opportunity before calling the plan shipped.

## Checklist

- [ ] Phase A — `git mv` both files; update `ScenarioCatalog` consts + delete special cases;
      update the two gate scripts to id-form selection; fix code/test references; gate green.
- [ ] Phase B — docs/skills reference sweep; final grep clean; DECISIONS entry; STATUS pointer
      if any behavior wording changes (none expected).
- [ ] Phase C — Windows gate run confirmed green; closeout + archive.
