# Ground Combat — Status

**Ground combat** (BOOTS slice M0–M7): movement, commit, combat resolution, FEBA, casualties,
retreat, hex ownership. Defender terrain modifier is active: `CombatResolver.resolve_at`
receives the defended hex's `defender_modifier` via `TurnConductor.defender_combat_modifier`.
**Support units** are mortal and included in casualty selection (weighted 1:4 vs maneuver units). If a side has only support units, they are "unscreened", contributing 0.5 strength each and taking losses. Golden invariant: the scripted beach-1 fight is byte-stable per gate; the pinned values live in
`tools/validate_headless_turn.gd` (re-baseline history: `docs/DECISIONS.md` →
`docs/archive/PLAN.md`).
**Only battalions ASHORE fight (plan 0037, USER call 2026-07-25)** — a brigade's `hex_id` is set by
its FIRST landed battalion, so `CombatForces` subtracts the off-map pools per battalion type
(`Brigade.landed_qty` is the single home of the rule; `TurnConductor` computes the map ONCE per turn
into `CombatRules.not_ashore_by_type` so two hexes cannot disagree). A brigade with nothing ashore
is excluded from `combat_contributors_for` entirely — otherwise `CombatCalculator`'s
`combat_min_effective_strength` floor would let it fight with phantom strength. Red supply applies
the same subtraction, so fighting strength and the ration bill always name the same battalions.
Green is unaffected (no pools). Deliberate re-baseline: `validate_dos_consumption`,
`validate_cleanup`. Coverage: `tests/landed_battalions_test.gd`.
