---
name: hexcombat-architecture-contract
description: The load-bearing design decisions of HexCombat, the invariants that must hold, and the known weak points. Read BEFORE designing any new module, changing module boundaries, adding an autoload, touching RNG flow, or changing how state moves between phases. Also the arbiter when two designs both "work" — pick the one this contract prefers.
---

# HexCombat architecture contract

The decisions below are settled. Do not relitigate them in a task; if one genuinely blocks you,
surface it to the user (open a Sketch plan in docs/plans/) instead of quietly diverging.

## The mission shapes the architecture

HexCombat is (1) primarily a **headless AI-vs-AI research engine** (Monte Carlo outcome
distributions, LLM players via the JSON API, narrative event logs, parameter sweeps) and
(2) secondarily a **live-adjudication aid** (facilitator enters orders in a UI, projector-friendly
display). Ratified 2026-07-02 (docs/archive/PLAN.md → Decisions). Consequences:

- **Everything must run headless.** The view is optional. Any feature that only works with a
  window is broken by design (screenshot capture is the one sanctioned windowed-only tool).
- **Determinism is non-negotiable.** Same seed → byte-identical outcome, across processes.
  Research results depend on it; so does every golden test.
- **The JSON observation/action contract is a public API.** LLM agents, validators, and the
  self-play harness all consume it. Extend it; never break it silently.
- **Scenario variants are first-class content.** Tunables live in scenario/data JSON, not code.

## Layers (where code goes)

| Layer | Location | Rules |
|---|---|---|
| Model | `scripts/model/` | Typed `Resource` DTOs. Plain data; no engine/scene/screen concerns. |
| Pure logic | `scripts/` (+ `scripts/ijfs/`, `scripts/resolvers/`) | `RefCounted`/`static func`; no `Node` dependency; no autoload access from inside; headless-testable in isolation. |
| Data service | `GameData` autoload | Loads JSON into typed objects once; holds lookups. |
| Runtime state | `GameState` autoload | Turn/phase/orders; sequences phase resolvers. Being decomposed (see below). |
| View/control | `HexMap`, `GameController`, `InfoPanel`, scenes | Reads state, draws, translates input into actions. Owns NO game state. |

**No new autoloads.** Decided by the user 2026-06-30: autoloads are hidden globals an agent must
already know about — the opposite of legible. New capabilities become pure classes with explicit
signatures, wired by the existing autoloads.

## The resolver interface (decided — the shape of all phase logic)

Each turn phase is (or is becoming) a **pure `RefCounted` resolver class** in `scripts/resolvers/`
with an explicit signature like `resolve(<inputs>, dice) -> <TypedSummary>`:

- Dependencies are **visible in the signature** — pass data in, return data out.
- No `EventBus` emits, no `GameData`/`GameState` autoload reads inside the class. Signal emits and
  autoload access stay in the thin `GameState` wrapper method that delegates to the resolver.
- `GameState` shrinks toward a thin orchestrator that sequences resolvers and owns cross-phase
  state. (Decomposition record: `docs/archive/refactor_audit.md` item 10.)

## Turn engine facts

- **WeGo:** both sides buffer orders in PLANNING; `resolve_turn(dice)` applies everything
  simultaneously; move-then-fight; combat is continuous per contested hex (FEBA accumulates).
- **Resolution order** (fixed): IJFS → anti-ship crossing → amphibious offload → movement/commit →
  ground combat → front-line → cleanup (+ victory census). New phases slot into this sequence
  explicitly — never as a side effect of another phase.
- **Cross-phase state** flows through fields owned by `GameState` (`ship_reserve`, `fleet`,
  `pending_lost_at_sea`, `antiship_systems`/`antiship_containers`, `last_ijfs_writeback`,
  `supply_state`, `game_over`/`winner`, per-brigade activity flags). Every producer→consumer edge
  must be explicit; do not add hidden coupling between phases.
- **Brigade is the atomic on-map unit.** Battalions are brigade attributes, never separately
  positioned.

## RNG topology (verified; preserve it)

All randomness flows through the injectable `Dice` abstraction (`scripts/Dice.gd` /
`SeededDice.gd`). `tools/validate_no_global_rng.gd` gates it.

- IJFS and anti-ship draw from **independent derived substreams** (`dice.derive("ijfs:…")`,
  `dice.derive("antiship:…")`).
- **Offload consumes no dice** (deterministic capacity ordering).
- **Ground combat is the sole base-stream consumer.**

Any extraction/refactor must keep this topology: a new consumer of the base stream, or a reordered
draw, shifts every subsequent roll and breaks the golden invariant. New random behavior gets its
own **derived substream**, never the base stream.

## Serialization seam (the `to_dict()` rule)

- **In-process:** typed Resources, typed field reads.
- **At every JSON boundary** (LLM API, event log, `TurnResult`, exporters, EventBus signal
  payloads that carry summaries): emit via the Resource's `to_dict()`. One serialization seam per
  type; the dict is the public contract, the Resource is the in-process storage.
- **`null` (not `{}`) is the "phase didn't resolve" sentinel** for summary Resources.
- Public `resolve_*` methods on `GameState` return `Dictionary` via `to_dict()` — validators and
  tools consume string keys; don't churn them.
- Deliberately untyped (user calls — do NOT type them): `last_ijfs_summary` (dynamic engine
  output, ~21 keys, 3 read), `combat_detail` (write-once JSON pass-through).

## Fail loud, not silent

Solo-developer tool: a crash you fix at the root beats defensive handling that hides bugs.
`push_error`/`assert` on unknown/missing data; **never a silent default fallback**. The costliest
bug in project history (exquisite intel dead for the whole project) was a `dict.get(key, default)`
silently absorbing a config that never arrived — see `hexcombat-failure-archaeology`.

## Known weak points (open, stated plainly)

- `GameState.ship_reserve`: bare `Array` of Dictionaries — key-typo-prone at every consumer.
- `AntishipCrossing.gd`: 6-stage pipeline passing untyped `Dictionary` ledgers/configs.
- `orders`/`commitments` buffers: typed Resources stored in untyped containers.
- Hex grid is geometry-only (no terrain/land flag) → victory census "on Taiwan land hexes" uses
  the all-placed-hexes default; `taiwan_hexes` config is the future hook.
- `CombatCalculator.gd` has a stale `feba_base_km = 2.0` default parameter (real callers pass
  `GameData.feba_base_km` = 3.5 from scenario); `BOOTSCalculator.gd` wrapper carries the same.
- Godot 4.7 headless teardown crash (see `hexcombat-debugging-playbook`) — engine-level, gated
  around, not fixable here.

## Where deeper detail lives

- Per-system data flow + TIV fidelity notes: `docs/systems/*.md` (start at the README index).
- Rationale for past choices: `docs/DECISIONS.md` (changelog with pointers); pre-2026-07-10
  history verbatim in `docs/archive/PLAN.md` → Decisions.
- What works today: `docs/STATUS.md`. Forward plan: `docs/plans/BACKLOG.md`.
