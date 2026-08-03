# IjfsWarmup

> **Reading aid, not an execution contract.** No detected edge is not permission to reorder.
> GDScript reads and writes are conservative source analysis; transition writes are also
> checked against the mutation manifest. Potential conflicts may refer to different object
> instances or conditional branches.

Generator format v1; scan scope `scripts/**/*.gd` plus `project.godot` autoload aliases.
Generated from commit `7bbf08693b44`; input SHA-256 `c879af92cf7693c7df1119a11083764377c92a9410144e7b95f361f509613378`;
tool/manifest/fixture SHA-256 `ea366ecafdb8f5cc7ecae22bb7554cd8802d1ed3433c5a903ecc07bbb7230f6c`; stable generation time `2026-08-02T17:09:31-04:00`.
Unresolved-analysis diagnostics on this page: **0**.

## Source summary

Port of ijfs_standalone/warmup_profiles.py. Prelanding warmup attrition-profile helpers. Profiles scale daily firing capacity only; per-strike kill probabilities stay owned by the munition-target pairings and strike resolution.

Source: `scripts/calc/IjfsWarmup.gd`

## Placement in resolution code

| Caller | Call-site instance |
|---|---|
| [`IjfsResolver.build_warmup_context`](IjfsResolver.md) | `IjfsWarmup.profile_multiplier` at `84` |
| [`IjfsResolver.build_warmup_context`](IjfsResolver.md) | `IjfsWarmup.scale_firing_capacity` at `85` |

## Dependency diagram

```mermaid
flowchart LR
  n_19c42b0ae313["IjfsWarmup"]
  n_944cf26bccb2["IjfsResolver.build_warmup_context"] --> n_19c42b0ae313
```

## Model-field evidence

| Field | Read | Written |
|---|:---:|:---:|
| _No persistent model field was resolved_ | | |

## Method dependencies

| Method | Calls (transitive effects are included above) |
|---|---|
| `profile_multiplier` | — |
| `scale_firing_capacity` | — |

## Analysis limits found here

No unresolved constructs were recorded.
