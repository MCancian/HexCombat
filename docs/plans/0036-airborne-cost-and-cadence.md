---
title: "0036: Airborne cost and sortie cadence"
status: "Sketch"
created: "2026-07-25"
---

# Plan 0036: Airborne cost and sortie cadence

**USER call 2026-07-25**, answering the plan-0032 balance question left open in
`docs/plans/BACKLOG.md`: *"Let's double baseline attrition. We can also gate airborne a little bit
by transport capacity. I could see China being able to only conduct 1 sortie every 2 days."*

## The problem this closes

Plan 0032 shipped the air path and measured it as close to free. Attrition is
`max_attrition_at_full_ad × effective_ad_health`, and the IJFS warmup has already driven Taiwan's
effective AD health to ~0.24 by turn 1 and ~0.12 by turn 4 — so a typical drop costs ~9–18% and the
permanent-airframe brake, the mechanic's intended self-limiting feature, barely engages. Red goes
83% → 97% against the strongest measured defence, and lift *quantity* saturates: 3 BN/turn is as
decisive as 14, which is why the cap is not the lever. Evidence:
`docs/reports/2026-07-24-airborne-insertion-sweep.md`.

The USER's answer applies two independent brakes:

1. **Cost** — double the baseline attrition coefficient, so every drop is bloodier and the airframe
   ledger actually erodes.
2. **Cadence** — a lift class cannot fly every turn. Transport aviation needs a turnaround; at one
   turn = one day, "1 sortie every 2 days" is an interval of 2.

They are deliberately different in kind. Cost scales with how well Red has suppressed the air
defences (a reward for the fires campaign). Cadence does not scale with anything — it is a hard
throughput ceiling that no amount of SEAD buys off, which is what makes it robust against the
saturation finding.

## Objective 1 — double baseline attrition

`max_attrition_at_full_ad`: **0.75 → 1.5** in `data/scenarios/red_airborne.json`.

This is a scenario-value change, not a code change: the coefficient is already a
`scenario:`-prefixed registry knob and `attrition_rate()` already clamps its result to [0, 1].

What it does in the regime the game actually occupies:

| `effective_ad_health` | today | doubled |
|---|---|---|
| 1.00 (intact, never observed post-warmup) | 75% | **100%** (clamped) |
| 0.244 (turn 1, measured) | 18.3% | **36.6%** |
| 0.12 (turn 4, measured) | 9.0% | **18.0%** |

**Two ambiguities, both settled here so implementation never stalls on them:**

- **"Baseline attrition" = the single coefficient `max_attrition_at_full_ad`.**
  `manpads_max_attrition` (0.25, the rotary-wing surcharge) is **left at 0.25**. The doubled term is
  the AD-health-keyed one both classes share; the surcharge rides on top of it unchanged, so class
  relativity shifts slightly toward fixed-wing being the riskier lift early. Doubling it too is a
  one-value edit if the USER later wants it.
- **The clamp eats the top of the curve; ship it anyway.** The original 0.75 was anchored on a
  USER-supplied number — an intact air defence system destroys 75% of an inserting packet. Doubling
  replaces that anchor with "an intact system destroys everything, and anything above 0.667 AD health
  is equally total." That region is unreachable in play (the warmup always fires first), so it costs
  nothing operationally. **Implement the literal doubling — do not stop to ask.** Rewrite
  `docs/systems/air-insertion.md` §5 (the anchor paragraph, currently lines 94–98) so the doc states
  the new rationale instead of contradicting the value, and update §4's config example (line 76) in
  the same commit. If the USER, seeing the sweep, wants the 75%-at-intact anchor back while still
  doubling the cost of a *realistic* drop, the alternative is a constant floor term (`min_attrition`,
  paid regardless of AD health) instead of a doubled slope — that also cures "a cleared sky is free"
  more directly. Raise it as a follow-up, not a blocker.

Nothing about this touches `scenario_default` or the golden — no shipped scenario except
`red_airborne` carries a `red_air_insertion` block at all.

