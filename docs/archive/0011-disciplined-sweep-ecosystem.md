---
status: Shipped
shipped: 2026-07-18
landed_in: 
---
# 0011 — Disciplined Sweep Ecosystem

## Goal
One disciplined way to run any parameter sweep: vary knob(s) → measure → report, reaching **any**
data-file knob, at the right runtime granularity, with batch-grade provenance, on both platforms.
Retire the bespoke, stdout-only GDScript sweeps and the Windows-only `run_sweep.ps1`.

## Context & Settled Facts
- **USER calls (2026-07-17):** target **Tier 2** (full unification), land in stop-anywhere
  increments; knob-injection primitive is a **runtime override map** (not variant-file generation,
  not in-process privates). **Parity required** — the retrofitted sweeps must reproduce the current
  scripts' numbers exactly (same seeds) before the old scripts are deleted. Of the bespoke antiship
  diagnostics: **keep the mines-only loss floor** (a real metric — the bound the intel lever can't
  beat); **discard** the subcategory census and the 3-point reference (one-time plan-0001
  archaeology; the reference is a subset of grid cells anyway).
- **What's already disciplined:** `tools/run_batch.py` + `tools/run_sweep.ps1` — one-knob
  *scenario-file* variants → common-seed batch → per-game records + `manifest.json` (commit/seeds/
  re-run cmd) + auto-report. This is the contract to generalize.
- **What's undisciplined:** `tools/sweep_antiship_crossing.gd`, `tools/sweep_crbm_maneuver.gd` —
  in-process, reach `GameState` privates (`_rebuild_ijfs_state` via
  `tools/ijfs_sweep_support.gd:fresh_ijfs_scenario`), hand-roll injection/metric/stats, print
  ephemeral stdout tables with no provenance or re-run path. Their knobs live in
  `data/ijfs/ijfs_scenario.json` (unreachable by `run_sweep.ps1`) and/or they need speed
  (antiship grid = 10×6 cells × 30 seeds of a single phase, not full games).
- **Non-negotiable invariant:** no override present ⇒ **byte-identical to today** (the seam is a
  strict no-op on the empty map). Any golden drift = a bug, never a re-baseline.

## Code anchors (verified 2026-07-17)
- **All JSON reads funnel through exactly three private helpers** — these are the seam:
  - `scripts/GameData.gd:771` `_read_json(path)` — used by `load_hex_grid` (:113), `_load_oob_file`
    (:182), `load_scenario` (:221), `load_terrain` (:320, :354), `load_theaters` (:515),
    `load_beaches` (:554), `load_infrastructure` (:593), `load_offload_weights` (:629),
    `load_ships` (:640).
  - `scripts/ijfs/IjfsLoaders.gd:493` `_read_json(path)` — used by `load_targets`,
    `load_munitions`, `load_pairings`, `load_scenario` (the `data/ijfs/ijfs_scenario.json` knobs),
    `load_air_classes`, `load_oob`, `load_sam_capabilities`.
  - `scripts/AntishipLoaders.gd:176` `_read_json(path)` — used by all antiship loaders incl.
    `load_minefields` (:146) and `load_mine_config` (:168).
- **Selection-precedence model to copy:** `scripts/ScenarioCatalog.gd` — pure statics, user arg
  (`--scenario=`, `ScenarioCatalog.gd:29`) wins over env var (`HEXCOMBAT_SCENARIO`), pure core
  (`select_path`) split from the OS-reading wrapper (`selected_path`) for testability.
- **Batch runner:** `tools/run_batch.py` — builds one `run_selfplay_game.gd` subprocess per
  (scenario, matchup, seed) via `game_command()` (:134), output under `reports/batches/<name>/`
  (`games/*.json` + `manifest.json` + `report.md`), checkpointing via `read_valid_record` (:85),
  report via `tools/make_batch_report.gd`. Guarded by `tools/validate_batch_runner.py` in the gate.
- **Selfplay runner seeding convention:** turn seed = `base_seed + turn_index`
  (`scripts/SelfPlayRunner.gd:99-101`); `tools/run_selfplay_game.gd` uses `play_game_seats(...,
  stop_on_game_over=true)`. The CRBM sweep instead runs a **fixed 40-turn horizon** (no early
  stop, same convention as `validate_golden_victory.gd`) with the same per-turn seeding — so a
  `--run-past-game-over` flag on `run_selfplay_game.gd` closes the convention gap.
- **Gate:** `tools/run_all_tests.sh` auto-discovers `tools/validate_*.gd` by glob (:163) — a new
  validator joins the gate by existing. Gate exports `HEXCOMBAT_SCENARIO=scenario_golden`; new
  validators must pass under that selection.
