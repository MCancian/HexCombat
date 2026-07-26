---
title: "0040: CombatRules — stop hand-threading 26 fields"
status: "Sketch"
created: "2026-07-25"
---

# Plan 0040: CombatRules — stop hand-threading 26 fields

## The problem, measured 2026-07-25

`scripts/model/CombatRules.gd` holds **26 fields**. `TurnConductor.resolve_combat_at` assigns **all 26
by hand**, and **22 of them** are copied straight off `GameData`:

```gdscript
var rules := CombatRules.new()
rules.feba_base_km = GameData.feba_base_km
rules.red_supply_pool = pool
rules.red_out_of_supply_effectiveness = GameData.red_out_of_supply_effectiveness
…22 more lines of the same shape…
```

`CombatCalculator` reads 23 of them. So every combat knob costs three edits in three files, in the
right order.

**The failure mode is silence.** Add a field to `CombatRules` and forget the assignment line, and the
field keeps its declared default — combat runs, the gate stays green, and the knob does nothing. There
is no validator watching this. `hexcombat-debugging-playbook` already carries "knob does nothing" as a
recognised symptom, which is evidence this has bitten before.

This is the same shape as the bug family plan 0034/0037 closed: a hand-maintained correspondence
between two lists, with no gate on completeness.

## Options

**(a) Registry-driven population.** A single table mapping `CombatRules` field → `GameData` source,
with `TurnConductor` looping it. Adding a knob becomes one table row. A validator asserts every
`CombatRules` field is either in the table or in an explicit "computed per hex, not from GameData"
allowlist (`red_supply_pool`, `isolated_red_brigade_ids`, `not_ashore_by_type`, `defender_terrain_modifier`).

**(b) `CombatRules.from_game_data(game_data, per_hex_overrides)`** — a named constructor owning the
copy, so `TurnConductor` stops knowing the field list at all. Simpler, no reflection, but adds a
`GameData` dependency to a model class, which `hexcombat-architecture-contract` discourages — and
`CombatRules` is in the `-s` tool compile closure, where naming the `GameData` autoload is fatal
(`tools/validate_tool_script_purity.gd`). It would have to take the values as arguments, which is the
threading problem again.

**(c) Do nothing structural; add only the completeness validator.** Cheapest. Catches the actual
failure (a field that is never assigned) without moving any code.

**Recommendation: (c) first, then (a) if it still feels worth it.** (c) is maybe an hour and removes
the silence, which is the whole risk; (a) is the nicer code but touches the combat path for no
behavioural gain. **This ordering is deliberate** — the risk here is a silent no-op knob, not the
verbosity, and the verbosity is at least honest and greppable.

Option (b) is recorded so it is not re-proposed: it is blocked by the tool-purity rule.

## Shape of (c) — the completeness validator

A `tools/validate_combat_rules_threading.gd` that:

1. Parses `scripts/model/CombatRules.gd` for its `var` names (the same textual approach
   `validate_tool_script_purity.gd` uses — no reflection needed, and it keeps working if the class
   cannot be instantiated headlessly).
2. Parses `TurnConductor.resolve_combat_at` for `rules.<field> =` assignments.
3. Fails naming any field declared but never assigned, unless it is in a documented allowlist in the
   validator itself with the reason.
4. Optionally also fails on a field assigned but never READ by `CombatCalculator` / `CombatResolver` —
   a dead knob is its own bug (report first, promote to failure only if it is clean today).

Verify it by deleting one assignment line and watching it go red, then restoring — per
`hexcombat-diff-review`, a validator that has not been seen to fail proves nothing.

## Verification

- Gate ALL PHASES GREEN. For (c), **no production code changes at all**, so no pin may move; if one
  does, something is very wrong.
- For (a), byte-stability is the whole test — the values fed to `CombatCalculator` must be identical.
  Prove it with a scratch script that builds `CombatRules` both ways and diffs all 26 fields across
  several turns, rather than trusting inspection.

## Design calls for the USER — none

No rules change, no balance change.

## Risks

- **(a) touches the combat path.** It is golden-touching by classification even though it is intended
  to be a pure move. One commit, gate green, no pin moved.
- **Reflection in (a).** `get_property_list()` on a `Resource` also returns engine properties; the
  loop must filter to script variables or it will try to assign `resource_name`.
- **Over-engineering.** If (c) lands and no knob is ever silently dropped again, (a) may simply not be
  worth doing. Revisit only when a knob is actually added.

## Dependencies / notes

- Measured at commit `ac571c5`: 26 fields declared, 26 assigned, 22 from `GameData`, 23 read by
  `CombatCalculator`.
- An earlier report of this issue said "35-field clump". That number came from a reviewer and was
  repeated without checking; the real count is 26. Recorded so the wrong figure does not propagate.
- Independent of plans 0038 and 0039. Can be done at any time; (c) does not touch `TurnConductor`, so
  it is not blocked by the dependency ceiling.
