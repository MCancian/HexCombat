---
status: Sketch
shipped: 
landed_in: 
---
# 0009 — CRBM Maneuver Attrition Calibration Knob

## Goal
Add a top-level calibration knob to `ijfs_scenario.json` that scales CRBM volley size and lethality against Maneuver Units. This allows Red to expend their excess missile inventory/sorties for higher attrition despite the 1-attack-per-target-per-day rule.

## Context & Settled Facts
- **Symptom:** In the late game, Red detects ~21% of surviving Maneuver Units via airborne ISR but destroys almost 0 targets despite executing 40–60 strikes.
- **Root Cause:** Base CRBM lethality (`probability_destroyed`) against dispersed/hiding Maneuver Units in `munition_target_pairings.json` is extremely low (~1.7% to 3.2%). Red is strictly capped at one attack per target per day (`no_reattack_within_day`), so they cannot fire multiple small volleys at the same target, leaving over 100 CRBM sorties unused daily.
- **Design Call:** Instead of bumping detection, Red will fire massive volleys (e.g., 480 missiles instead of 48 per engagement) to force higher lethality. We need a configurable knob similar to the `intel_locked_antiship_strike_bonus` (Plan 0001).

## Approach
1. **Config Additions:** Add two related fields to the root of `data/ijfs/ijfs_scenario.json`:
   - `crbm_maneuver_rounds_override` (int, e.g., 480): Overrides the default rounds expended per engagement.
   - `crbm_maneuver_strike_bonus` (float, e.g., 0.15): An additive bonus to the base `probability_destroyed`.
2. **Dynamic Loader Logic:** In `scripts/ijfs/IjfsLoaders.gd` (`load_scenario` / `load_pairings`):
   - Find pairings where `target_category == "Maneuver Units"` and `munition_id` is a CRBM (`pch191_bre6_crbm`, `pch191_bre8_crbm`).
   - Dynamically overwrite their `rounds_expended_per_engagement` with the override value.
   - Synthesize a new `strike_probability_modifiers` entry (e.g., `modifier_id: crbm_heavy_volley_maneuver_bonus`) that applies the additive bonus to these matchups, bypassing the legacy mobile caps.
3. **Validation:** Ensure that the increased ammo expenditure successfully depletes the CRBM inventory correctly in headless runs, and that the PK bonus actually yields kills.

## Checklist
- [ ] Add `crbm_maneuver_rounds_override` and `crbm_maneuver_strike_bonus` to `ijfs_scenario.json`.
- [ ] Implement synthesis logic in `IjfsLoaders.gd` to overwrite pairing expenditures and inject the lethality modifier.
- [ ] Run a test game (`tools/run_llm_game.gd` or `run_batch`) and verify the `strike_log` shows 480 rounds expended and a >0% kill rate on Maneuver Units.
- [ ] Re-baseline golden gate (`tools/validate_headless_turn.gd`) if this significantly alters the golden seed outcome.
- [ ] Update `docs/systems/ijfs.md` to document the new calibration knob.
- [ ] Close out this plan file and update `docs/STATUS.md`.
