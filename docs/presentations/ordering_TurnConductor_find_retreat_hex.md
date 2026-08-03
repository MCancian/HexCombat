# Ordering: `TurnConductor.find_retreat_hex`

> **Reading aid, not an execution contract.** No detected edge is not permission to reorder.
> GDScript reads and writes are conservative source analysis; transition writes are also
> checked against the mutation manifest. Potential conflicts may refer to different object
> instances or conditional branches.

Generator format v1; scan scope `scripts/**/*.gd` plus `project.godot` autoload aliases.
Generated from commit `7bbf08693b44`; input SHA-256 `c879af92cf7693c7df1119a11083764377c92a9410144e7b95f361f509613378`;
tool/manifest/fixture SHA-256 `ea366ecafdb8f5cc7ecae22bb7554cd8802d1ed3433c5a903ecc07bbb7230f6c`; stable generation time `2026-08-02T17:09:31-04:00`.
Unresolved-analysis diagnostics on this page: **1**.

Source: `scripts/phases/TurnConductor.gd:298`

## Lexical call-site map (CALL edges)

> Source order is not an execution count: loop calls repeat, branch calls may be skipped
> or mutually exclusive, and nested arguments execute before their outer call.

```mermaid
flowchart TD
  n_05c54b45276c["1. GameDataStore.get_neighbors (line 305)"]
  n_7d13548a112e["2. GameDataStore.get_terrain (line 307)"]
  n_ce40a1b1d0e8["3. GameDataStore.get_brigades_in_hex (line 312)"]
  n_6c7b6da74a61["4. GameDataStore.get_brigade (line 313)"]
  n_05c54b45276c -->|CALL| n_7d13548a112e
  n_7d13548a112e -->|CALL| n_ce40a1b1d0e8
  n_ce40a1b1d0e8 -->|CALL| n_6c7b6da74a61
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
| 1 | `GameDataStore.get_neighbors` at `scripts/phases/TurnConductor.gd:305` | `GameDataStore.neighbor_lookup` | — | — |
| 2 | `GameDataStore.get_terrain` at `scripts/phases/TurnConductor.gd:307` | `GameDataStore.hex_lookup`, `GameDataStore.terrain_types` | — | — |
| 3 | `GameDataStore.get_brigades_in_hex` at `scripts/phases/TurnConductor.gd:312` | `GameDataStore.brigades_by_hex` | — | — |
| 4 | `GameDataStore.get_brigade` at `scripts/phases/TurnConductor.gd:313` | `GameDataStore.brigades` | — | — |

## Analysis limits found here

Showing 1 of 1 diagnostics; class pages provide the narrower context.

| Kind | Source | Why it matters |
|---|---|---|
| `untyped_alias` | `scripts/phases/TurnConductor.gd:320` `var owner := String(GameData.hex_states[neighbor_id].hex_owner)` | The receiver type could not be proven. |
