---
title: "0042: Mutation-authority foundation"
status: "Complete"
created: "2026-07-26"
---

# Plan 0042: Mutation-authority foundation

> **CLOSED 2026-07-26.** Shipped: `tools/validate_mutation_authority.gd` +
> `tools/mutation_authority_manifest.json` + self-proving fixtures under
> `tools/fixtures/mutation_authority/`; anti-ship registered in migration mode with five named legacy
> writers. Facts landed in: the validator header (detected write forms, blind spots), the manifest
> (ownership), `docs/STATUS.md` (current gate behavior), `hexcombat-architecture-contract` (the
> convention), `hexcombat-change-control` non-negotiable 8, `hexcombat-validation-and-qa` (proving a
> source-scanning validator still detects), `hexcombat-docs-and-writing` (one-home row),
> `hexcombat-add-phase-resolver` step 6, `AGENTS.md`, and `docs/DECISIONS.md`.
> No production script moved and no gameplay behavior changed.

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

Because GDScript does not make a passed `Resource`, `Array`, or `Dictionary` read-only, a calculator
must receive a typed snapshot or an owned copy whenever a live alias would permit protected writes.
Directory placement is not proof of purity: the source gate must still recognize writes through typed
aliases, nested containers, setters/model mutators, and dynamic mutation forms.

### Mutation authority

The only production class allowed to change a published/runtime aggregate after construction. Exact
construction writers may initialize fresh unpublished objects but are not alternate authorities. Its
methods:

1. validate all referenced ids and expected pre-state;
2. snapshot the minimum pre-state needed to prove the transition;
3. apply the complete change;
4. validate local invariants and exact deltas;
5. return a typed domain receipt when another phase/report needs the applied facts.

Names use the domain plus `Transitions` unless the implementation review finds a clearer established
term: `AntishipTransitions`, `ForceTransitions`, `SealiftTransitions`, and so on. Do not use
`Manager`, `Controller`, or `Service` interchangeably. Authority is granted to the exact file named in
the manifest, not to every file in an authority directory; one authority must never be able to write
another aggregate merely because both live under `scripts/transitions/`.

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
var receipt: AntishipCrossingReceipt = AntishipTransitions.apply_crossing_effects(
    state.antiship_systems, outcome)

