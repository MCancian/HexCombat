# HexCombat — Current State

**The single orientation doc.** Read this first to know what works today and where it lives. Present
tense, no dates (dates live only in the append-only history logs). For *future* work see
`docs/plans/BACKLOG.md`; for *why* a choice was made see `PLAN.md` → Decisions; for *lessons* see
`docs/RETROSPECTIVES.md`.

## How the docs are organized (and the tracking rules)

| Doc | Holds | Tense / dates |
|---|---|---|
| **`docs/STATUS.md`** (this) | What is implemented today + where | present tense, **no dates** |
| **`docs/plans/`** | Forward work: `BACKLOG.md` (tracks), `port_audit.md`, `refactor_audit.md` | future intent |
| **`PLAN.md` → Decisions** | Append-only log of *why* (one dated entry per choice) | history — dates OK |
| **`docs/RETROSPECTIVES.md`** | Append-only per-task lessons + triage | history — dates OK |
| **`ROADMAP.md`** | Milestone map + TIV oracle file/line refs | reference |
| **`AGENTS.md` / `CLAUDE.md`** | Rules for agents (incl. the mission) / primary-agent workflow | reference |
| **`.claude/skills/`** | Procedure library — task→skill map in its `README.md` | reference |

**Tracking rules for agents:**
1. When you **finish** a feature, update **this file** (present tense, no date) and check the item off
   in `docs/plans/BACKLOG.md`. Record the *why* in `PLAN.md` → Decisions (dated) and *lessons* in
   `RETROSPECTIVES.md` (dated).
2. When you **plan** new work, add it to `docs/plans/` — never to STATUS.md.
3. **Don't date implemented-state text.** Once something works, describe the behavior, not when it
   landed. Dates belong only in the two append-only logs above.
4. One source of truth for "what works": this file. If another doc disagrees, this file wins (and fix
   the other doc).

## What works today

