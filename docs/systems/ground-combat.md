# Ground combat (BOOTS) — system reference

## 1. Purpose

Resolve ground combat when Red and Green brigades occupy the same hex after movement. Ported 1:1 from **TaiwanInvasionViewer** (`src/services/boots_calculator.py`, method `resolve_map_attack`). Produces force-ratio-based losses, FEBA shift, and a `CombatResult` with casualty lists.

## 2. Files & responsibilities

| File | Role |
|---|---|
| `scripts/CombatCalculator.gd` | Core attack resolver — `resolve_map_attack()`: formula, rolls, loss rates, FEBA, casualty selection. Pure `static func` in `RefCounted`. |
| `scripts/CombatForces.gd` | Force aggregation — flattens brigades into maneuver-unit arrays and support-count dicts, filtering by tags. |
| `scripts/UnitStats.gd` | `TYPE_DEFS` strength/tags table + `FALLBACK_CATEGORY_DEFS`. Lookups: `strength_for_type()`, `has_tag()`. |
| `scripts/model/CombatResult.gd` | `Resource` holding strength, ratio, losses, casualties, `feba_movement_km`, and full `combat_detail` dict. |
| `scripts/model/Brigade.gd` | Brigade resource with `to_combat_units()`, composition of `Battalion[]`. |
| `scripts/model/Battalion.gd` | Single battalion type + qty; `combat_strength` getter delegates to `UnitStats`. |
| `scripts/model/MoveOrder.gd` | Move order: `brigade_id`, `target_hex`, `mode` ("tactical"/"administrative"). |
| `scripts/model/CommitOrder.gd` | Commit order: `brigade_id`, `target_hex` (no mode — always tactical). |
| `scripts/Movement.gd` | `move_allowance()`: tactical 1/2, administrative 10/20 based on fast-slow mobility. |
| `scripts/resolvers/CombatResolver.gd` | Pure per-hex combat core (`resolve_at`): builds maneuver/support forces, injects supply effectiveness, calls `CombatCalculator.resolve_map_attack`, builds the `CombatSummary`. Applies nothing — read its header for the full resolver/`GameState` split rationale. |
| `scripts/GameState.gd` | Thin turn orchestrator — `resolve_turn()` sequences the resolvers (movement → contested-hex discovery → combat → FEBA retreats → …); `_resolve_combat_at()` gathers per-hex contributors and delegates the dice-consuming core to `CombatResolver.resolve_at`, then applies casualties/FEBA/ownership. |

## 3. Combat formula (transcribed from `CombatCalculator.resolve_map_attack`)

**Inputs:** `attacker_units[]`, `defender_units[]`, `attacker_support{}`, `defender_support{}`, `defender_terrain_modifier` (floored to 1.0), `feba_base_km`.

**Strengths** (`_sum_unit_strength`):
  `maneuver = Σ(strength_for_type(unit.type) × supply_effectiveness)` for each maneuver unit.

**Support strength** (`_support_strength`):
  `support = Σ(count[type] × SUPPORT_MULTIPLIERS[type])`
  Multipliers: `artillery:0.8`, `rocket_artillery:1.2`, `cas:1.4`, `crbm:0.6`, `rotary_wing:1.3`.

**Final strengths**:
  ```
  attacker_unmodified  = attacker_maneuver + attacker_support_strength
  defender_unmodified  = defender_maneuver + defender_support_strength
  attacker_strength    = attacker_unmodified                     [floored to 0.1 if ≤ 0]
  defender_strength    = defender_unmodified × terrain_modifier  [floored to 0.1 if ≤ 0; terrain min 1.0]
  ```
  Ratios: `unmodified_ratio = attacker_unmodified / defender_unmodified`, `ratio = attacker_strength / defender_strength`. Defender-unmodified also floored to 0.1 for the ratio.

**Loss rolls** (order: attacker-roll → defender-roll → feba-roll):
  ```
  attacker_loss_roll  = dice.roll_d100()
  defender_loss_roll  = dice.roll_d100()
  feba_roll           = dice.roll_d100()
  ```

**Loss rates**:
  ```
  attacker_loss_rate  = clamp(0.20 − (ratio − 1) × 0.08 + (attacker_loss_roll − 50) / 1000,   0.05, 0.45)
  defender_loss_rate  = clamp(0.20 + (ratio − 1) × 0.10 + (defender_loss_roll − 50) / 1000,   0.05, 0.50)
  ```

**Loss counts**: `losses = round(unit_count × loss_rate)`.

**Min-one-loss rule**: if both sides present and both loss-counts are 0, the weaker side gets 1 loss (ratio ≥ 1 → defender loses 1, else attacker loses 1).

**Casualty selection** (`_select_casualties`): filter out units tagged `"artillery"`, then `dice.choose_indices(eligible.size(), min(loss_count, eligible.size()))` without replacement. Non-artillery only.

