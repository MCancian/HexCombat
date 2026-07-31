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

## Mutation authority (campaign 0042–0050 — COMPLETE, 2026-07-31)

> Every mutable gameplay aggregate has one named authority. Calculators return outcomes; only the
> authority applies them. Every cross-aggregate transition proves its preconditions and deltas
> before returning.

An **aggregate** is a set of mutable objects whose invariants must hold together (the anti-ship
establishment; the force; sealift; map infrastructure) — boundaries follow invariants, not files.
The **authority** is a pure `RefCounted` class, named `<Domain>Transitions`, in
`scripts/transitions/`; it validates ids and pre-state, applies the whole change, checks the exact
delta, and returns a typed receipt. It is **not** a base class, an autoload, or a generic
`MutationRequest`/`EntityController` — those are explicitly rejected. A phase module may coordinate
two authorities but never writes their fields itself.

**Where the facts live:** `tools/mutation_authority_manifest.json` is the single home for exact
ownership — authority file, protected fields and their lifetimes, and construction allowances.
(Legacy-writer allowances were the campaign's migration device and are now **zero** across all ten
aggregates; an entry that stops matching a real write fails as stale.) Headers and systems docs point
at it and must not copy its lists. `tools/validate_mutation_authority.gd` enforces it (its header
documents every write form it detects and every blind spot it does not). Its abstract fixtures prove
write forms; generated probes bind every real claim to the real type corpus; a committed claim pin is
an expected-output oracle only and is never read as ownership.

**What this means for your change:**

- Adding a mutable field to a registered model without classifying it fails the gate.
- Adding a write to a protected field outside its authority fails the gate, by file:line and form.
- An allowance that stops matching a real write fails as stale — dead exceptions get deleted.
- If the gate cannot resolve your receiver's type, annotate it. That is the intended fix, not an
  allowance entry.
- Aggregates migrated one at a time, and the mechanism is still there: one may be strict while a new
  one is unregistered. **All ten are `enforced` with zero legacy writers as of 2026-07-31**, so a new
  aggregate is now an ADDITION to a closed world, not a step in an open migration.
- `scripts/transitions/` grants nothing by being a directory: a file there that is no aggregate's
  `authority_path` fails the gate.

**The rule that survived the whole campaign, and the one to reach for first: enforce by ABSENCE.**
An invariant you can express in the authority's API is documentation; an invariant you cannot express
is enforced. `MapTransitions` has no owner setter at all, so sticky hex ownership cannot be written
away (0047). `TurnLifecycleTransitions` has no destination setter, so an illegal phase transition is
inexpressible (0049) — and the first draft of that claim was FALSE, because the edges were factored
through a private helper taking a destination, and a GDScript underscore is not access control.
Deleting a generic `set_x(target, value)` beats migrating it: one such setter lets any caller express
nearly every forbidden assignment through the permitted file.

**A forwarding property on an autoload is a public door the scan cannot see.** `GameState.<field> = x`
resolves its receiver to `GameStateType`, not `GameStateData`, so the gate never judges it — seventeen
validator writes to `GameState.turn_number` hid there. Every protected field's façade property is now
get-only. When you register a field, delete its setter in the same change.

**Field NAMES are protected repo-wide.** Register `IjfsMunition.name` and 22 unrelated view-layer lines
become unresolved-write failures (0046). Prefer a distinctive name — `cohort_state`, not `state`.

**Directory claims go stale without anyone editing the file.** `AntishipResolver` sat in
`scripts/resolvers/` for seven plans because one function wrote the caller's `ship_reserve` in place;
plan 0044 replaced that seam elsewhere and left the function with no production caller at all, which
nothing noticed until 0050 swept for it. When you delete a writer, re-ask what its file's directory is
still claiming.

**The pilot, measured — copy this shape.** `AntishipTransitions` came out at 187 lines, 8 functions
(5 public mutation operations, 3 private helpers) and 6 dependencies. Read it before writing the
next authority; the parts that are the pattern rather than the anti-ship domain:

- **Public methods are JOBS, not fields.** `ensure_establishment`, `reset_establishment`,
  `apply_ijfs_effects`, `apply_launch_attrition`, `reset_transient_flags`. Five is a soft threshold on
  public mutation OPERATIONS, not a cap on total methods — private helpers do not count, and forcing a
  split to satisfy a number would create the second writer the whole convention exists to prevent.
