# HexCombat — Current State

**What works today, present tense, no dates.** This is the only home for current behavior: if
another doc disagrees, this file wins (fix the other doc). The full one-home-per-fact map and
task-shaped reading lists live in `AGENTS.md` → Orientation; recording rules in
`hexcombat-docs-and-writing`. Forward work: `docs/plans/`. Why/history: `docs/DECISIONS.md` →
`docs/archive/`. Lessons: `docs/RETROSPECTIVES.md`.

## What works today

**Engine.** Godot 4 / GDScript. WeGo turn model in `GameState` (autoload): plan orders →
`resolve_turn(dice)` → `begin_next_turn`. Deterministic via an injectable `Dice` (seeded; no global
RNG — enforced by a validator). RNG is **hierarchical** (`Dice.derive(salt)`): the root turn seed
spawns independent substreams per phase and per contested hex (`ijfs:<turn>:<day>`,
`antiship:<turn>`, `combat:<turn>:<hex_id>`), so a roll-count change in one phase or hex never
scrambles another's dice (`ScriptedDice.derive` returns self, so scripted fixtures are unaffected). `GameData` (autoload) loads hexes, both OOBs (PLA + ROC brigades),
ships, theaters, beaches. `EventBus` for signals. **Every phase's logic lives in a pure
`RefCounted` class under `scripts/resolvers/`** (5 builders + `SupplyResolver`,
`FrontlineResolver`, `CleanupResolver`, `OffloadResolver`, `AntishipResolver`, `IjfsResolver`,
`CombatResolver`). Turn orchestration is **`TurnConductor`** (also `RefCounted`, all `static`):
its methods take a `GameStateData` value object as their first argument, own the EventBus emits,
cross-phase field assignment, and combat casualty/FEBA/retreat application (which stays in the
conductor deliberately: per-hex application interleaves with the next hex's contributor
gathering). Runtime state itself is the plain **`GameStateData`** value object
(`scripts/model/`); **`GameState` (autoload) is a thin state-holder** — it owns one
`GameStateData` and exposes delegating wrappers to `TurnConductor` (turns), `OrderValidator`
(order validation), and `GameStateBuilder` (scenario construction), plus typed forwarding
properties for the fields external callers read (plan 0014 / decomposition campaign). New phases
follow `.claude/skills/hexcombat-add-phase-resolver`. Order validation (`add_move_order` /
`add_commit_order`) returns a typed **`OrderResult`** (`ok`/`code`/`message`) rather than
`push_error`, so callers — the LLM API included — can branch on the rejection and surface its
reason (plan 0017).

**Turn resolution order** (`resolve_turn`): IJFS air/missile fires → **sealift (tick ship
returns + embark the crossing wave)** → anti-ship crossing → amphibious offload → movement & commit
→ ground combat → front-line → cleanup (+ victory census).

**Phases / subsystems implemented:**
- **Ground combat** (BOOTS slice M0–M7): movement, commit, combat resolution, FEBA, casualties,
  retreat, hex ownership. Defender terrain modifier is active: `CombatResolver.resolve_at`
  receives the defended hex's `defender_modifier` via `TurnConductor.defender_combat_modifier`.
  **Support units** are mortal and included in casualty selection (weighted 1:4 vs maneuver units). If a side has only support units, they are "unscreened", contributing 0.5 strength each and taking losses. Golden invariant: the scripted beach-1 fight is byte-stable per gate; the pinned values live in
  `tools/validate_headless_turn.gd` (re-baseline history: `docs/DECISIONS.md` →
  `docs/archive/PLAN.md`).
- **D1 Amphibious offload** — ship reserve → beach landing; lands brigades onto beach hexes.
  Every scenario's `red_ship_reserve.beach_hex` must be coastal (< 6 land neighbors) —
  `validate_scenario_data.gd` rejects fully-inland landing hexes.
- **Sealift lifecycle** (plan 0004, 2026-07-12) — ships cycle ready→sent→offloading→returning→ready
  (`SealiftState` + `SealiftResolver`); follow-on echelons embark onto ready amphibious lift so
  crossing sustains across turns instead of draining by ~turn 3. A BN crosses **once** (attrited on
  its crossing turn, then safe offloading). Escorts carry a cross-turn SAM magazine and cycle to
  reload when low. Follow-on is either an explicit `red_followon_reserve` (curated echelon — no
  shipped scenario uses this today) or an opt-in deep pool auto-seeded from the OOB
  (`auto_seed_followon_pool`, on for both `scenario_default` and `roc_full_defense`); amphibious lift is classified
  by `ShipDef.is_amphibious_lift()` and `pack_bns_into_hulls` aggregates fractional hull capacity.
  Facts: `docs/systems/amphibious-offload.md` → "Sealift lifecycle".
