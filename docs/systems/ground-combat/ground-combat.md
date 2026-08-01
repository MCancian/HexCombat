# Ground combat (BOOTS) — system reference

## 1. Purpose

Resolve ground combat when Red and Green brigades occupy the same hex after movement. Ported 1:1 from **TaiwanInvasionViewer** (`src/services/boots_calculator.py`, method `resolve_map_attack`). Produces force-ratio-based losses, FEBA shift, and a `CombatResult` with casualty lists.

## 2. Files & responsibilities

| File | Role |
|---|---|
| `scripts/calc/CombatCalculator.gd` | Core attack resolver — `resolve_map_attack()`: formula, rolls, loss rates, FEBA, casualty selection. Pure `static func` in `RefCounted`. |
| `scripts/CombatForces.gd` | Force aggregation — flattens brigades into maneuver-unit arrays and support-count dicts, filtering by tags. |
| `scripts/UnitStats.gd` | `TYPE_DEFS` strength/tags table + `FALLBACK_CATEGORY_DEFS`. Lookups: `strength_for_type()`, `has_tag()`. |
| `scripts/model/CombatResult.gd` | `Resource` holding strength, ratio, losses, casualties, `feba_movement_km`, and full `combat_detail` dict. |
| `scripts/model/Brigade.gd` | Brigade resource: composition of `Battalion[]`, plus `landed_qty()` / `landed_battalion_count()` — the single home of the "which battalions are actually ashore" rule (plan 0037). Unit expansion for combat lives in `CombatForces`, which delegates here. |
| `scripts/model/Battalion.gd` | Single battalion type + qty; `combat_strength` getter delegates to `UnitStats`. |
| `scripts/model/MoveOrder.gd` | Move order: `brigade_id`, `target_hex`, `mode` ("tactical"/"administrative"). |
| `scripts/model/CommitOrder.gd` | Commit order: `brigade_id`, `target_hex` (no mode — always tactical). |
| `scripts/Movement.gd` | `move_allowance()`: tactical 1/2, administrative 10/20 based on fast-slow mobility. |
| `scripts/calc/CombatResolver.gd` | Pure per-hex combat core (`resolve_at`): builds maneuver/support forces, injects supply effectiveness, calls `CombatCalculator.resolve_map_attack`, builds the `CombatSummary`. Applies nothing — read its header for the full resolver/`GameState` split rationale. |
| `scripts/GameState.gd` / `scripts/phases/TurnConductor.gd` | Thin turn orchestrator — sequences movement → contested-hex discovery → combat → FEBA retreats → …; `resolve_combat_at()` gathers per-hex contributors and delegates the dice-consuming core to `CombatResolver.resolve_at`, then applies casualties via `ForceTransitions` and FEBA/ownership. |

## 3. Combat formula (transcribed from `CombatCalculator.resolve_map_attack`)

**Inputs:** `attacker_units[]`, `defender_units[]`, `attacker_support{}`, `defender_support{}`, `defender_terrain_modifier` (floored to 1.0), `feba_base_km`.

**Strengths** (`_sum_unit_strength`):
  `maneuver = Σ(strength_for_type(unit.type) × supply_effectiveness)` for each maneuver unit.

**Support strength** (`_support_strength`):
  `support = Σ(count[type] × SUPPORT_MULTIPLIERS[type])`
  Multipliers: `artillery:0.8`, `rocket_artillery:1.2`, `cas:1.4`, `crbm:0.6`, `rotary_wing:1.3`.
  If a side has no maneuver units but has on-map support units, those support units are "unscreened". Each unscreened support battalion contributes `0.5` strength (defined by `UNSCREENED_SUPPORT_STRENGTH`), and they take the minimum-blood losses if attacked.

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

**Casualty selection** (`_select_casualties`): weighted random selection without replacement using `weighted_choice` from the `dice` interface. All battalions (maneuver and support) are eligible, weighted by their type category (maneuver = 4.0, support = 1.0). The selection is proportional to these weights.

**FEBA**:
  ```
  balance       = (attacker_strength − defender_strength) / max(attacker_strength + defender_strength, 0.1)
  roll_factor   = 0.75 + (feba_roll / 100) × 0.5
  feba_shift_km = feba_base_km × clamp(balance × 2, −2, 2) × roll_factor
  ```

**Result label**: `ratio ≥ 1.2 → "Attacker Advantage"`, `ratio ≤ 0.85 → "Defender Advantage"`, else `"Contested"`.

## 4. Casualty selection

