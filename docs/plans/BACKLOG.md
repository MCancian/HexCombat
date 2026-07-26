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

- [ ] **The front-line phase is the last non-pipeline occupant of `TurnConductor`
  (raised independently by `opencode/deepseek-v4-flash-free` and `gem-explore` in the plan-0038 step-3
  diff review, 2026-07-25).** After plan 0038, `TurnConductor` is the turn's ORDER plus the phases
  whose application interleaves with it (movement, ground combat, FEBA retreats).
  `resolve_frontline_phase` + `frontline_hex_centers` are not in the turn pipeline at all — they take
  operator-drawn polyline coordinates and are reachable only through the `GameState` façade — and
  they are the sole reason `TurnConductor` still names `FrontlineResolver`. Plan 0038 flagged this as
  "a separate, optional tidy" and deliberately left it. Cost: one small module, one façade
  redirection, ~2 deps. Do it only if something else brings you into this file.

- [ ] **Validator harness: `_fail` / `_finish` / asserts are copy-pasted across the validators
  (found 2026-07-25, refactor review).** Measured: `func _fail` in **30 of 36** `tools/validate_*.gd`,
  `_finish` in 31, `_assert_equal_int` in 12, `_assert_true` in 11. A `tools/ValidatorHarness.gd`
  owning the assert vocabulary would remove the duplication. **Note the claim that failed review:**
  this does NOT fix the gate-hang class — a script that fails to COMPILE never runs, harness included
  (caught by gem-explore; two other models wrongly agreed it would). That hole is closed separately by
  `--quit-after` in `run_all_tests.py`. So this is deduplication only, worth doing when validators are
  being touched anyway, in slices of 5-6 with the gate green between. Good `opencode` delegation.
- [ ] **Doc-anchor validator checks links, not symbols (found 2026-07-25).** `tools/validate_doc_anchors.gd`
  matches `ClassName.member` in backticks, so a doc naming a bare `CONSTANT` that no longer exists
  passes — `docs/systems/ground-combat.md` described `CombatCalculator.TERRAIN_MODIFIERS` as "dead code,
  left untouched" long after the symbol was deleted (fixed 2026-07-25). Extending the check to bare
  backticked ALL_CAPS identifiers was considered and **deferred deliberately**: `PI`, `INFINITY` and
  ordinary prose constants would false-positive, and neither reviewer had a scoping rule that survived
  scrutiny. Needs a real rule before it is built.
- [ ] **Combat-loop caches live as mutable fields on `GameStateData` (found 2026-07-25).**
  `isolated_air_landed_brigades` (`:43`) and `not_ashore_by_type` (`:49`) are both computed once per
  turn at `TurnConductor:65`/`:70` and read by every contested hex; nothing enforces that a third such
  cache follows the rule or that either is cleared between turns. A `begin_combat_loop(state)`
  returning a context value object would make staleness impossible by construction. **Deferred:**
  reviewers split on risk/reward — the caches are correct today and the change touches
  `CombatResolver.resolve_at`'s signature for no behavioural gain. Do it when that seam is open anyway.

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
- **`docs/*.md` and `docs/plans/*.md` have no anchor gate.** `tools/validate_doc_anchors.gd` scans
  `res://docs/systems` only, and `tools/validate_skill_references.gd` scans `.claude/skills` only, so
  `STATUS.md`, `DECISIONS.md`, `RETROSPECTIVES.md` and every plan can cite a dead path unnoticed —
  which is how four skills came to point at a validator that had been deleted. Extending one of the two
  to cover them is cheap; the obstacle is that those files legitimately DISCUSS dead paths, so they need
  the `(historical)` escape marker applied first or the gate will fire on the record of the very cleanup
  that removed them.
- **`docs/STATUS.md` quotes golden pins in prose, against the one-home rule.** Two places name pinned
  validator output directly: the re-baselined golden `casualties`/`feba` pair, and the 40-turn stalemate
  census. `hexcombat-docs-and-writing` is explicit that the validator's `PASS:` line is the only home for
  a pin and that no doc quotes one — these rotted twice on 2026-07-09 alone, which is why the rule
  exists. Replace both with a pointer to the owning validator. Found 2026-07-26 by a diff reviewer while
  reviewing plan 0040; pre-existing, so deliberately not fixed inside that commit.
- **`hexcombat-plan-review`'s launch snippet cannot work as written.** It backgrounds
  `opencode run` twice plus `gem-explore` simultaneously; two concurrent `opencode run` invocations make
  the second die with `database is locked` (the shared session DB does not tolerate it). Observed twice
  on 2026-07-26, costing two review slots. Fix: run the two opencode models serially and `gem-explore`
  alongside either one, and say so in both `hexcombat-plan-review` and `hexcombat-diff-review`. Consider
  also recording `deepseek-v4-flash-free`'s stall-with-no-final-message and nemotron's
  `Streaming response failed` as expected flakes with a retry policy, so the next agent does not read a
  missing write-up as a clean review.
- **`CombatCalculator._normalize_support` is dead code.** It is a one-line pass-through returning
  `normalize_support(raw_support)` and is called from nowhere in `scripts/`, `tests/` or `tools/` (the real
  callers use `normalize_support` directly, including `tools/validate_combat_data.gd`). Delete it. It is
  the shape that trapped an editor before — `Brigade.to_combat_units` was a live-looking function that
  did not subtract pools — so a leftover with a plausible name is worth removing rather than tolerating.
  Found 2026-07-26 by a diff reviewer during plan 0040; out of scope there, which touched no production
  code.
- **Four `tools/` validators duplicate a comment/string stripper and a `.gd` directory walker — decided
  2026-07-26 NOT to unify, revisit only with new evidence.** `validate_tool_script_purity.gd`,
  `validate_no_global_rng.gd`, `validate_doc_anchors.gd` and `validate_combat_rules_threading.gd` each
  carry their own, with differing semantics. The tempting reason to unify was to fix the shared
  escaped-quote hole (`"say \"hi\""` ends the string match early and exposes the middle as code) in one
  place instead of four. Rejected on two measurements: (1) that hole fails in the LOUD direction —
  blanking leaves more text exposed, not less, so it yields a spurious FAIL, never a silent pass, in
  every current consumer; (2) `validate_tool_script_purity.gd` needs TWO stripper modes, not one — it
  finds `preload("res://…")` paths with a comments-only pass that deliberately PRESERVES strings, so a
  naive unification would silently stop finding preloads, turning a gate into a false negative. That is a
  worse outcome than the duplication. If unified later, the acceptance test is per-validator stdout
  byte-identical AND each still FINDING what it found — a validator that finds fewer things is not
  output-neutral even when its wording is unchanged. Note this is a DIFFERENT item from the
  `_fail`/`_finish` harness dedup above, which remains worth doing on its own terms — a reviewer proposed
  the harness migration as a substitute for this one, and it is not: it addresses different duplication,
  and doing it wholesale would change output (27 of 38 validators still have their own helpers, and
  `ValidatorHarness`'s docstring records that several deviate deliberately), which is why that item
  correctly says slices-with-the-gate-green rather than a sweep.
