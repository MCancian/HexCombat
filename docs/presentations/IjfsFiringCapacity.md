# IjfsFiringCapacity

> **Reading aid, not an execution contract.** No detected edge is not permission to reorder.
> GDScript reads and writes are conservative source analysis; transition writes are also
> checked against the mutation manifest. Potential conflicts may refer to different object
> instances or conditional branches.

Generator format v1; scan scope `scripts/**/*.gd` plus `project.godot` autoload aliases.
Generated from commit `7bbf08693b44`; input SHA-256 `c879af92cf7693c7df1119a11083764377c92a9410144e7b95f361f509613378`;
tool/manifest/fixture SHA-256 `ea366ecafdb8f5cc7ecae22bb7554cd8802d1ed3433c5a903ecc07bbb7230f6c`; stable generation time `2026-08-02T17:09:31-04:00`.
Unresolved-analysis diagnostics on this page: **2**.

## Source summary

No source summary was found; see the access tables below.

Source: `scripts/calc/IjfsFiringCapacity.gd`

## Placement in resolution code

| Caller | Call-site instance |
|---|---|
| [`IjfsEngine.run_daily`](ordering_IjfsEngine_run_daily.md) | `IjfsFiringCapacity.FiringCapacityBudget.new` at `123` |
| [`IjfsEngine.run_daily`](ordering_IjfsEngine_run_daily.md) | `IjfsFiringCapacity.FiringCapacityBudget.new` at `129` |
| [`IjfsEngine.run_daily`](ordering_IjfsEngine_run_daily.md) | `IjfsFiringCapacity.OrganicStrikeBudget.new` at `161` |

## Dependency diagram

```mermaid
flowchart LR
  n_c0794b3e0ffe["IjfsFiringCapacity"]
  n_e4731c9359c3["IjfsEngine.run_daily"] --> n_c0794b3e0ffe
```

## Inner-class boundary

This outer script's budgets are implemented as inner classes. Godot reflects their
signatures but exposes no body AST, so their class-level effect table is intentionally
incomplete. Follow the linked Placement rows to inspect effects at each call site.

## Model-field evidence

| Field | Read | Written |
|---|:---:|:---:|
| _No persistent model field was resolved_ | | |

## Method dependencies

| Method | Calls (transitive effects are included above) |
|---|---|

## Analysis limits found here

Showing 2 of 2 diagnostics; class pages provide the narrower context.

| Kind | Source | Why it matters |
|---|---|---|
| `inner_class_unanalysed` | `scripts/calc/IjfsFiringCapacity.gd:0` `inner class FiringCapacityBudget` | Godot reflected an inner class, but its indented method bodies are not analysed. |
| `inner_class_unanalysed` | `scripts/calc/IjfsFiringCapacity.gd:0` `inner class OrganicStrikeBudget` | Godot reflected an inner class, but its indented method bodies are not analysed. |