**FEBA**:
  ```
  balance       = (attacker_strength − defender_strength) / max(attacker_strength + defender_strength, 0.1)
  roll_factor   = 0.75 + (feba_roll / 100) × 0.5
  feba_shift_km = feba_base_km × clamp(balance × 2, −2, 2) × roll_factor
  ```

**Result label**: `ratio ≥ 1.2 → "Attacker Advantage"`, `ratio ≤ 0.85 → "Defender Advantage"`, else `"Contested"`.

## 4. Casualty selection

`_select_casualties` (`CombatCalculator.gd`):
- Filters `units` to those whose `UnitStats.tags_for_type(type)` does **not** contain `"artillery"`.
- Uses `dice.choose_indices(eligible.size(), min(loss_count, eligible.size()))` — random without replacement.
- Returns empty array if `loss_count ≤ 0` or `eligible` is empty.

This excludes Field Artillery, Mechanized Artillery, and Rocket Artillery battalions from being selected as losses (they contribute support instead).

## 5. Unit strength table (from `UnitStats.TYPE_DEFS`)

| Type | Strength | Tags |
|---|---|---|
| Air Assault Infantry Battalion | 1.4 | infantry, air_assault |
| Air Defense Battalion | 0.9 | air_defense |
| Amphibious Infantry Battalion | 1.2 | infantry, amphibious |
| Armor Battalion | 2.0 | armor |
| Attack Helicopter Battalion | 0.5 | aviation, rotary_wing, attack |
| Combined Arms Battalion | 1.5 | maneuver, mechanized |
| Field Artillery Battalion | 0.8 | artillery |
| Infantry Battalion (Reserve) | 0.5 | infantry, reserve |
| Mechanized Artillery Battalion | 1.3 | artillery, mechanized |
| Mechanized Infantry Battalion | 1.5 | infantry, mechanized |
| Reconnaissance Battalion | 0.7 | recon |
| Rocket Artillery Battalion | 1.3 | artillery, rocket |
| Service Support Battalion | 0.3 | support, service_support |
| Special Forces Battalion | 1.8 | special_forces |
| Support Battalion | 0.3 | support |
| Tank Battalion | 2.0 | armor |
| Utility Helicopter Battalion | 0.5 | aviation, rotary_wing, utility |

Fallback categories (`FALLBACK_CATEGORY_DEFS`) provide strength/tag values for unknown types via substring matching; a warning is emitted.

## 6. Force aggregation (`CombatForces`)

`maneuver_units(brigades)`: iterates each brigade's `composition`, skips battalions where `is_support_type()` returns true (tag `"artillery"` or `"rotary_wing"`), and emits one `{brigade_id, type, supply_effectiveness:1.0}` dict per `battalion.qty`.

`support_counts(brigades)`: sums `battalion.qty` by support type, routing via tags: `"rocket"` → `rocket_artillery`, `"artillery"` → `artillery`, `"rotary_wing"` → `rotary_wing`. Does not count `cas` or `crbm` — those are external munition strikes, not organic battalions.

`GameState._resolve_combat_at()` gathers forces per hex via `_combat_contributors_for()`, which collects:
- Brigades **already in** the hex (not destroyed, not admin-moved, matching team).
- Brigades with a **commit order** targeting that hex (same filters, deduped by `seen`).

It then delegates the dice-consuming core to `CombatResolver.resolve_at` (`scripts/resolvers/CombatResolver.gd`) — read that class's header for the resolver/`GameState` purity split. Red is always assigned as attacker, Green as defender.

## 7. Movement

Modes (`Movement.gd`): `"tactical"` and `"administrative"`.

Allowance (`move_allowance()`):
| Mode | Slow (leg) | Fast (mechanized/armor/tank) |
|---|---|---|
| Tactical | 1 hex | 2 hexes |
| Administrative | 10 hexes | 20 hexes |

Fast mobility (`is_fast_mobility()`): brigade's `nato_type` string contains `"mechanized"`, `"armor"`, or `"tank"` (case-insensitive). Composition is **ignored** — a deliberate divergence from TIV (see the note in `Movement.gd`).

Administrative-moved brigades cannot commit to combat that turn.

## 8. Turn flow (`GameState.resolve_turn`)

