---
title: "0039: One truth about where a battalion is"
status: "Superseded by 0044"
created: "2026-07-25"
updated: "2026-07-26"
---

# Plan 0039: One truth about where a battalion is — SUPERSEDED

**Superseded by [plan 0044](0044-force-mutation-authority.md) as part of the USER-directed
mutation-authority campaign. Do the work under 0042 → 0044, not this plan.**

## Why it was superseded

This plan correctly identified the dangerous split between `Brigade.composition`, off-map pools,
transport cohorts, and brigade placement. It incorrectly proposed a derived, non-authoritative
`BattalionLedger` as an independently useful first guard.

A ledger rebuilt from the current roster and pools cannot catch the historical ghost-landing failure:
if a pool entry disappears while the roster stays unchanged, the derived subtraction simply labels
that unexplained battalion “ashore.” Its conservation equation remains true by construction. It can
only detect the bug if it already knows the intended transition or is itself authoritative.

Plan 0044 replaces that approach with one `ForceTransitions` mutation authority. Every casualty,
embark, offload, air insertion, movement, retreat, mobilization, and placement change goes through a
typed operation that preflights the source and proves exact post-transition deltas. Counts and current
serialized BN ids remain in place; battalion instances are still deferred until a concrete research
need requires individual identity.

## Preserved evidence and requirements

The historical incidents remain the acceptance tests for the replacement plan:

- crossing-drowned BN removed from a pool but not the roster (`bff4a1c`);
- partially drained mainland pool omitted from landed/census accounting (`5f79317`).

The replacement must deliberately reintroduce both one-sided failures and observe the new transition
checks fail before the phase wrapper returns. `tools/validate_pool_enumeration.gd`, runtime-index
validation, and settled-boundary roster checks remain independent backstops until plan 0044 proves
which can safely be demoted.
