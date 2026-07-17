---
status: Sketch
shipped: 
landed_in: 
---
# 0008 — Immortal Support Units in Ground Combat

## Goal
Fix a ground combat defect where brigades that have lost all maneuver units but retain support units (like artillery) become immortal in ground combat.

## Context & Settled Facts
- **Symptom:** In game records (e.g., `game_20260710.viewer.json`), the Red ashore census plateaus at exactly 4 battalions from Turn 11 to Turn 30. Red's ground combat losses drop to 0 permanently, yet Red continues to initiate combat.
- **Evidence:** Analysis of the combat summaries reveals that by Turn 12, the `attacker` (Red) has 0 maneuver units left (`maneuver_unit_count: 0`), but still has 1 support unit per brigade (the remaining 4 battalions).
- **Root Cause:** `CombatCalculator.resolve_map_attack` derives casualties solely from the `attacker_units` and `defender_units` arrays, which are explicitly filtered to only contain maneuver units (`CombatForces.maneuver_units()`). In `_select_casualties`, support units (like artillery) are excluded. If `attacker_units.size() == 0`, `attacker_losses` is 0, and the minimum-loss rule (`attacker_losses = 1`) is skipped because of the `if attacker_units.size() > 0` gate. Consequently, a force of purely support units can attack but can never take casualties.
- **Do-not-relitigate:** Green's inability to counterattack and destroy these units is a separate known design gap (see Plan 0003). This plan focuses solely on the immortality of support units in combat.

## Approach
- **Casualty Eligibility:** Modify `CombatCalculator._select_casualties` so that support units (like artillery) have some risk of dying even when maneuver units are present.
- **Combat Strength without Maneuver Screen:** When a force has 0 maneuver units but retains support units, the support units fight at half the strength of infantry (the weakest maneuver unit), and they become fully eligible for all casualty rolls.
- Ensure `CombatCalculator.resolve_map_attack` correctly identifies this state (0 maneuver, >0 support) and scales the support units' power as requested.

## Checklist
- [ ] Determine design for unsupported support-unit casualties (USER call). **(Done: Support units fight at 0.5x infantry strength when alone, and should have some baseline risk of dying when maneuver units are present).**
- [ ] Implement the new casualty logic in `CombatCalculator._select_casualties` so support units take casualties (both when alone, and occasionally when maneuver units are present).
- [ ] Implement the half-infantry-strength calculation for unsupported support units in `CombatCalculator.gd`.
- [ ] Add a GdUnit4 test in `tests/` isolating a combat between a maneuver-less attacker and a normal defender, asserting the attacker takes losses and fights at reduced strength.
- [ ] Re-baseline golden gate (`tools/validate_headless_turn.gd`) if this changes the pinned scenario.
- [ ] Update `docs/systems/ground-combat.md` with the new casualty eligibility and strength rules.
- [ ] Update `docs/STATUS.md` and add a `docs/DECISIONS.md` entry.
- [ ] Close out this plan file.
