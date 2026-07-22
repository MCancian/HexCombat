---
name: hexcombat-config-and-knobs
description: Catalog of every HexCombat configuration axis — scenario parameters, data/*.json content files, tuning knobs and their defaults — plus the checklist for adding a new scenario parameter. Use when changing balance/content values, authoring a scenario variant, or wiring a new tunable.
---

# HexCombat configuration & knobs

Everything tunable comes from `data/*.json` + the scenario file — adding content is a data change,
not a code change. Verify a knob is actually read before relying on it (grep the consumer;
"knob does nothing" = silent-default bug class, see `hexcombat-debugging-playbook`).

## The scenario file (`data/scenarios/scenario_default.json` + `data/scenarios/*.json` variants)

Loaded by `GameData.load_scenario()`; which file a process loads is decided by
`ScenarioCatalog.selected_path()` (`--scenario=<id-or-path>` user arg beats
`HEXCOMBAT_SCENARIO` env var; no selection → `scenario_default` = the research default). **The pinned
gate does NOT run `scenario_default`:** `run_all_tests.sh`/`.ps1` export
`HEXCOMBAT_SCENARIO=res://data/scenarios/scenario_golden.json` (a frozen one-shot assault fixture) so golden
pins stay byte-stable while `scenario_default` evolves as the deep-pool research scenario. To run a
golden validator by hand, export the same var. Variant authoring: `hexcombat-scenario-authoring`.
Current axes:

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
| `red_followon_reserve` | `[]` (explicit follow-on echelon; `roc_full_defense` uses 10) | Sealift `mainland_pool` (`SealiftStateBuilder`) |
| `auto_seed_followon_pool` | `false`; `scenario_default` sets `true` | Opt-in deep pool auto-seeded from OOB when no explicit follow-on |
| `amphibious_return_time_turns` | `0`; `scenario_default`/`roc_full_defense` use `3` | Freed-hull return delay (`SealiftResolver`) |
| `escort_reload_time_turns` | `0` (magazine off); `roc_full_defense` uses `4` | Escort SAM reload cycle |
| `use_offload_weight_matrix` | `false` (flat TONS_PER_BN); `scenario_default` sets `true` | Day-N offload cost = per-type weight × bn_class/ship_category multiplier (`data/offload_weights.json` → `OffloadCostModel`; plan 0006) |
| `auto_jlsf` | `false`; `scenario_default` sets `true` | Auto-queue a JLSF deployment to every newly seized port/airbridge (`GameState._consume_jlsf_orders`); explicit `deploy_jlsf` Red orders work regardless |
| `jlsf_lift_bn_equiv` | `4` | Abstract amphibious-lift cost of one JLSF deployment (`JlsfCargo` pseudo-BNs; attritable in the crossing) |
| `disable_phases` | `[]` (allowlist: `movement`, `ground_combat` — `GameDataStore.DISABLEABLE_PHASES`) | Research bypass (plan 0012): `GameState.resolve_turn` skips the listed ground WeGo phases wholesale (buffered orders never execute; no dice consumed, so `[]` is byte-identical). No canned sweep sets it — they use the `noop` matchup instead — but it's override-reachable for fast what-if runs |
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
(300/150/150); offload only in `OffloadRates.gd`. `CombatCalculator.SUPPORT_MULTIPLIERS` is a code
constant today — data-driven promotion is fine if a scenario variant needs it.
`CombatCalculator.resolve_map_attack`'s `feba_base_km` is a required param (no default) — real
callers always pass the scenario value; there is no fallback to silently diverge to.

## Terrain knobs (Track F)

Full knob catalog (per-class `defender_modifier`/`move_cost`/`impassable`/`color`, per-hex
assignment, region-border rendering, grid-inclusion threshold) and the consumers of each live in
`docs/systems/terrain.md` §2 — that doc is the one home for these values; don't duplicate the
table here.

## Adding a scenario parameter (checklist)

1. Add the key to `data/scenarios/scenario_default.json` with a `_comment` if non-obvious.
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

Measured, never eyeballed: use the sweep harness (`python3 tools/run_sweep.py --spec tools/sweeps/<spec>.json` or `python3 tools/run_sweep.py --name <study> --knob ...`)
— fixed seed grid + multi-seed means, report per-knob deltas. Balance targets and lever analyses
live in docs/plans/ (plan 0001, the crossing-loss calibration, USER-dialed 2026-07-11, re-read as 32.9% on the post-0004 wave and accepted 2026-07-18; deep
record in docs/archive/PLAN.md). Deliberate balance changes are USER calls and re-baseline events.

`data/ijfs/ijfs_scenario.json.intel_locked_antiship_strike_bonus` (float, golden = 0.20, plan 0001)
is a calibration knob living in the IJFS data file, NOT `data/scenarios/scenario_default.json`. The IJFS
scenario file's path is fixed, so this knob isn't reachable from a scenario variant, but it can be
swept using `run_sweep.py --spec tools/sweeps/antiship_crossing.json`. `IjfsLoaders.load_scenario`
synthesizes it into `strike_probability_modifiers` via `apply_intel_locked_strike_bonus`. Paired
companion lever: `prelanding.intel.exquisite_intel.antiship.initial_count` (golden = 36), same file.
`data/antiship/antiship_grouping_spec.json.disable_antiship_systems` (bool, default false, plan
0012) zeroes the crossing interceptors (containers/IJFS targets intact) — the mines-only floor
cell of the antiship sweep sets it via override.

`data/ijfs/ijfs_scenario.json.crbm_maneuver_rounds_override` (int, shipped = 480) and
`.crbm_maneuver_strike_bonus` (float = 0.15, USER-dialed 2026-07-17 via `tools/sweeps/crbm_maneuver.json`,
~38% ROC maneuver-pool attrition; plan 0009) are the coupled CRBM heavy-volley maneuver-attrition knobs.
The rounds override retargets `rounds_expended_per_engagement` on every CRBM×"Maneuver Units"
pairing (depletion only, applied by `IjfsLoaders.apply_crbm_maneuver_rounds_override` from
`IjfsStateBuilder.build`); the strike bonus is the lethality lever, synthesized into
`strike_probability_modifiers` via `apply_crbm_maneuver_strike_bonus`. Both absent/0.0 = golden no-op.
Detail: `docs/systems/ijfs.md` §4 Strike.

## Research knob registry (plan 0018) — the comparability backbone

`data/knobs/registry.json` is the **curated** catalog of outcome-relevant knobs (IJFS warmup →
beach capacity + the plan 0001/0009 calibration levers). It exists so **every game record carries
the full resolved value of every knob** (`record["knobs"]`, stamped by `run_selfplay_game.gd` via
`KnobRegistry.resolve_all`) — that is what lets any two records, from any sweep, sit in one
knob-space and be compared. Adding a knob is a deliberate one-line entry here (not auto-derived).

- **Path grammar:** a `path` is a file prefix + a JsonPath. Prefix `scenario:` resolves against the
  *active* scenario file (variants work); `<data/rel/file.json>:` is literal. The dot-path/array
  grammar after the `:` is **JsonPath's — `scripts/JsonPath.gd` is the canonical spec** (`name[*]` /
  `name[]` = every array element, `name[N]` = one), shared by the record dump (`KnobRegistry._extract`)
  and `DataOverrides` so read and write can't drift. `kind` (`llm_model` / `prompt_hash`) replaces
  `path` for values not in a data file — model id from `HEXCOMBAT_LLM_MODEL`, prompt hash stamped by
  `llm_sidecar.py` into the JSONL log (capture-only; prompt-variant *files* are a follow-up).
- **`sweepable`:** `true` = overridable via `DataOverrides` — **scalars and array knobs alike**
  (array knobs fan out, so `run_sweep.py --knob "data/beaches.json:beaches[*].capacity_battalions"
  --values 2,4,6` scales all nine beaches at once). `false` = dump-only (only the two capture `kind`
  knobs today).
- **Validator:** `tools/validate_knob_registry.gd` (in the gate) proves structure + that every
  path knob resolves against the default scenario — catches typos and the silent-default class.
  A scenario knob absent from the default (code-default applies) resolves null and is allowed.
- **Analysis:** `tools/research_knobs.py {ledger,sensitivity}` over `reports/` — see
  `hexcombat-research-runs`.
