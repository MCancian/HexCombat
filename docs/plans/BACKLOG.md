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

- [ ] **A partially-landed brigade FIGHTS at full strength (found 2026-07-25, gem-explore review of
  plan 0034).** The census now subtracts battalions that are not ashore, but ground combat does not:
  `CombatForces.maneuver_units` / `support_units` (`scripts/CombatForces.gd:9`, `:24`) walk the whole
  `brigade.composition` and emit one unit per `qty`. A brigade's `hex_id` is set by its FIRST landed
  battalion, so a formation with 4 of 8 battalions ashore fights with 8 — its at-sea and
  still-on-the-mainland battalions swing rifles from the boat. This is **not** the ghost-landing bug
  (those battalions are alive, just elsewhere) and it is bigger in scope than the census one: it
  perturbs every contested hex every turn, not just the terminal count. Both loss paths already
  shrink `composition`, so the fix is a not-ashore subtraction, not a roster change — feed
  `PendingBattalions` (a `by_brigade_and_type` variant) into unit generation.
  **Not a free bug fix:** it changes ported combat math and moves the golden, so it needs a USER call
  and a deliberate re-baseline. The supply-side twin IS deliberate and documented
  (`docs/systems/air-insertion.md` → "A partially-arrived brigade consumes full DOS"); whether combat
  should match supply or diverge from it is exactly the question to put to the USER.
- [ ] **The LLM observation cannot see the mainland pool (same review).** `_ship_reserve_observations`
  (`scripts/LLMGameAPI.gd:301`) enumerates `ship_reserve` only, so an LLM seat has no way to know how
  many of its battalions are still queued for a hull — while `brigade_observations` reports each
  brigade's full battalion count. An agent reasoning about its own force therefore sees strength that
  is not on the island. Additive contract change; gate is `tools/validate_llm_api.gd` + the schemas.

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

- [x] **Air insertion balance dial (plan 0032 follow-up)** — **answered by the USER 2026-07-25**:
  double the baseline attrition coefficient and gate drops on a sortie cadence (~1 sortie per 2
  days). Now owned by plan `docs/plans/0036-airborne-cost-and-cadence.md`. Evidence that motivated
  it: `docs/reports/2026-07-24-airborne-insertion-sweep.md`.
- **The 2 PLAA air assault brigades are unmodelled (plan 0032).** The USER's source gives the PLAA 15
  aviation brigades, two of them air assault (6 transport + up to 3 infantry BN each); the OOB has 13,
  none air assault. Today only the Airborne Corps' own 130th feeds the rotary-wing lift cap. Adding
  them is an OOB change plus a `nato_type` retag — add-2 vs convert-2 was put to the USER 2026-07-25
  and the call was **leave unmodelled for now**; re-ask before touching the OOB.
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
