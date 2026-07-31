# Mutation authority (campaign 0042–0050)

## 1. Purpose

Every mutable gameplay aggregate has **one named authority class** that is its only production
writer. Calculators return outcomes; only the authority applies them. A source gate reads the tree
and fails the build on a write from anywhere else.

This doc is the **procedure** for adding an aggregate — the ordering constraints and traps that cost
real time to discover. It deliberately holds no ownership facts. Those live in exactly two places and
are not copied here:

| Question | Home |
|---|---|
| Which class owns which fields, allowances, legacy writers | `tools/mutation_authority_manifest.json` |
| What write forms the scanner detects, and its blind spots | `tools/validate_mutation_authority.gd` header |

Why it exists: the campaign runs one aggregate per plan (0043 → 0050), so each step is a fresh agent
re-deriving the same half-dozen sequencing rules from a 90-line code comment, a JSON `_doc`, and
several archived plans. Read this first, then the manifest.

## 2. Files & responsibilities

| File | Responsibility |
|---|---|
| `tools/mutation_authority_manifest.json` | THE ownership record: aggregates, protected fields, allowances. `_schema_rules` is normative. |
| `tools/validate_mutation_authority.gd` | The gate. Resolves each write's receiver TYPE, then asks whether that (class, field) pair is protected. |
| `tools/fixtures/mutation_authority/*.gdfixture` | Abstract illegal-write forms, compared exactly every run against the abstract fixture manifest. |
| `tools/fixtures/mutation_authority/real_claims_pin.json` | Non-authoritative regression oracle for real claim identities; never an ownership input. |
| `scripts/transitions/` | The authority directory. Membership grants nothing; the manifest names each file. |

## 3. Adding an aggregate — the order that works

The steps are ordered because several of them cannot be reordered without a red gate.

1. **Inventory every writer first, by measurement.** `file:line` + verbatim line + enclosing
   function, for fields AND containers. Put the table in the plan; it is the artifact that makes the
   migration safe, and reviewers check it. Sweep `scripts/` and `tools/`; `tests/` is out of scan
   scope but still needs updating when a type or name changes.
2. **Pick protected field names before writing any code.** See §4.
3. **Make the aggregate typed if it is not.** The gate resolves the receiver's type, so values inside
   an untyped `Dictionary`/`Array` are invisible to it — no manifest entry can protect
   `node["status"] = x`. Typing is a precondition for enforcement, not cleanup.
4. **Characterize current behaviour in `tests/transitions/`** before anything moves.
5. **Ship the authority atomically** — the class file, its manifest entry, every writer migration,
   and the updated real-claim pin, in one commit. Extend the abstract illegal fixtures only when the
   aggregate introduces a write FORM or structural shape they do not already exercise. See §5.
6. **Close the gate:** the abstract fixture comparison, generated real-contract probes, claim-pin
   comparison and production scan must all pass. If a new detector form landed, deliberately break
   its expectation once and observe the self-test fail before restoring it.

### What those four proofs establish

- **Abstract `.gdfixture` cases prove scanner forms.** They use invented classes and their own
  manifest so direct/compound/container/dynamic/cast/unresolved/wrong-authority detection stays small
  and exact. Do not copy real ownership into `fixture_manifest.json`.
- **Generated real-contract probes prove integration.** On every run the validator creates, in
  memory, one typed illegal assignment per claim in the REAL manifest and every ordered pair of a
  REAL authority path writing another aggregate, then scans them using the REAL class/type corpus. No production file is
  edited and no generated probe survives the run.
- **`real_claims_pin.json` prevents oracle circularity.** A probe generated solely from the manifest
  would disappear when its claim was deleted. The committed pin is compared exactly by aggregate,
  owned/hosted section and `Class.field`, so deletion, reassignment or demotion fails. It is an
  expected-output artifact, never a second ownership input. Like any golden, an intentional change can
  update manifest and pin together; the control makes that ownership change explicit in review, not
  impossible.
- **The production scan proves the live tree is clean.** Dead paths/fields, owned-model omissions,
  stale allowances, inert authorities and unauthorized writes fail independently.

A temporary write injection remains useful while debugging, but it is a one-time measurement, not a
closeout artifact and never a substitute for these repeating checks.

## 4. Choosing protected field names

**A protected field NAME is claimed repo-wide.** The gate reports an unresolvable receiver writing a
protected name as a backstop failure — that is a deliberate false-NEGATIVE guard, and it means a
generic name poisons unrelated code.

- Plan 0046 registered `IjfsMunition.name` and turned **22 innocent view-layer lines** into
  unresolved-write failures. `name` is a built-in `Node` property.