`_select_casualties` (`scripts/calc/CombatCalculator.gd`):
- All maneuver and on-map support units are pooled together.
- Weight assignment: `MANEUVER_CASUALTY_WEIGHT = 4.0`, `SUPPORT_CASUALTY_WEIGHT = 1.0`.
- Uses `dice.weighted_choice(weights)` in a loop without replacement (selected indices have their weight set to `0.0`).
- Returns empty array if `loss_count ≤ 0` or `pool` is empty.

This exposes all support units (Field Artillery, Mechanized Artillery, Rocket Artillery, and Attack/Utility Helicopters) to combat losses instead of leaving them immortal.

## 5. Unit strength table (from `UnitStats.TYPE_DEFS`)

| Type | Strength | Tags |
|---|---|---|
| Air Assault Infantry Battalion | 1.4 | infantry, air_assault |
| Air Defense Battalion | 0.9 | air_defense |
| Airborne Combined Arms Battalion | 1.3 | infantry, airborne |
| Amphibious Infantry Battalion | 1.2 | infantry, amphibious |
| Armor Battalion | 2.0 | armor |
| Attack Helicopter Battalion | 0.5 | aviation, rotary_wing, attack |
| Combined Arms Battalion | 1.5 | maneuver, mechanized |
| Field Artillery Battalion | 0.8 | artillery |
| Infantry Battalion (Reserve) | 0.5 | infantry, reserve |
| Mechanized Airborne Combined Arms Battalion | 1.4 | infantry, airborne, mechanized |
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

`split_units(brigades, not_ashore_by_type := {})` is the single implementation: it walks each brigade's `composition` once and buckets battalions by `is_support_type()` (tag `"artillery"` or `"rotary_wing"`), emitting one `{brigade_id, type, supply_effectiveness:1.0}` dict per battalion **ashore** — `Brigade.landed_qty(battalion, brigade_not_ashore)`, NOT `battalion.qty` (see DIVERGENCE 5 in §9). `maneuver_units()` and `support_units()` are one-line views on it, kept for callers that want one half.

`support_counts(brigades, not_ashore_by_type := {})`: sums `Brigade.landed_qty(...)` by support type, routing via tags: `"rocket"` → `rocket_artillery`, `"artillery"` → `artillery`, `"rotary_wing"` → `rotary_wing`. Does not count `cas` or `crbm` — those are external munition strikes, not organic battalions.

`TurnConductor.resolve_combat_at()` gathers forces per hex via `TurnConductor.combat_contributors_for()`, which collects:
- Brigades **already in** the hex (not destroyed, not admin-moved, matching team, **and with at least one battalion ashore**).
- Brigades with a **commit order** targeting that hex (same filters, deduped by `seen`).

The "at least one battalion ashore" test is load-bearing, not a tidy-up: `CombatCalculator` floors a degenerate zero-strength side to `combat_min_effective_strength`, so a brigade holding a hex with its whole composition still at sea would otherwise fight — and inflict real casualties — with nobody on the island.

It then delegates the dice-consuming core to `CombatResolver.resolve_at` (`scripts/calc/CombatResolver.gd`) — read that class's header for the resolver/`GameState` purity split. Red is always assigned as attacker, Green as defender. Casualty application is a force-aggregate mutation: `TurnConductor` sends the casualty reports straight to `ForceTransitions.apply_battalion_casualties`, which owns the protected `Brigade.composition` / `Battalion.qty` writes and the destruction placement.

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

