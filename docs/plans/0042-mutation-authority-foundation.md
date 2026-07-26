---
title: "0042: Mutation-authority foundation"
status: "Sketch"
created: "2026-07-26"
---

# Plan 0042: Mutation-authority foundation

## Goal

Establish the one mutation rule every later plan in this campaign follows:

> **Every mutable gameplay aggregate has one named authority. Calculators return outcomes; only the
> authority applies them. Every cross-aggregate transition proves its preconditions and deltas before
> returning.**

This plan builds the convention and its mechanical enforcement. It does **not** migrate a gameplay
subsystem and must not change outcomes, serialized records, phase order, or RNG consumption.

## Settled USER direction — do not relitigate

- Every mutable game item must be changed through a controller/API rather than arbitrary field writes.
- This means one **uniform mutation discipline**, not one universal state representation and not one
  God-object controller.
- Controllers are pure `RefCounted` classes with explicit arguments. There are no new autoloads.
- Existing state shapes may remain different where their invariants differ: counts, queues, ledgers,
  persistent targets, and state machines do not need a common base class.
- Anti-ship destruction from both IJFS and launch attrition is permanent; plan 0043 is the first
  vertical implementation of this architecture.

Architecture constraints remain those in `.claude/skills/hexcombat-architecture-contract`: explicit
resolver signatures, deterministic RNG, `GameStateData` as plain runtime data, and `TurnConductor` as
phase-order owner.

## Vocabulary and boundaries

### Aggregate

A set of mutable objects whose invariants must be maintained together. Examples:

- force: brigades, battalion roster counts, off-map manifests, brigade placement index;
- anti-ship establishment: surviving launchers, permanent losses, temporary suppression;
- sealift: fleet buckets, cohorts, return pipeline, escort ammunition;
- map infrastructure: hex runtime state, seizure, repair, JLSF status.

Aggregate boundaries follow invariants, not file count. A controller may own multiple Resource types
when updating one without the others would be invalid.

### Calculator / resolver

Computes a deterministic outcome from explicit inputs. It may mutate private ephemeral working state
when that is part of an algorithm, but it does not write a protected campaign aggregate. Dice draw
order remains entirely inside the calculator/resolver and is not repeated by a controller.

### Mutation authority

The only production class allowed to change an aggregate. Its methods:

1. validate all referenced ids and expected pre-state;
2. snapshot the minimum pre-state needed to prove the transition;
3. apply the complete change;
4. validate local invariants and exact deltas;
5. return a typed domain receipt when another phase/report needs the applied facts.

Names use the domain plus `Transitions` unless the implementation review finds a clearer established
term: `AntishipTransitions`, `ForceTransitions`, `SealiftTransitions`, and so on. Do not use
`Manager`, `Controller`, or `Service` interchangeably.

### Cross-aggregate coordinator

A phase wrapper may coordinate two authorities, but may not write their protected fields itself. It
captures the requested transition, calls both authorities in a fixed order, and asserts the combined
postcondition. Existing phase modules (`FiresPhases`, `ReinforcementPhases`, `TurnClosure`) remain the
natural coordinators unless dependency ceilings require a smaller application class.

Atomic here means **fail before mutation whenever possible, then prove the complete transition before
returning**. Godot has no rollback transaction; therefore every controller must finish a transition
within one synchronous call and fail loud at the first inconsistency.

## Target call shape

```gdscript
# Calculator: consumes Dice, returns facts, does not mutate protected campaign state.
var outcome: AntishipOutcome = AntishipResolver.resolve(inputs, dice)

# Authority: consumes outcome, applies state once, proves the delta.
var receipt: AntishipTransitionReceipt = AntishipTransitions.apply_crossing_effects(
    state.antiship_systems, outcome)

# Coordinator: uses the receipt for the event/summary; it does not reconstruct the mutation.
```

Do not create a generic `MutationRequest` Dictionary or a universal `EntityController`. Domain
requests and receipts stay typed and named by their actual job. Introduce a shared receipt base only
if two shipped authorities demonstrate a genuinely identical contract.