- Plan 0047 renamed `HexState.owner` → `hex_owner` pre-emptively for the same reason (`Node.owner`),
  and named a new field `node_status` rather than `status`. Both cost nothing, because no offending
  write existed yet — which is exactly when a rename is cheap. Neither serialized key moved.

So: prefer a distinctive name, check `grep -rn "\.<name>\s*=" scripts/ tools/` before registering it,
and **keep the serialized key unchanged** — rename the field, not the `to_dict()` key, or every
fixture and game record moves.

## 5. The ordering traps

- **An authority file cannot exist before it is registered.** `_check_authority_dir` fails
  `E_UNREGISTERED_AUTHORITY_FILE` for any file under `scripts/transitions/` that no aggregate names as
  its `authority_path`. "Add the class now, register it later" can never be green.
- **`status: "migration"` and an `authority_path` are mutually exclusive.** A file in the authority
  directory must be some aggregate's authority, and a migration aggregate may not declare one — so an
  aggregate goes straight to `enforced`, and `legacy_writers` (each with a `removal_plan`) carries any
  not-yet-migrated writer.
- **Dependency ceilings are paid for, not raised** (`hexcombat-architecture-contract`). Naming a new
  authority from a coordinator costs it a dependency, and several coordinators sit at exactly their
  ceiling. Check headroom while DESIGNING the call shape — `hexcombat-code-quality` has the command.
  The two shapes that work: route through an existing façade (the
  `GameData.set_brigade_hex → ForceTransitions` pattern), or find a dependency that genuinely leaves
  (plan 0043 held `FiresPhases` at 14 by a one-for-one swap).
- **Hosting a class costs you its WHOLE field list, not just your slice.** Since 2026-07-30 every
  class under any aggregate's `hosted_fields` must account for every mutable field it declares —
  claimed by exactly one aggregate, or excluded in `shared_model_policies` with a classification and a
  reason. So the aggregate that first hosts a big shared model pays for classifying all of it (closing
  `GameStateData` alone took 29 entries), and a later aggregate that claims one of those fields must
  DELETE its exclusion in the same edit, or the gate fails `E_CLAIMED_AND_EXCLUDED`. Budget that in the
  inventory step, not at the gate. A classification that is a PROMISE (`planned_transitional`,
  `order_buffer`) must name a plan file under the manifest's `plan_dir` that still resolves, so
  **archiving the plan that shipped it turns the exclusion red on purpose** — closing out a plan means
  clearing its exclusions in the same commit.
- **When two authorities share one model, whichever commits FIRST decides where the refusals must
  go.** Plan 0048 split `AirInsertionState`: `ForceTransitions` drains the pool, applies roster losses
  and places brigades; `AirInsertionTransitions` then erodes the lift and appends the log. The force
  commit is irreversible, so a refusal in the SECOND authority leaves the roster moved and the ledger
  unwritten — a partial write that no single authority's guards can see. The fix is not ordering, it
  is a **preflight predicate**: the second authority exposes `can_<operation>(...)` sharing one private
  helper with its guard, the coordinator asks it BEFORE calling the first authority, and a refusal
  then costs nothing because nothing has been written. Adding an authority to a model another one
  already writes means auditing this even when the field sets are disjoint.
- **A new authority costs its caller a dependency, and its REQUEST TYPE costs a second one — unless
  the factory lives on the authority.** Plan 0048 needed `AirInsertionTransitions` plus an
  `AirLiftRequest` from a coordinator with zero headroom. Putting `lift_request()` on the authority
  (as `ForceTransitions` already does with `ground_combat_casualty_request`) means `var x :=
  Authority.factory(...)` names one class, not two: `tools/gd_metrics.py` counts `class_name` tokens
  appearing literally in the file, so a type reached only through another file's declared return type
  is free. Worth knowing before concluding a ceiling cannot be met.
- **Allowances must stay live.** `construction_writers` are for fresh, unpublished objects only;
  an allowance that no longer writes anything fails `E_STALE_ALLOWANCE`, so removing the last write
  means removing the entry.
- **Transitional scaffolding must name the step that deletes it, and that step is the one that pays
  the ceiling.** Plan 0047 could not type its node and register its authority in the same commit (an
  authority file cannot precede its manifest entry, above), so the typing step left two helpers that
  read and wrote the field without naming the new type. Their comment originally said the next step
  would "replace both bodies", which was wrong: the ceiling is only repaid when the OLD class's
  constants leave the CALL SITES too, which happens when those sites become authority calls. Swapping
  the bodies alone leaves the constants, still breaches the ceiling, and leaves a generic setter
  where operation-specific methods belong. Write the deletion instruction, not a rewrite instruction.

