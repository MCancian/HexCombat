# Air Insertion — Status

**PLAAF air insertion (plan 0032, USER call)** — a non-amphibious path onto Taiwan:
Red flies battalions from an off-map pool onto **any passable hex** (enemy-held included), capped
per turn per lift class. The plan assumed the OOB already had airborne units; it did not (945 PLA
BNs, zero airborne), so the same work **adds the PLAAF Airborne Corps** — 6 brigades / 50 BNs
appended to `pla_ground_forces.json` (3 light airborne, 2 mechanized airborne, 1 air assault; USER
split), plus two `UnitStats` types. `LiftClass` maps OOB `nato_type` → lift class and keeps the
corps out of the sealift follow-on pool. Attrition is keyed on Taiwan's air defences —
`0.75 × effective_ad_health`, **plus** `0.25 × MANPADS threat fraction` for rotary-wing lift
(the MANPADS layer is excluded from AD health yet is what engages helicopters) — rolled per
battalion on the `air_insertion:<turn>` substream. Every loss also destroys one battalion of lift
**permanently**. Landed brigades fight **out of supply** until a Red-held corridor links them to a
beach or port. New `air_insert` order (Red-only) in the LLM/observation contract; new
`air_assault` policy (selfplay_default + seize-the-nearest-port doctrine). Scenario block
`red_air_insertion` — **absent by default, so the phase is inert and golden stays byte-stable**;
only `data/scenarios/red_airborne.json` opts in (`scenario_default` deliberately untouched).
Phase runs after IJFS (attrition reads that turn's air-defence picture) and before movement (an
opposed drop is fought the same turn). Coverage: `tools/validate_air_insertion.gd` +
`tests/air_insertion_resolver_test.gd`, `tests/air_insertion_builder_test.gd`, `tests/air_insertion_order_test.gd`. Detail: `docs/systems/air-insertion/air-insertion.md`.
**Measured (30 seeds/cell, `red_airborne`, 30 turns):** against the plan-0029
mobilizing defender (12 brigades held back — the strongest defence measured to date, which held
Red to 83%), the air path takes Red to **97%** and halves median decision from turn 21 to 11.
Lift *quantity* is not the constraint: 3 BN/turn is as decisive as 14 (step, not slope). It is
this strong because the IJFS warmup has already cleared the sky — a typical drop costs ~9%, so
the permanent-airframe brake barely engages. Report:
`docs/reports/2026-07-24-airborne-insertion-sweep.md`.
