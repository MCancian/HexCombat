---
name: hexcombat-config-and-knobs
description: Catalog of every HexCombat configuration axis — scenario parameters, data/*.json content files, tuning knobs and their defaults — plus the checklist for adding a new scenario parameter. Use when changing balance/content values, authoring a scenario variant, or wiring a new tunable.
---

# HexCombat configuration & knobs

Everything tunable comes from `data/*.json` + the scenario file — adding content is a data change,
not a code change. Verify a knob is actually read before relying on it (grep the consumer;
"knob does nothing" = silent-default bug class, see `hexcombat-debugging-playbook`).

## The scenario file (`data/scenario_default.json` + `data/scenarios/*.json` variants)

Loaded by `GameData.load_scenario()`; which file a process loads is decided by
`ScenarioCatalog.selected_path()` (`--scenario=<id-or-path>` user arg beats
`HEXCOMBAT_SCENARIO` env var; no selection → the default, so all pins hold; selection survives
`reset_to_scenario`). Variant authoring recipe: `hexcombat-scenario-authoring`. Current axes:

| Key | Default | Consumed by |
|---|---|---|
| `turn_length_days` | 1 | `GameState` turn engine |
| `red_dos_start` | 100 | D2 supply pool (`SupplyState`) |
| `feba_base_km` | 3.5 (TIV value) | Ground combat FEBA shift (`GameData.feba_base_km` → `CombatCalculator`) |
| `red_out_of_supply_effectiveness` | 0.5 | Red combat strength when DOS pool ≤ 0 |
| `stacking_soft_cap` | 6 | Stacking |
| `victory.loss_check_arm` | `after_first_landing` here; code default `unconditional`; also `after_turn:<N>` | Victory census arming |
| `victory.taiwan_hexes` | `null` = all placed hexes (land-data hook) | Victory census scope |
| `red_ship_reserve` | 4 PLA amphibious brigades, locked beaches + `beach_hex` + `offset_bearing` | D1 offload start-at-sea |
| `placements` | 4 ROC defenders with hex + `offset_bearing` | Initial placement |

**Scenario variants are first-class** (user objective): a new variant = a new scenario JSON.
Anything hard-coded that a variant would want to vary is a bug — promote it to a scenario key.

## Content data files

| File(s) | Content | Validator |
|---|---|---|
| `data/taiwan_hex_grid.json` | 466 hexes (GSHHG-coastline-reconciled, Track F), odd-r offset coords + centers | (loaded in smoke) |
| `data/terrain/terrain_types.json` | 5 terrain classes: per-class `defender_modifier`, `move_cost`, `impassable`, `color` | `tools/validate_terrain_data.gd` |
| `data/terrain/hex_terrain.json` | Per-hex terrain class assignment (every grid hex classified) | `tools/validate_terrain_data.gd` |
| `data/pla_ground_forces.json` / `roc_ground_forces.json` | OOBs: 111 PLA + 32 ROC brigades | `validate_oob_data.gd` |
| `data/nato_symbol_map.json` | nato_type → SVG symbol | `validate_symbol_map.gd` |
| `data/beaches.json`, `data/offload_rates.json` | Beach defs; offload throughput (TONS_PER_BN=2200) | `validate_beaches_data.gd`, `validate_offload_data.gd` |
| `data/ships.json`, `data/theaters.json` | Ship types (optional per-hull `mine_neutralization_likelihood`), theaters | `validate_ship_data.gd`, `validate_theater_data.gd` |
| `data/ijfs/*.json` | Air OOB, munitions, targets, pairings, SAM caps, IJFS scenario (warmup days etc.) | `validate_ijfs_data.gd` |
| `data/antiship/*.json` | Systems, combat catalog, magazines, grouping, crossing config, minefields | `validate_antiship_data.gd` |
| `data/antiship/minefields.json` | Geometric mine model knobs: `geometry` (field size, `danger_radius`, sweeper rates) + `transit` (decoy mix/order) | `validate_antiship_data.gd` |

## Code-resident constants (single-source rule)

Unit strengths live ONLY in `UnitStats.TYPE_DEFS`; DOS constants only in `DosConsumption.gd`
(300/150/150); offload only in `OffloadRates.gd`. `CombatCalculator`'s `TERRAIN_MODIFIERS` (an old
unused string-keyed const, superseded by `data/terrain/terrain_types.json` +
`GameData.get_terrain` — dead code, left untouched) and `SUPPORT_MULTIPLIERS` are code constants
today — data-driven promotion is fine if a scenario variant needs them. Known wart:
`CombatCalculator.gd` carries a stale `feba_base_km=2.0` default param; real callers pass the
scenario value.

## Terrain knobs (Track F)

| Knob | Where it lives | Consumed by |
|---|---|---|
| Per-class `defender_modifier` (plains 1.0, hills 1.5, urban 2.0, mountain 2.0, metropolis 3.0) | `data/terrain/terrain_types.json` | `GameState._defender_combat_modifier` → `CombatResolver.resolve_at` (ground combat) |
| Per-class `move_cost` (plains/urban/mountain 1, hills/metropolis 2) | `data/terrain/terrain_types.json` | `GameData._terrain_entry_cost` → `HexMath.find_path`/`find_reachable` (weighted Dijkstra) |
| Per-class `impassable` (mountain only) | `data/terrain/terrain_types.json` | `GameData._with_impassable` (movement) |
| Per-class `color` (fill tint) | `data/terrain/terrain_types.json` | `HexMap.get_hex_color` (view) |
| Per-hex terrain class assignment | `data/terrain/hex_terrain.json` (generated by `tools/terrain/classify_hexes.py`; edit `tools/terrain/overrides.json` to correct a hex, never this file directly) | `GameData.load_terrain()` |
| Red/contested region-border style (3px, z 4, full-alpha red/contested-ramp; hex fills stay pure terrain color) | Code-resident literals in `scripts/HexMap.gd` (`_build_ownership_borders`/`_add_border_line`) — not scenario/data-driven | `HexMap._build_ownership_borders` (view) |
| Grid-inclusion land-fraction threshold (≥0.05) | Code-resident literal, `tools/terrain/reconcile_grid.py:46` (`_LAND_FRAC_THRESHOLD`) — a one-shot regeneration script, not a runtime knob | `tools/terrain/reconcile_grid.py` (grid regeneration, not run at game time) |

Full behavior: `docs/systems/terrain.md`.

## Adding a scenario parameter (checklist)

1. Add the key to `data/scenario_default.json` with a `_comment` if non-obvious.
2. Read it in `GameData.load_scenario()` into a typed field — **fail loud** if malformed;
   a genuinely optional key gets an explicit, documented default in ONE place.
3. Thread it to the consumer explicitly (signature param or typed field — no `.get()` chains).
4. Extend `validate_scenario_data.gd` to assert presence/type/range (its generic checks run
   against EVERY scenario in `data/scenarios/` — new keys must hold for variants too).
5. If it affects resolution: golden impact expected? If the golden scenario uses the default,
   keep the default = old behavior so the golden stays byte-stable; the variant exercises the
   new value (per "tie to a need" — `hexcombat-change-control`).
6. If agents should see it: surface through the LLM observation + schema + fixture regen.
7. Document: this skill's table + `docs/systems/` of the consuming system.

## Calibration / balance work

Measured, never eyeballed: use/extend the sweep harness pattern (`tools/sweep_antiship_crossing.gd`)
— fixed seed grid + multi-seed means, report per-knob deltas. Balance targets and lever analyses
live in PLAN.md → Open Questions (e.g. the ~25% crossing-loss calibration record). Deliberate
balance changes are USER calls and re-baseline events.
