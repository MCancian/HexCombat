---
name: hexcombat-scenario-authoring
description: How to author a new Taiwan scenario variant — force mixes, start postures, timelines, victory arming, balance knobs — validate it, and register it for research runs. Use when the user asks for a new scenario, an excursion case ("what if Red had 8 brigades"), or a comparative study setup.
---

# Authoring a scenario variant

Scenario variants are **first-class content** (user objective 2026-07-02): comparative research
runs ("baseline vs more-mines vs degraded-IJFS") are a core deliverable. A variant is a data
change; if authoring one forces a code change, that's a parameterization gap — fix it per
`hexcombat-config-and-knobs` (promote the hard-coded value to a scenario key) and record it.

## Recipe

1. **Copy the baseline:** `data/scenario_default.json` → `data/scenarios/<slug>.json`
   (keep `scenario_default.json` untouched — the golden gate and every pinned test load it).
   The variant's **id is the filename stem**; any headless process selects it with the
   `--scenario=<id>` user arg (after Godot's `--` separator) or `HEXCOMBAT_SCENARIO=<id>` env
   var (arg wins; ids, `res://`/absolute paths, and `default` all resolve via
   `ScenarioCatalog.resolve_path`). The selection survives `GameState.reset_to_scenario()`;
   no selection → the default, so all pins hold.
2. **Vary the axes** (full key reference: `hexcombat-config-and-knobs`):
   - Forces: `red_ship_reserve` entries (brigade IDs from `data/pla_ground_forces.json`),
     `placements` (from `roc_ground_forces.json`); beach assignments + bearings.
   - Posture/timeline: IJFS warmup days (`data/ijfs/ijfs_scenario.json` — note: some phase
     content lives in phase data files, not the scenario file; a variant that varies those needs
     them scenario-selectable too — same parameterization-gap rule).
   - Logistics: `red_dos_start`, offload rates.
   - Balance: `feba_base_km`, `red_out_of_supply_effectiveness`, minefield geometry/transit.
   - Victory: `loss_check_arm`, `taiwan_hexes`.
3. **Name and describe:** `name` + `description` state the variant's *research question* — what
   comparison it exists to make.
4. **Validate:** `tools/validate_scenario_data.gd` already covers **every** file in
   `data/scenarios/` (generic authoring-contract checks) plus pinned expectations on the
   default — run it (it's also in the full gate). Beach/placement adjacency is only pinned for
   the default's designed geometry; if your variant wants defenders adjacent to beaches, check
   with `HexMath.neighbor_coords`, never by eyeball — a scenario once had a non-adjacent
   "neighbor" that masked the adjacency bug.
5. **Prove it plays:** headless self-play for N turns (`SelfPlayRunner`) — it must run to a
   terminal or turn-limit with no errors, deterministically (same seed twice → identical
   snapshot). A scenario that can't self-play headless is not done.
6. **Register:** nothing manual — `ScenarioCatalog.list_scenario_paths()` enumerates the
   default + every `data/scenarios/*.json` for the validator and batch runs
   (see `hexcombat-research-runs`).

## Design cautions

- The golden scenario is a **calibration artifact**, not just an example — never edit it to make
  a variant; variants are additive files.
- OOB edits (new brigades/battalion mixes) belong in the OOB JSONs with `validate_oob_data.gd`
  updated counts; a scenario references forces, it doesn't define them.
- Balance-knob variants change outcomes by design — they never re-baseline the golden (which is
  pinned to the default scenario).
- If a variant needs a mechanic that doesn't exist (e.g. reinforcement schedules), that's a new
  phase/mechanic task (`hexcombat-add-phase-resolver`), designed with the user first.
