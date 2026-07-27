---
title: "0049: Accounting and turn-lifecycle mutation authority"
status: "Sketch"
created: "2026-07-26"
---

# Plan 0049: Accounting and turn-lifecycle mutation authority

## Goal

Finish domain migration for mutable runtime state that is not a physical force/platform aggregate:
DOS supply balance/history, order buffers, turn/phase lifecycle, victory latches, and last-result
projections. Preserve `GameStateData` as a plain value object and `TurnConductor` as the sole owner of
phase order while ensuring these fields also have named mutation APIs.

## Settled constraints

- `GameStateData` remains data-only; do not turn it into a God object with gameplay methods.
- `GameState` remains the autoload façade/lifecycle entrypoint; no new autoloads.
- `TurnConductor.resolve_turn` remains the only full phase-order list.
- Orders enter through validation APIs; external action `type` and internal order `kind` remain
  separate boundaries.
- `SupplyState.current_dos_tons` is authoritative; `day_history` is its audit ledger.
- Victory census is derived fresh; `game_over`, `winner`, and `_china_has_landed` are latches applied
  together from one cleanup result.
- Summary/observation Dictionaries are serialized projections, not writable state authorities.

## Aggregate authorities

### SupplyTransitions

`SupplyTransitions` lives at `scripts/transitions/SupplyTransitions.gd` as the exact sanctioned
writer. `SupplyResolver` calculates consumption and a typed balance transition without mutating
`SupplyState`. `SupplyTransitions` alone applies:

- pool before/consumed/pool after;
- clamp-at-zero behavior;
- effectiveness state if stored;
- append-only day-history row.

It proves the new row starts from the prior authoritative balance and ends at the applied balance.
Do not add a second independently maintained initial-minus-consumption total.

### OrderTransitions

`OrderTransitions` lives at `scripts/transitions/OrderTransitions.gd` as the exact sanctioned writer.
Split the current `OrderValidator`: pure legality/eligibility calculation may retain that name under
`scripts/calc/`, while only `OrderTransitions` appends or clears buffers. The authority owns additions,
rejection receipts, and clearing of:

- move orders;
- commitments;
- air-insert orders, including consumption/removal after their resolution in the handoff from plan
  0048;
- JLSF orders, including consumption/removal after their resolution.

Validation remains domain-specific and typed. Bulk/internal and LLM boundaries call the same
sanctioned buffer operations without forcing their external vocabularies to merge.

### TurnLifecycleTransitions

`TurnLifecycleTransitions` lives at `scripts/transitions/TurnLifecycleTransitions.gd` and is the exact
only writer for:

- phase and turn number;
- per-turn buffer reset trigger;
- game-over/winner/landing latches;
- last-summary/result slots and disabled-phase clearing where those are runtime lifecycle facts.

It does **not** decide phase order or calculate summaries. `TurnConductor` and phase coordinators
submit typed lifecycle operations at the existing seams. Domain authorities continue to own their
own transient reset semantics; lifecycle invokes them rather than editing domain fields.

If metrics show summary-slot application is too broad for one authority, split a small
`TurnResults` projection writer, but do not leave each phase wrapper assigning arbitrary
`GameStateData` fields.

## Required invariants

- legal phase transitions only: PLANNING → RESOLUTION → END → PLANNING;
- turn increments exactly once on END → PLANNING;
- no order accepted outside planning and no buffer silently survives begin-next-turn;
- rejection never partially appends;
- supply history forms a chain and matches `current_dos_tons` after every applied row;
- winner/game_over/reason-compatible latch fields update from one cleanup receipt;
- `_china_has_landed` is monotone;
- last-result slots identify their resolved turn and are cleared/replaced on the established schedule;
- lifecycle operations consume no Dice and cannot change phase ordering.

## Commit sequence

1. **Inventory and characterize.** Register direct writes to supply, order buffers, phase/turn,
   victory latches, and summary slots. Pin legal/rejected orders, phase transitions, cleanup latch,
   and supply history.
