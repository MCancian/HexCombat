# Ordering: `ReinforcementPhases.isolated_air_landed_brigades`

> **Reading aid, not an execution contract.** No detected edge is not permission to reorder.
> GDScript reads and writes are conservative source analysis; transition writes are also
> checked against the mutation manifest. Potential conflicts may refer to different object
> instances or conditional branches.

Generator format v1; scan scope `scripts/**/*.gd` plus `project.godot` autoload aliases.
Generated from commit `7bbf08693b44`; input SHA-256 `c879af92cf7693c7df1119a11083764377c92a9410144e7b95f361f509613378`;
tool/manifest/fixture SHA-256 `ea366ecafdb8f5cc7ecae22bb7554cd8802d1ed3433c5a903ecc07bbb7230f6c`; stable generation time `2026-08-02T17:09:31-04:00`.
Unresolved-analysis diagnostics on this page: **10**.

Source: `scripts/phases/ReinforcementPhases.gd:347`

## Lexical call-site map (CALL edges)

> Source order is not an execution count: loop calls repeat, branch calls may be skipped
> or mutually exclusive, and nested arguments execute before their outer call.

```mermaid
flowchart TD
  n_25a6f9ac29c6["1. GameDataStore.get_brigade (line 352)"]
  n_e71e0c14947b["2. AirInsertionResolver.isolated_brigades (line 355)"]
  n_0640b15df614["3. ReinforcementPhases.red_lodgement_hexes (line 355)"]
  n_346f1f9123c0["4. GameDataStore.hex_owner_of (line 355)"]
  n_60956cd97f9b["5. GameDataStore.get_neighbors (line 355)"]
  n_25a6f9ac29c6 -->|CALL| n_e71e0c14947b
  n_e71e0c14947b -->|CALL| n_0640b15df614
  n_0640b15df614 -->|CALL| n_346f1f9123c0
  n_346f1f9123c0 -->|CALL| n_60956cd97f9b
```

## State and RNG constraints

| Earlier node | Later node | Kinds | Shared evidence |
|---|---|---|---|
| _No constraint edge resolved_ | | | This is not evidence that calls are reorderable. |

## Detected campaign-state/RNG overview

This compact diagram shows up to 40 detected RAW/WAR/WAW/RNG constraints involving protected
campaign fields. The table above remains the complete conservative evidence.

```mermaid
flowchart LR
  empty["No protected-state/RNG edge resolved"]
```

## Call-site detail

Effects include the called method and every statically resolved helper beneath it.

| # | Call site | Reads | Writes | RNG streams |
|---:|---|---|---|---|
| 1 | `GameDataStore.get_brigade` at `scripts/phases/ReinforcementPhases.gd:352` | `GameDataStore.brigades` | — | — |
| 2 | `AirInsertionResolver.isolated_brigades` at `scripts/phases/ReinforcementPhases.gd:355` | `AirInsertionState.landed`, `GameStateData.air_insertion_state` | — | — |
| 3 | `ReinforcementPhases.red_lodgement_hexes` at `scripts/phases/ReinforcementPhases.gd:355` | `GameDataStore.hex_states`, `GameDataStore.infrastructure`, `GameDataStore.red_ship_reserve`, `GameStateData.infrastructure_state`, `HexState.hex_owner`, `InfrastructureDef.hex_id`, `InfrastructureDef.kind`, `InfrastructureDef.to_number`, `InfrastructureNodeState.node_status`, `InfrastructureState.nodes` | — | — |
| 4 | `GameDataStore.hex_owner_of` at `scripts/phases/ReinforcementPhases.gd:355` | `GameDataStore.hex_states`, `HexState.hex_owner` | — | — |
| 5 | `GameDataStore.get_neighbors` at `scripts/phases/ReinforcementPhases.gd:355` | `GameDataStore.neighbor_lookup` | — | — |

## Analysis limits found here

Showing 10 of 10 diagnostics; class pages provide the narrower context.

| Kind | Source | Why it matters |
|---|---|---|
| `dynamic_dispatch` | `scripts/calc/AirInsertionResolver.gd:60` `if connected.has(source_hex) or not bool(is_red_hex.call(source_hex)):` | A string/dynamic call has no statically known target. |
| `dynamic_dispatch` | `scripts/calc/AirInsertionResolver.gd:66` `for neighbor_value in neighbors_of.call(hex_id):` | A string/dynamic call has no statically known target. |
| `dynamic_dispatch` | `scripts/calc/AirInsertionResolver.gd:68` `if connected.has(neighbor) or not bool(is_red_hex.call(neighbor)):` | A string/dynamic call has no statically known target. |
| `dynamic_dispatch` | `scripts/calc/AirInsertionResolver.gd:80` `for neighbor_value in neighbors_of.call(hex_id):` | A string/dynamic call has no statically known target. |
| `untyped_alias` | `scripts/calc/InfrastructureResolver.gd:86` `var def_val: Variant = infra_defs.get(id)` | The receiver type could not be proven. |
| `untyped_iteration` | `scripts/phases/ReinforcementPhases.gd:203` `for hex_id in GameData.hex_states.keys():` | The collection element type could not be proven. |
| `callable_or_lambda` | `scripts/phases/ReinforcementPhases.gd:355` `return AirInsertionResolver.isolated_brigades( state.air_insertion_state.landed, brigade_hexes, red_lodgement_hexes(state), func(hex_id: String) -> bool: return GameData.hex_own…` | Callable/lambda dataflow is outside this analyser. |
| `multi_call_statement` | `scripts/phases/ReinforcementPhases.gd:355` `return AirInsertionResolver.isolated_brigades( state.air_insertion_state.landed, brigade_hexes, red_lodgement_hexes(state), func(hex_id: String) -> bool: return GameData.hex_own…` | Multiple calls share one statement; the map preserves lexical sites, not nested evaluation order. |
| `multi_call_statement` | `scripts/phases/ReinforcementPhases.gd:370` `for node_value in InfrastructureResolver.red_offload_nodes( state.infrastructure_state, GameData.infrastructure, owner_by_hex()):` | Multiple calls share one statement; the map preserves lexical sites, not nested evaluation order. |
| `untyped_iteration` | `scripts/phases/ReinforcementPhases.gd:370` `for node_value in InfrastructureResolver.red_offload_nodes( state.infrastructure_state, GameData.infrastructure, owner_by_hex()):` | The collection element type could not be proven. |
