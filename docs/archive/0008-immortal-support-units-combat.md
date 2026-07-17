---
status: ✅ Shipped
shipped: 2026-07-17
landed_in: docs/systems/ground-combat.md, docs/STATUS.md, docs/DECISIONS.md
---
# 0008 — Immortal Support Units in Ground Combat

Design settled (USER calls 2026-07-17). Ready to implement — the spec below is complete; do not
re-open the design decisions.

## Goal
Fix a ground combat defect where brigades that have lost all maneuver units but retain support
units (like artillery) become immortal in ground combat.

## Context & Settled Facts
- **Symptom:** In game records (e.g., `game_20260710.viewer.json`), the Red ashore census
  plateaus at exactly 4 battalions from Turn 11 to Turn 30. Red's ground combat losses drop to 0
  permanently, yet Red continues to initiate combat.
- **Root cause (verified 2026-07-17):**
  - `CombatForces.maneuver_units` (`scripts/CombatForces.gd:9`) drops every battalion whose type
    is `is_support_type` (tags `artillery` or `rotary_wing`), so support units never enter the
    `attacker_units`/`defender_units` arrays.
  - `CombatCalculator._loss_counts` (`scripts/CombatCalculator.gd:167`) bases casualty counts on
    those arrays' sizes: 0 maneuver units → `round(0 × rate) = 0` losses, and the minimum-blood
    rule is gated on `attacker_count > 0 and defender_count > 0`.
  - `CombatCalculator._select_casualties` (`scripts/CombatCalculator.gd:268`) additionally
    filters out `artillery`-tagged units (redundant today; remove with this change).
  - Net: a force of purely support units attacks every turn but can never take casualties.
- **Support strength today:** support enters combat power only via `SUPPORT_MULTIPLIERS`
  (`scripts/CombatCalculator.gd:4`): artillery 0.8, rocket_artillery 1.2, cas 1.4, crbm 0.6,
  rotary_wing 1.3 — per-count, computed in `_support_strength` from the `support_counts` dicts.
- **cas / crbm are off-map:** they are never battalions inside brigades
  (`CombatForces.support_counts` initializes them to 0 and nothing in the game path populates
  them; `CombatResolver.resolve_at` is the sole in-game caller of `resolve_map_attack`). They
  cannot take ground casualties by construction and are OUT OF SCOPE.
- **Casualty application:** `GameState._apply_casualty` (`scripts/GameState.gd:961`) decrements a
  battalion by `{brigade_id, type}` — it already works for support types as long as casualty
  dicts have the same shape as maneuver unit dicts.
- **Do-not-relitigate:** Green's inability to counterattack and destroy these units is a separate
  known design gap (see Plan 0003). This plan focuses solely on support units in combat.

## Design decisions (USER, 2026-07-17 — final)
1. **Casualty exposure (screen model): quarter weight.** In casualty selection, a support unit
   has ¼ the selection weight of a maneuver unit (maneuver weight 4.0, support weight 1.0). The
   maneuver screen protects support, but counter-battery/deep fires still reach it.
2. **Scope: all on-map support** — `artillery`, `rocket_artillery`, `rotary_wing` (i.e.
   everything `CombatForces.is_support_type` matches). cas/crbm stay immune (off-map).