**The doubling compounds — say so out loud, because it is bigger than "each drop is bloodier."**
Every lost battalion permanently destroys one battalion of lift (`AirInsertionResolver.gd:198-200`),
so the cap follows `cap_next = cap × (1 − rate)` and *lifetime* delivered lift falls much faster than
the per-drop survival rate does. Sketching it at the measured turn-1 rate with an airborne cap of 7:

| | per-drop loss | cap after 1 / 2 / 3 sorties | order-of-magnitude lifetime delivery |
|---|---|---|---|
| today (0.75) | ~18% | 7 → 5.7 → 4.7 | most of the 50-BN corps, given turns |
| doubled (1.5) | ~37% | 7 → 4.4 → 2.8 | roughly 15 BN before the lift is gone |

(Illustrative, not a prediction — the real rate *falls* each turn as the IJFS campaign grinds AD
health down, which softens the decay. The sweep measures the truth.)

This is plausibly exactly what the USER asked for — the airframe brake engaging is the stated goal,
and a corps that can deliver ~15 of its 50 battalions is a gamble rather than a sure thing. But it
converts the doubling from a throughput *tax* into a hard ceiling on total air-delivered force, which
is a different mechanic than "drops cost more". **Report `caps` vs `initial_caps` prominently in the
sweep and put this in front of the USER with the numbers** — if they wanted bloodier drops but not a
self-extinguishing corps, the lever is the erosion rule (e.g. only a fraction of losses destroy
airframes), not the attrition coefficient.

## Objective 2 — sortie cadence

A new scenario field, per lift class, defaulting to today's behaviour:

```json
"red_air_insertion": {
  "sortie_interval_turns": 2
}
```

**Semantics.** Fixing these now, because each one is a place the implementation could silently pick
the other reading:

- **Scope: per lift class.** Fixed-wing transports and helicopters are different fleets with
  different turnarounds, and the two classes already have separate budgets and separate attrition.
  One value configures both; the field may be a plain int (both classes) — split it into
  `airborne_sortie_interval_turns` / `air_assault_sortie_interval_turns` only if the USER wants them
  to differ, which nothing yet suggests.
- **A "sortie" is a turn in which any packet of that class flew**, not a per-brigade cooldown. Two
  brigades dropping on the same turn is one sortie; the cap already limits how much goes in it.
- **"Flew" means `sent > 0`, not `landed > 0`.** The aircraft took off; whether the air defences
  killed the whole packet is irrelevant to the turnaround. An order rejected for an unknown hex, an
  empty pool, or an exhausted cap never gets that far and must not burn the cadence — a typo'd order
  costing two days of lift would be a bug.
- **Never-flown must not read as "on cooldown".** `last_sortie_turn` defaults to 0, so a naive
  `next_legal = last + interval` makes turn 1 illegal at interval 2 (`0 + 2 = 2`) and the corps never
  gets off the ground. The rule is: **a class that has never flown is always legal**; only once
  `last_sortie_turn > 0` does `next_legal = last_sortie_turn + interval` apply. Interval 1 ⇒ every
  turn ⇒ byte-identical to today; interval 2 ⇒ turns 1, 3, 5, …
- **The cooldown must be evaluated against the state at the START of the turn.**
  `AirInsertionResolver.resolve` walks orders sequentially, sharing one per-class budget
  (`AirInsertionResolver.gd:160-196`). Writing `state.last_sortie_turn[lift_class] = turn_number`
  *inside* that loop would make the second brigade of the same class fail its own cooldown check in
  the same turn — silently collapsing the mechanic to one brigade per class per turn, which is not
  what "one sortie" means and would look like the cadence working. **Implementation: snapshot the
  cooldown decision per class before the loop (or collect the classes that flew in a local set), and
  write `last_sortie_turn` only after the loop finishes.** This is the single most likely way to get
  this feature subtly wrong; the unit test below exists specifically to catch it.
- **`first_turn` still gates the first sortie**; cadence applies from the first one that flies.

**State.** `AirInsertionState` gains `last_sortie_turn: Dictionary` (lift_class → int, 0 = never
flown), serialized in `to_dict()`.

