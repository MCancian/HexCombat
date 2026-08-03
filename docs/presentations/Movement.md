# Movement

> **Reading aid, not an execution contract.** No detected edge is not permission to reorder.
> GDScript reads and writes are conservative source analysis; transition writes are also
> checked against the mutation manifest. Potential conflicts may refer to different object
> instances or conditional branches.

Generator format v1; scan scope `scripts/**/*.gd` plus `project.godot` autoload aliases.
Generated from commit `7bbf08693b44`; input SHA-256 `c879af92cf7693c7df1119a11083764377c92a9410144e7b95f361f509613378`;
tool/manifest/fixture SHA-256 `ea366ecafdb8f5cc7ecae22bb7554cd8802d1ed3433c5a903ecc07bbb7230f6c`; stable generation time `2026-08-02T17:09:31-04:00`.
Unresolved-analysis diagnostics on this page: **1**.

## Source summary

No source summary was found; see the access tables below.

Source: `scripts/calc/Movement.gd`

## Placement in resolution code

| Caller | Call-site instance |
|---|---|
| `GameController._update_reachable` | `Movement.move_allowance` at `82` |
| `LLMGameAPI._legal_move_observations` | `Movement.move_allowance` at `491` |
| `LLMGameAPI._legal_move_observations` | `Movement.move_allowance` at `491` |
| [`Movement.administrative_speed`](Movement.md) | `Movement.is_fast_mobility` at `32` |
| [`Movement.move_allowance`](Movement.md) | `Movement.tactical_speed` at `38` |
| [`Movement.move_allowance`](Movement.md) | `Movement.administrative_speed` at `40` |
| [`Movement.tactical_speed`](Movement.md) | `Movement.is_fast_mobility` at `28` |
| [`OrderValidator.check_move_order`](OrderValidator.md) | `Movement.move_allowance` at `61` |

## Dependency diagram

```mermaid
flowchart LR
  n_c0aa7747566b["Movement"]
  n_11e025ebe7be["GameController._update_reachable"] --> n_c0aa7747566b
  n_811ab3d2b54e["LLMGameAPI._legal_move_observations"] --> n_c0aa7747566b
  n_87acd946c942["Movement.administrative_speed"] --> n_c0aa7747566b
  n_1e4cf79f89b9["Movement.move_allowance"] --> n_c0aa7747566b
  n_519a2f45f62f["Movement.tactical_speed"] --> n_c0aa7747566b
  n_faa166acdb0e["OrderValidator.check_move_order"] --> n_c0aa7747566b
  n_c0aa7747566b --> n_8e4baa446c61["Movement.administrative_speed"]
  n_c0aa7747566b --> n_c9f89a8b88cd["Movement.is_fast_mobility"]
  n_c0aa7747566b --> n_9777a4e2d4f3["Movement.tactical_speed"]
```

## Model-field evidence

| Field | Read | Written |
|---|:---:|:---:|
| `Brigade.nato_type` | yes |  |

## Method dependencies

| Method | Calls (transitive effects are included above) |
|---|---|
| `administrative_speed` | `Movement.is_fast_mobility` |
| `is_fast_mobility` | — |
| `move_allowance` | `Movement.administrative_speed`, `Movement.tactical_speed` |
| `tactical_speed` | `Movement.is_fast_mobility` |

## Analysis limits found here

Showing 1 of 1 diagnostics; class pages provide the narrower context.

| Kind | Source | Why it matters |
|---|---|---|
| `untyped_alias` | `scripts/calc/Movement.gd:19` `var nato_type_lower := brigade.nato_type.to_lower()` | The receiver type could not be proven. |