- **Sweep scripts' current numbers** (the parity targets): antiship grid/floor in
  `sweep_antiship_crossing.gd` (`SEED=20260624`, `SWEEP_N_SEEDS=30`, grid counts×bonuses at
  :178-179); CRBM table in `sweep_crbm_maneuver.gd` (`SEED=20260624`, `N_SEEDS=24`,
  `MAX_TURNS=40`, `BONUSES` at :21). Attrition is measured by **surviving-target count, not
  writeback** (plan-0009 ratified convention) — preserve it.

## Design decisions (settled here — do not relitigate)
- **`scripts/DataOverrides.gd`** — new pure-static `RefCounted` (`class_name DataOverrides`), NOT
  an autoload (architecture contract forbids new autoloads). Modeled on `ScenarioCatalog`.
- **Override key format:** `"<data-file>:<dot.path>"` where `<data-file>` is the path relative to
  `res://` exactly as loaders pass it (e.g. `data/ijfs/ijfs_scenario.json:crbm_maneuver_strike_bonus`,
  `data/scenario_default.json:red_dos_start`). `apply()` normalizes the incoming loader path by
  stripping `res://` before matching. Dot path traverses Dictionary keys only (no array indices —
  same restriction as `run_sweep.ps1`); value replaces whatever is there, as parsed from JSON.
- **Sources & precedence:** `--overrides=<value>` user arg (after `--`) wins over
  `HEXCOMBAT_OVERRIDES` env var; no source ⇒ empty map. `<value>` starting with `{` is inline
  JSON; anything else is a path to a JSON file holding the map. Read once, cached in a
  `static var`. A programmatic `DataOverrides.set_map(map)` entry exists for in-process tools
  (the retrofitted sweeps set per-cell maps without process restarts).
- **Orthogonal to `HEXCOMBAT_SCENARIO`:** scenario selection picks *which* scenario file loads;
  overrides then patch *any* loaded JSON — including the selected scenario file, addressed by its
  own path. A sweep over a scenario key must therefore address the file actually selected.
- **Fail loud (project contract):** a dot path whose file matched but whose key path doesn't exist
  → `push_error` + `assert` (never create missing keys, never silently skip). Overrides that never
  matched any loaded file by process end are a typo — `DataOverrides.unapplied()` returns them and
  `run_selfplay_game.gd` / the sweep runners fail the run if non-empty. (Check must be at process
  end, not after `GameData.load_all()` — IJFS/antiship files load lazily on turn 1.)
- **Structure:** split pure core `apply_map(map, path, parsed)` from OS-reading wrapper (same
  pattern as `select_path` vs `selected_path`) so the validator tests logic without env state.
- **Sweep output home:** `reports/sweeps/<name>/` — `sweep.json` (provenance), `cells/…`
  (per-cell samples/records), `report.md`. Never under `data/` (committed content is authored,
  not generated).
- **RNG:** sweeps consume existing entry points (`resolve_ijfs_turn`, `resolve_antiship_turn`,
  `end_turn` actions) with `SeededDice` exactly as today — no new dice consumers, no reordered
  draws.

## Phases — stop-anywhere increments

### Phase A — Override map + loader seam *(keystone)*
1. Write `scripts/DataOverrides.gd`: static `map()` (lazy: arg → env → file/inline parse, cached),
   `set_map(map)` (programmatic, also resets the applied-tracking), `apply(path, parsed)` (no-op
   fast-path when map empty), pure `apply_map(...)` core, `unapplied() -> Array[String]`.
2. Add one line in each of the three `_read_json` helpers (anchors above): after successful parse,
   `return DataOverrides.apply(path, parsed)`.
3. New `tools/validate_data_overrides.gd` (auto-joins gate): asserts (a) empty map ⇒ `apply`
   returns the identical structure (no-op guard); (b) an override on a nested dot path lands in the
   parsed dict; (c) file-address normalization (`res://data/x.json` matches `data/x.json` key);
   (d) unapplied tracking reports unmatched keys. Print `PASS:` line, `quit(0)`.
4. Wire `--overrides` parsing into `tools/run_selfplay_game.gd` (manual arg loop, same style as its
   existing args) + fail-loud `unapplied()` check before writing the record; record the applied map
   in the game record JSON (`"overrides": {...}`, `{}` when none — a new key, additive, no fixture
   churn expected but verify Phase 5 fixture drift stays clean).
5. Gate: `bash tools/run_all_tests.sh` → ALL PHASES GREEN. The golden phases ARE the empty-map
   byte-identity proof.
   Commit. **Stopping point: any knob in any data file is injectable per-process.**