`to_dict()` serializes unconditionally (`AirInsertionState.gd:116`), so a
non-airborne scenario would emit `"last_sortie_turn": {}` — but that is harmless and no record
widens: checked 2026-07-25, `AirInsertionState.to_dict()` has **no caller outside its own class**.
Game records carry `TurnResult.air_insertion_summary` (the `AirInsertionSummary` projection), and the
observation builds its own block at `LLMGameAPI.gd:342` gated on a non-empty pool. Serialize the new
field plainly; do not add an omit-when-empty special case.

**Rejection.** A new `AirInsertionSummary.REASON_ON_COOLDOWN`, reported in `summary.rejected` the
same way `REASON_CAP_EXHAUSTED` is. Consistent with the existing design: the cadence is spent at
resolution, not enforced at order time, because the resolver is the one place that knows what
actually flew.

**Legality surface.** `eligible_orders()` must carry the cadence so a player is not ordering into a
guaranteed rejection. Its signature grows: `eligible_orders(brigades, pending_orders)`
(`AirInsertionState.gd:84`) takes the current turn and the interval, and each returned row gains
`next_sortie_turn`. Every caller moves with it — `LLMGameAPI` (~`:356`), `AirAssaultPolicy` (~`:36`),
`tests/air_insertion_order_test.gd`. The observation's `air_insertion` block gains a per-class
`next_sortie_turn`. `AirAssaultPolicy` skips any eligible row whose `next_sortie_turn` exceeds the
observation's `turn` — otherwise the scripted doctrine emits a rejected order every other turn, which
pollutes every batch record with noise and makes the sweep harder to read.

**Where the config lives.** `AirInsertionStateBuilder.attrition_config()` is named for attrition
coefficients and should not quietly become a general config bag. Add a sibling `cadence_config()`
(or rename the pair to `resolver_config()` if the resolver ends up wanting one dictionary) and give
`resolve()` an explicit interval argument rather than smuggling it through `config`. Also required in
the same commit: `sortie_interval_turns` added to `AirInsertionStateBuilder.KNOWN_KEYS` (~`:35`,
which fails loud on unknown keys) and a `DEFAULT_SORTIE_INTERVAL_TURNS := 1` const alongside the
existing `DEFAULT_*` block (~`:18`).

## Objective 3 — measure both, separately and together

The saturation finding means neither brake can be assumed to bite. Cadence in particular halves a
throughput that was already 4× more than needed, so it may do nothing on its own — that is a real
possible outcome and the sweep must be able to report it.

A 2×2 over the same instrument the 0032 report used, so the numbers are directly comparable to the
83% / 97% table:

- **Spec:** new `tools/sweeps/airborne_cost_cadence.json`, modelled on `tools/sweeps/airborne_lift.json`.
  Knob paths are raw `file:dot.path`, not registry ids — `run_sweep.py` derives human-readable cell
  names from the last `:`-segment:
  `data/scenarios/red_airborne.json:red_air_insertion.max_attrition_at_full_ad` and
  `…:red_air_insertion.sortie_interval_turns`, with `green_mobilization.held_back_brigades` pinned
  as a third single-valued knob exactly as `airborne_lift.json` does.
- **Scenario** `red_airborne`, **matchup** `air_assault:roc_defense`, **30 turns**, the same 30 seeds
  (20260624–20260653), `green_mobilization.held_back_brigades` pinned at **12** — the plan-0029
  defender, the only configuration where the win rate is not already saturated at 100%.
- **Grid:** `max_attrition_at_full_ad` ∈ {0.75, 1.5} × `sortie_interval_turns` ∈ {1, 2}.
- **A second arm with the cap pinned low, or the cadence cell proves nothing.** At the default
  `airborne_cap_per_turn` of 7, interval 2 still averages 3.5 BN/turn — *above* the ~3 BN/turn
  saturation floor the 0032 sweep measured, so the (0.75, 2) cell will very likely read identical to
  (0.75, 1) and that null result would say nothing about whether the cadence works. Run the interval
  arm a second time with `airborne_cap_per_turn` pinned to **4** (interval 2 ⇒ 2 BN/turn average,
  strictly below saturation). If cadence moves the outcome there and not at cap 7, the honest
  conclusion is "cadence binds only once it pushes throughput under the saturation floor" — which is
  itself the answer to whether it is a real lever.
