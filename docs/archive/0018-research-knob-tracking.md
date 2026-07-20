---
title: "0018: Research knob tracking — consolidate knobs so all sweeps are comparable"
status: "Shipped 2026-07-20"
created: "2026-07-19"
fleshed: "2026-07-20"
---

# 0018 — Research knob tracking

## The problem (verified 2026-07-20)

Knobs are any `data/*.json` value, addressable as `file:dot.path` and overridable at runtime via
`DataOverrides` (`--overrides=`). `tools/run_sweep.py` varies them per cell. **But each game record
only stores the overrides that were *applied* (`record["overrides"]`) — not the full resolved knob
vector.** So two sweeps that varied different knobs cannot be placed in a common space: you can't
tell what the *un-varied* knobs were set to in either. That is the root of "sweeps not cleanly
comparable." Two further gaps: (a) there is no canonical catalog of "every knob that exists," and
(b) the LLM **system prompt is hardcoded inside `tools/llm_sidecar.py`** and the model id lives only
in an env var — a prompt/model change silently moves outcomes with nothing in the record.

## Decisions (USER, 2026-07-20)

- **Knob universe = curated registry** (not auto-dump-everything). Hand-maintained list of
  outcome-relevant knobs; adding one is a deliberate one-line entry. (Auto-dumping every scalar
  would bury OOB/hex/ship tables as noise.) USER asked to review the proposed v1 list (below).
- **Prompts = capture-only now.** Record model id + a hash of the current sidecar prompt so runs
  are comparable; externalizing prompts into swappable variant files is a follow-up.
- **Build everything in one pass:** registry + per-record resolved dump + prompt/model capture +
  ledger + sensitivity ranking. (Sensitivity is validated against a real small sweep run during
  this plan, not only synthetic records.)

## Architecture

### 1. Knob registry — `data/knobs/registry.json`

The canonical universe. One entry per knob:

```json
{ "id": "feba_base_km", "path": "scenario:feba_base_km",
  "label": "Ground FEBA base shift (km)", "group": "ground", "sweepable": true }
```

- `path` grammar: `scenario:<dot.path>` resolves against the **active** scenario file
  (`GameData.scenario_path`, so variants work); `<data/rel/file.json>:<dot.path>` is a literal file.
- `sweepable`: `true` = scalar single-path, overridable today via `DataOverrides`. `false` =
  dump-only (e.g. array-valued `beaches[].capacity_battalions` — the current override scheme
  traverses dicts only, so array knobs are recorded but not yet swept; see Follow-ups).
- LLM knobs carry `"kind": "llm_model" | "prompt_hash"` instead of a `path` (resolved from
  env / sidecar, not a data file).
- A validator proves every non-LLM path resolves in the default data (catches typos and the
  silent-default bug class).

### 2. Per-record resolved dump — `GameData.dump_tunables()`

Runs in-process (GameData loaded, `DataOverrides` active). For each registry entry: re-read the
resolved file (scenario sentinel → `scenario_path`), apply `DataOverrides`, extract the dot.path
(null for a dump-only array or missing key → recorded as-is). LLM entries pulled from env / the
sidecar log. Embedded as `record["knobs"]` + `record["knobs_registry_version"]` by
`tools/run_selfplay_game.gd::_build_record`. Additive — no existing field changes.

### 3. Prompt / model capture (capture-only)

- Model: `record["knobs"]["llm_model"]` = `HEXCOMBAT_LLM_MODEL` (empty for non-LLM games).
- Prompt: `tools/llm_sidecar.py` computes a stable hash of its system-prompt text and writes
  `prompt_hash` into each JSONL log entry (alongside the `model` it already logs);
  `run_selfplay_game.gd` reads the last log line into `record["knobs"]["llm_prompt_hash"]` when a
  seat is LLM. Non-LLM games record empty strings.

### 4. Ledger — `tools/make_research_ledger.py`

Scans record JSONs under `reports/` (batches + sweeps), reads each `record["knobs"]`, and renders
`reports/research_ledger.md`: one row per distinct knob-vector, columns = knob ids, plus game
count, source sweeps, and an outcome summary (red/green/undecided rates, mean census margin). This
is the "what parameter space have we explored" view.

### 5. Sensitivity ranking — `tools/knob_sensitivity.py`

Given a record set, for each knob that **varies** across it: rank by effect size on a chosen
outcome metric (default `red_win_rate`; also `census_margin`). v1 method: group records by the
knob's value, report the spread (range of the per-value mean) and rank knobs by that spread.
Cleanest within one sweep (grids vary one knob at a time); cross-sweep only ranks knobs that vary,
with an explicit confounding caveat when several co-vary. Output: ranked Markdown table. Validated
against a real short sweep (noop matchup, 1 turn, a 2-value grid) generated during this plan.

## Proposed v1 registry (USER review — pruning is a one-line data edit)