- **Research default vs golden fixture** (2026-07-12) — `scenario_default.json` is the realistic
  deep-pool sustained invasion (research/self-play); the pinned gate runs the frozen
  `scenario_golden.json` (one-shot assault) via `HEXCOMBAT_SCENARIO`, keeping golden pins byte-stable
  as the default evolves. Deep-pool coverage: `tools/validate_deep_pool_smoke.gd`.
- **Offload capacity gate** (plan 0006) — Red buildup is gated by held/operational offload
  infrastructure, not just ship lift: ports/airbridges (`data/infrastructure.json`,
  `InfrastructureResolver`) contribute throughput once seized and JLSF-repaired (`deploy_jlsf`
  order / `auto_jlsf` policy); day-N offload costs vary by BN type × ship category
  (`use_offload_weight_matrix` → `OffloadCostModel`, with cross-turn carry-over for heavy
  loads); a per-beach occupancy valve (`BeachDef.depth`) closes a beach until landed brigades
  move inland. All default-off; `scenario_default` enables the matrix + auto-JLSF. Empty-orders
  self-play hard-plateaus instead of overrunning; seizing a port visibly raises the landing
  rate. Facts: `docs/systems/amphibious-offload.md` §9.
- **D2 Red DOS supply** — supply pool / effectiveness tracking. An exhausted Red pool now degrades Red
  ground-combat strength (`red_out_of_supply_effectiveness`, default 0.5) via
  `GameState._inject_supply_effectiveness`.
- **D3 Anti-ship & mine warfare** — IJFS-fed firing plan → crossing damage (count-based) → **geometric
  mine model** (randomized approach path, dangerous-mine count within `danger_radius`, decoy-sponge
  transit; knobs in `data/antiship/minefields.json`). Ship losses → BNs lost at sea. Crossing
  lethality is calibrated to the USER-accepted 32.9% mean loss on the 81-BN sent-cohort wave
  (2026-07-18; superseded plan 0001's ~25%-of-36-BN target) via `data/ijfs/ijfs_scenario.json`'s
  `intel_locked_antiship_strike_bonus` (0.20) and `prelanding.intel.exquisite_intel.antiship.initial_count`
  (36) — see `docs/archive/0001-crossing-lethality-calibration.md`.
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
  **CRBM heavy-volley maneuver attrition (plan 0009, 2026-07-17 USER call):** two coupled scenario
  knobs in `ijfs_scenario.json` let Red spend its excess CRBM inventory on maneuver battalions —
  `crbm_maneuver_rounds_override` (480) forces the volley size on every CRBM×Maneuver pairing
  (depletion only), and `crbm_maneuver_strike_bonus` (0.15, USER-dialed 2026-07-17 via
  `python3 tools/run_sweep.py --spec tools/sweeps/crbm_maneuver.json` — ~38% ROC maneuver-pool attrition over 40 turns) is the paired
  lethality lever, synthesized into a strike modifier. Both synthesized by `IjfsLoaders`
  (`apply_crbm_maneuver_*`), wired in `IjfsStateBuilder.build`. Detail: `docs/systems/ijfs.md`
  §4 Strike.
  **MANPADS layer (2026-07-10, USER design call — TIV-oracle divergence):** the ~2,500 Stingers are
  per-TO container bins (category `MANPADS`, excluded from SEAD/AD-health) that intercept
  low-altitude strikes (UAV/OWA/strike-aircraft munitions; ballistic/cruise immune) and contest
  SEAD/strike squadrons island-wide, deteriorating via usage, bombardment, and TO ground losses
  (`IjfsManpads.gd`; spec in `docs/systems/ijfs.md` → "MANPADS layer"; surfaced as
  `ijfs_summary.manpads`).
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
- **Batch runner (research harness B2/B7)** — `python3 tools/run_batch.py --name <study>
  --scenarios default,<variant> --matchups red:green,... --n 30` plays a scenario × matchup ×
  common-seed matrix, one headless Godot process per game, up to `--parallel` at a time. A bare
  matchup policy means the same policy in both seats. Each game (`tools/run_selfplay_game.gd`)
  writes a timestamp-free, byte-reproducible (for deterministic seats) v2 JSON record with
  explicit Red/Green policy identities to `reports/batches/<study>/games/`; verdicts are
  artifact-based; re-running resumes only valid records; `manifest.json` stamps matchups,
  commit, and per-game re-run command lines. The runner writes `report.md` automatically
  (`--no-report` suppresses it). The runner warns when a live-model matchup uses more than one
  worker; use `--parallel 1`.
- **Outcome reports (research harness B3)** — `tools/make_batch_report.gd -- --batch=<study>`
  aggregates a batch's records into `report.md`: per-condition (scenario × Red policy × Green
  policy) win rates, turn/census/margin distributions, per-game loss means, a methods line
  (commit, mixed-commit and dirty-tree warnings), and standing caveats (including LLM
  non-determinism). Aggregation/rendering is pure `BatchReport` statics (GdUnit-tested).