3. **Unscreened strength: flat 0.5 per support unit.** When a side has 0 maneuver units but >0
   support units, each support unit fights at 0.5 combat strength (half of Light Infantry's 1.0),
   scaled by its `supply_effectiveness` like any maneuver unit. This **replaces** that side's
   on-map `SUPPORT_MULTIPLIERS` contribution (do not add both); any cas/crbm multiplier
   contribution (always 0 in-game) still adds.
4. **Loss-count basis: total units.** `_loss_counts` unit counts become
   `maneuver + on-map support` per side. A 4-battalion support-only force takes losses like any
   4-battalion force, and the minimum-blood rule now covers support-only forces.

## Implementation spec

### 1. `scripts/CombatForces.gd` — new `support_units()`
Add, mirroring `maneuver_units` exactly but keeping only support battalions:

```gdscript
static func support_units(brigades: Array) -> Array:
    # same loop as maneuver_units, but `if not is_support_type(battalion.type): continue`
    # same dict shape: {"brigade_id", "type", "supply_effectiveness": 1.0}
```

Do NOT change `maneuver_units` or `support_counts`.

### 2. `scripts/resolvers/CombatResolver.gd` — build & pass support unit arrays
In `resolve_at` (`scripts/resolvers/CombatResolver.gd:38`):
- Build `attacker_support_units := CombatForces.support_units(attacker_brigades)` (same for
  defender).
- Run `inject_supply_effectiveness` on the support arrays too (same calls as for maneuver —
  Red DOS degradation applies to support units identically).
- Pass both arrays to `resolve_map_attack` as new trailing arguments.

### 3. `scripts/CombatCalculator.gd` — the core change
New constants (named per code-quality magic-number policy):

```gdscript
const UNSCREENED_SUPPORT_STRENGTH := 0.5   # half Light Infantry (1.0); USER call 2026-07-17
const MANEUVER_CASUALTY_WEIGHT := 4.0      # quarter-weight screen: support picked 1/4 as often
const SUPPORT_CASUALTY_WEIGHT := 1.0
```

**`resolve_map_attack` signature** — append two params with defaults (keeps the two
calculator-direct test call sites compiling):

```gdscript
attacker_support_units: Array = [],
defender_support_units: Array = [],
```

**Strength (`_force_strengths`)** — pass the support-unit arrays in. Per side:
- If maneuver array non-empty: unchanged (maneuver Σ + `_support_strength(support_counts)`).
- If maneuver array empty and support-unit array non-empty: side support strength =
  `Σ (UNSCREENED_SUPPORT_STRENGTH × unit supply_effectiveness)` over the support-unit array,
  **plus** `_support_strength` computed over a copy of the support dict with `artillery`,
  `rocket_artillery`, `rotary_wing` zeroed (keeps cas/crbm well-defined for direct callers).
- Surface both in the returned dict so `combat_detail` can report which mode applied.

**Loss counts (`_loss_counts`)** — call with
`attacker_units.size() + attacker_support_units.size()` (same for defender). Body unchanged; the
minimum-blood rule now fires for support-only forces automatically.

**Casualty selection (`_select_casualties`)** — rework:
- New signature: `(maneuver_units: Array, support_units: Array, loss_count: int, dice: Dice)`.
- Pool = maneuver units then support units (order matters for determinism). Delete the old
  `artillery`-tag filter entirely.
- Weights array aligned with the pool: `MANEUVER_CASUALTY_WEIGHT` per maneuver unit,
  `SUPPORT_CASUALTY_WEIGHT` per support unit.
- `select_count = min(loss_count, pool.size())`; if `select_count <= 0` return `[]`.
- Draw **without replacement**: loop `select_count` times; each iteration calls
  `dice.weighted_choice(weights)`, appends `pool[index]` to casualties, then sets
  `weights[index] = 0.0`. Do NOT use `dice.weighted_choices()` — it draws WITH replacement
  (`scripts/SeededDice.gd:66`) and would double-kill units.
- Dice-stream contract: draw order stays attacker-selection then defender-selection, after the
  three d100 rolls. The stream composition changes (one `choose_indices` call per side becomes
  `select_count` × `weighted_choice` calls) — golden re-baseline is expected and required.

**`combat_detail`** — additive fields only (don't rename existing keys, minimizes downstream
churn): per side add `support_unit_count` and `unscreened: bool` (true when that side fought
maneuver-less). Existing `maneuver_unit_count` etc. unchanged.

### 4. Tests
- **New test `tests/combat_support_casualties_test.gd`** (GdUnit4, patterns from
  `tests/combat_resolution_test.gd` — `_make_brigade` / ScriptedDice):
  - Maneuver-less attacker (e.g. 4× field artillery) vs normal defender: attacker takes ≥1 loss
    (minimum-blood), attacker strength = 4 × 0.5 = 2.0 (assert via
    `combat_detail.attacker.total_combat_power_unmodified` with `unscreened: true`), casualties
    carry support types and `_apply_casualty` decrements the brigade.
  - Mixed force: scripted `weighted` picks prove a support unit CAN be selected and that weights
    are 4.0/1.0 in pool order.
  - Supply effectiveness scales unscreened strength (mirror
    `tests/supply_combat_effectiveness_test.gd`).
- **Existing tests that will break — expected, update them:**
  - `tests/combat_golden_test.gd` — pins `resolve_map_attack` outputs with SeededDice; casualty
    selection now consumes `weighted_choice` draws instead of `choose_indices`. Re-pin the
    expected values after the change (this is the calculator-level golden; re-derive, don't
    fudge).
  - `tests/combat_resolution_test.gd` and any suite scripting ScriptedDice `choices` for combat
    casualties: selection now consumes the `weighted` script array
    (`tests/helpers/ScriptedDice.gd:58`), one index per casualty. Update constructor args.
- **Golden gate:** dice stream changes ⇒ `tools/validate_headless_turn.gd` golden WILL drift.
  Re-baseline per `hexcombat-change-control` (this is a sanctioned behavior change; record the
  re-baseline rationale in the commit message). Regenerate dependent fixtures
  (`docs/examples/llm_result_after_turn.json` etc.) via the exporters in
  `hexcombat-run-and-operate`.

### 5. Out of scope
- cas/crbm ground casualties (off-map by construction).
- Whether support-only brigades should be allowed to *initiate* attacks (separate design
  question; leave behavior as-is).
- Making the new constants data-driven knobs (plan 0009 territory; USER call).

## Checklist
- [x] Determine design for support-unit casualties (USER call 2026-07-17): quarter-weight
  screen; all on-map support types; flat 0.5 unscreened strength (replaces multipliers); loss
  counts use total units.
- [x] `CombatForces.support_units()` added.
- [x] `CombatResolver.resolve_at` builds/injects/passes support-unit arrays.
- [x] `CombatCalculator`: constants, signature, `_force_strengths` unscreened branch,
  `_loss_counts` total basis, weighted no-replacement `_select_casualties`, `combat_detail`
  additive fields.
- [x] New `tests/combat_support_casualties_test.gd` green; `combat_golden_test.gd` re-pinned;
  ScriptedDice-scripted combat suites updated.
- [x] Full gate `bash tools/run_all_tests.sh` (Linux) / `pwsh -File tools/run_all_tests.ps1`
  (Windows) — ALL PHASES GREEN; golden re-baselined with rationale.
- [x] Update `docs/systems/ground-combat.md` (casualty eligibility, quarter-weight screen,
  unscreened 0.5 rule).
- [x] `docs/STATUS.md` + `docs/DECISIONS.md` entry (the four USER calls above).
- [x] Close out this plan file per `hexcombat-docs-and-writing`.