## Mechanical enforcement design

Availability of an API is insufficient while direct field assignment remains possible. Build a
staged gate, `tools/validate_mutation_authority.gd`, with a machine-readable ownership manifest under
`tools/` (exact filename settled during implementation). The manifest is the single home for:

- aggregate name;
- protected model/state paths;
- protected fields or nested state shapes;
- authority file;
- temporary legacy writer files still awaiting migration.

The validator must:

1. fail if a manifest path or protected field no longer exists;
2. fail if an authority file is absent;
3. find direct assignment and in-place container mutation of protected state outside the authority
   and explicitly listed legacy writers;
4. fail on an unclassified mutable field added to a protected model;
5. fail vacuously if it scans zero models or zero assignments;
6. print every remaining legacy writer so the campaign's progress is visible;
7. support one aggregate becoming strict while others remain unregistered.

The implementation must first run a factual spike over current GDScript write forms: direct `=`,
compound assignment, array/dictionary element writes, `append`/`erase`/`clear`, and mutations through
typed aliases. If reliable static detection cannot be achieved without broad false positives, stop
and compare two alternatives before proceeding:

- private backing fields plus read-only public properties and authority-called model methods;
- a narrower source gate covering explicit protected symbols, backed by negative tests.

Do not land a validator that claims to enforce nested state it cannot see.

## Implementation sequence — one green commit each

1. **Inventory only.** Produce a temporary report of current mutable aggregate write sites grouped by
   model and file. Reconcile it against the source-of-truth synthesis; do not commit generated noise.
2. **Prove enforceability.** Apply each relevant write form to a tiny test fixture or temporary
   mutation and show the proposed detector catches it. Record false-positive/false-negative limits in
   the validator header.
3. **Land the convention.** Add the ownership manifest format and validator with one inert fixture
   aggregate or a reporting-only baseline. Add it to both test runners.
4. **Register the anti-ship aggregate in migration mode.** Its current writers are temporary legacy
   writers; the validator must reject a new writer in an unrelated file while remaining green on the
   current tree. Plan 0043 removes those exceptions.
5. **Document the implementation procedure.** Add the controller/authority rule to
   `.claude/skills/hexcombat-architecture-contract` only after the gate and first registration prove
   the exact convention. Do not update `docs/STATUS.md` until enforcement actually works.

## Acceptance criteria

- No production gameplay file changes behavior.
- The full gate is ALL PHASES GREEN and all golden/fixture output is byte-stable.
- The authority validator is seen to fail for every write form it claims to detect, including a new
  writer file and an unclassified field.
- It also fails if its manifest points to a dead path or scans nothing.
- The anti-ship aggregate is registered with an explicit, visible legacy-writer count ready for 0043.
- No controller base class, new autoload, reflection registry, or generic Dictionary mutation API is
  introduced.

## Risks and stop conditions

- **False confidence from source scanning.** This is the primary risk. Stop rather than calling a
  partial regex a complete guard.
- **Manifest duplication.** The manifest is enforcement metadata, not a second gameplay state store.
  It must be validated against model declarations so it cannot silently omit new fields.
- **Dependency ceilings.** The validator is tool-only. This plan must not add dependencies to any
  ceilinged production file.
- **Premature framework.** One authority pattern is not proven until 0043 ships. Keep the foundation
  deliberately small and let the pilot reshape naming or receipt conventions.

## Closeout homes

When shipped: architecture procedure in `.claude/skills/hexcombat-architecture-contract`, current
gate fact in `docs/STATUS.md`, validator details in its own header, a short `docs/DECISIONS.md` entry,
and this plan archived. No systems doc changes are expected because no subsystem behavior changes.

## Dependencies

First plan in the campaign. Every plan 0043–0049 depends on its enforceability decision and manifest
format. Independent feature work may continue, but no new direct mutation path should be added while
this plan is in progress.
