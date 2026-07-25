---
title: "0034: One home for 'battalions not yet ashore'"
status: "Sketch"
created: "2026-07-24"
---

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