| id | path | default | group | sweepable |
|---|---|---|---|---|
| `red_dos_start` | `scenario:red_dos_start` | 100 | supply | ✓ |
| `feba_base_km` | `scenario:feba_base_km` | 3.5 | ground | ✓ |
| `red_out_of_supply_effectiveness` | `scenario:red_out_of_supply_effectiveness` | 0.5 | supply | ✓ |
| `stacking_soft_cap` | `scenario:stacking_soft_cap` | 6 | ground | ✓ |
| `amphibious_return_time_turns` | `scenario:amphibious_return_time_turns` | 3 | sealift | ✓ |
| `escort_reload_time_turns` | `scenario:escort_reload_time_turns` | 0 | antiship | ✓ |
| `victory_loss_check_arm` | `scenario:victory.loss_check_arm` | after_first_landing | victory | ✓ |
| `ijfs_warmup_days` | `data/ijfs/ijfs_scenario.json:prelanding.days` | 3 | ijfs | ✓ |
| `intel_locked_antiship_strike_bonus` | `data/ijfs/ijfs_scenario.json:intel_locked_antiship_strike_bonus` | 0.2 | ijfs | ✓ |
| `exquisite_antiship_initial_count` | `data/ijfs/ijfs_scenario.json:prelanding.intel.exquisite_intel.antiship.initial_count` | 36 | ijfs | ✓ |
| `crbm_maneuver_strike_bonus` | `data/ijfs/ijfs_scenario.json:crbm_maneuver_strike_bonus` | 0.15 | ijfs | ✓ |
| `missile_group_size` | `data/antiship/antiship_crossing_config.json:missile_group_size` | 4 | antiship | ✓ |
| `screen_target_preference` | `data/antiship/antiship_crossing_config.json:screen_target_preference` | 3.0 | antiship | ✓ |
| `terminal_defense_base_prob` | `data/antiship/antiship_crossing_config.json:terminal_defense.base_probability` | 0.45 | antiship | ✓ |
| `damaged_hull_neut_multiplier` | `data/antiship/antiship_crossing_config.json:damaged_hull_neut_multiplier` | 1.5 | antiship | ✓ |
| `available_minesweepers` | `data/antiship/minefields.json:available_minesweepers` | 6 | mine | ✓ |
| `mine_danger_radius` | `data/antiship/minefields.json:geometry.danger_radius` | 50 | mine | ✓ |
| `prelanding_clear_per_sweeper` | `data/antiship/minefields.json:transit.prelanding_clear_per_sweeper` | 1 | mine | ✓ |
| `offload_beach_base_rate` | `data/offload_rates.json:rates.beach_base` | 4400 | offload | ✓ |
| `offload_operational_port_rate` | `data/offload_rates.json:rates.operational_port` | 11000 | offload | ✓ |
| `beach_capacities` | `data/beaches.json:beaches[].capacity_battalions` | [2,4,…] | offload | ✗ (dump-only) |
| `llm_model` | *(env)* | "" | llm | ✗ (capture) |
| `llm_prompt_hash` | *(sidecar)* | "" | llm | ✗ (capture) |

Rationale for the cut: these are the levers the resolvers actually branch on for outcomes (crossing
lethality, IJFS warmup slaughter, supply, offload throughput, mine attrition) plus the two prior
calibration knobs (plans 0001/0009). Excluded deliberately: OOB tables, hex geometry, per-ship
stats, NATO symbol maps — content, not outcome knobs.

## Objectives / steps (each its own commit, gated)

1. Registry file + `data/knobs/` + a resolve-check validator; wire validator into the gate.
2. `GameData.dump_tunables()` + unit test (resolves defaults; an override shows through).
3. Embed `record["knobs"]` in `_build_record`; re-baseline only research fixtures if their shape
   legitimately changed (records are not golden-pinned; confirm no fixture asserts the full dict).
4. Prompt/model capture: sidecar `prompt_hash` in the log; record reads model + hash.
5. `tools/make_research_ledger.py` + unit test on synthetic records.
6. `tools/knob_sensitivity.py` + unit test + a real short validation sweep.
7. Docs: `hexcombat-config-and-knobs` (registry + dump), `hexcombat-research-runs` (ledger +
   sensitivity workflow), DECISIONS entry, STATUS capability line, backlog check-off, archive.

## Verification

- `bash tools/run_all_tests.sh` ALL PHASES GREEN — golden byte-stable (the `knobs` field is
  additive to research records; it must not perturb any golden/certified fixture).
- Registry validator green (every non-LLM path resolves).
- `dump_tunables` test: override one knob, confirm the dumped value changes and un-varied knobs
  hold defaults.
- Ledger + sensitivity produce a correct table over a real short sweep.

## Follow-ups (out of scope here)

- **Array-knob sweeping** (`beaches[].capacity_battalions`, per-ship stats): extend `DataOverrides`
  to address array elements / apply a scalar multiplier, then flip those registry entries to
  `sweepable`. Needed to sweep "beach capacity," which USER named as a target knob.
- **Prompt variant files**: externalize the sidecar system prompt into named `--prompt-variant`
  files and make `llm_prompt` a swept knob (this plan only records its hash).