- **The receipt is a typed Resource, not a Dictionary.** `AntishipLaunchOutcome` carries one
  operation's result plus its own `consistency_error()`; the authority refuses a request that fails it.
- **Derived fields are recomputed in ONE private function** (`_reproject`) that every campaign write
  ends with, so no caller has to know the arithmetic. Keep the invariant check there even when it is
  currently unreachable: it guards the next write added to the file, not today's inputs.
- **Application is all-or-nothing.** Match and validate every row first, then apply. A half-applied
  aggregate with the operation still marked unapplied is worse than a refusal.
- **Guards `push_error` and change nothing; they do NOT `assert(false)`.** A research batch should not
  die on one bad row, and a guard that only push_errors can be exercised by a test
  (`assert_error(...).is_push_error(...)`). That is what makes the refusals testable rather than
  aspirational.
- **Absence is not zero.** A cumulative source that reports nothing for a row has said nothing about
  it; reading that as "zero losses" resurrects state. This was a real blocker caught in review.
- **Distinguish cumulative-ASSIGNED from cumulative-ACCUMULATED sources**, and never merge two
  sources that count different projections of the same thing — clamp their sum instead of asserting it.
- **The ceiling is paid for, not raised.** Naming a new authority from a ceilinged phase module means
  finding a dependency that genuinely leaves. In the pilot that was deleting `Theaters`, whose last
  caller was re-deriving a map `GameData` already held.
- **The cheapest owner is usually the right one — and the ceiling will tell you which it is.** Plan
  0050 first gave the crossing's BN-equivalent ledger to the anti-ship authority because the anti-ship
  phase produces it. Review killed that on a measurement: the consumer is `ReinforcementPhases`, whose
  ceiling was exactly full, and it does not depend on `AntishipTransitions`. `SealiftTransitions` was
  already a dependency of both coordinators — and, once asked, the more accurate owner too, because the
  ledger is the BN-equivalent conversion of the HULL losses that authority books. When a ceiling refuses
  an ownership choice, re-derive the boundary from the invariant before spending a dependency on it.

## Turn engine facts

- **WeGo:** both sides buffer orders in PLANNING; `resolve_turn(dice)` applies everything
  simultaneously; move-then-fight; combat is continuous per contested hex (FEBA accumulates).
- **Resolution order** (fixed): IJFS → anti-ship crossing → amphibious offload → movement/commit →
  ground combat → front-line → cleanup (+ victory census). New phases slot into this sequence
  explicitly — never as a side effect of another phase.
- **Cross-phase state** flows through fields on `GameStateData`. Most are owned by exactly one
  authority (`ship_reserve`, `fleet`, `sealift_state`, the crossing ledger, `antiship_systems`,
  `supply_state`, `game_over`/`winner`, per-brigade activity flags). The `last_*` slots are NOT: they
  are classified `phase_output` in the manifest, because they REPORT state that is authoritative
  somewhere else. Several are still read by a later phase (`last_ijfs_writeback` by the anti-ship step,
  `last_sealift_sent_by_type` by the crossing), so they are cross-phase edges without being protected —
  reshaping one is a behaviour change even though no authority guards it. Every producer→consumer edge
  must be explicit; do not add hidden coupling between phases. A handoff whose
  consumer must also CLEAR it is one read-and-clear call on the authority, not a read plus an
  assignment — a separate clear is a step a caller can forget or run twice.
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
  `GameData.feba_base_km` = 3.5 from scenario); TIV's `BOOTSCalculator.gd` wrapper carries the same. (upstream)
- Godot 4.7 headless teardown crash (see `hexcombat-debugging-playbook`) — engine-level, gated
  around, not fixable here.

## Where deeper detail lives

- Per-system data flow + TIV fidelity notes: `docs/systems/*.md` (start at the README index).
- Rationale for past choices: `docs/DECISIONS.md` (changelog with pointers); pre-2026-07-10
  history verbatim in `docs/archive/PLAN.md` → Decisions.
- What works today: `docs/STATUS.md`. Forward plan: `docs/plans/BACKLOG.md`.