- **Reference points already measured** at (0.75, 1): Red 97%, median decision turn 11. The
  no-drops floor is 83%.
- **Metrics:** `red_win_rate` primary; also read median decision turn, Red ground losses, and
  `caps` vs `initial_caps` at game end — the airframe ledger is the thing the doubling is *supposed*
  to make bite, and if the caps still finish near their start value the brake still is not engaging.

The USER decides from that table whether the dial is right; this plan does not pre-commit to a
target win rate.

## Verification

- **Golden byte-stable.** Both objectives default to inert: `scenario_default` has no
  `red_air_insertion` block, and `sortie_interval_turns` defaults to 1. Any golden drift means the
  cadence leaked into the no-block path.
- `tools/validate_air_insertion.gd` runs on `red_airborne` and **will** move — the doubled
  coefficient changes its pinned 45-landed / 2-lost / 70:84 census. That is a deliberate pin update,
  not a regression; the commit message must say so, per `hexcombat-change-control`.
- New unit coverage in `tests/air_insertion_resolver_test.gd`: interval 1 is byte-identical to
  today; interval 2 blocks the very next turn and permits the one after; a wholly-rejected turn does
  not spend the sortie; the two lift classes hold independent cooldowns.
- Order-legality coverage in `tests/air_insertion_order_test.gd`: `eligible_orders` reports
  `next_sortie_turn`; `AirAssaultPolicy` issues nothing on a cooldown turn.
- `tools/validate_knob_registry.gd` — the new knob must be registered and its path must resolve
  (the phantom-path failure mode from `docs/plans/BACKLOG.md`).
- `tools/validate_llm_api.gd` + `schemas/*.schema.json` — the observation gains fields; the contract
  is gated. `docs/LLM_OBSERVATION_SCHEMA.md` and the committed example observation move with it.
- **Docs are part of the change, not the closeout:** `docs/systems/air-insertion.md` §4 (config
  block), §5 (the attrition rationale, which the doubling contradicts), §8 (the observation field
  list gains `next_sortie_turn`), plus a 3–5-line `docs/DECISIONS.md` entry per
  `hexcombat-change-control` — two decisions here, the doubled coefficient and the cadence.

## Risks

- **A knob that is recorded but inert.** `sortie_interval_turns` must land in
  `data/knobs/registry.json` *and* be verified to actually change a game — this repo has already
  shipped two knobs that were dumped into every record while affecting nothing
  (`combat_*_advantage_ratio`, the phantom `offload_beach_base_rate` path). Sweep cell (0.75, 2) vs
  (0.75, 1) must not be byte-identical; if it is, the wiring is wrong, not the mechanic.
- **Unknown-key fail-loud.** `AirInsertionStateBuilder` rejects unknown config keys, so the new field
  must be added to the builder in the same commit as the scenario JSON or `red_airborne` fails to
  load. Cheap to hit, cheap to fix, but it fails at scenario load with a message about the scenario,
  not about this plan.
- **Contract churn.** `last_sortie_turn` and `next_sortie_turn` widen a JSON contract that game
  records and the viewer bundle already carry. Additive only; no existing key changes meaning.

## Dependencies / notes

- Independent of plan 0034 and 0035. Touches `AirInsertionState`, `AirInsertionResolver`,
  `AirInsertionStateBuilder`, `AirInsertionSummary`, `AirAssaultPolicy`, `LLMGameAPI`, the schema,
  `data/scenarios/red_airborne.json`, `data/knobs/registry.json`.
- Sequence the two objectives as **separate commits** — attrition (data + doc + pin re-baseline)
  first, cadence (code + contract) second — so the sweep can attribute any surprise to one of them.
- Related open item, deliberately NOT in scope: the PLAA's two air assault brigades stay unmodelled
  (USER call 2026-07-25).