**Engine.** Godot 4 / GDScript. WeGo turn model in `GameState` (autoload): plan orders →
`resolve_turn(dice)` → `begin_next_turn`. Deterministic via an injectable `Dice` (seeded; no global
RNG — enforced by a validator). `GameData` (autoload) loads hexes, both OOBs (PLA + ROC brigades),
ships, theaters, beaches. `EventBus` for signals. **Every phase's logic lives in a pure
`RefCounted` class under `scripts/resolvers/`** (5 builders + `SupplyResolver`,
`FrontlineResolver`, `CleanupResolver`, `OffloadResolver`, `AntishipResolver`, `IjfsResolver`,
`CombatResolver`); `GameState` is the thin orchestrator — its methods are delegating wrappers
owning EventBus emits, autoload access, cross-phase field assignment, and state application
(combat casualty/FEBA/retreat application stays there deliberately: per-hex application
interleaves with the next hex's contributor gathering). New phases follow
`.claude/skills/hexcombat-add-phase-resolver`.

**Turn resolution order** (`resolve_turn`): IJFS air/missile fires → anti-ship crossing → amphibious
offload → movement & commit → ground combat → front-line → cleanup (+ victory census).

**Phases / subsystems implemented:**
- **Ground combat** (BOOTS slice M0–M7): movement, commit, combat resolution, FEBA, casualties,
  retreat, hex ownership. Defender terrain modifier (Track F) is active: `CombatResolver.resolve_at`
  now receives the defended hex's `GameData.get_terrain(hex_id).defender_modifier` from
  `GameState._defender_combat_modifier` instead of a hardcoded 1.0. Golden invariant: seed
  20260624 → `casualties=6, feba=-3.04` (byte-stable gate; re-baselined three times — when the
  hex-adjacency coordinate bug was fixed, when `feba_base_km` was set to TIV's 3.5, and 2026-07-09
  when the terrain modifier was activated — see `PLAN.md` → Decisions).
- **D1 Amphibious offload** — ship reserve → beach landing; lands brigades onto beach hexes.
  Every scenario's `red_ship_reserve.beach_hex` must be coastal (< 6 land neighbors) —
  `validate_scenario_data.gd` rejects fully-inland landing hexes.
- **D2 Red DOS supply** — supply pool / effectiveness tracking. An exhausted Red pool now degrades Red
  ground-combat strength (`red_out_of_supply_effectiveness`, default 0.5) via
  `GameState._inject_supply_effectiveness`.
- **D3 Anti-ship & mine warfare** — IJFS-fed firing plan → crossing damage (count-based) → **geometric
  mine model** (randomized approach path, dangerous-mine count within `danger_radius`, decoy-sponge
  transit; knobs in `data/antiship/minefields.json`). Ship losses → BNs lost at sea.
- **D4 IJFS** (joint/air-missile fires) — detection → targeting → strike → suppression, with a
  multi-day pre-invasion warmup (exquisite intel) on the first turn. Per-(TO,type) writeback feeds D3.
  **IJFS now also attrits ground forces:** Green/ROC maneuver battalions are IJFS targets
  (`build_maneuver_targets`); destroyed ones are removed from the OOB before ground combat
  (`_apply_ijfs_maneuver_casualties`) — the D4-H ground-casualty linkage. Detectability is biased by
  unit type (mobility/hardness via the `MANEUVER_TYPE_MAP` profile) and by recent activity: a brigade
  that moved or fought last turn presents an `"active"` posture (`_update_maneuver_posture`), making its
  maneuver units easier to detect. Each turn `_sync_maneuver_targets_to_oob` retires maneuver targets
  whose battalions have died (IJFS or ground combat), so the air/missile campaign stops targeting units
  that no longer exist — without disturbing detection continuity for survivors.
- **D5 Front-line / cleanup** — `FrontLineService` (polyline → hex redistribution), cleanup phase.
- **Victory conditions** — end-of-cleanup census of PLA vs ROC battalions *present* on Taiwan (landed
  only: a brigade's battalions still at sea in `ship_reserve` are excluded even after its first BN
  lands); `game_over` / `winner` on `GameState`/`TurnResult`/LLM observation. Config: scenario `victory`
  block. `victory.taiwan_hexes` as an array restricts the census to those hexes (used by
  `roc_full_defense` to exclude the offshore Green/Orchid Island hexes; the 451-hex main-island
  list is generated by `tools/gen_main_island_hexes.py` and guarded by
  `tools/validate_victory_hexes.gd`); `null` counts every placed hex (the golden default).
- **AI-readiness (Track E)** — `GameState.play_turn(red, green, dice) -> TurnResult`, per-turn event
  log, `LLMGameAPI` observation/action contract (JSON-schema-gated), headless self-play harness.
- **Scenario selection (research harness B1)** — any headless process picks its scenario via the
  `--scenario=<id-or-path>` user arg or `HEXCOMBAT_SCENARIO` env var (`ScenarioCatalog`; arg wins,
  no selection = `data/scenario_default.json` so all pins hold). Variant files live in
  `data/scenarios/` (id = filename stem, enumerated by `ScenarioCatalog.list_scenario_paths()`);
  the selection survives `GameState.reset_to_scenario()`; `validate_scenario_data.gd` checks every
  scenario generically + the default's pinned shape.
- **Batch runner (research harness B2)** — `pwsh -File tools/run_batch.ps1 -Name <study>` plays a
  scenario × policy × common-seed matrix, one headless Godot process per game, up to `-Parallel`
  at a time. Each game (`tools/run_selfplay_game.gd`) writes a timestamp-free, byte-reproducible
  JSON record (commit, scenario/policy identity, seed, terminal state + census, turn digests) to
  `reports/batches/<study>/games/`; verdicts are artifact-based; re-running the batch command
  resumes (existing valid records skipped); `manifest.json` stamps commit + per-game re-run
  command lines. Policies are named in `PolicyCatalog` (`selfplay_default` today; unknown ids
  fail loud).
- **Outcome reports (research harness B3)** — `tools/make_batch_report.gd -- --batch=<study>`
  aggregates a batch's records into `report.md`: per-condition (scenario × policy) win rates,
  turn/census/margin distributions, per-game loss means, a methods line (commit, mixed-commit
  and dirty-tree warnings), and standing caveats. Aggregation/rendering is pure `BatchReport`
  statics (GdUnit-tested).
- **Narrative renderer (research harness B4)** — `tools/make_game_narrative.gd`
  (`--record=<file>` or `--batch=<study> --pick=median|longest|shortest`) renders a game
  record's event log into a turn-by-turn Markdown account (IJFS strikes + air-defense
  degradation, the crossing, maneuver/commitments, per-hex ground combat with FEBA movement,
  end-of-turn census, outcome). Pure `GameNarrative` statics (GdUnit-tested).
