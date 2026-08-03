# State transition dictionary

> **Reading aid, not an execution contract.** No detected edge is not permission to reorder.
> GDScript reads and writes are conservative source analysis; transition writes are also
> checked against the mutation manifest. Potential conflicts may refer to different object
> instances or conditional branches.

Generator format v1; scan scope `scripts/**/*.gd` plus `project.godot` autoload aliases.
Generated from commit `7bbf08693b44`; input SHA-256 `c879af92cf7693c7df1119a11083764377c92a9410144e7b95f361f509613378`;
tool/manifest/fixture SHA-256 `ea366ecafdb8f5cc7ecae22bb7554cd8802d1ed3433c5a903ecc07bbb7230f6c`; stable generation time `2026-08-02T17:09:31-04:00`.
Unresolved-analysis diagnostics on this page: **103**.

This is a generated view of transition-method effects. Ownership remains authoritative only in
`tools/mutation_authority_manifest.json`.

| Transition method | Model fields it may write |
|---|---|
| `AirInsertionTransitions.rebuild_air_insertion_state` | `AirInsertionState.caps`, `AirInsertionState.initial_caps`, `AirInsertionState.pool`, `GameStateData.air_insertion_state` |
| `AirInsertionTransitions.record_insertions` | `AirInsertionState.caps`, `AirInsertionState.history` |
| `AntishipTransitions._reproject` | `AntishipSystem.destroyed`, `AntishipSystem.quantity` |
| `AntishipTransitions.apply_ijfs_effects` | `AntishipSystem.destroyed`, `AntishipSystem.ijfs_destroyed_cumulative`, `AntishipSystem.quantity`, `AntishipSystem.suppressed_now` |
| `AntishipTransitions.apply_launch_attrition` | `AntishipSystem.active`, `AntishipSystem.destroyed`, `AntishipSystem.destroyed_this_turn`, `AntishipSystem.fired`, `AntishipSystem.launch_destroyed_cumulative`, `AntishipSystem.quantity`, `GameStateData._antiship_launch_turn` |
| `AntishipTransitions.ensure_establishment` | `AntishipSystem.detectability`, `AntishipSystem.ijfs_profile`, `AntishipSystem.original_quantity`, `AntishipSystem.quantity`, `AntishipSystem.special`, `AntishipSystem.to_number`, `AntishipSystem.type_id`, `AntishipSystem.type_name`, `GameStateData._antiship_built`, `GameStateData.antiship_containers`, `GameStateData.antiship_systems` |
| `AntishipTransitions.reset_establishment` | `GameStateData._antiship_built`, `GameStateData._antiship_launch_turn`, `GameStateData.antiship_containers`, `GameStateData.antiship_systems` |
| `AntishipTransitions.reset_transient_flags` | `AntishipSystem.active`, `AntishipSystem.destroyed_this_turn`, `AntishipSystem.fired`, `AntishipSystem.suppressed_now` |
| `ForceTransitions._apply_crossing_roster_losses` | `Battalion.qty`, `Brigade.composition`, `Brigade.destroyed`, `Brigade.hex_id`, `GameDataStore.brigades_by_hex` |
| `ForceTransitions._apply_first_offload_placements` | `Brigade.entry_bearing`, `Brigade.hex_id`, `GameDataStore.brigades_by_hex` |
| `ForceTransitions._apply_hex` | `Brigade.hex_id`, `GameDataStore.brigades_by_hex` |
| `ForceTransitions._apply_roster_loss` | `Battalion.qty`, `Brigade.composition` |
| `ForceTransitions._commit_air_insertion` | `AirInsertionState.landed`, `AirInsertionState.pool`, `Battalion.qty`, `Brigade.composition`, `Brigade.destroyed`, `Brigade.entry_bearing`, `Brigade.hex_id`, `GameDataStore.brigades_by_hex` |
| `ForceTransitions._commit_embark` | `SealiftCohort.bn_ids`, `SealiftCohort.cohort_state`, `SealiftCohort.hulls_by_type`, `SealiftState.cohorts`, `SealiftState.mainland_pool` |
| `ForceTransitions._commit_mobilization` | `Brigade.entry_bearing`, `Brigade.hex_id`, `GameDataStore.brigades_by_hex`, `MobilizationState.pending`, `MobilizationState.released` |
| `ForceTransitions._drop_empty_air_pool_entries` | `AirInsertionState.pool` |
| `ForceTransitions.apply_activity` | `Brigade.fought_last_turn`, `Brigade.fought_this_turn`, `Brigade.moved_admin_this_turn`, `Brigade.moved_last_turn`, `Brigade.moved_this_turn`, `Brigade.organization` |
| `ForceTransitions.apply_air_insertion_outcome` | `AirInsertionState.landed`, `AirInsertionState.pool`, `Battalion.qty`, `Brigade.composition`, `Brigade.destroyed`, `Brigade.entry_bearing`, `Brigade.hex_id`, `GameDataStore.brigades_by_hex` |
| `ForceTransitions.apply_battalion_casualties` | `Battalion.qty`, `Brigade.composition`, `Brigade.destroyed`, `Brigade.hex_id`, `GameDataStore.brigades_by_hex` |
| `ForceTransitions.apply_crossing_loss` | `Battalion.qty`, `Brigade.composition`, `Brigade.destroyed`, `Brigade.hex_id`, `GameDataStore.brigades_by_hex` |
| `ForceTransitions.apply_embark` | `SealiftCohort.bn_ids`, `SealiftCohort.cohort_state`, `SealiftCohort.hulls_by_type`, `SealiftState.cohorts`, `SealiftState.mainland_pool` |
| `ForceTransitions.apply_offload` | `Brigade.entry_bearing`, `Brigade.hex_id`, `GameDataStore.brigades_by_hex` |
| `ForceTransitions.apply_queue_jlsf` | `SealiftState.mainland_pool` |
| `ForceTransitions.apply_sent_cohort` | `SealiftCohort.bn_ids`, `SealiftCohort.cohort_state`, `SealiftCohort.hulls_by_type`, `SealiftState.cohorts` |
| `ForceTransitions.free_emptied_cohorts` | `SealiftState.cohorts` |
| `ForceTransitions.initialize_ship_reserve` | `GameStateData.ship_reserve` |
| `ForceTransitions.latch_prior_activity` | `Brigade.fought_last_turn`, `Brigade.fought_this_turn`, `Brigade.moved_admin_this_turn`, `Brigade.moved_last_turn`, `Brigade.moved_this_turn`, `Brigade.organization` |
| `ForceTransitions.place_brigade` | `Brigade.entry_bearing`, `Brigade.hex_id`, `GameDataStore.brigades_by_hex` |
| `ForceTransitions.rebuild_mobilization_state` | `GameStateData.mobilization_state`, `MobilizationState.pending` |
| `ForceTransitions.release_mobilized_brigades` | `Brigade.entry_bearing`, `Brigade.hex_id`, `GameDataStore.brigades_by_hex`, `MobilizationState.pending`, `MobilizationState.released` |
| `ForceTransitions.remove_brigade_from_map` | `Brigade.entry_bearing`, `Brigade.hex_id`, `GameDataStore.brigades_by_hex` |
| `ForceTransitions.reset_placement_index` | `GameDataStore.brigades_by_hex` |
| `IjfsTransitions.add_targets` | `IjfsDailyState.targets` |
| `IjfsTransitions.advance_day` | `GameStateData._ijfs_day` |
| `IjfsTransitions.apply_activity_posture` | `IjfsTarget.posture` |
| `IjfsTransitions.apply_detection_results` | `IjfsTarget.detected_this_turn`, `IjfsTarget.known_to_red`, `IjfsTarget.last_detected_day` |
| `IjfsTransitions.apply_package_member_loss` | `IjfsSquadron.alive`, `IjfsSquadron.losses_campaign`, `IjfsSquadron.losses_today`, `IjfsSquadron.rtb_today`, `IjfsSquadron.sead_assigned_today` |
| `IjfsTransitions.apply_sead_destruction` | `IjfsTarget.destroyed`, `IjfsTarget.detected_this_turn`, `IjfsTarget.known_to_red`, `IjfsTarget.sead_result`, `IjfsTarget.suppressed`, `IjfsTarget.suppressed_this_turn` |
| `IjfsTransitions.apply_sead_suppression` | `IjfsTarget.sead_result`, `IjfsTarget.suppressed`, `IjfsTarget.suppressed_this_turn` |
| `IjfsTransitions.apply_squadron_losses` | `IjfsSquadron.alive`, `IjfsSquadron.losses_campaign`, `IjfsSquadron.losses_today`, `IjfsSquadron.rtb_today`, `IjfsSquadron.sead_assigned_today` |
| `IjfsTransitions.apply_strike_destruction` | `IjfsTarget.destroyed`, `IjfsTarget.known_to_red`, `IjfsTarget.suppressed`, `IjfsTarget.suppressed_this_turn` |
| `IjfsTransitions.apply_strike_suppression` | `IjfsTarget.suppressed`, `IjfsTarget.suppressed_this_turn` |
| `IjfsTransitions.apply_warmup_posture_override` | `IjfsTarget.posture` |
| `IjfsTransitions.assign_to_sead` | `IjfsSquadron.sead_assigned_today` |
| `IjfsTransitions.book_rtb` | `IjfsSquadron.rtb_today` |
| `IjfsTransitions.carry_to_next_day` | `IjfsSquadron.losses_today`, `IjfsSquadron.rtb_today`, `IjfsSquadron.sead_assigned_today`, `IjfsTarget.sead_result`, `IjfsTarget.suppressed`, `IjfsTarget.suppressed_this_turn` |
| `IjfsTransitions.consume_munition` | `IjfsMunition.inventory_remaining` |
| `IjfsTransitions.install_daily_state` | `GameStateData._ijfs_day`, `GameStateData.ijfs_state` |
| `IjfsTransitions.mark_intel_locked` | `IjfsTarget.intel_locked` |
| `IjfsTransitions.mark_sead_unengaged` | `IjfsTarget.sead_result` |
| `IjfsTransitions.reset_daily_state` | `GameStateData._ijfs_day`, `GameStateData.ijfs_state` |
| `IjfsTransitions.retire_target` | `IjfsTarget.destroyed` |
| `IjfsTransitions.set_manpads_remaining` | `IjfsTarget.manpads_remaining`, `IjfsTarget.metadata[systems_remaining]` |
| `InfrastructureTransitions._set_marker` | `InfrastructureNodeState.jlsf` |
| `InfrastructureTransitions.apply_node_plan` | `InfrastructureNodeState.node_status`, `InfrastructureNodeState.repair_turns_remaining` |
| `InfrastructureTransitions.clear_jlsf` | `InfrastructureNodeState.jlsf` |
| `InfrastructureTransitions.mark_jlsf_arrived` | `InfrastructureNodeState.jlsf` |
| `InfrastructureTransitions.mark_jlsf_enroute` | `InfrastructureNodeState.jlsf` |
| `InfrastructureTransitions.queue_jlsf` | `InfrastructureNodeState.jlsf` |
| `InfrastructureTransitions.rebuild_infrastructure` | `GameStateData.infrastructure_state`, `InfrastructureState.nodes` |
| `MapTransitions.apply_feba_delta` | `HexState.feba_km` |
| `MapTransitions.clear_feba` | `HexState.feba_km` |
| `MapTransitions.clear_hex_states` | `GameDataStore.hex_states` |
| `MapTransitions.initialize_hex_states` | `GameDataStore.hex_states` |
| `MapTransitions.recompute_ownership` | `HexState.hex_owner` |
| `MapTransitions.reset_hex_states` | `GameDataStore.hex_states` |
| `OrderTransitions.add_air_insert_order` | `GameStateData.air_insert_orders` |
| `OrderTransitions.add_commit_order` | `GameStateData.commitments` |
| `OrderTransitions.add_jlsf_order` | `GameStateData.jlsf_orders` |
| `OrderTransitions.add_move_order` | `GameStateData.orders` |
| `OrderTransitions.apply_bulk_order` | `GameStateData.air_insert_orders`, `GameStateData.commitments`, `GameStateData.jlsf_orders`, `GameStateData.orders` |
| `OrderTransitions.clear_turn_buffers` | `GameStateData.commitments`, `GameStateData.orders` |
| `OrderTransitions.consume_air_insert_orders` | `GameStateData.air_insert_orders` |
| `OrderTransitions.consume_jlsf_orders` | `GameStateData.jlsf_orders` |
| `OrderTransitions.reset_buffers` | `GameStateData.air_insert_orders`, `GameStateData.commitments`, `GameStateData.jlsf_orders`, `GameStateData.orders` |
| `SealiftTransitions.apply_escort_consumption` | `SealiftState.escort_reload`, `SealiftState.escort_sam` |
| `SealiftTransitions.apply_hull_losses` | `ShipState.destroyed`, `ShipState.fleet_surviving_total`, `ShipState.offloading`, `ShipState.ready`, `ShipState.returning`, `ShipState.surviving_sent` |
| `SealiftTransitions.consume_ship_losses` | `GameStateData.pending_lost_at_sea` |
| `SealiftTransitions.install_campaign_state` | `GameStateData.lost_at_sea_accumulator`, `GameStateData.pending_lost_at_sea`, `GameStateData.sealift_state` |
| `SealiftTransitions.project_fleet` | `ShipState.offloading`, `ShipState.ready`, `ShipState.returning`, `ShipState.surviving_sent` |
| `SealiftTransitions.rebuild_fleet` | `GameStateData.fleet`, `ShipState.destroyed`, `ShipState.fleet_surviving_total`, `ShipState.fleet_total`, `ShipState.offloading`, `ShipState.ready`, `ShipState.returning`, `ShipState.ship_type`, `ShipState.surviving_sent` |
| `SealiftTransitions.record_crossing_carryover` | `GameStateData.lost_at_sea_accumulator` |
| `SealiftTransitions.register_ship_losses` | `GameStateData.pending_lost_at_sea` |
| `SealiftTransitions.release_hulls` | `SealiftState.return_pipeline` |
| `SealiftTransitions.swap_state` | `GameStateData.sealift_state` |
| `SealiftTransitions.tick_escort_reload` | `SealiftState.escort_reload`, `SealiftState.escort_sam` |
| `SealiftTransitions.tick_returns` | `SealiftState.return_pipeline` |
| `SupplyTransitions.apply_daily_bill` | `SupplyState.current_dos_tons`, `SupplyState.day_history` |
| `SupplyTransitions.rebuild_supply_state` | `GameStateData.supply_state`, `SupplyState.current_dos_tons`, `SupplyState.day_history` |
| `TurnLifecycleTransitions.apply_cleanup_verdict` | `GameStateData._china_has_landed`, `GameStateData.game_over`, `GameStateData.winner` |
| `TurnLifecycleTransitions.begin_next_turn` | `GameStateData.phase`, `GameStateData.turn_number` |
| `TurnLifecycleTransitions.begin_resolution` | `GameStateData.phase` |
| `TurnLifecycleTransitions.end_resolution` | `GameStateData.phase` |
| `TurnLifecycleTransitions.reset_to_turn_one` | `GameStateData._china_has_landed`, `GameStateData.game_over`, `GameStateData.phase`, `GameStateData.turn_number`, `GameStateData.winner` |

