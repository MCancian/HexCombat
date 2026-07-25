---
title: "0034: One home for 'battalions not yet ashore'"
status: "Shipped"
created: "2026-07-24"
closed: "2026-07-25"
---

> **CLOSED 2026-07-25.** Shipped as designed, but NOT as a pure refactor: the "a pool the census does
> not know about" failure the plan called hypothetical was already live — `SealiftState.mainland_pool`
> was never subtracted, inflating Red's `scenario_default` census by up to 8 battalions.
> Durable facts: `docs/systems/frontline-cleanup-victory.md` → "Not-ashore pools", `docs/STATUS.md`
> → Victory conditions, `docs/DECISIONS.md` 2026-07-25. Enforcement landed as
> `GameStateData.pending_battalion_pools()` (the pools live on that value object) rather than as a
> registry inside `PendingBattalions` — `TurnConductor` was at its dependency ceiling, and the object
> that owns the fields is the right home for enumerating them.
>
> **Objective 2 was delivered in its weaker form — know this before trusting it.** The plan asked for
> a mechanism making it *impossible* for a new pool to escape the census. What exists is *one obvious
> place to add it*: `census()` now takes a single pool list instead of named parameters, and both
> callers pass `pending_battalion_pools()`, so there is exactly one seam. A new pool still escapes if
> someone adds a parameter back to `census()`, or writes an independent battalion count. GDScript
> offers no compile-time check here, and shape-sniffing the pools reflectively fails on the case that
> matters (a brand-new pool starts empty, so it is indistinguishable from any other empty Array).
> Treat the enumeration as a convention with a single enforcement point, not a guarantee.

# Plan 0034: One home for pending-battalion pools

## The duplication

Three separate places hold "battalions belonging to a brigade that are not on the map yet", all in
the same shape — `{brigade_id, …, bns: [{id, type}]}`:

| Pool | Owner | Built by |
|---|---|---|
| `ship_reserve` | `GameStateData` | `ShipReserveBuilder` |
| `SealiftState.mainland_pool` | sealift (plan 0004) | `ShipReserveBuilder` |
| `AirInsertionState.pool` | air insertion (plan 0032) | `AirInsertionStateBuilder.battalion_manifest` |

Two builders produce the manifests with different id conventions. The victory census has to subtract
**every** such pool from `Brigade.get_battalion_count()`, and it learns about each one by hand: plan
0032 had to widen `CleanupResolver.census` to walk a second array, and a third pool would have to
remember to do the same.

## Why this is worth fixing

The failure mode is not cosmetic. A pool the census does not know about **credits its side with
battalions that are not there** — which is exactly the ghost-landing bug
(`docs/archive/`, 2026-07-24, commit `bff4a1c`), where drowned battalions stayed in
`Brigade.composition` and inflated China's count by enough to move the flip threshold 30-60×. The
census is the victory condition; a silent miscount there invalidates every study built on it.

Right now nothing enforces that a new pool joins the census. The next mechanic that parks battalions
off-map (a rotary-wing shuttle, a second echelon, a re-embarkation) will have to rediscover the rule.

## Shape of the fix

1. **One manifest builder.** A single `battalion_manifest(brigade, id_prefix)` producing the
   `{id, type}` entries, replacing `ShipReserveBuilder`'s and
   `AirInsertionStateBuilder.battalion_manifest`'s parallel copies. Ids stay unique per brigade and
   stable, since records and fixtures contain them.
2. **One "not ashore" accessor.** Something like `PendingBattalions.by_brigade(pools: Array) -> Dictionary`
   that sums across any number of pools, with `CleanupResolver.census` taking the pool list rather
   than named parameters. `TurnConductor.air_insertion_pool()` and its ship-reserve sibling become
   one list-assembling call.
3. **A gate that fails when a pool is missed.** The valuable half. Options to weigh: a debug-build
   invariant comparing the census against an independently-computed total; or a registry of pool
   accessors that the census walks, so adding a pool without registering it is impossible rather than
   merely discouraged.

## Objectives

1. Single manifest builder, single not-ashore accessor, census takes a pool list.
2. An enforcement mechanism so a future off-map pool cannot silently escape the census.
3. No behaviour change.

## Verification

- **Golden byte-stable** — this is a pure refactor; any drift means the consolidation changed
  semantics and is wrong.
- `validate_cleanup`'s combat fingerprint and the victory validators unchanged.
- `validate_air_insertion` reproduces its current numbers (45 landed / 2 lost / census 70:84 on seed
  20260624).
- Re-run one recorded `scenario_default` game and diff the turn digests — the check that caught the
  0032 OOB addition being inert.

## Risks

- The census is victory-critical and the ghost-landing bug lives in this exact code. Do this on its
  own, with nothing else in the commit.
- BN ids appear in game records and LLM fixtures; changing an id convention is a fixture-visible
  change even when behaviour is identical. Prefer keeping both existing conventions over renaming.

## Dependencies / notes

- Independent. Touches `CleanupResolver`, `ShipReserveBuilder`, `AirInsertionStateBuilder`,
  `TurnConductor`, and the two state Resources.
- Sequence AFTER any in-flight work that adds a pool, so the consolidation absorbs it rather than
  racing it.