Canonical order (see `docs/STATUS.md` → "Turn resolution order"; each phase's logic lives in its own resolver under `scripts/calc/` or `scripts/interleaved/`, sequenced by the thin `GameState` orchestrator):

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
 10. resolve_supply_turn()         — Red DOS (SupplyBill + SupplyTransitions)
 11. resolve_frontline_phase()     — D5 front-line redistribution (FrontlineResolver; user-triggered, not auto-run every turn)
 12. resolve_cleanup_phase()       — Per-turn flag reset + victory census (CleanupResolver)
```

Combat sits at step 7, after all movement and before FEBA retreats/ownership changes; front-line sits between combat/supply and cleanup.

## 9. TIV-port fidelity notes

**Oracle:** `TaiwanInvasionViewer/src/services/boots_calculator.py`, method `resolve_map_attack`.

**Core formula match:** Near line-for-line identical — same loss-rate formulas, same clamps (0.05–0.45 / 0.05–0.50), same support multipliers, same FEBA math, same min-one-loss rule, same strength floor at 0.1. (Unlike TIV, HexCombat removes the non-artillery casualty filter and pools all maneuver and support units together).

**DIVERGENCE 1 — RNG algorithm.** TIV uses `numpy.random.default_rng(seed)` with `rng.integers(1,101)` and `rng.choice(a, size=k, replace=False)`. HexCombat uses `SeededDice` (`scripts/support/SeededDice.gd`), which wraps Godot's `RandomNumberGenerator` (`randi_range(1,100)` and Fisher-Yates partial shuffle for `choose_indices`). The roll *sequence* (attacker-loss → defender-loss → feba → casualty indices) matches TIV's same-sequence, but the RNG *algorithm* differs — HexCombat is **not value-identical** to TIV for a given seed. It is self-consistent only.

**DIVERGENCE 2 — combat_detail shape.** TIV includes `"support_power_breakdown"` *and* `"support_unit_count"` per side. HexCombat (`scripts/calc/CombatCalculator.gd`) uses key `"support_breakdown"` and includes `"support_unit_count"`. Minor shape divergence.

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
to match TIV's `_load_feba_base_km`) and passed by `TurnConductor.resolve_combat_at`. The golden pin
that moved when this landed lives in `tools/validate_headless_turn.gd` — that validator's PASS
line is truth, not this doc.

**DIVERGENCE 5 — only LANDED battalions fight (2026-07-25, USER call, plan 0037).** TIV expands a
brigade's whole `composition` into combat units. HexCombat subtracts the battalions that are not
ashore — at sea, on the mainland awaiting a hull, or waiting to fly — because a brigade's `hex_id` is
set by its FIRST landed battalion while the rest of the roster is still off-map. The rule lives in
`Brigade.landed_qty` and reaches combat through `CombatForces` (all three functions, `support_counts`
included) via `CombatRules.not_ashore_by_type`, which `TurnConductor` computes ONCE per turn before
the combat loop so two hexes cannot disagree about who is present. A brigade with zero battalions
ashore is excluded from `combat_contributors_for` entirely: `CombatCalculator` floors a degenerate
zero-strength side to `combat_min_effective_strength`, so an empty contributor would fight with
phantom strength. Red supply (`active_red_battalion_units`) applies the same subtraction, so a
brigade's fighting strength and its ration bill always describe the same battalions. Green is
unaffected — it has no off-map pools. Pins that moved: `tools/validate_dos_consumption.gd` and
`tools/validate_cleanup.gd` (their PASS lines are truth, not this doc).

**Terrain modifiers — ACTIVE since 2026-07-09 (Track F).** The live path is
`TurnConductor.defender_combat_modifier()` (reads `GameData.get_terrain(hex_id).defender_modifier`,
falling back to `1.0` for an unclassified hex) → passed as `defender_terrain_modifier` into
`CombatResolver.resolve_at` → `CombatCalculator.resolve_map_attack`. Full terrain data model,
per-class values, and rendering: `docs/systems/terrain.md`.

## The combat-knob correspondence

Every tunable the combat maths reads arrives on a `CombatRules` instance that
`TurnConductor.resolve_combat_at` fills in by hand, one line per field, most of them copied straight off
the same-named `GameData` property. Adding a knob is therefore three edits in three files, in order.

- **Enforcement**: `tools/validate_combat_rules_threading.gd` runs in the gate and fails if a
  `CombatRules` field is declared but not populated by `TurnConductor.resolve_combat_at`, is fed from a
  differently-named `GameData` property, is written in a second place, or is never read by
  `CombatCalculator` / `CombatResolver`. Without it, a forgotten assignment line left the field on its
  declared default: combat ran, the gate stayed green, and the knob did nothing.
- **The four fields not copied from `GameData`** — `red_supply_pool`, `isolated_red_brigade_ids`,
  `not_ashore_by_type`, `defender_terrain_modifier` — are computed per turn or per hex. They are listed
  as exceptions in the validator with the reason, and the validator also fails if one of them silently
  becomes a plain `GameData` copy.
- **`CombatRules` defaults are not the scenario values** and deliberately differ from `GameData` for
  `feba_base_km` and `red_out_of_supply_effectiveness`. They are the neutral values the unit tests
  construct against, so changing one is a golden-drift event; the validator does not check parity for
  exactly this reason.

## 10. State & authority

This subsystem mutates the **`force`** aggregate. Its designated authority is `ForceTransitions`, which applies all casualty and FEBA movement writes.
- **Outcome/receipt types:** `ForceCasualtyReceipt`, `ForcePlacementReceipt`.
- **Manifest:** [tools/mutation_authority_manifest.json](../../../tools/mutation_authority_manifest.json).

**Rules:**
- Casualties shrink the roster exactly by the requested counts.
- Movement updates `Brigade.hex_id` and the map index in one transaction.
