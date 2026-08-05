---
title: "0062: Type the off-map battalion pools (close the aliased-container blind spot)"
status: "Exploring"
created: "2026-08-05"
---

# Plan 0062: Type the off-map battalion pools

## Golden-pin budget

`validate_pool_enumeration` first, then the whole `bash tools/run_all_tests.sh` gate — expect as many
re-baselines as there are serialized-output consumers of the pool shape (need to count them before
committing; `validate_headless_offload`, `validate_deep_pool_smoke`, `validate_golden_victory` are the
candidates). This budget is deliberately **provisional**: the whole point of this plan is that the
migration touches a shape a shape-probe gate compiles against (see the Design fork), so the real
re-baseline list cannot be known until step 0 is done. A future agent sets the real list the moment
the design fork is resolved.

## Goal

Give the off-map battalion pools a **typed** representation and thereby close the worst instance of
the mutation-authority "aliased-container blind spot". Today ~580+ battalion rows in the default
scenario travel through bare `Dictionary`/`Array` of the shape
`{brigade_id, locked_beach, beach_hex, offset_bearing, bns:[{id,type}]}`. The gate resolves a write's
**receiver type**, so a value reached through an untyped container has no type to resolve and the
write is *invisible* — neither permitted nor refused. That is not theoretical: `SealiftResolver`'s
last illegal write (a `ship_category` stamp into force-owned reserve rows) was found by hand in plan
0045, not by the gate, through exactly this alias.