- **Narrative renderer (research harness B4)** — `tools/make_game_narrative.gd`
  (`--record=<file>` or `--batch=<study> --pick=median|longest|shortest`) renders a game
  record's event log into a turn-by-turn Markdown account (IJFS strikes + air-defense
  degradation, the crossing, maneuver/commitments, per-hex ground combat with FEBA movement,
  end-of-turn census, outcome). Pure `GameNarrative` statics (GdUnit-tested).
- **Knob sweeps (research harness B5)** — `python3 tools/run_sweep.py --spec tools/sweeps/<spec>.json` or `python3 tools/run_sweep.py --name <study> --knob <file:dot.path> --values a,b,c` generates cell variants
  (via `DataOverrides` map), batches them over a common seed set, and reports per-value
  outcome rows. One backend since plan 0012: every cell is a parallel `run_batch.py` job set of
  standard `run_selfplay_game.gd` games; `sweep_metrics.py` extracts raw numbers from the game
  records (turn digests + terminal census) and `make_sweep_report.py` owns all display
  formatting. The canned calibration specs run `matchup: noop` (pure engine dynamics — the
  measurement semantics their dialed reference tables were accepted under; per-seed parity with
  the retired in-process cell runner verified 2026-07-18), and the antiship mines-only floor is
  the `disable_antiship_systems` grouping-spec override. Any JSON knob in `data/` can be swept.
  A spec's `scenario` id must resolve to a file before any game runs; typo'd override paths fail
  loud via `DataOverrides.unapplied()` in the selfplay entrypoint; reports match cells by
  override content, not filename. **The
  antiship crossing instrument changed 2026-07-18:** the harness now runs sealift between IJFS
  and the crossing (mandatory since plan 0004 — without it no cohort is "sent" and losses read
  zero), and the wave is the sent cohort (~81 BNs incl. follow-on echelons), not the 36-BN ship
  reserve. The plan-0001 dial (ic=36, bonus=0.20) reads **32.9%** mean crossing loss on the new wave
  semantics — USER accepted 2026-07-18 (supersedes the ~25%-of-36-BN target; table:
  `reports/sweeps/antiship_crossing/report.md`).
