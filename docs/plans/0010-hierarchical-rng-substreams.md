---
status: Sketch
shipped: 
landed_in: 
---
# 0010 — Hierarchical Deterministic RNG (Sub-streams)

## Mission
Decouple the deterministic random number generator (RNG) across independent phases and spatial hexes to prevent butterfly-effect golden fixture drift. Add localized RNG sub-streams derived from a root turn seed, ensuring that design tweaks in one phase (e.g. anti-ship) do not scramble the dice-rolls of unrelated subsequent phases (e.g. ground combat).

## Motivation
Currently, HexCombat passes a single linear `SeededDice` instance through the entire turn resolution (`resolve_turn`). If an early phase (like IJFS or anti-ship) rolls one additional time due to a design tweak, the entire random sequence shifts for every subsequent phase. This causes unrelated golden fixtures (like `llm_result_after_turn.json` or `tools/validate_golden_victory.gd`) to fail and requires constant global re-baselining even for strictly localized design changes.

## Architecture

Instead of passing the global `Dice` instance down the line, we will use a hierarchical seeding model:

1. **Root Turn Seed**: `SeededDice.new(hash(scenario_seed + turn_number))` (Generated once per turn in `GameState.resolve_turn`).
2. **Phase Sub-streams**: `dice.derive(phase_name)`
   - `resolve_ijfs_turn(dice.derive("ijfs"))`
   - `resolve_antiship_turn(dice.derive("antiship"))`
   - `_resolve_combat_at(hex_id, dice.derive("combat_" + hex_id))`

This ensures that:
- Adding a dice roll in `resolve_ijfs_turn` does not affect the sub-stream given to `resolve_antiship_turn`.
- Changing casualty selection logic in `hex_44_16` does not affect the dice stream of `hex_43_13`.

## Checklist

- [ ] Update `SeededDice.gd` with a `derive(salt: String) -> SeededDice` method (hashes the current seed with the salt).
- [ ] Update `GameState.resolve_turn()` to create sub-streams for:
  - `resolve_ijfs_turn`
  - `resolve_antiship_turn` (currently does this partially but needs normalization)
  - `resolve_offload_turn` (if it ever consumes dice)
- [ ] Update `GameState._resolve_combat_at` to use `dice.derive("combat_" + hex_id)`.
- [ ] Update `ScriptedDice` to support or mock `.derive()` gracefully for unit tests.
- [ ] Run the full gate and re-baseline EVERY golden pin in the repository. Provide clear change-control rationale for the massive golden shift.
- [ ] Update `docs/DECISIONS.md` and `docs/STATUS.md` with the new hierarchical RNG architecture.
