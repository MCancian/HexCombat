# Plan 0058 — Make OffloadCalculator a pure calculator

> **Shipped 2026-08-02.** `OffloadCalculator` is pure in `scripts/calc/`; ForceTransitions now
> validates and applies banked offload progress as part of its offload transaction.
> **Facts:** `docs/systems/amphibious-offload/`; **evidence:** byte-stable full validation gate.

**Status:** ✅ Shipped

## Progress

- Preflight complete: the only campaign writes in `OffloadCalculator` are the bank and erase of
  `offload_progress_tons`; the bank is deferrable because `ForceTransitions` maintains one reserve
  entry per brigade.
- An independent review reshaped the update contract and test matrix below.
- AGY and opencode plan reviews completed: both confirmed the architecture; their required
  companion edits are incorporated below.
- Shipped; all plan steps complete.

## Golden-pin budget

**None.** This is a byte-stable refactor: no formulas, offload order, or RNG topology may change.
`tools/validate_headless_offload.gd`, `tools/validate_headless_turn.gd`, and
`tools/validate_cleanup.gd` must retain their existing pins.

## Dependencies

Required reading: `hexcombat-architecture-contract`, `hexcombat-change-control`,
`hexcombat-code-quality`, `hexcombat-validation-and-qa`, and `hexcombat-plan-review`.

## Goal

Move `OffloadCalculator` from `scripts/` root to `scripts/calc/` by making it genuinely pure:
it returns cross-turn offload-progress outcomes, and `ForceTransitions` applies those outcomes to
the force aggregate's `ship_reserve`.

## Preflight evidence

- `OffloadCalculator._resolve_day_n` reads banked progress, erases it for a beach landing, and
  writes it when beach capacity partially advances a BN. The input is live `state.ship_reserve`:
  `ReinforcementPhases` passes it to `OffloadResolver`, which passes the same entries through
  `troop_reserve` to the calculator.
- The state is intentionally cross-turn (plan 0006 C8), so the refactor preserves the bank rather
  than removing it. No dice are consumed in the offload pipeline.
- A duplicate brigade ID would make a deferred update non-deferrable, but the production embark
  route cannot create one: `ForceTransitions._merge_reserve_entry` merges by brigade ID. Add a
  fail-loud duplicate-priority assertion to the calculator because malformed input would otherwise
  double-process the final entry.
- `ForceTransitions.apply_offload` already receives the live reserve and a typed
  `ForceOffloadRequest`; its measured dependency count remains 30, and this plan adds no dependency.
  `OffloadCalculator` has 3 dependencies. The path move does not alter either class name.

## Implementation

1. Have `OffloadCalculator.resolve_offload_day` return an internal `progress_updates` array of
   `{brigade_id, bn_id, previous_progress_tons, offload_progress_tons}` rows, where the latter is
   an absolute target. It computes those rows without mutating a handed BN dictionary; its landing
   and deferral manifests retain their existing public shapes. Reject duplicate priority brigade IDs
   before resolution so malformed duplicate reserve entries fail loud rather than double-process.
2. Keep `progress_updates` out of the public manifest: `OffloadResolver` extracts it from the
   calculator result before returning/emitting the existing manifest, then carries it only in a
   deep-copied `ForceOffloadRequest`.
3. Extend `ForceValidationHelper.preflight_offload` to reject empty, duplicate, missing, JLSF,
   landed/cargo-overlapping, non-finite, non-positive, non-monotonic, or stale/replayed progress
   updates before any state change. Each accepted update must name one reserve BN and one
   offloading-cohort occurrence, and its current progress must exactly match
   `previous_progress_tons`. Have `ForceTransitions.apply_offload` apply the validated updates to
   the live reserve before its existing placement/removal transaction.
4. Move `OffloadCalculator.gd` and its `.uid` into `scripts/calc/`. Remove it from
   `ROOT_FILE_POLICY`, re-key its path-keyed parameter-ceiling entries, and replace stale blind-spot
   caveats with the truthful pure boundary. Remove the root-policy error text that names the former
   exception, and update the metric-script comment that still names the root path.
5. Update the calculator suite to prove the input remains byte-identical while its returned update
   plan preserves heavy-BN carry-over and rejects duplicate priorities. Update transition tests to
   prove application, atomic refusal, and stale-update rejection. Exercise `OffloadResolver` wiring
   plus a following-day resolution; cover a pre-banked BN routed through infrastructure, which must
   land without a new update. Update all stale code headers, the offload system docs, and tracking
   homes.

## Review findings incorporated

- The update plan is an internal force request, not a public manifest field: the offload event,
  `TurnResult`, and fixtures retain their existing payload shape.
- Update rows now carry both prior and target values, allowing the authority to reject replay and
  stale results before writing. Existing landing validation alone is insufficient for that guarantee.
- The path move must re-key `gd_metrics.py` parameter ceilings; stale path entries are gated.
- The policy's stale `OffloadCalculator` allowlist entry and hard-coded former-root wording must
  both leave with the file. The current calculator tests that assert an in-place BN mutation move
  their assertions to returned update rows and authority application.

## Explicitly out of scope (checked, do not re-raise)

- General interprocedural alias/container analysis in
  `tools/validate_authority_call_placement.gd`: this plan removes the one bounded current
  instance; a general scan needs separate evidence and design.
- Rebalancing offload costs, beach capacity, infrastructure routing, or the plan 0006 carry-over
  rule: this change preserves each exactly and must leave goldens byte-stable.