This is the **bounded instance** the backlog item (BACKLOG.md, "Mutation-authority protection reaches
only TYPED receivers") points at: *"The `OffloadCalculator` item is the one bounded instance, and a
data point toward that measurement."* The audit (below) confirms the untyped surface is NOT a long
tail — it is one recurring shape repeated across four fields — so one model + one migration collapses
the large majority of it.

## Scope — what this plan does and what it deliberately leaves open

**In scope (commit to these):** the pool-family fields and their entry shape:
`GameStateData.ship_reserve` (first echelon), `SealiftState.mainland_pool` (follow-on), and — if the
same shape — `MobilizationState.pending`/`.released` and `AirInsertionState.pool`. These share the
`{brigade_id, …, bns:[{id,type}]}` entry shape and are the only large, durable, write-invisible
surface in the tree.

**Explicitly LEFT OPEN to a future agent (do not assume this plan resolves them):**
- **Whether to touch the `last_*` transport dicts** (`last_ijfs_summary`, `last_ijfs_air_oob`,
  `last_offload_summary`, `last_sealift_sent_by_type`, the IJFS logs). These are transport/report
  only; the backlog's "typed turn-resolution outcome" item already reasoned they must stay on the
  state regardless of any refactor. The audit found them NOT to be a blind-spot source (nothing mutates them at
  campaign-critical resolve time), so the default recommendation is to **leave them alone** — but that
  is a judgement call, not a settled invariant, and a future agent may choose to type them if another
  reason opens the seam.
- **Whether to touch the recomputed caches** (`isolated_air_landed_brigades`,
  `not_ashore_by_type`). They are recomputed per turn and read-only during the combat loop, so they are
  low risk; the audit found them out of the critical path. Default recommendation: leave alone.
- **The exact migration mechanics** described in the Approach below are a *proposal*; the Design fork
  (§ below) may require a different shaped conclusion, and the agent who implements this is expected
  to re-derive the specifics against the source rather than transcribe them.
- **Naming** of the new model(s). Everything here uses placeholder names.

## Read these first

| What | Where |
|---|---|
| The measurement (this plan's evidence base) | the Diagnosis section below, from the 2026-08-05 read-only audit |
| The one shared entry shape, in all its homes | `scripts/builders/ShipReserveBuilder.gd`, `scripts/builders/SealiftStateBuilder.gd` (`resolve_followon_reserve`), `scripts/model/PendingBattalions.gd` |
| Who consumes the pools smallest-to-largest | `scripts/model/GameStateData.gd::pending_battalion_pools`, `scripts/calc/OffloadCalculator.gd`, `scripts/calc/SealiftResolver.gd`, `scripts/calc/OffloadResolver.gd`, `scripts/transitions/ForceTransitions.gd`, `scripts/transitions/SealiftTransitions.gd` |
| **The gate this migration could break — READ THIS FIRST** | `tools/validate_pool_enumeration.gd` (a *shape* probe that matches `{brigade_id, bns}` dicts by reference) |
| Who may write what | `tools/mutation_authority_manifest.json` (the ONLY home — run `python3 tools/mutation_ownership.py` before editing) |
| The gate everything has to stay green under | `bash tools/run_all_tests.sh` |

## Diagnosis — the 2026-08-05 audit (evidence)

The audit asked *how much live campaign state travels through untyped containers*. It excluded
transport-only report dicts and per-turn recomputed caches, then counted the durable, mutable surface:

- **The off-map pool family dominates.** `GameStateData.ship_reserve` (~24 battalion rows, first
  echelon), `SealiftState.mainland_pool` (**~560 rows** in the default scenario — the auto-seeded
  deep mainland force), and `AirInsertionState.pool` (~6 brigades) all use the identical
  `{brigade_id, … , bns:[{id,type}]}` dict-of-dicts shape. All three are registered in the **force**
  aggregate as *hosted_fields*, but the gate resolves the container, not the elements — so every row
  write is invisible (the aliased-container blind spot in the manifest `_schema_rules`).
- **`MobilizationState.pending`/`.released`** use the same shape family and are declared untyped.
- **The rest is small, recomputed, or typed-on-the-inside:** `orders`/`commitments`/`fleet`/`antiship_systems`
  hold typed values once dereferenced; `isolated_air_landed_brigades`/`not_ashore_by_type` are
  recomputed; the `last_*` dicts are transport-only.

**Verdict:** the untyped surface is large in magnitude (~580+ rows) but **concentrated in one
recurring shape across four fields** — not a heterogeneous long tail. That makes it tractable as a
*single bounded migration*, which is precisely why this plan exists. The measurement also answers the
backlog's gate: the number is large enough that this *does* promote to a plan (at least for this
bounded slice).

### The mutation gate's own blind spot, concretely

```gdscript
# today — the receiver is a Dictionary, so the gate has no type to resolve:
entry["bns"].push_back({"id": "…", "type": "…"})   # invisible to validate_mutation_authority
```

The plan's point is to make that receiver typed so the gate can finally see and enforce it.

## The Design fork — MUST be resolved by the implementing agent before step 1

There is a genuine tension this plan must surface, found during the audit, that blocks a naive
migration:

- `validate_pool_enumeration.gd` closes the ghost-landing bug family by a **structural shape probe**:
  it walks live state and matches arrays **by reference identity** that look like `{brigade_id, bns}`
  dictionaries, and fails unless every such array is one of `pending_battalion_pools()`'s returns.
- If the pools become typed `Resource` collections with elements that are `Resource`s rather than
  dicts, **the shape probe no longer recognises them** — the validator could go silently vacuous
  (exactly the "proven by fixtures or it's a false negative waiting to happen" failure the repo's
  standard forbids).

So typing the pools must be paired with a decision about how the enumeration gate keeps its teeth. The
candidate resolutions (pick/refine, don't assume):
1. Teach `validate_pool_enumeration` to recognise the new typed shape (e.g. match by a marker field or
   a typed predicate instead of the dict shape heuristic), keeping the by-reference contract.
2. Keep a parallel untyped shape in one gorilla pool for the probe while typing the rest — **not
   recommended** (reintroduces the blind spot you're removing).
3. Replace the shape heuristic with an explicit typed registry/gate, and prove it with fixtures in both
   directions.

**This is the "leave the specifics open" the plan is built around.** The audit diagnosed the *need* and
the *barrier*, but did not choose a resolution; the implementing agent must.

## Approach — a proposal, re-derive against source

### Step 0 — settle the design fork (unlocks everything)
Resolve the Design fork above and write the resolution into the systems doc before touching any pool.
Produce a fixtures proof for whichever shape-recognition path the enumeration gate takes (a false
negative detector is the repo's standard, not an aspirational one).

### Step 1 — introduce the typed entry model(s) (no behavior change)
Add a typed entry `Resource` (placeholder names) for the shared shape, e.g.
`ReservePoolEntry { brigade_id: String, locked_beach: int, beach_hex: String, offset_bearing: float,
bns: Array[ReservePoolBattalion] }` with `ReservePoolBattalion { id: String, type: String }`. Build
them with the existing builders (`ShipReserveBuilder`, `SealiftStateBuilder.resolve_followon_reserve`,
and the mobilization/air builds). Keep the *semantics and ordering* byte-identical — the builders are
already deterministic and tested; only the representation changes.

### Step 2 — swap the four fields' types
`GameStateData.ship_reserve`, `SealiftState.mainland_pool`, `MobilizationState.pending`/`.released`,
and `AirInsertionState.pool` become typed containers of the new entry type. Update
`pending_battalion_pools()`, `PendingBattalions`, `OffloadCalculator`, and the resolvers/transitions
that mutate entries so every write now lands on a typed receiver the gate can resolve.

### Step 3 — register and gate
Classify the new fields/elements in `tools/mutation_authority_manifest.json` (likely `owned_models` /
typed `hosted_fields`). Ensure `validate_mutation_authority` now *rejects* an illegal pool write —
write the fixtures in both directions. The 2026-08-01 triage's standard: a detector is proven by
fixtures or it is a false negative.

### Step 4 — serialization / goldens
Determine which consumers serialize the pool shape into output, and re-baseline deliberately as one
batch (measure together; see Golden-pin budget). Confirm gate green, commit, close out per
`hexcombat-change-control` / `hexcombat-docs-and-writing` (systems doc for the mutation-authority and
sealift modules, `docs/DECISIONS.md` note, closeout header, move to `docs/archive/`).

## Traps

- **Trap 1 — the enumeration gate.** See the Design fork. Do not start migrating until you know how
  `validate_pool_enumeration` keeps matching; a typed migration that silently empties it is a
  regression dressed as a refactor.
- **Trap 2 — reference identity.** `validate_pool_enumeration` matches **by reference** (`is_same`).
  If the plan keeps any shape probe, `pending_battalion_pools()` must still return the *held* arrays,
  never `.duplicate()`/`.map()` copies — that contract is load-bearing.
- **Trap 3 — don't widen scope into the transport dicts.** The audit says leave `last_*` and the
  caches alone. Doing them here in the same migration would multiply the re-baseline surface and
  re-open BACKLOG item 1's verdict for no gate benefit. If a future agent disagrees, that is a *separate,
  deliberate* step with its own golden budget — not an incidental addition.
- **Trap 4 — ordering is semantics.** Pool order is deterministic and drives crossing order
  (each brigade inherits a beach; battalions land in pool order). Change representation, not order.

## Open questions (a future agent answers these)

1. Which Design-fork resolution keeps `validate_pool_enumeration` non-vacuous, and is it proven by
   fixtures in both directions?
2. Does any serialized output / research report consume the pool dict shape, and what is the real
   re-baseline list?
3. Do `MobilizationState.pending`/`.released` and `AirInsertionState.pool` share the exact entry shape
   (so one model covers them) or do their entries need their own fields?
4. Should the new type(s) carry only the pool fields, or also fold in `isolated_air_landed_brigades` /
   `not_ashore_by_type` are explicitly NOT in scope (recommended) — confirm before you accidentally
   expand.
