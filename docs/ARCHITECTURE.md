# Architecture

Deeper companion to the summary in `AGENTS.md`. This file holds rationale and grows with the
project; `AGENTS.md` stays the short operational rulebook.

## Layered design

```
data/*.json ──► GameData (autoload)        typed model (scripts/model/)
                 loads once, holds          Hex · Brigade · Battalion · CombatResult
                 lookups + hex states
                        │
        pure logic libs │ (scripts/, static / RefCounted, headless-testable)
        HexMath · CombatCalculator · UnitStats · MapProjection
                        │
   GameState (autoload): turn / phase / order buffers / phase sequencing
                        │
        view / control: HexMap (Node2D renderer) · GameController · Main.tscn
```

Why this split:

- **Model vs. logic vs. state vs. view** keeps game math headless-testable and free of engine
  coupling, lets runtime state evolve without touching rendering, and keeps the renderer dumb
  (it reads state and draws).
- **One data autoload** gives every layer a single, already-loaded source of truth and a
  deterministic init order (autoloads run before the main scene).
- **Pure static logic** is why combat/hex math can be unit- and golden-tested without a scene.

## Determinism

Randomness must flow through an **injectable, seedable RNG** rather than global `randi()`/
`randf()`. This makes combat and every future phase reproducible for golden tests, CI, and
debugging. (Refactor tracked in `ROADMAP.md` M0.)

## Control & actions (headless-drivable)

The brigade is the **atomic on-map unit**; battalions are brigade attributes (strength,
casualties), never separately positioned. Gameplay runs through a **view-independent
action/resolution layer** on top of `GameState`: discrete commands such as
`MoveBrigade(brigade, to_hex)` and `ResolveCombat(target_hex, attacker_composition,
defender_composition)`.

- The **view** translates clicks into these commands; it owns no game state.
- **AI agents** and the future **B2 auto-resolve** mode emit the *same* commands.
- This is what makes **headless AI-vs-AI** play, deterministic golden tests, and the autonomous
  orchestrator possible.

Under the **WeGo** turn model the layer first *collects* both sides' orders for the turn, then a
single deterministic **resolver** applies them together (the one place simultaneous move/combat
conflicts are sequenced). Hex ownership is by **occupancy** — both sides present → contested; one
side → that side; empty → last owner — with FEBA driving post-combat retreat. The resolver order
is **move-then-fight**: movement applies first, then every hex with both sides present fights.
Combat is **continuous** — a contested hex resolves a round each turn (a day), FEBA accumulating
across turns, so reinforcements arriving later join the unfolding engagement.

In manual mode, declaring an attack opens a **combat-composition menu**: both sides may add
eligible supporting forces and other available maneuver units (target hex contributes all units;
adjacent hexes contribute maneuver/artillery; support assets feed `resolve_map_attack`'s support
dicts) — i.e. a manual front-end over the same collection logic the source automated.

## Per-phase template

Each TaiwanInvasionViewer phase becomes a self-contained module that reuses `GameData`/
`HexMath`:

1. **Typed model** under `scripts/model/`.
2. **Pure logic lib** under `scripts/` (`static`/`RefCounted`).
3. **Wiring** through `GameData`/`GameState` and the event bus — no reach-through between phases.
4. **Tests:** a `tools/validate_*.gd` data-contract script + GdUnit4 unit/golden tests mirroring
   the source `tests/python/` cases.

BOOTS is the reference implementation of this template.

## Source-of-truth mapping

Port traceability (extend per phase under `docs/phases/` as work proceeds):

| Domain | TaiwanInvasionViewer | HexCombat |
| --- | --- | --- |
| Hex grid / pathfinding | `src/core/hex_grid.py` | `scripts/HexMath.gd`, `GameData` |
| Ground combat | `src/services/boots_calculator.py` | `scripts/CombatCalculator.gd`, `UnitStats.gd` |
| Movement / front | `src/services/boots_hex_service.py` | `scripts/Movement.gd`, `GameState` move orders; front-line in `scripts/FrontLineService.gd` |

The full per-system source map (all D1–D5 phases, IJFS, anti-ship/mine) lives in
`docs/systems/*.md` — that reference supersedes this table for ported detail.

## Resolver decomposition (shipped 2026-07-02)

`GameState` was decomposed into pure `RefCounted` resolver classes under `scripts/resolvers/`
(`CombatResolver`, `FrontlineResolver`, `CleanupResolver`, `OffloadResolver`, `AntishipResolver`,
`IjfsResolver`, `SupplyResolver`, plus the Phase-A builders), each with an explicit
`resolve(<inputs>, dice) -> <TypedSummary>` signature (USER-decided interface; no new autoloads).
`GameState` is now the thin orchestrator that sequences them and owns EventBus emits, autoload
access, and cross-phase state. New phases follow this shape going forward. Contract and campaign
record: `.claude/skills/hexcombat-architecture-contract` and
`.claude/skills/hexcombat-gamestate-decomposition-campaign`; the template for adding the next
phase is `.claude/skills/hexcombat-add-phase-resolver`.
