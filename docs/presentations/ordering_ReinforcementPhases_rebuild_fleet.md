# Ordering: `ReinforcementPhases.rebuild_fleet`

> **Reading aid, not an execution contract.** No detected edge is not permission to reorder.
> GDScript reads and writes are conservative source analysis; transition writes are also
> checked against the mutation manifest. Potential conflicts may refer to different object
> instances or conditional branches.

Generator format v1; scan scope `scripts/**/*.gd` plus `project.godot` autoload aliases.
Generated from commit `8829181ae4b6`; input SHA-256 `1c5ff5483615f0cca5b2767540c56e9a13e1387c4c1a3c66db909a97ad2e94fb`;
tool/manifest/fixture SHA-256 `ea366ecafdb8f5cc7ecae22bb7554cd8802d1ed3433c5a903ecc07bbb7230f6c`; stable generation time `2026-08-02T09:03:12-04:00`.
Unresolved-analysis diagnostics on this page: **0**.

Source: `scripts/phases/ReinforcementPhases.gd:36`

## Lexical call-site map (CALL edges)

> Source order is not an execution count: loop calls repeat, branch calls may be skipped
> or mutually exclusive, and nested arguments execute before their outer call.

```mermaid
flowchart TD
  n_c22e94558800["1. SealiftTransitions.rebuild_fleet (line 37)"]
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
| 1 | `SealiftTransitions.rebuild_fleet` at `scripts/phases/ReinforcementPhases.gd:37` | `ShipDef.name`, `ShipDef.total_count`, `ShipState.destroyed`, `ShipState.fleet_surviving_total`, `ShipState.fleet_total`, `ShipState.offloading`, `ShipState.ready`, `ShipState.returning`, `ShipState.ship_type`, `ShipState.surviving_sent` | `GameStateData.fleet`, `ShipState.destroyed`, `ShipState.fleet_surviving_total`, `ShipState.fleet_total`, `ShipState.offloading`, `ShipState.ready`, `ShipState.returning`, `ShipState.ship_type`, `ShipState.surviving_sent` | — |

## Analysis limits found here

No unresolved constructs were recorded.