- **LLM players (research harness B6)** — policy id `llm_local` (`LLMPolicy`) marshals a seat's
  perspective observation to an out-of-process Python sidecar (`tools/llm_sidecar.py`) that calls a
  local OpenAI-compatible model (`HEXCOMBAT_LLM_BASE_URL`/`_MODEL`/`_API_KEY`, default vLLM at
  `localhost:8088/v1`), validates the returned actions against the legal sets, and appends every
  observation/action pair to a JSONL replay log. `SelfPlayRunner.play_game_seats` runs two
  independent seats to a simultaneous WeGo resolve; `godot --headless --path . -s
  res://tools/run_selfplay_game.gd -- --seed=S --red-policy=llm_local --green-policy=llm_local
  [--scenario=X] [--turns=N] [--model=M] [--out=f.json] [--log=f.jsonl]` plays one full
  LLM-vs-LLM game and writes a record + replay log.
  `HEXCOMBAT_LLM_SIDECAR` overrides the sidecar (e.g. `tools/llm_sidecar_stub.py`, the network-free
  stub used by the gate). LLM decisions are NOT seed-reproducible; the JSONL log is the replay
  artifact — each entry carries the full observation, the raw model reply, the validated actions,
  and any sidecar `warnings` (stderr is dropped by the engine's `OS.execute`, so the log is where
  diagnostics surface). Hardening from the 2026-07-10 live runs: duplicate orders for one brigade
  are deduped in the sidecar (engine rule mirrored, first order wins); an unparseable reply gets
  ONE strict "JSON only" retry before forfeiting the turn (rescues reasoning-model token-budget
  overruns); `HEXCOMBAT_LLM_MAX_TOKENS` default raised 8192→32768 (observed CoT overruns at 8192;
  worst prompt ≈21K tokens vs DeepSeek-V4-Flash's 131072 context, so headroom is cheap — the
  budget's real cost is wall-clock on rambling turns). Use IPv4 (`127.0.0.1`, default) not
  `localhost`. Live-verified against local vLLM (model `jarvis`): seeds 20260710/20260711, both
  30/30 turns GAME OK; the second (post-fix) run had zero forfeited turns. `llm_local` now also
  runs in either B7 batch seat (mixed or LLM-vs-LLM); mixed game logs include both seat
  observations/actions so they remain bundle-ready.
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
  (`TurnConductor.defender_combat_modifier` → `CombatResolver.resolve_at`): plains ×1.0, hills ×1.5,
  urban ×2.0, mountain ×2.0, metropolis ×3.0 — golden currently seed 20260624
  `casualties=9, feba=1.98` (re-baselined 2026-07-09 for the full-defense laydown). Terrain is
  surfaced per-hex in the LLM `occupied_hexes` observation and IS the map fill: every classified
  hex renders pure `TerrainType.color` (USER call — match `terrain_preview.png`); RED/CONTESTED
  ownership renders as a 3px perimeter border around each connected pocket, no interior lines
  (`HexMap._build_ownership_borders`), with numbered beach glyphs. Full detail:
  `docs/systems/terrain.md`.
- **Default scenario = full ROC defense (2026-07-09 USER call)** — `data/scenario_default.json`
  places all 32 ROC brigades (laydown shared with `roc_full_defense`; beaches 1/3/6/9 garrisoned
  on-hex, every landing beach covered on-hex or adjacent — pinned by `validate_scenario_data.gd`).
  Under empty-orders self-play the default now runs to the 40-turn stalemate census 24/88 pinned
  in `validate_golden_victory.gd` (the 4-brigade landing wave cannot out-census 88 ROC battalions;
  victory FIRING stays covered by `tests/victory_conditions_test.gd`).
- **Brigade marker rendering (`HexMap`)** — brigades are grouped per hex: same-hex stacks render
  as a 0.62× ring with a ×N count badge at 3+; a lone brigade shrinks to 0.75× and pins to the
  hex center when any neighbor hex is occupied (full-size markers are wider than the hex spacing
  and would overlap); an isolated brigade renders full-size with its entry-bearing offset.
  Visual-only — headless gates don't cover it; verify by screenshot.
- **Post-game briefing viewer** — `tools/make_game_bundle.py` (stdlib-only) merges an
  AI-vs-AI game record (`reports/llm/<name>.json`) with its JSONL replay log into one
  `<name>.viewer.json` bundle (meta / per-turn digest+actions+observation / per-side 3-line LLM
  SITREPs / embedded map data); `--html` bakes it into a single shareable `<name>.game.html`,
  and `--from-bundle` re-bakes that HTML from an existing bundle without re-running sitrep LLM
  calls. `tools/viewer/game_viewer.html` is a single self-contained briefing page (open
  directly, no server): opens at turn 1 and advances one turn at a time (mouse wheel with a
  momentum guard, ◀ ▶ / ⏮ ⏭-Final buttons, arrow keys, Home/End) — each advance re-renders the
  SVG hex map (terrain fill + red/contested perimeter borders + beach glyphs + brigade markers,
  ported from `HexMap.gd`'s projection/border logic) and extends the chart reveal.
  The map box holds **two viewports over one shared render** (content lives once
  in a `<defs>` group; both `<svg>` `<use>` it, differing only in `viewBox`): a full-island
  **theater** view and a **front** view whose `viewBox` crops to the bbox of the contested/Red
  hexes + their neighbors (same owner predicate as the border layer, so the two always agree; no
  landing yet → falls back to the full island). Non-contiguous fronts (two beachheads → one bbox
  spanning both) are a known follow-up, tracked in BACKLOG. Advancing also swaps the
  turn's narrative (SITREPs, collapsible transcripts, adjudication prose, phase-detail tables)
  in place; the wheel scrolls an overflowing narrative instead of stepping. Charts render
  ghost-future (full game faint, turns ≤ current in color): census, cumulative ship losses,
  and per-turn battalion losses per side (China stacked ground / drowned-at-sea) derived
  client-side from the digests. Tolerates older JSONL logs that lack `observation` (map falls
  back to the nearest earlier observed turn / "no map data this turn"). Visual-only tool, not
  part of the canonical gate — verify with a headless-Chromium (Playwright) pass over a rebuilt
  `game.html` plus screenshots.

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
  `TurnConductor.defender_combat_modifier`'s `* 1.0` situational-modifier slot. See
  `docs/plans/BACKLOG.md`.
- **Deferred ports** — anti-ship missile pipeline depth (strike-coverage lever), ground-casualty
  IJFS↔OOB linkage; **per-hull** escort magazines (aggregate per-type magazines shipped 2026-07-12,
  plan 0004; per-hull granularity + damage-driven repair delay still deferred). See `docs/plans/README.md` (plan index) and
  `docs/archive/port_audit.md`.
- **Refactors** — see `docs/archive/refactor_audit.md` (e.g. victory census should count *present*, not
  OOB, battalions; typed `WarmupContext`/`HexState`).