2. **Supply split.** Make `SupplyResolver` return a typed transition; apply it through
   `SupplyTransitions` and prove history chaining. Keep public summaries byte-stable.
3. **Order authority.** Route all four buffers and clearing through `OrderTransitions`; preserve
   `OrderResult` codes/messages and LLM behavior.
4. **Victory/latch authority.** Apply cleanup verdict and landing latch atomically from the existing
   `CleanupSummary`/typed receipt.
5. **Phase/turn authority.** Move phase changes, turn increments, and reset sequencing behind legal
   lifecycle methods without moving the actual ordered phase list.
6. **Summary projections.** Route `last_*` application/clearing through named methods or a focused
   results writer so phase calculators do not assign public state ad hoc.
7. **Domain reset calls.** Replace cleanup/begin-next-turn direct field resets with calls to the
   relevant domain authorities established in 0043–0048.
8. **Role placement.** Move supply calculation and order legality/eligibility to `scripts/calc/`
   only after protected writes are absent. Remove or make read-only the broad `GameState` forwarding
   setters for protected fields; a façade must not bypass the authorities. Preserve `.gd.uid` files
   and update manifest/path anchors mechanically.
9. **Close the gate.** Remove accounting/lifecycle legacy writers and prove direct writes, façade
   setters, model-mutator/dynamic bypasses, wrong-authority writes, and illegal phase transitions fail.

## Tests and validation

Required authority tests under `tests/transitions/`:

- every legal and illegal phase transition;
- begin-next-turn increments/clears once and preserves campaign-persistent state;
- duplicate/invalid order rejection leaves buffers unchanged;
- internal bulk and LLM action paths produce identical accepted buffers;
- supply normal drain, zero clamp, no-consumption day, and multi-day history chain;
- cleanup verdict atomically updates all latches and landing monotonicity;
- summaries/events are built before buffers clear and retain current ordering;
- disabled phases clear only their established outputs;
- no lifecycle operation consumes or derives Dice;
- unauthorized field assignment caught by the authority gate.

Verification:

- order, supply, cleanup, victory, LLM API, and turn-engine suites/validators;
- event and fixture drift checks;
- canonical golden and full gate after every commit;
- one multi-game same-process reset test;
- mutation-authority deliberate red tests.

## Out of scope

- New orders or action-schema vocabulary.
- Victory-condition or supply-balance changes.
- Changing phase order or adding phases.
- Making `GameStateData` immutable or event-sourced.
- A universal transaction log or replay engine.
- Replacing EventBus.

## Risks and stop conditions

- **God lifecycle authority:** keep it to legal application of already-decided transitions. It must
  not calculate combat, supply, victory, or phase outcomes.
- **Event ordering:** order buffers must still exist when `TurnEventLog.build` reads them.
- **Public API drift:** preserve `OrderResult`, `TurnResult`, observation, and action response shapes.
- **Dependency ceilings:** `GameState`, `TurnConductor`, and `TurnClosure` are ceilinged. Controller
  calls must replace dependencies or be introduced through a prior extraction.
- Stop if summary-slot centralization increases coupling without preventing a real write class; it is
  acceptable to register a phase coordinator as the sole projection writer when the state is purely
  `last_*` output rather than an evolving quantity.

## Closeout homes

On shipment: `docs/STATUS.md`; `docs/systems/supply-dos.md`, `llm-api-selfplay.md`,
`frontline-cleanup-victory.md`, and `turn-engine.md`; authority headers and architecture skill;
`docs/DECISIONS.md`; plan archived. Owning docs update their short numbered **State & authority**
section with aggregate, authority, operation-specific outcome/receipt types, and manifest link only.

## Dependencies

Requires all prior authority APIs, especially 0043 for anti-ship cleanup and 0048 for reinforcement
order clearing. Execute after 0048 and before the repository-wide closeout in 0050.