Canonical order (see `docs/STATUS.md` → "Turn resolution order"; each phase's logic lives in its own resolver under `scripts/resolvers/`, sequenced by the thin `GameState` orchestrator):

```
  1. resolve_ijfs_turn()           — Red joint/air-missile fires (IjfsResolver)
  2. resolve_antiship_turn()       — Green anti-ship + mines (AntishipResolver)
  3. resolve_offload_turn()        — Amphibious landing (OffloadResolver)
  4. _apply_move_orders(RED)       — Planned movement
  5. _apply_move_orders(GREEN)
  6. _find_contested_hexes()       — Hexes with both teams present
  7. _resolve_combat_at(hex)       — Per contested hex (CombatResolver → CombatCalculator)
  8. _apply_feba_retreats()        — Push defenders back by feba_km
  9. GameData.recompute_hex_ownership()
 10. resolve_supply_turn()         — Red DOS (SupplyResolver)
 11. resolve_frontline_phase()     — D5 front-line redistribution (FrontlineResolver; user-triggered, not auto-run every turn)
 12. resolve_cleanup_phase()       — Per-turn flag reset + victory census (CleanupResolver)
```

Combat sits at step 7, after all movement and before FEBA retreats/ownership changes; front-line sits between combat/supply and cleanup.

## 9. TIV-port fidelity notes

**Oracle:** `TaiwanInvasionViewer/src/services/boots_calculator.py`, method `resolve_map_attack`.

**Core formula match:** Near line-for-line identical — same loss-rate formulas, same clamps (0.05–0.45 / 0.05–0.50), same support multipliers, same FEBA math, same min-one-loss rule, same non-artillery casualty filter, same strength floor at 0.1.

**DIVERGENCE 1 — RNG algorithm.** TIV uses `numpy.random.default_rng(seed)` with `rng.integers(1,101)` and `rng.choice(a, size=k, replace=False)`. HexCombat uses `SeededDice` (`scripts/SeededDice.gd`), which wraps Godot's `RandomNumberGenerator` (`randi_range(1,100)` and Fisher-Yates partial shuffle for `choose_indices`). The roll *sequence* (attacker-loss → defender-loss → feba → casualty indices) matches TIV's same-sequence, but the RNG *algorithm* differs — HexCombat is **not value-identical** to TIV for a given seed. It is self-consistent only.

**DIVERGENCE 2 — combat_detail shape.** TIV includes `"support_power_breakdown"` *and* `"support_unit_count"` per side. HexCombat (`CombatCalculator.gd`) uses key `"support_breakdown"` and omits `"support_unit_count"`. Minor shape divergence.

**DIVERGENCE 3 — unit strength values (✅ RESOLVED 2026-06-29 — keep HexCombat's table; see `docs/archive/PORT_FIDELITY_DECISIONS.md`).**
Ratified as the intended design. Note re helicopters: `rotary_wing` (and `artillery`) battalions are
combat **support**, not `maneuver_units` (`CombatForces.gd`) — in both HexCombat and TIV — so their
maneuver-strength value is never used; the apparent 0.5-vs-1.4 helicopter mismatch has no combat effect. Verified by calling TIV's own
calculator: TIV's `_map_type_to_strength_key()` only maps a few lowercase short forms, so the **full
battalion-name** `Type` strings the OOB actually carries fall through to the `1.0` default. Result —
**12 of the 17 OOB battalion types resolve differently**: TIV gives almost every maneuver unit `1.0`
(Armor, Tank, Combined Arms, Mech Inf, Amphibious, Air Assault, Recon, Air Defense, Support, Service
Support, Reserve all = 1.0), and only Field Artillery (0.8), Mech/Rocket Artillery (1.3), SOF (1.8),
and **Attack/Utility Helicopter (1.4)** map. HexCombat's `TYPE_DEFS` instead differentiates them
(Armor/Tank 2.0, Combined Arms/Mech Inf 1.5, Amphibious 1.2, Air Assault 1.4, Recon 0.7, Air Defense
0.9, Support 0.3, Reserve 0.5) and gives **helicopters 0.5**. HexCombat effectively ported TIV's
*intended* table (`unit_combat_strength` by category) rather than its buggy runtime output. TIV has no
pytest pinning strength values, so neither matches nor contradicts a TIV test. Helicopters are the one
case where HexCombat also diverges from TIV's *intent* (0.5 vs 1.4).

**DIVERGENCE 4 — feba_base_km (✅ RESOLVED 2026-06-29 — now scenario-configurable, default 3.5).**
Was hardcoded `2.0`; now `GameData.feba_base_km` (loaded from scenario `feba_base_km`, default **3.5**
to match TIV's `_load_feba_base_km`) and passed by `GameState._resolve_combat_at`. The golden pin
that moved when this landed lives in `tools/validate_headless_turn.gd` — that validator's PASS
line is truth, not this doc.

**Terrain modifiers — ACTIVE since 2026-07-09 (Track F).** `CombatCalculator.gd`'s own
`TERRAIN_MODIFIERS` dict is dead code (superseded, left untouched — see
`.claude/skills/hexcombat-config-and-knobs`). The live path is
`GameState._defender_combat_modifier()` (reads `GameData.get_terrain(hex_id).defender_modifier`,
falling back to `1.0` for an unclassified hex) → passed as `defender_terrain_modifier` into
`CombatResolver.resolve_at` → `CombatCalculator.resolve_map_attack`. Full terrain data model,
per-class values, and rendering: `docs/systems/terrain.md`.
