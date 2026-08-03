# Ordering: `ReinforcementPhases.hex_can_receive_mobilized`

> **Reading aid, not an execution contract.** No detected edge is not permission to reorder.
> GDScript reads and writes are conservative source analysis; transition writes are also
> checked against the mutation manifest. Potential conflicts may refer to different object
> instances or conditional branches.

Generator format v1; scan scope `scripts/**/*.gd` plus `project.godot` autoload aliases.
Generated from commit `7bbf08693b44`; input SHA-256 `c879af92cf7693c7df1119a11083764377c92a9410144e7b95f361f509613378`;
tool/manifest/fixture SHA-256 `ea366ecafdb8f5cc7ecae22bb7554cd8802d1ed3433c5a903ecc07bbb7230f6c`; stable generation time `2026-08-02T17:09:31-04:00`.
Unresolved-analysis diagnostics on this page: **0**.

Source: `scripts/phases/ReinforcementPhases.gd:271`

## Lexical call-site map (CALL edges)

> Source order is not an execution count: loop calls repeat, branch calls may be skipped
> or mutually exclusive, and nested arguments execute before their outer call.

```mermaid
flowchart TD
  n_67f6f1c0c5f6["1. GameDataStore.hex_owner_of (line 275)"]
  n_f14e6921f162["2. GameDataStore.get_terrain (line 280)"]
  n_67f6f1c0c5f6 -->|CALL| n_f14e6921f162
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
| 1 | `GameDataStore.hex_owner_of` at `scripts/phases/ReinforcementPhases.gd:275` | `GameDataStore.hex_states`, `HexState.hex_owner` | — | — |
| 2 | `GameDataStore.get_terrain` at `scripts/phases/ReinforcementPhases.gd:280` | `GameDataStore.hex_lookup`, `GameDataStore.terrain_types` | — | — |

## Analysis limits found here

No unresolved constructs were recorded.
