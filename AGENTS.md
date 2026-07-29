# AGENTS.md — HexCombat Agent Guide

Godot 4.7 / GDScript hex-grid wargame of a PLA invasion of Taiwan, ported from
**TaiwanInvasionViewer** (TIV, Python/Flask). Claude-harness specifics live in `CLAUDE.md`.

**Mission (USER-ratified 2026-07-02):**
1. **Primary — AI-vs-AI research instrument:** headless batch games → Monte Carlo outcome
   distributions, LLM players via the JSON API, human-readable narratives + HTML game reports,
   parameter sweeps.
2. **Secondary — live-adjudication aid:** a facilitator enters both sides' orders in the UI and
   the sim resolves; projector-friendly display.

The USER is a non-coding wargame designer; agents do all coding — **legibility to future agents
is a design requirement**. Design of record is HexCombat itself: TIV was the port oracle
(preserve ported math unless a change is directed; read TIV source + `tests/python/` before
adapting its mechanics), but new design and rebalances are USER calls.

## Orientation — read this, then ONLY your task's list

Every fact has exactly one home. Don't hunt for it elsewhere:

| You need… | Go to |
|---|---|
| What works today (cross-cutting) | `docs/STATUS.md` (hub — engine, turn model, gate, mutation authority) |
| What works today (per module) | `docs/systems/<module>/STATUS.md` |
| What's next / work in flight | `docs/plans/README.md` (active plan index) |
| Tech debt / hygiene queue | `docs/plans/BACKLOG.md` |
| Past work / archived plans | `docs/plans/ARCHIVE.md` |
| How a module works | `docs/systems/<module>/` (system doc + STATUS + RETRO) |
| Module internals / boundaries | the code header: `scripts/resolvers/*.gd`, `GameState.gd` |
| A procedure (build, debug, author, verify…) | `.claude/skills/README.md` task→skill map |
| Exact expected numbers (goldens) | the validator (`tools/validate_*.gd`) — its PASS line is truth |
| Why something is the way it is | `docs/DECISIONS.md` (changelog → pointers); deep history `docs/archive/` |
| A problem that feels familiar | `hexcombat-failure-archaeology` |

**Task-shaped minimum reads** (skills via `.claude/skills/`):

- **Bug fix / small change:** `docs/systems/<module>/STATUS.md` → `hexcombat-change-control` →
  `hexcombat-debugging-playbook` (if a gate is red) → the module's system doc or resolver header.
- **New mechanic / phase:** the above + `hexcombat-architecture-contract` →
  `hexcombat-add-phase-resolver` → `hexcombat-validation-and-qa`.
- **Research question (outcomes, sweeps, AI-vs-AI):** `hexcombat-research-runs` →
  `hexcombat-run-and-operate`.
- **Scenario/balance content:** `hexcombat-scenario-authoring` → `hexcombat-config-and-knobs`.