### Phase B — Sweep record contract + retrofit both sweeps *(parity gate lives here)*
1. Define the sweep record: `reports/sweeps/<name>/sweep.json` = `{sweep_name, created_utc,
   commit, dirty, base_scenario, knobs: [override addresses], grid: [[values...]], seeds,
   runtime_mode: "in_process"|"full_game", rerun_command, metrics: [names]}`;
   `cells/<cell-id>.json` = `{overrides: {...}, samples: [{seed, <raw measurement fields>}...]}`.
   Cell id = slugged `knob=value` pairs joined by `__` (filename-safe, mirrors `run_sweep.ps1`'s
   `<knob>_<value>` naming).
2. Retrofit `sweep_antiship_crossing.gd` and `sweep_crbm_maneuver.gd`:
   - Injection: replace the scenario-dict mutation + manual synthesizer re-runs with
     `DataOverrides.set_map({...})` per cell **before** `IjfsSweepSupport.fresh_ijfs_scenario` /
     reset (the rebuild re-reads `ijfs_scenario.json`, so the load-time seam applies the knob and
     the normal loader path runs every synthesizer — no more `apply_intel_locked_strike_bonus` /
     `apply_crbm_maneuver_strike_bonus` calls in the sweeps).
   - Output: per-cell raw samples to `reports/sweeps/<name>/cells/`, `sweep.json`, and keep a
     brief stdout table (mean±sd) as a courtesy echo.
   - Antiship: drop `_baseline_diagnostic`'s subcategory census and `_multiseed_reference`
     (USER call); keep the **mines-only floor** as a dedicated cell (`overrides: none`,
     `mines_only: true` in the cell record — it stays the writeback-kill special case for now).
3. **Parity protocol (USER: required):** capture each script's current stdout table on this
   commit BEFORE retrofitting (run once, save under `reports/sweeps/_parity/`); after retrofit,
   re-run and diff mean±sd per cell — must match **exactly** (same seeds, deterministic engine).
   Any mismatch = injection semantics bug; fix it, never accept drift. Record the parity proof
   path in the commit message.
4. Gate green (sweeps stay out of the gate; the gate proves no engine drift). Commit.
   **Stopping point: existing sweeps are reproducible artifacts.**

### Phase C — Metric registry (python, over records)
1. `tools/sweep_metrics.py`: registry `{name: fn(samples|game_records) -> value(s)}` with
   `crossing_loss_pct` (bns_lost_at_sea / wave_bns), `maneuver_attrition_pct` (survivor-based),
   `warmup_killed`, `terminal_census`, `red_win_rate`, plus shared mean/sd. Metrics compute in
   python from emitted records — GDScript emits raw fields only.
2. `tools/make_sweep_report.py`: reads `sweep.json` + cells, computes the declared metrics,
   renders `report.md` (grid table, mean±sd per cell, provenance header with re-run command —
   mirrors `make_batch_report`'s shape).
3. Point the two retrofitted sweeps' stdout echo + `report.md` at this path (delete their
   in-GDScript stats once report.md reproduces the parity numbers; `IjfsSweepSupport.mean/stdev`
   die here if nothing else uses them). Commit.

### Phase D — `tools/run_sweep.py` orchestrator (cross-platform; retires `run_sweep.ps1`)
1. CLI: `--name`, `--knob <file:dot.path>` (repeatable → grid axes), `--values` (per knob,
   comma-separated; numeric strings become numbers, same coercion rules as the ps1), `--scenario`,
   `--n/--seeds/--base-seed`, `--turns`, `--parallel`, `--metrics`, `--godot`,
   `--run-past-game-over`.