## Analysis limits found here

Showing 30 of 103 diagnostics; class pages provide the narrower context.

| Kind | Source | Why it matters |
|---|---|---|
| `callable_or_lambda` | `scripts/GameData.gd:523` `return HexMath.find_reachable(start_id, max_distance, Callable(self, "get_neighbors"), _with_impassable(blocked), Callable(self, "_terrain_entry_cost"))` | Callable/lambda dataflow is outside this analyser. |
| `multi_call_statement` | `scripts/GameData.gd:523` `return HexMath.find_reachable(start_id, max_distance, Callable(self, "get_neighbors"), _with_impassable(blocked), Callable(self, "_terrain_entry_cost"))` | Multiple calls share one statement; the map preserves lexical sites, not nested evaluation order. |
| `multi_call_statement` | `scripts/builders/AntishipSystemsBuilder.gd:19` `return { "systems": AntishipLoaders.load_systems(GROUPING_PATH, types), "containers": AntishipLoaders.load_containers(GROUPING_PATH, types), }` | Multiple calls share one statement; the map preserves lexical sites, not nested evaluation order. |
| `untyped_iteration` | `scripts/calc/ForceMobilizationValidation.gd:13` `for entry_value in state.pending:` | The collection element type could not be proven. |
| `untyped_iteration` | `scripts/calc/ForceMobilizationValidation.gd:19` `for arrival_value in request.arrivals:` | The collection element type could not be proven. |
| `untyped_alias` | `scripts/calc/ForceValidationHelper.gd:20` `var batch_ids: Variant = _unique_ids(request.batch_bn_ids, "embark batch")` | The receiver type could not be proven. |
| `untyped_iteration` | `scripts/calc/ForceValidationHelper.gd:33` `for spec_value in request.brigade_specs:` | The collection element type could not be proven. |
| `untyped_iteration` | `scripts/calc/ForceValidationHelper.gd:73` `for landing_value in request.landings:` | The collection element type could not be proven. |
| `untyped_alias` | `scripts/calc/ForceValidationHelper.gd:99` `var expected_first := not landed_bns.is_empty() and not air_state.landed.has(brigade_id)` | The receiver type could not be proven. |
| `untyped_iteration` | `scripts/calc/ForceValidationHelper.gd:122` `for landing_value in request.landings:` | The collection element type could not be proven. |
| `untyped_iteration` | `scripts/calc/ForceValidationHelper.gd:127` `for arrival_value in request.cargo_arrivals:` | The collection element type could not be proven. |
| `unresolved_receiver` | `scripts/calc/ForceValidationHelper.gd:286` `if String(battalion_value.type) == battalion_type and int(battalion_value.qty) > 0:` | A protected field name appeared on an unresolved receiver. |
| `unresolved_receiver` | `scripts/calc/ForceValidationHelper.gd:298` `for id_value in cohort.bn_ids:` | A protected field name appeared on an unresolved receiver. |
| `untyped_iteration` | `scripts/calc/ForceValidationHelper.gd:298` `for id_value in cohort.bn_ids:` | The collection element type could not be proven. |
| `unresolved_receiver` | `scripts/calc/ForceValidationHelper.gd:307` `if cohort.cohort_state != state_label:` | A protected field name appeared on an unresolved receiver. |
| `unresolved_receiver` | `scripts/calc/ForceValidationHelper.gd:309` `for id_value in cohort.bn_ids:` | A protected field name appeared on an unresolved receiver. |
| `untyped_iteration` | `scripts/calc/ForceValidationHelper.gd:309` `for id_value in cohort.bn_ids:` | The collection element type could not be proven. |
| `unresolved_receiver` | `scripts/calc/ForceValidationHelper.gd:356` `available += int(battalion_value.qty)` | A protected field name appeared on an unresolved receiver. |
| `dynamic_dispatch` | `scripts/calc/HexMath.gd:57` `return entry_cost.call(hex_id)` | A string/dynamic call has no statically known target. |
| `dynamic_dispatch` | `scripts/calc/HexMath.gd:121` `for neighbor_id in get_neighbors.call(current_id):` | A string/dynamic call has no statically known target. |
| `dynamic_dispatch` | `scripts/calc/HexMath.gd:133` `for neighbor_id in get_neighbors.call(start_id):` | A string/dynamic call has no statically known target. |
| `untyped_iteration` | `scripts/calc/HexOwnershipCalculator.gd:27` `for brigade_id_value in data_store.get_brigades_in_hex(hex_id):` | The collection element type could not be proven. |
| `untyped_alias` | `scripts/calc/Movement.gd:19` `var nato_type_lower := brigade.nato_type.to_lower()` | The receiver type could not be proven. |
| `multi_call_statement` | `scripts/calc/OrderValidator.gd:51` `return OrderResult.reject(OrderResult.Code.TEAM_MISMATCH, "Move order team mismatch for %s: order=%s brigade=%s" % [order.brigade_id, Brigade.team_name(team), Brigade.team_name(…` | Multiple calls share one statement; the map preserves lexical sites, not nested evaluation order. |
| `untyped_alias` | `scripts/calc/OrderValidator.gd:62` `var reachable := store.find_reachable(brigade.hex_id, allowance)` | The receiver type could not be proven. |
| `multi_call_statement` | `scripts/calc/OrderValidator.gd:78` `return OrderResult.reject(OrderResult.Code.TEAM_MISMATCH, "Commit order team mismatch for %s: order=%s brigade=%s" % [order.brigade_id, Brigade.team_name(team), Brigade.team_nam…` | Multiple calls share one statement; the map preserves lexical sites, not nested evaluation order. |
| `untyped_iteration` | `scripts/calc/OrderValidator.gd:133` `for pending_value in state.air_insert_orders:` | The collection element type could not be proven. |
| `untyped_iteration` | `scripts/calc/OrderValidator.gd:201` `for pending_order in state.orders[team]:` | The collection element type could not be proven. |
| `untyped_iteration` | `scripts/calc/OrderValidator.gd:205` `for pending_commitment in state.commitments[team]:` | The collection element type could not be proven. |
| `nested_index_unanalysed` | `scripts/loaders/AntishipLoaders.gd:19` `types[int(entry["id"])] = { "name": String(entry.get("name", "")), "detectability": String(entry.get("detectability", "")), "deprecated": bool(entry.get("deprecated", false)), "…` | Nested collection indexes exceed the balanced-chain subset; this statement contributes no field effects. |
| _…_ | _73 additional diagnostics omitted from this page_ | See the called class pages. |