When you finish: update the canonical homes you touched (`docs/systems/<module>/STATUS.md`,
the module's system doc, 3–5-line `docs/DECISIONS.md` entry), close out any plan per
`docs/plans/README.md`, then commit. Rules: `hexcombat-docs-and-writing`.

## Architecture (keep new code inside these layers)

- **Model — typed `Resource` classes** (`scripts/model/`): plain typed data; no engine/scene
  concerns. Prefer adding fields over passing untyped `Dictionary` blobs.
- **Logic — pure libraries** (`scripts/`, `scripts/ijfs/`, …): `RefCounted` / `static func`;
  no `Node` dependency; headless-testable.
- **Resolvers** (`scripts/resolvers/`): one pure class per turn phase; `GameState` methods are
  thin delegating wrappers. Each resolver's header states its purity boundary — read it before
  editing. New phases follow `hexcombat-add-phase-resolver`.
- **Phase coordinators** (`scripts/phases/`): the WHEN, not the how — `TurnConductor` holds the
  ordered phase list, the rest group phases that share state (`FiresPhases`, `ReinforcementPhases`,
  `TurnClosure`, `FrontlinePhase`). A coordinator may call two authorities; it writes neither's
  fields itself.
- **Builders** (`scripts/builders/`): produce FRESH state from scenario/content data and hand it
  back. Nothing holds what they are building yet, which is why the mutation manifest grants them
  CONSTRUCTION allowances — never confuse one with a resolver.
- **Calculators** (`scripts/calc/`): compute and report, hold no state, write none that outlives the
  call. A file that mutates anything live does not belong here, however pure the rest of it is.
- **Data service — `GameData` autoload**: loads `data/*.json` into typed objects once.
- **Runtime state — `GameState` autoload**: turn/phase/orders; owns `resolve_turn` (its inline
  comments carry the phase-order and RNG-substream rationale).
- **View / control**: `HexMap.gd`, `GameController.gd`, `scenes/Main.tscn`. No sim logic here.
- **Mutation authority** (campaign 0042–0050, in progress): a registered aggregate has ONE named
  writer. Calculators return outcomes; only the authority applies them. Ownership facts live in
  `tools/mutation_authority_manifest.json` and are gated by `tools/validate_mutation_authority.gd`
  — do not copy its field/writer lists into a header or doc. Adding a field to a registered model,
  or a new write to one, needs a manifest entry; the gate names the file, line, and write form.
- Deeper rationale + invariants: `docs/ARCHITECTURE.md` and `hexcombat-architecture-contract`.

## Running & verifying

Two boxes; full environment recipes (paths, class-cache import, flatpak sandbox traps) in
`hexcombat-build-and-env`:

- **Linux (this box):** Godot = flatpak `godot` on PATH; canonical gate =
  `bash tools/run_all_tests.sh`. The sandbox can't read/write outside the project dir.
- **Windows:** Godot = `C:\Godot_v4.7-stable_win64.exe`; gate = `pwsh -File tools/run_all_tests.ps1`.

The gate (import → smoke → every `tools/validate_*.gd` → GdUnit4) must be **ALL PHASES GREEN**
before declaring work done — verdict by marker lines, never exit codes (known teardown flake).
After adding a `class_name` script, run `godot --headless --path . --import` or it won't resolve.

## Testing

1. **Headless validators** (`tools/validate_*.gd`) — data contracts, smoke, port equivalence,
   golden pins. 2. **GdUnit4** (`tests/`) — unit/integration.
- **Seeded RNG only** — inject `Dice`; never global `randi()`/`randf()` in logic.
- New behavior ships with a test; mirror the source pytest when one exists.
- Golden re-baselines are deliberate change-control events (`hexcombat-change-control`).

## Conventions

- Typed GDScript throughout (`class_name`, typed params/returns).
- **Single source of truth** — no duplicated tables/constants (unit strengths live in `UnitStats`).
- **Fail loud, not silent** — solo-developer tool: `push_error`/assert at the root cause beats
  defensive guards that hide bugs. No silent default fallbacks.
- Pure logic = static `RefCounted` libs; runtime state = autoloads; visuals = view layer.
- **Quality budgets on touched code** (complexity/length/params ceilings, magic-number policy,
  naming glossary, test bar): `.claude/skills/hexcombat-code-quality`; baseline audit in
  `docs/reports/2026-07-16-code-quality-baseline.md`.

## LLM play / headless JSON API

`LLMGameAPI` (autoload) exposes observation/action JSON; contract reference =
`docs/LLM_OBSERVATION_SCHEMA.md` + `schemas/*.schema.json`; gate = `tools/validate_llm_api.gd`.
New phases must extend the observation with their state — never break the contract. Running
games, self-play, LLM seats, exporters, HTML reports: `hexcombat-run-and-operate` and
`docs/systems/llm-api-selfplay/llm-api-selfplay.md`.

## Guardrails

- Preserve ported combat math exactly unless the USER directs a change; record every deliberate
  divergence in `docs/DECISIONS.md` (pointer) + the module's systems-doc fidelity notes.
- Refactors keep goldens **byte-stable**; re-baselines are USER-aware change-control events.
- **Only the primary agent commits.** Subagents leave changes for it to verify and commit.
- Never commit `.mcp.json` (machine-specific).
