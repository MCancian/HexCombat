# HexCombat — Tech Debt & Hygiene Backlog

This document is strictly a place for agents to dump observations of tech debt, hygiene issues, and necessary refactors encountered during development. 

Focused multi-session efforts (features, content, balancing) get a numbered plan in the `docs/plans/` directory and are tracked in [README.md](README.md).

## Deferred Debt & Hygiene Items

**Code-quality debt deferred from the 2026-07-16 baseline** (report:
`docs/reports/2026-07-16-code-quality-baseline.md`; actionable items worked under plan 0009):

- [x] **GameState dependency ceiling** — shipped as plan 0014 (2026-07-19): state → `GameStateData`
  value object, orchestration/construction/validation → `static` `TurnConductor`/`GameStateBuilder`/
  `OrderValidator` taking `GameStateData`; deps 48→24, ceiling enforced via
  `gd_metrics.py --check-ceiling`. See `docs/archive/0014-gamestate-dependency-ceiling.md`.
- [x] **HexMap cosmetic literals**: 93 view-layer color/offset literals — hoisted opportunistically.
- [x] **Const→data knob promotion**: any const hoisted under 0009 the USER wants tunable moves to
  `data/*.json` per `hexcombat-config-and-knobs` — one USER call per knob (change-control #7).

*(Agents: append new technical debt and hygiene observations here)*

- [ ] **mc_chart.py degenerate-input crashes (pre-existing, found 2026-07-24 gem-explore review).** Two
  chart builders crash on an empty/degenerate summary rather than failing loud: `histogram_panel`
  `first = next(i for i, b ... if b["count"] > 0)` raises `StopIteration` if every margin bin is zero
  (empty batch); `sensitivity_panel` `min(xs)`/`max(xs)` raises `ValueError` on an empty `points` list.
  Only reachable with a 0-game batch, so low priority — guard both with a clear "no data" message when
  a real empty-batch case appears. (The `--flip`/`--heat`/`make_heat_spec` degenerate paths were
  already guarded in the 2026-07-24 review round.)

- [ ] **Inert knob-registry entries (found 2026-07-23, MC sweep investigation).** Two knobs are
  dumped into every record but do NOT affect the sim (overriding them yields byte-identical games),
  so a sweep on either silently reports false robustness:
  - `combat_defender_advantage_ratio` / `combat_attacker_advantage_ratio` — recorded but never reach
    `CombatResolver`. Either wire them into the combat math or drop them from `data/knobs/registry.json`.
  - `offload_operational_port_rate` — **now owned by plan 0031 (Objective 0, USER 2026-07-24)**: port
    throughput is the `OffloadRates.OPERATIONAL_PORT` GDScript constant, not loaded from
    `offload_rates.json`, so it's not DataOverrides-sweepable (now marked `sweepable:false`). To make
    it a real lever, load `offload_rates.json` through `GameData._read_json` (routes through
    DataOverrides) and have `InfrastructureResolver` read the loaded rate. Same applies to the other
    `OffloadRates` constants (beach base uses `beaches.json:offload_rate` and already works).
  - Consider a gate check that fails when a `sweepable:true` registry knob's override doesn't actually
    apply (would have caught the phantom `offload_beach_base_rate` path).

- **Air insertion balance dial (plan 0032 follow-up, needs a USER call).** The measured air path is
  close to free: attrition is `0.75 × effective_ad_health`, and the IJFS warmup has already driven AD
  health to ~0.24 by turn 1 and ~0.12 by turn 4, so a typical drop loses ~9% and the
  permanent-airframe brake never engages. Red goes 83% → 97% against the strongest measured defence,
  and lift quantity saturates (3 BN/turn ≈ 14 BN/turn), so the cap is NOT the lever. If the corps
  should be a gamble rather than a sure thing the candidates are: raise `max_attrition_at_full_ad`,
  decouple insertion attrition from AD health so the sky is never fully clear, or gate drops on
  something scarcer than airframes. Evidence: `docs/reports/2026-07-24-airborne-insertion-sweep.md`.
- **The 2 PLAA air assault brigades are unmodelled (plan 0032).** The USER's source gives the PLAA 15
  aviation brigades, two of them air assault (6 transport + up to 3 infantry BN each); the OOB has 13,
  none air assault. Today only the Airborne Corps' own 130th feeds the rotary-wing lift cap. Adding
  them is an OOB change plus a `nato_type` retag — decide add-2 vs convert-2 with the USER first.
- **Order-kind dispatch lives in three places.** `GameState._apply_order`, `LLMGameAPI.apply_agent_response`
  and `schemas/llm_action_response.schema.json` each enumerate the order kinds independently. Adding
  `air_insert` (plan 0032) meant editing all three, and the duplication had already rotted: `deploy_jlsf`
  was missing from the schema until 2026-07-24. Give the kinds one home and derive the dispatch (or at
  minimum add a gate check that every dispatch arm has a schema variant and vice versa).
- **`UnitStats.FALLBACK_CATEGORY_DEFS` reachability is unknown.** 90 entries, and NO composition entry in
  either OOB declares a `category` — the table is reachable only through `_fallback_category_for_type`'s
  type-name heuristics. Plan 0032 anchored two new airborne strengths on entries that were dead until
  then. Instrument `_fallback_category_for_type` over both OOBs, list the keys actually hit, and delete
  or document the rest. Do NOT delete on inspection alone; the matching is indirect.
- **`CombatResolver` assumes attacker=Red / defender=Green.** `resolve_at` hardcodes it — the two
  defender-side `inject_supply_effectiveness` calls were no-ops for exactly this reason and were removed
  2026-07-24, leaving a comment. If Green ever counterattacks (plan 0029 Tier B), supply injection and
  anything else keyed on side must be driven by each side's actual team, not its role. Ported combat
  semantics, so a USER-aware change, not a refactor.
