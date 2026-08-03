# Ordering: `FrontlinePhase.resolve_frontline_phase`

> **Reading aid, not an execution contract.** No detected edge is not permission to reorder.
> GDScript reads and writes are conservative source analysis; transition writes are also
> checked against the mutation manifest. Potential conflicts may refer to different object
> instances or conditional branches.

Generator format v1; scan scope `scripts/**/*.gd` plus `project.godot` autoload aliases.
Generated from commit `7bbf08693b44`; input SHA-256 `c879af92cf7693c7df1119a11083764377c92a9410144e7b95f361f509613378`;
tool/manifest/fixture SHA-256 `ea366ecafdb8f5cc7ecae22bb7554cd8802d1ed3433c5a903ecc07bbb7230f6c`; stable generation time `2026-08-02T17:09:31-04:00`.
Unresolved-analysis diagnostics on this page: **7**.

Source: `scripts/phases/FrontlinePhase.gd:11`

## Lexical call-site map (CALL edges)

> Source order is not an execution count: loop calls repeat, branch calls may be skipped
> or mutually exclusive, and nested arguments execute before their outer call.

```mermaid
flowchart TD
  n_125bcd5d87c5["1. FrontlineResolver.resolve (line 18)"]
  n_9443fd9997c3["2. FrontlinePhase.frontline_hex_centers (line 18)"]
  n_433e9e864ff2["3. GameDataStore.set_brigade_hex (line 20)"]
  n_b5568b1a18a6["4. FrontlineSummary.to_dict (line 21)"]
  n_248754779832["5. FrontlineSummary.to_dict (line 22)"]
  n_125bcd5d87c5 -->|CALL| n_9443fd9997c3
  n_9443fd9997c3 -->|CALL| n_433e9e864ff2
  n_433e9e864ff2 -->|CALL| n_b5568b1a18a6
  n_b5568b1a18a6 -->|CALL| n_248754779832
```

## State and RNG constraints

| Earlier node | Later node | Kinds | Shared evidence |
|---|---|---|---|
| `FrontlineResolver.resolve` (L18) | `GameDataStore.set_brigade_hex` (L20) | **RAW**, **WAR** | `Brigade.hex_id`, `FrontlineSummary.moves`, `GameStateData.last_frontline_summary` |
| `FrontlineResolver.resolve` (L18) | `FrontlineSummary.to_dict` (L21) | **RAW** | `FrontlineSummary.affected_brigades`, `FrontlineSummary.hex_sequence`, `FrontlineSummary.moves`, `GameStateData.last_frontline_summary` |
| `FrontlineResolver.resolve` (L18) | `FrontlineSummary.to_dict` (L22) | **RAW** | `FrontlineSummary.affected_brigades`, `FrontlineSummary.hex_sequence`, `FrontlineSummary.moves`, `GameStateData.last_frontline_summary` |

## Detected campaign-state/RNG overview

This compact diagram shows up to 40 detected RAW/WAR/WAW/RNG constraints involving protected
campaign fields. The table above remains the complete conservative evidence.

```mermaid
flowchart LR
  n_125bcd5d87c5["FrontlineResolver.resolve L18"]
  n_433e9e864ff2["GameDataStore.set_brigade_hex L20"]
  n_125bcd5d87c5 -->|WAR| n_433e9e864ff2
```

## Call-site detail

Effects include the called method and every statically resolved helper beneath it.

| # | Call site | Reads | Writes | RNG streams |
|---:|---|---|---|---|
| 1 | `FrontlineResolver.resolve` at `scripts/phases/FrontlinePhase.gd:18` | `Brigade.hex_id`, `Brigade.id` | `FrontlineSummary.affected_brigades`, `FrontlineSummary.hex_sequence`, `FrontlineSummary.moves`, `GameStateData.last_frontline_summary` | — |
| 2 | `FrontlinePhase.frontline_hex_centers` at `scripts/phases/FrontlinePhase.gd:18` | `GameDataStore.hexes`, `Hex.center`, `Hex.id` | — | — |
| 3 | `GameDataStore.set_brigade_hex` at `scripts/phases/FrontlinePhase.gd:20` | `Brigade.hex_id`, `Brigade.id`, `ForcePlacementRequest.brigade_id`, `ForcePlacementRequest.destination`, `ForcePlacementRequest.destination_hex`, `ForcePlacementRequest.entry_bearing`, `ForcePlacementRequest.has_entry_bearing`, `ForcePlacementRequest.phase`, `FrontlineSummary.moves`, `GameDataStore.brigades`; _+3 more_ | `Brigade.entry_bearing`, `Brigade.hex_id`, `ForcePlacementReceipt.brigade_id`, `ForcePlacementReceipt.destination`, `ForcePlacementReceipt.new_hex`, `ForcePlacementReceipt.old_hex`, `ForcePlacementReceipt.phase`, `ForcePlacementRequest.brigade_id`, `ForcePlacementRequest.destination`, `ForcePlacementRequest.destination_hex`; _+2 more_ | — |
| 4 | `FrontlineSummary.to_dict` at `scripts/phases/FrontlinePhase.gd:21` | `FrontlineSummary.affected_brigades`, `FrontlineSummary.hex_sequence`, `FrontlineSummary.moves`, `GameStateData.last_frontline_summary` | — | — |
| 5 | `FrontlineSummary.to_dict` at `scripts/phases/FrontlinePhase.gd:22` | `FrontlineSummary.affected_brigades`, `FrontlineSummary.hex_sequence`, `FrontlineSummary.moves`, `GameStateData.last_frontline_summary` | — | — |

## Analysis limits found here

Showing 7 of 7 diagnostics; class pages provide the narrower context.

| Kind | Source | Why it matters |
|---|---|---|
| `multi_call_statement` | `scripts/GameData.gd:559` `ForceTransitions.place_brigade(self, ForcePlacementRequest.ashore(brigade_id, hex_id, "GameData façade"))` | Multiple calls share one statement; the map preserves lexical sites, not nested evaluation order. |
| `nested_index_unanalysed` | `scripts/calc/FrontLineService.gd:108` `result[str(unit_ids[k])] = str(hex_sequence[idx])` | Nested collection indexes exceed the balanced-chain subset; this statement contributes no field effects. |
| `multi_call_statement` | `scripts/phases/FrontlinePhase.gd:18` `state.last_frontline_summary = FrontlineResolver.resolve(polyline_coords, frontline_hex_centers(), candidate_brigades)` | Multiple calls share one statement; the map preserves lexical sites, not nested evaluation order. |
| `untyped_iteration` | `scripts/phases/FrontlinePhase.gd:19` `for brigade_id in state.last_frontline_summary.moves.keys():` | The collection element type could not be proven. |
| `multi_call_statement` | `scripts/transitions/ForceTransitions.gd:53` `return place_brigade(data_store, ForcePlacementRequest.off_map(brigade_id, "remove"))` | Multiple calls share one statement; the map preserves lexical sites, not nested evaluation order. |
| `callable_or_lambda` | `scripts/transitions/ForceTransitions.gd:605` `data_store.brigades_by_hex[old_hex] = (data_store.brigades_by_hex[old_hex] as Array).filter( func(id: String) -> bool: return id != brigade.id)` | Callable/lambda dataflow is outside this analyser. |
| `untyped_alias` | `scripts/transitions/ForceTransitions.gd:619` `var violations := data_store.validate_runtime_indexes()` | The receiver type could not be proven. |
