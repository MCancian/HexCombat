# IjfsEngine

> **Reading aid, not an execution contract.** No detected edge is not permission to reorder.
> GDScript reads and writes are conservative source analysis; transition writes are also
> checked against the mutation manifest. Potential conflicts may refer to different object
> instances or conditional branches.

Generator format v1; scan scope `scripts/**/*.gd` plus `project.godot` autoload aliases.
Generated from commit `8829181ae4b6`; input SHA-256 `1c5ff5483615f0cca5b2767540c56e9a13e1387c4c1a3c66db909a97ad2e94fb`;
tool/manifest/fixture SHA-256 `ea366ecafdb8f5cc7ecae22bb7554cd8802d1ed3433c5a903ecc07bbb7230f6c`; stable generation time `2026-08-02T09:03:12-04:00`.
Unresolved-analysis diagnostics on this page: **98**.

## Source summary

Port of ijfs_standalone/run_daily_ijfs.py (the 6-phase daily orchestration) + run_context.py (day-semantics). Deliberately does NOT port write_outputs file IO: run_daily returns the ledgers dict directly (detection / strike / engagement / contest / free-shot / target-status / inventory / OOB / summary).  This file is the ORDER of a day and nothing else. Two halves moved out on 2026-08-01 (plan 0060) — IjfsStrikePhase owns each strike pass, IjfsLedgers owns the summary and the record — which both reads better and pays for the collaborators plan 0060 adds, since the engine was already at its dependency ceiling and that ceiling is paid, never raised.  RNG fidelity: a single shared `dice: Dice` is threaded into every probabilistic phase, exactly mirroring the Python single `state.rng`. Draw order across phases: 1. (warmup only) exquisite-intel auto-detect rolls 2. satellite (phase1) detection 3. pre-AD strike phase (resolve_strike per attacked target) 4. SEAD stages A/B/C (on the day's air-engagement substream) + return fire 5. aircraft (phase2) detection 6. post-AD strike phase 7. post-phase-2 free shot  Continuity: targets/munitions/squadron_force live on the state and persist across days; call carry_to_next_day(state) between days to reproduce the loader's reload reset (clear suppression + sead_result; destroyed / known_to_red / inventory / squadron attrition carry forward).

Source: `scripts/interleaved/IjfsEngine.gd`

## Placement in resolution code

| Caller | Call-site instance |
|---|---|
| [`IjfsEngine.run_daily`](ordering_IjfsEngine_run_daily.md) | `IjfsEngine.make_run_context` at `91` |
| [`IjfsEngine.run_daily`](ordering_IjfsEngine_run_daily.md) | `IjfsEngine.unknown_warmup_keys` at `111` |
| [`IjfsResolver.resolve`](IjfsResolver.md) | `IjfsEngine.carry_to_next_day` at `49` |
| [`IjfsResolver.resolve`](IjfsResolver.md) | `IjfsEngine.run_daily` at `54` |
| [`IjfsResolver.resolve`](IjfsResolver.md) | `IjfsEngine.carry_to_next_day` at `58` |
| [`IjfsResolver.resolve`](IjfsResolver.md) | `IjfsEngine.run_daily` at `59` |

## Dependency diagram

```mermaid
flowchart LR
  n_9d80ff26ba73["IjfsEngine"]
  n_e4731c9359c3["IjfsEngine.run_daily"] --> n_9d80ff26ba73
  n_3ee2b3c13ed8["IjfsResolver.resolve"] --> n_9d80ff26ba73
  n_9d80ff26ba73 --> n_18b99cbee55e["Dice.derive"]
  n_9d80ff26ba73 --> n_818a7f9357fc["IjfsAdHealth.compute_taiwan_ad_health"]
  n_9d80ff26ba73 --> n_b814e4e437f8["IjfsAttritionProfile.build"]
  n_9d80ff26ba73 --> n_e57d4b05e21b["IjfsDetection.aircraft_detect_target_ids"]
  n_9d80ff26ba73 --> n_8636e425ba38["IjfsDetection.apply_detection_ids"]
  n_9d80ff26ba73 --> n_cf06a2fc5b95["IjfsDetection.satellite_detect_target_ids"]
  n_9d80ff26ba73 --> n_8ec805975125["IjfsEngagement.apply_post_phase_2_free_shot"]
  n_9d80ff26ba73 --> n_c28f21de229d["IjfsEngagement.resolve_package_return_fire"]
  n_9d80ff26ba73 --> n_3cabb6d345b0["IjfsEngine.make_run_context"]
  n_9d80ff26ba73 --> n_ed8e2217cb93["IjfsEngine.unknown_warmup_keys"]
  n_9d80ff26ba73 --> n_84e903a0440a["IjfsFiringCapacity.FiringCapacityBudget.new"]
  n_9d80ff26ba73 --> n_ed11277a47cc["IjfsFiringCapacity.OrganicStrikeBudget.new"]
  n_9d80ff26ba73 --> n_914b402b0048["IjfsLedgers.build_ledgers"]
  n_9d80ff26ba73 --> n_259e24d771ff["IjfsLedgers.summarize_run"]
  n_9d80ff26ba73 --> n_63d5c9183134["IjfsSeadStage.resolve"]
  n_9d80ff26ba73 --> n_7d9bccfa4792["IjfsStrikePhase.append_final_skips"]
  n_9d80ff26ba73 --> n_7ca4cbf5bb33["IjfsStrikePhase.run"]
  n_9d80ff26ba73 --> n_2f87daa3ebde["IjfsStrikePhaseContext.new"]
  n_9d80ff26ba73 --> n_c85927b5d27d["IjfsTargeting.apply_exquisite_intel"]
  n_9d80ff26ba73 --> n_4a4441265a4d["IjfsTargeting.apply_posture_override"]
  n_9d80ff26ba73 --> n_2b3a0242e0ce["IjfsTransitions.carry_to_next_day"]
```

## Model-field evidence

| Field | Read | Written |
|---|:---:|:---:|
| `IjfsAirPackage.dedicated_size` | yes | yes |
| `IjfsAirPackage.initial_size` | yes | yes |
| `IjfsAirPackage.kind` | yes | yes |
| `IjfsAirPackage.members` | yes | yes |
| `IjfsAirPackage.munition_id` | yes | yes |
| `IjfsAirPackage.package_id` | yes | yes |
| `IjfsAirPackage.target_id` |  | yes |
| `IjfsAirPackage.to_number` | yes | yes |
| `IjfsDailyState.air_classes` | yes |  |
| `IjfsDailyState.contest_log` | yes | yes |
| `IjfsDailyState.detection_log` | yes | yes |
| `IjfsDailyState.engagement_log` | yes | yes |
| `IjfsDailyState.exquisite_intel_overrides` | yes | yes |
| `IjfsDailyState.free_shot_log` | yes | yes |
| `IjfsDailyState.manpads_intercept_log` | yes | yes |
| `IjfsDailyState.munitions` | yes |  |
| `IjfsDailyState.pairings` | yes |  |
| `IjfsDailyState.scenario` | yes |  |
| `IjfsDailyState.seed` | yes |  |
| `IjfsDailyState.source_files` | yes |  |
| `IjfsDailyState.squadron_force` | yes |  |
| `IjfsDailyState.strike_log` | yes | yes |
| `IjfsDailyState.taiwan_ad_health_after` | yes | yes |
| `IjfsDailyState.taiwan_ad_health_after_missile_phase` | yes | yes |
| `IjfsDailyState.taiwan_ad_health_after_sead` | yes | yes |
| `IjfsDailyState.taiwan_ad_health_before` | yes | yes |
| `IjfsDailyState.targets` | yes |  |
| `IjfsDailyState.warnings` | yes |  |
| `IjfsMunition.category` | yes |  |
| `IjfsMunition.display_label` | yes |  |
| `IjfsMunition.inventory_remaining` | yes | yes |
| `IjfsMunition.manpads_vulnerability` | yes |  |
| `IjfsMunition.munition_id` | yes |  |
| `IjfsMunition.munition_name` | yes |  |
| `IjfsMunition.rounds_per_engagement_default` | yes |  |
| `IjfsPairing.munition_id` | yes |  |
| `IjfsPairing.pairing_id` | yes |  |
| `IjfsPairing.probability_destroyed` | yes |  |
| `IjfsPairing.probability_suppressed_if_not_destroyed` | yes |  |
| `IjfsPairing.rounds_expended_per_engagement` | yes |  |
| `IjfsPairing.source_target_ids` | yes |  |
| `IjfsPairing.target_category` | yes |  |
| `IjfsPairing.target_hardness` | yes |  |
| `IjfsPairing.target_mobility` | yes |  |
| `IjfsPairing.target_subcategory` | yes |  |
| `IjfsSquadron.aircraft_class` | yes |  |
| `IjfsSquadron.alive` | yes | yes |
| `IjfsSquadron.initial` | yes |  |
| `IjfsSquadron.losses_campaign` | yes | yes |
| `IjfsSquadron.losses_today` | yes | yes |
| `IjfsSquadron.role` | yes |  |
| `IjfsSquadron.rtb_today` | yes | yes |
| `IjfsSquadron.sead_assigned_today` | yes | yes |
| `IjfsSquadron.squadron_id` | yes |  |
| `IjfsStrikeContext.current_day` | yes | yes |
| `IjfsStrikeContext.doctrine_rule_name` | yes | yes |
| `IjfsStrikeContext.doctrine_selection` | yes | yes |
| `IjfsStrikeContext.phase` | yes | yes |
| `IjfsStrikeContext.survivor_fraction` | yes | yes |
| `IjfsStrikePhaseContext.ad_attrition_enabled` | yes | yes |
| `IjfsStrikePhaseContext.air_engagement_dice` | yes | yes |
| `IjfsStrikePhaseContext.attacked` | yes | yes |
| `IjfsStrikePhaseContext.attrition` | yes | yes |
| `IjfsStrikePhaseContext.capacity_budget` | yes | yes |
| `IjfsStrikePhaseContext.current_day` | yes | yes |
| `IjfsStrikePhaseContext.munition_filter` | yes | yes |
| `IjfsStrikePhaseContext.organic_budget` | yes | yes |
| `IjfsStrikePhaseContext.packages_launched` | yes | yes |
| `IjfsStrikePhaseContext.release_rules` | yes | yes |
| `IjfsStrikePhaseContext.skip_reasons` | yes | yes |
| `IjfsStrikePhaseContext.z_day` | yes | yes |
| `IjfsTarget.category` | yes |  |
| `IjfsTarget.destroyed` | yes | yes |
| `IjfsTarget.detectability_active` | yes |  |
| `IjfsTarget.detectability_hiding` | yes |  |
| `IjfsTarget.detected_this_turn` | yes | yes |
| `IjfsTarget.hardness` | yes |  |
| `IjfsTarget.instance_index` | yes |  |
| `IjfsTarget.intel_locked` | yes | yes |
| `IjfsTarget.known_to_red` | yes | yes |
| `IjfsTarget.last_detected_day` | yes | yes |
| `IjfsTarget.manpads_remaining` | yes | yes |
| `IjfsTarget.metadata` | yes |  |
| `IjfsTarget.metadata[systems_remaining]` |  | yes |
| `IjfsTarget.metadata[to_number]` | yes |  |
| `IjfsTarget.mobility` | yes |  |
| `IjfsTarget.posture` | yes | yes |
| `IjfsTarget.quantity` | yes |  |
| `IjfsTarget.sam_score` | yes |  |
| `IjfsTarget.sead_result` | yes | yes |
| `IjfsTarget.source_target_id` | yes |  |
| `IjfsTarget.subcategory` | yes |  |
| `IjfsTarget.suppressed` | yes | yes |
| `IjfsTarget.suppressed_this_turn` | yes | yes |
| `IjfsTarget.target_id` | yes |  |

## Method dependencies

| Method | Calls (transitive effects are included above) |
|---|---|
| `carry_to_next_day` | `IjfsTransitions.carry_to_next_day` |
| `make_run_context` | — |
| `run_daily` | `Dice.derive`, `IjfsAdHealth.compute_taiwan_ad_health`, `IjfsAttritionProfile.build`, `IjfsDetection.aircraft_detect_target_ids`, `IjfsDetection.apply_detection_ids`, `IjfsDetection.satellite_detect_target_ids`, `IjfsEngagement.apply_post_phase_2_free_shot`, `IjfsEngagement.resolve_package_return_fire`, `IjfsEngine.make_run_context`, `IjfsEngine.unknown_warmup_keys`, `IjfsFiringCapacity.FiringCapacityBudget.new`, `IjfsFiringCapacity.OrganicStrikeBudget.new`, `IjfsLedgers.build_ledgers`, `IjfsLedgers.summarize_run`, `IjfsSeadStage.resolve`, `IjfsStrikePhase.append_final_skips`, `IjfsStrikePhase.run`, `IjfsStrikePhaseContext.new`, `IjfsTargeting.apply_exquisite_intel`, `IjfsTargeting.apply_posture_override` |
| `unknown_warmup_keys` | — |

## Analysis limits found here

Showing 30 of 98 diagnostics; class pages provide the narrower context.

| Kind | Source | Why it matters |
|---|---|---|
| `multi_call_statement` | `scripts/calc/IjfsAttritionProfile.gd:71` `return clampf(base_rate * role_exposure(role) * rcs_survival(aircraft_class), 0.0, 1.0)` | Multiple calls share one statement; the map preserves lexical sites, not nested evaluation order. |
| `untyped_iteration` | `scripts/calc/IjfsLedgers.gd:30` `for entry in state.detection_log:` | The collection element type could not be proven. |
| `untyped_iteration` | `scripts/calc/IjfsLedgers.gd:37` `for entry in state.strike_log:` | The collection element type could not be proven. |
| `untyped_iteration` | `scripts/calc/IjfsLedgers.gd:42` `for entry in state.engagement_log:` | The collection element type could not be proven. |
| `multi_call_statement` | `scripts/calc/IjfsLedgers.gd:50` `return { "target_counts_by_category_status": target_counts, "detections_by_mobility": detections_by_mobility, "detections_by_category": detections_by_category, "attacks": attack…` | Multiple calls share one statement; the map preserves lexical sites, not nested evaluation order. |
| `untyped_iteration` | `scripts/calc/IjfsLedgers.gd:106` `for entry in state.manpads_intercept_log:` | The collection element type could not be proven. |
| `multi_call_statement` | `scripts/calc/IjfsLedgers.gd:111` `return { "ready_systems_by_to": IjfsManpads.ready_systems_by_to(state.targets), "attempts": state.manpads_intercept_log.size(), "kills": kills, "aborts": aborts, "unaffected": i…` | Multiple calls share one statement; the map preserves lexical sites, not nested evaluation order. |
| `callable_or_lambda` | `scripts/calc/IjfsLedgers.gd:126` `sorted_targets.sort_custom(func(a: IjfsTarget, b: IjfsTarget) -> bool: return a.target_id < b.target_id)` | Callable/lambda dataflow is outside this analyser. |
| `unresolved_receiver` | `scripts/calc/IjfsLedgers.gd:126` `sorted_targets.sort_custom(func(a: IjfsTarget, b: IjfsTarget) -> bool: return a.target_id < b.target_id)` | A protected field name appeared on an unresolved receiver. |
| `multi_call_statement` | `scripts/calc/IjfsLedgers.gd:131` `return { "metadata": { "current_day": current_day, "seed": state.seed, "source_files": state.source_files.duplicate(), "created_by": "ijfs_standalone", }, "detection_log": state…` | Multiple calls share one statement; the map preserves lexical sites, not nested evaluation order. |
| `untyped_alias` | `scripts/calc/IjfsStrikePhase.gd:43` `var pairing: Variant = selection["selected"]` | The receiver type could not be proven. |
| `untyped_alias` | `scripts/calc/IjfsStrikePhase.gd:47` `var reason: Variant = selection["reason"]` | The receiver type could not be proven. |
| `unresolved_receiver` | `scripts/calc/IjfsStrikePhase.gd:50` `var munition: Variant = state.munitions.get(pairing.munition_id, null)` | A protected field name appeared on an unresolved receiver. |
| `untyped_alias` | `scripts/calc/IjfsStrikePhase.gd:50` `var munition: Variant = state.munitions.get(pairing.munition_id, null)` | The receiver type could not be proven. |
| `unresolved_receiver` | `scripts/calc/IjfsStrikePhase.gd:51` `var is_organic: bool = munition != null and munition.category == "Organic"` | A protected field name appeared on an unresolved receiver. |
| `untyped_alias` | `scripts/calc/IjfsStrikePhase.gd:52` `var budget: Variant = ctx.organic_budget if is_organic else ctx.capacity_budget` | The receiver type could not be proven. |
| `unresolved_receiver` | `scripts/calc/IjfsStrikePhase.gd:53` `if budget != null and not budget.has_capacity(pairing.munition_id):` | A protected field name appeared on an unresolved receiver. |
| `unresolved_receiver` | `scripts/calc/IjfsStrikePhase.gd:63` `package = IjfsPackageIngress.assemble( state, pairing.munition_id, target, ctx.packages_launched, ctx.air_engagement_dice)` | A protected field name appeared on an unresolved receiver. |
| `unresolved_receiver` | `scripts/calc/IjfsStrikePhase.gd:69` `budget.try_consume(pairing.munition_id)` | A protected field name appeared on an unresolved receiver. |
| `untyped_alias` | `scripts/calc/IjfsStrikePhase.gd:107` `var row := target.to_dict()` | The receiver type could not be proven. |
| `untyped_alias` | `scripts/interleaved/IjfsDetection.gd:12` `var override: Variant = source.get("runtime_capability_override", null)` | The receiver type could not be proven. |
| `untyped_alias` | `scripts/interleaved/IjfsDetection.gd:118` `var components := { "detectability_label": label, "satellite_floor": float(satellite_by_mobility.get(posture, 0.0)), "base_probability": float(detectability_label_base_probabili…` | The receiver type could not be proven. |
| `untyped_alias` | `scripts/interleaved/IjfsDetection.gd:147` `var method := "intel_locked" if target.intel_locked and target.mobility != "static" else "static_known"` | The receiver type could not be proven. |
| `untyped_alias` | `scripts/interleaved/IjfsDetection.gd:191` `var entry := { "phase": phase, "target_id": target.target_id, "source_target_id": target.source_target_id, "category": target.category, "subcategory": target.subcategory, "mobil…` | The receiver type could not be proven. |
| `callable_or_lambda` | `scripts/interleaved/IjfsDetection.gd:219` `sorted.sort_custom(func(a: IjfsTarget, b: IjfsTarget) -> bool: return a.target_id < b.target_id)` | Callable/lambda dataflow is outside this analyser. |
| `unresolved_receiver` | `scripts/interleaved/IjfsDetection.gd:219` `sorted.sort_custom(func(a: IjfsTarget, b: IjfsTarget) -> bool: return a.target_id < b.target_id)` | A protected field name appeared on an unresolved receiver. |
| `untyped_alias` | `scripts/interleaved/IjfsDetection.gd:228` `var from_object: Variant = force.get("squadrons")` | The receiver type could not be proven. |
| `untyped_alias` | `scripts/interleaved/IjfsEngagement.gd:84` `var factor := float(state.scenario.get(IjfsLoaders.SAM_RETURN_FIRE_KNOB, 0.0))` | The receiver type could not be proven. |
| `untyped_alias` | `scripts/interleaved/IjfsEngagement.gd:100` `var members_before := package.size()` | The receiver type could not be proven. |
| `untyped_alias` | `scripts/interleaved/IjfsEngagement.gd:106` `var score := maxi(1, target.sam_score)` | The receiver type could not be proven. |
| _…_ | _68 additional diagnostics omitted from this page_ | See the called class pages. |