2. Per cell: write `cells/<cell-id>/overrides.json`, invoke `run_batch.py` for that cell.
   `run_batch.py` gains `--overrides <path>` (threaded into `game_command` as
   `--overrides=<path>`) and `--out-root` (default `reports/batches`) so sweep cells land under
   `reports/sweeps/<name>/cells/<cell-id>/`. Manifest gains the overrides map. Keep
   `tools/validate_batch_runner.py` green (it gates run_batch's contract).
3. Add `--run-past-game-over` to `run_selfplay_game.gd` → `play_game_seats(...,
   stop_on_game_over=false)` for fixed-horizon sweeps.
4. Write `sweep.json` + run `make_sweep_report.py` at the end.
5. **Equivalence check (plan risk #2):** one scenario knob (e.g.
   `data/scenario_default.json:red_dos_start`), 3 seeds — records via `--overrides` must match
   records via a hand-made variant scenario file on every outcome field (identity fields like
   scenario name/id may differ; compare census/turns/winner/violations). This proves override-map
   injection ≡ the old variant-file path.
6. Delete `tools/run_sweep.ps1`. Gate green. Commit.
   **Stopping point: any scenario-or-data knob sweeps cross-platform with full provenance.**

### Phase E — Single-phase backend + delete bespoke scripts
1. Generic `tools/run_sweep_cells.gd` (SceneTree, `-s`): takes `--spec=<json>` = cells (override
   map each), seeds, measurement id, out dir. Measurements are named extractors registered in the
   script: `antiship_crossing` (reset → warmup → crossing → emit wave_bns/bns_lost_at_sea/
   mine_status hulls; plus the mines-only-floor special cell) and `crbm_full_game` (fixed-horizon
   empty-orders game → pool/killed/warmup_killed/taiwan, survivor-based). This replaces the two
   sweep scripts' bodies; `run_sweep.py --backend in-process` drives it (one Godot process runs
   all cells; `DataOverrides.set_map` per cell).
2. Re-run both canned sweeps through the orchestrator; **numbers must still match the Phase-B
   parity tables.** Then delete `sweep_antiship_crossing.gd`, `sweep_crbm_maneuver.gd`, and fold
   or delete `ijfs_sweep_support.gd` (whatever `run_sweep_cells.gd` still needs of the injection
   kernel moves into it; the `GameState._rebuild_ijfs_state` private reach is confined to this one
   tool file).
3. Check in the two canned sweep specs under `tools/sweeps/*.json` (antiship_crossing.json,
   crbm_maneuver.json) — a future re-calibration is `python tools/run_sweep.py --spec
   tools/sweeps/crbm_maneuver.json`.
4. Update skills: `hexcombat-research-runs` (the one sweep workflow, both backends, record
   contract), `hexcombat-config-and-knobs` (knob addressing = override-map key format). Gate
   green. Commit.

### Phase F — (optional, deferred) machine-readable knob registry
Knob manifest (address, default, type, range, doc link) promoting `hexcombat-config-and-knobs`
prose; sweeps reference knobs by name, validation centralizes. **Do not build until a concrete
need** (USER call: deferred).

## Risks & Validation
- **Loader seam is cross-cutting** — strict no-op on empty map; the untouched golden gate is the
  byte-identity proof, `validate_data_overrides.gd` the unit proof. Golden drift = bug, never
  re-baseline.
- **Parity is the deletion gate** — old scripts die only after the disciplined path reproduces
  their numbers exactly (Phase B capture → Phase E re-check).
- **Override ≡ variant-file equivalence** — Phase D step 5 cross-check.
- **Typo'd knob addresses** — `unapplied()` fail-loud check at process end (lazy loads forbid an
  earlier check).
- Sweeps stay **out of the gate** (on-demand research tools); `validate_data_overrides.gd` and
  `validate_batch_runner.py` are the gate-side guards.

## Checklist
- [x] Phase A — DataOverrides + 3-helper seam + validator + run_selfplay_game wiring; gate green.
- [x] Phase B — record schema + parity capture + retrofit both sweeps (mines-only floor kept,
  census/reference dropped); parity exact; gate green.
- [x] Phase C — sweep_metrics.py + make_sweep_report.py; sweeps' stats move to python.
- [x] Phase D — `run_sweep.py` + `run_batch.py --overrides/--out-root` + `--run-past-game-over`;
  equivalence check; delete `run_sweep.ps1`; gate green.
- [x] Phase E — `run_sweep_cells.gd` backend + canned specs; parity re-check; delete both bespoke
  sweeps + shrink/absorb `ijfs_sweep_support.gd`; update the two skills; gate green.
- [x] Phase F — deferred (no action).
- [x] Closeout: facts to `hexcombat-research-runs` / `hexcombat-config-and-knobs` / STATUS /
  DECISIONS; archive this plan.

## Post-closeout review (2026-07-18)

The Phase B/E antiship "parity exact" was vacuous: both old and migrated harnesses read 0.0
losses in every cell because neither called `resolve_sealift_turn` — mandatory since plan 0004
for the crossing to have a sent wave at all. The antiship leg also never actually ran through the
new `--spec` pipeline (its manifest still pointed at the deleted GDScript), and the report
generator's filename-slug matching could not have rendered a spec-pipeline run. All fixed in the
same-day review pass — see DECISIONS 2026-07-18 (review fixes) for the itemized list. Lesson for
parity protocols: a parity criterion must be a KNOWN-NONZERO reference table; 0≡0 proves nothing.
