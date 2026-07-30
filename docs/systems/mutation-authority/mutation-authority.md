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
| `tools/fixtures/mutation_authority/` | Illegal-write fixtures, compared exactly every run, so a detector that stops working fails as a false negative. |
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
   and the illegal fixtures, in one commit. See §5.
6. **Close the gate:** prove each illegal fixture fails.

## 4. Choosing protected field names

**A protected field NAME is claimed repo-wide.** The gate reports an unresolvable receiver writing a
protected name as a backstop failure — that is a deliberate false-NEGATIVE guard, and it means a
generic name poisons unrelated code.

- Plan 0046 registered `IjfsMunition.name` and turned **22 innocent view-layer lines** into
  unresolved-write failures. `name` is a built-in `Node` property.
- Plan 0047 renamed `HexState.owner` → `hex_owner` pre-emptively for the same reason (`Node.owner`),
  and named a new field `node_status` rather than `status`.

So: prefer a distinctive name, check `grep -rn "\.<name>\s*=" scripts/ tools/` before registering it,
and **keep the serialized key unchanged** — rename the field, not the `to_dict()` key, or every
fixture and game record moves.

## 5. The four ordering traps

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
- **Allowances must stay live.** `construction_writers` are for fresh, unpublished objects only;
  an allowance that no longer writes anything fails `E_STALE_ALLOWANCE`, so removing the last write
  means removing the entry.

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
- **Apply where the old assignment was, when a later decision reads it.** Deferring application to
  end-of-phase is only safe when nothing downstream in the same pass reads the written state. Two
  measured counter-examples: IJFS stages consume dice conditionally on state an earlier stage wrote
  (plan 0046), and `InfrastructureResolver.tick`'s repair branch reads the status its seizure branch
  just wrote in the same iteration (plan 0047).

## 7. State & authority

This subsystem owns no runtime aggregate of its own — it is the governance layer for everyone
else's. Current aggregates, authorities and status: `tools/mutation_authority_manifest.json`, and the
summary table in `docs/STATUS.md`.
