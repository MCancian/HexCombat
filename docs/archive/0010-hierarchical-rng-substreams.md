---
status: Shipped
shipped: 2026-07-17
landed_in: main
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

- [x] `SeededDice.derive(salt) -> Dice` — already present (hashes `str(_seed) + ":" + label`).
- [x] `GameState.resolve_turn()` sub-streams: `resolve_ijfs_turn` (derives per day in
  `IjfsResolver._derive_day_dice`) and `resolve_antiship_turn` (`dice.derive("antiship:%d")`) already
  derive; `resolve_offload_turn` consumes NO dice (deterministic capacity ordering) — nothing to do.
- [x] `GameState._resolve_combat_at` now receives a per-hex substream: the combat loop passes
  `dice.derive("combat:%d:%s" % [turn_number, hex_id])`.
- [x] `ScriptedDice.derive` — already present; returns self so scripted fixtures share one queue.
- [x] Ran the full gate. Only TWO SeededDice golden pins shifted (per-hex derivation re-derives
  combat draws — equally valid, not a behaviour change): `validate_cleanup.gd`
  (`casualties=9,feba=-0.48` → `casualties=8,feba=-0.23`) and `validate_golden_victory.gd`
  (census `27/94` → `25/92`). All GdUnit suites + `validate_headless_turn` unaffected. ALL PHASES GREEN.
- [x] `docs/DECISIONS.md` + `docs/STATUS.md` updated.

## Outcome

The plan's core infrastructure (`derive` + ijfs/antiship substreams) was already in place; the one
substantive change was wiring the per-hex combat substream. The feared "massive golden re-baseline"
was two pins, because combat was already isolated from the sea phases (they derive) and the only
remaining butterfly was hex-to-hex within the combat loop.
