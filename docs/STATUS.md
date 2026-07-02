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
  retreat, hex ownership. Golden invariant: seed 20260624 → `casualties=3, feba=-0.96` (byte-stable gate; re-baselined twice —
when the hex-adjacency coordinate bug was fixed, and when `feba_base_km` was set to TIV's 3.5 — see
`PLAN.md` → Decisions).
- **D1 Amphibious offload** — ship reserve → beach landing; lands brigades onto beach hexes.
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
  block.
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

**Verification.** `pwsh tools/run_all_tests.ps1` is the canonical gate: import → headless smoke →
`tools/validate_*.gd` (golden turn, anti-ship, IJFS, victory e2e, data validators, no-global-RNG) →
GdUnit4 suites under `tests/`. Must end **ALL PHASES GREEN**. A debug-only assert
(`OS.is_debug_build()`-gated) at the end of `resolve_turn` checks `GameData.validate_runtime_indexes()`,
so any silent brigade↔hex index desync fails loud in every debug/test/headless turn (compiled out of
release).

## What is NOT done (see `docs/plans/`)

- **Graphics** (Track 5): anti-ship/mine visualization, front-line draw UI (D5-D), unit/HUD polish,
  map/terrain polish. Needs visual verification (not headless-gateable).
- **Terrain / land classification** — the hex grid is geometry-only; a later ArcGIS-sourced phase.
  (Blocks the precise "main-island land hex" victory census; `taiwan_hexes` config is the hook.)
- **Deferred ports** — anti-ship missile pipeline depth (strike-coverage lever), ground-casualty
  IJFS↔OOB linkage, per-hull escort magazines. See `docs/plans/port_audit.md`.
- **Refactors** — see `docs/plans/refactor_audit.md` (e.g. victory census should count *present*, not
  OOB, battalions; typed `WarmupContext`/`HexState`).
