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
   GameState (planned autoload): turn / phase / active side
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
| Movement / front | `src/services/boots_hex_service.py` | *(pending — M4/M5)* |