# Coordinator: uses the receipt for the event/summary; it does not reconstruct the mutation.
```

Do not create a generic `MutationRequest` Dictionary or a universal `EntityController`. Domain
requests and receipts stay typed and named by their actual job. Operation-specific receipts are
allowed; do not force unrelated operations into one domain receipt full of optional fields. Introduce
a shared receipt base only if two shipped authorities demonstrate a genuinely identical contract.

## Role-directory end-state and classification

Classify a file by its observable effects, never by its current name or dominant line count:

1. `scripts/transitions/` — exact manifest-named authorities that write published gameplay state;
2. `scripts/phases/` — phase-order/coordinator code that invokes calculators and authorities, owns
   EventBus/report wiring, and has no protected writes at campaign closeout;
3. `scripts/builders/` — construction APIs that may initialize only fresh unpublished objects through
   exact manifest allowances and never accept live protected aggregate state;
4. `scripts/calc/` — deterministic calculators/queries that consume snapshots and return outcomes;
   they may mutate only owned, non-escaping ephemeral work;
5. `scripts/model/` — typed state, definitions, requests, outcomes, and receipts; protected model
   mutator methods are not authority bypasses.

A file spanning two roles is split before it moves. In particular, `OrderValidator` must separate
legality from buffer application; `RosterMutations` is absorbed into `ForceTransitions` rather than
surviving as a second force writer; `GameStateBuilder` moves intact as a builder façade only after
confirming it accepts construction inputs rather than live protected state; `AntishipCrossing` is a
calculator; and `MineWarfareService` is a calculator only while its mutated minefield/fleet inputs are
fresh, private working copies. The inventory covers root `scripts/` and `scripts/ijfs/` as well as the
mixed resolver directory.

The role split begins only after plan 0043's pilot review. Path-only commits move one destination
family at a time, preserve class names and `.gd.uid` files, update manifest/validator/ceiling/doc paths,
re-import the class cache, and keep the full gate byte-stable.

## Mechanical enforcement design

Availability of an API is insufficient while direct field assignment remains possible. Build a
staged gate, `tools/validate_mutation_authority.gd`, with its machine-readable ownership manifest at
**`tools/mutation_authority_manifest.json`**. This is tooling/governance metadata, not sweepable game
content, so it must not live under `data/`. The manifest is the single home for exact ownership facts:

- schema version and aggregate id;
- exact authority file/class for a declared authority, or a `planned_authority` name while an
  aggregate is migration-only and has no authority file yet;
- protected model/state declaration paths;
- protected fields, nested paths, and recognized mutation forms;
- exact construction-only writers;
- temporary legacy writers, each with its removal plan;
- an optional routing hint, only when the validator proves the named method exists.

Authority headers own the semantic boundary and invariants; systems docs own data flow. Neither may
repeat the manifest's exhaustive protected-field or writer lists. If a generated/structured header
block is ever added, the validator must derive or compare it exactly rather than trusting prose.

The validator must:

1. fail if a manifest path or protected field no longer exists;
2. fail if a declared authority file is absent; a migration-only aggregate may omit the authority
   path only when it names `planned_authority` and every current writer is an explicit legacy entry;
3. find direct/compound assignment, element assignment, setters/dynamic `set`, model-mutator
   bypasses, and in-place container mutation of protected state outside the exact authority file and
   explicitly listed construction/legacy writers;
4. fail when two aggregates claim the same protected path unless an explicit shared projection is
   justified;
5. fail on an unclassified mutable field added to a protected model;
6. fail when a declared authority, construction allowance, or legacy allowance is stale and performs
   no matching write;
7. fail vacuously if it scans zero models, zero protected symbols, or zero assignments;
8. print every remaining legacy writer and its removal plan so campaign progress is visible;
9. support one aggregate becoming strict while others remain unregistered;
10. reject an unregistered file under `scripts/transitions/` so the directory cannot become a grab bag.

The implementation must first run a factual spike over current GDScript write forms: direct `=`,
compound assignment, array/dictionary element writes, `append`/`push_*`/`pop_*`/`erase`/`clear`/
in-place sort, property setters, `Object.set`, model mutator methods, and mutations through typed or
nested aliases. Deliberately illegal source fixtures live under
`tools/fixtures/mutation_authority/` with a non-`.gd` fixture suffix, so Godot/GdUnit discovery does
not compile expected violations as ordinary suites. Positive authority behavior suites live under
`tests/transitions/`. If reliable static detection cannot be achieved without broad false positives,
stop and compare two alternatives before proceeding:

- private backing fields plus read-only public properties and authority-called model methods;
- a narrower source gate covering explicit protected symbols, backed by negative tests.

Do not land a validator that claims to enforce nested state it cannot see.

## Implementation sequence — one green commit each

**No production script moves in plan 0042.** Suffix naming plus exact manifest paths are the temporary
orientation mechanism. The reviewed fallback is to keep the current layout until the anti-ship pilot
in plan 0043 proves the authority pattern; moving first would classify mixed resolver/calculator files
before the gate can verify the claim.

1. **Inventory only.** Produce a temporary report of current mutable aggregate write sites grouped by
   model and file. Include `scripts/`, `scripts/resolvers/`, `scripts/ijfs/`, model mutator methods,
   `GameState` forwarding setters, and construction writes. Reconcile it against the source-of-truth
   synthesis; do not commit generated noise.
2. **Prove enforceability.** Apply every claimed write form to the dedicated fixtures and show the
   proposed detector catches it. Record false-positive/false-negative limits in the validator header.
   Stop here if alias-aware enforcement is not credible.
3. **Land the convention.** Add `tools/mutation_authority_manifest.json`, its schema/semantic checks,
   and the validator with one inert fixture aggregate or a reporting-only baseline. Add it to both test
   runners. Construction is an exact exception: a builder may initialize only a fresh, unpublished
   object and may not accept live protected aggregate state.
4. **Register the anti-ship aggregate in migration mode.** Set `planned_authority` to
   `AntishipTransitions` without requiring a placeholder file. Its current writers are temporary
   legacy writers with plan-0043 removal metadata; the validator must reject a new writer in an unrelated
   file while remaining green on the current tree.
5. **Make diagnostics teach the rule.** Failures name aggregate, symbol/write form, exact file:line,
   authority class/file, manifest path, and removal plan. Name a specific authority method only when
   the manifest hint is validated against source; otherwise require an operation-shaped method.
6. **Document the proven procedure.** Update `AGENTS.md`, `hexcombat-architecture-contract`,
   `hexcombat-change-control`, `hexcombat-add-phase-resolver`, `hexcombat-docs-and-writing`, and
   `hexcombat-validation-and-qa`. Extend `validate_skill_references` to check the concrete manifest
   path. Do this only after the gate and first registration prove the exact convention. Do not update
   `docs/STATUS.md` until enforcement actually works.

## Acceptance criteria

- No production gameplay file changes behavior.
- The full gate is ALL PHASES GREEN and all golden/fixture output is byte-stable.
- The authority validator is seen to fail for every write form it claims to detect, including a new
  writer file, a wrong authority file under `scripts/transitions/`, a stale allowance, and an
  unclassified field.
- It also fails if its manifest points to a dead path or scans nothing.
- The anti-ship aggregate is registered in `tools/mutation_authority_manifest.json` with an explicit,
  visible legacy-writer count and removal-plan metadata ready for 0043.
- No production script has moved; current outputs, class names, and dependency-ceiling paths remain
  unchanged in this plan.
- No controller base class, new autoload, reflection registry, or generic Dictionary mutation API is
  introduced.

## Risks and stop conditions

- **False confidence from source scanning.** This is the primary risk. Stop rather than calling a
  partial regex a complete guard.
- **Manifest duplication.** The manifest is enforcement metadata, not a second gameplay state store.
  It must be validated against model declarations so it cannot silently omit new fields. Headers and
  docs point to it rather than copying its exhaustive lists.
- **Dependency ceilings.** The validator is tool-only. This plan must not add dependencies to any
  ceilinged production file.
- **Premature framework.** One authority pattern is not proven until 0043 ships. Keep the foundation
  deliberately small and let the pilot reshape naming or receipt conventions.

## Closeout homes

When shipped: architecture/change-control/validation procedures in the skills named above, current
gate fact in `docs/STATUS.md`, validator details in its own header, a short `docs/DECISIONS.md` entry,
and this plan archived. No systems doc authority section lands yet because no subsystem authority has
shipped; plan 0043 establishes the first one.

## Dependencies

First plan in the campaign. Every plan 0043–0049 depends on its enforceability decision and manifest
format. Independent feature work may continue, but no new direct mutation path should be added while
this plan is in progress.