- **Knob sweeps (research harness B5)** — `pwsh -File tools/run_sweep.ps1 -Name <study>
  -Knob <dot.path> -Values a,b,c` generates one-knob scenario variants (as generated artifacts
  in the sweep's report dir), batches them over a common seed set, and reports per-value
  outcome rows. Array params to the ps1 tools may be comma-joined strings (normalized inside —
  `pwsh -File` does not split them).
- **LLM players (research harness B6)** — policy id `llm_local` (`LLMPolicy`) marshals a seat's
  perspective observation to an out-of-process Python sidecar (`tools/llm_sidecar.py`) that calls a
  local OpenAI-compatible model (`HEXCOMBAT_LLM_BASE_URL`/`_MODEL`/`_API_KEY`, default vLLM at
  `localhost:8088/v1`), validates the returned actions against the legal sets, and appends every
  observation/action pair to a JSONL replay log. `SelfPlayRunner.play_game_seats` runs two
  independent seats to a simultaneous WeGo resolve; `godot --headless --path . -s
  res://tools/run_llm_game.gd -- --seed=S [--scenario=X] [--turns=N] [--model=M]
  [--out=f.json] [--log=f.jsonl]` plays one full LLM-vs-LLM game and writes a record + replay log.
  `HEXCOMBAT_LLM_SIDECAR` overrides the sidecar (e.g. `tools/llm_sidecar_stub.py`, the network-free
  stub used by the gate). LLM decisions are NOT seed-reproducible; the JSONL log is the replay
  artifact. Use IPv4 (`127.0.0.1`, default) not `localhost`; reasoning models need
  `HEXCOMBAT_LLM_MAX_TOKENS` headroom (default 8192) or the budget is spent on reasoning before any
  action. Live-verified against local vLLM (model `jarvis`). (The B2 batch runner is still
  single-policy — LLM seats run via `run_llm_game.gd`, not yet inside multi-condition batches.)
- **`roc_full_defense` scenario** — variant placing all 32 ROC brigades (124 battalions) at their
  real garrison hexes vs the default's 4 PLA amphibious brigades; select with
  `--scenario=roc_full_defense`. Gives AI-vs-AI games a multi-turn fight instead of the default
  4-defender beachhead's turn-1 census decision. Its victory census is restricted to the 451-hex
  main island (see Victory conditions above).
- **Terrain model (Track F)** — every hex in the 466-hex grid (`data/taiwan_hex_grid.json`,
  reconciled against the real GSHHG coastline) carries one of 5 terrain classes
  (`data/terrain/terrain_types.json` + `data/terrain/hex_terrain.json`, loaded by
  `GameData.load_terrain()`): plains, hills, urban, mountain, metropolis (≥50% built-up cover, 9
  metro-core hexes). Movement consumes per-class entry cost via weighted Dijkstra
  (`GameData._terrain_entry_cost`, `HexMath.find_path`/`find_reachable`: hills/metropolis cost 2,
  plains/urban/mountain cost 1) with a min-one-step guarantee (a unit that hasn't moved may always
  take one step into an adjacent passable hex); mountains are impassable
  (`GameData._with_impassable`). Ground combat's defender gets a per-class strength modifier
  (`GameState._defender_combat_modifier` → `CombatResolver.resolve_at`): plains ×1.0, hills ×1.5,
  urban ×2.0, mountain ×2.0, metropolis ×3.0 — golden re-baselined to seed 20260624
  `casualties=6, feba=-3.04`. Terrain is surfaced per-hex in the LLM `occupied_hexes` observation
  and tints the map view fill (`HexMap.get_hex_color`, ownership lerped over the terrain tint at
  weight 0.35, terrain-dominant — USER call after screenshot comparison), with numbered beach
  glyphs. Full detail: `docs/systems/terrain.md`.
- **Brigade marker rendering (`HexMap`)** — brigades are grouped per hex: same-hex stacks render
  as a 0.62× ring with a ×N count badge at 3+; a lone brigade shrinks to 0.75× and pins to the
  hex center when any neighbor hex is occupied (full-size markers are wider than the hex spacing
  and would overlap); an isolated brigade renders full-size with its entry-bearing offset.
  Visual-only — headless gates don't cover it; verify by screenshot.

**Verification.** The canonical gate — `bash tools/run_all_tests.sh` (Linux; resolves Godot via
`$GODOT_BIN` else `godot` on PATH) or `pwsh tools/run_all_tests.ps1` (Windows) — runs: import → headless smoke →
`tools/validate_*.gd` (golden turn, anti-ship, IJFS, victory e2e, data validators, no-global-RNG) →
GdUnit4 suites under `tests/`. Must end **ALL PHASES GREEN**. A debug-only assert
(`OS.is_debug_build()`-gated) at the end of `resolve_turn` checks `GameData.validate_runtime_indexes()`,
so any silent brigade↔hex index desync fails loud in every debug/test/headless turn (compiled out of
release).

## What is NOT done (see `docs/plans/`)

- **Graphics** (Track 5): anti-ship/mine visualization, front-line draw UI (D5-D), unit/HUD polish.
  Needs visual verification (not headless-gateable).
- **Beach first-landing ×2 defender penalty** — deferred design call (2026-07-09); the seam is
  `GameState._defender_combat_modifier`'s `* 1.0` situational-modifier slot. See
  `docs/plans/BACKLOG.md`.
- **Deferred ports** — anti-ship missile pipeline depth (strike-coverage lever), ground-casualty
  IJFS↔OOB linkage, per-hull escort magazines. See `docs/plans/port_audit.md`.
- **Refactors** — see `docs/plans/refactor_audit.md` (e.g. victory census should count *present*, not
  OOB, battalions; typed `WarmupContext`/`HexState`).