## 6. What an authority looks like

Read `scripts/transitions/IjfsTransitions.gd` and `ForceTransitions.gd` as the worked examples. The
house shape:

- Static methods; first argument is the state or store being mutated; no dice, no autoload reads.
- **Job-shaped operations, not setters.** A generic `set_x(target, value, cause)` whose `cause` is
  recorded nowhere is an authority bypass in sanctioned clothing — it lets any caller express nearly
  every forbidden assignment through the permitted file. Plan 0047 deleted two such setters at review
  and drove the one caller that wanted them through real domain operations instead.
- **Enforce invariants by absence where possible.** `IjfsTransitions` has no method that clears
  `destroyed`; monotonic destruction is guaranteed by there being no way to express it, not by a guard
  that can be argued with.
- Guards `push_error` and change nothing rather than `assert(false)`: a research batch must not die on
  one bad row, and a `push_error` guard is testable with `assert_error(...).is_push_error(...)`.
- **Enforce by ABSENCE where the invariant is "do not touch what you were not told about".**
  `IjfsTransitions` guarantees monotonic destruction by having no method that clears `destroyed`.
  `MapTransitions` (plan 0047) goes further: it has no owner setter at all, because hex ownership is
  DERIVED. The calculator omits unoccupied hexes and the authority iterates only what it returned, so
  the sticky-ownership rule survives — whereas a `set_owner` plus a `.get(hex_id, default)` loop would
  silently un-seize every captured port. When an authority's only expressible operations are the legal
  ones, the invariant needs no guard that a later reader can argue with.
- **A calculator that stages a chain must stage it in LOCALS, and carry an ORDERED event list.**
  Plan 0047's infrastructure tick has a branch that reads what the branch above it just decided, in
  the same iteration, so one node can legitimately emit two events in one tick. A plan object holding
  one label per entity cannot express that, and a planner reading the pre-tick snapshot in both
  branches silently adds a turn. Splitting calculate-from-apply does not mean evaluating everything
  against the starting state.
- **Take the calculator's ROWS, not its post-state.** Plan 0048's first draft had the authority accept
  `AirInsertionSummary.caps_after` — the budget the resolver had already computed — and guard that it
  had only fallen. A reviewer pointed out what that shape actually permits: a plausible cap decrease
  with no corresponding loss, and a log that disagrees with the erosion, because the two arrive as
  separate inputs. Taking the per-packet rows instead and DERIVING the new budget from them
  (`caps[c] = max(0, caps[c] - lost)`, the resolver's own arithmetic) makes "the cap fell by exactly
  the reported losses" true by construction, makes the log and the erosion literally the same array,
  and deletes the guard entirely — a raised cap stops being refused and becomes unexpressible. Generic
  rule: **when an authority could either re-derive a value or be handed it, re-deriving is what turns
  a checked invariant into an absent one.** The calculator's post-state stays report-only; pin that
  the two agree.
- **Apply where the old assignment was, when a later decision reads it.** Deferring application to
  end-of-phase is only safe when nothing downstream in the same pass reads the written state. Two
  measured counter-examples: IJFS stages consume dice conditionally on state an earlier stage wrote
  (plan 0046), and `InfrastructureResolver.tick`'s repair branch reads the status its seizure branch
  just wrote in the same iteration (plan 0047).

## 7. Maintaining this doc

**Every remaining campaign plan (0049, 0050) updates this file at closeout** — it is in the
ownership table in `hexcombat-docs-and-writing`, so the check is mechanical, not a thing to remember.
Add only what generalizes:

- a **new ordering trap** in §5 — something that made the gate red in a way the existing rules did not
  predict;
- a **new authority shape** in §6 — a situation the worked examples do not cover;
- a **field-naming casualty** in §4, with the measured cost.

Do **not** add per-aggregate ownership facts (the manifest holds those), per-plan narrative (the
archived plan holds that), or a restatement of the scanner's detection rules (the validator header
holds those). This doc was written from one plan's experience and is deliberately thin; the risk it
carries is stale *prose* over valid anchors, which `tools/validate_doc_anchors.gd` cannot catch.

Open extraction task: plans 0042–0046 are archived with their own review rounds and retrospectives,
and their generalizable lessons were never consolidated here. §5 and §6 currently reflect 0046, 0047
and 0048 only.

## 8. State & authority

This subsystem owns no runtime aggregate of its own — it is the governance layer for everyone
else's. Current aggregates, authorities and status: `tools/mutation_authority_manifest.json`, and the
summary table in `docs/STATUS.md`.
