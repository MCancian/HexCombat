---
title: "0050: Mutation-authority enforcement and campaign closeout"
status: "Sketch"
created: "2026-07-26"
---

# Plan 0050: Mutation-authority enforcement and campaign closeout

## Goal

Prove that every gameplay-relevant mutable aggregate has one enforced mutation authority, remove the
campaign's temporary legacy-writer allowances, reconcile documentation and public contracts, and
measure that the architecture remains deterministic and operational over full games.

This is an audit/closeout plan, not a final broad refactor. Any aggregate still requiring substantive
migration gets a focused follow-up plan rather than being hurried into this one.

## Definition of done for the campaign

For every mutable aggregate discovered in the plan-0042 inventory:

1. one authority is named in the mutation-ownership manifest;
2. protected state has no production writer outside that authority;
3. builders initialize through the authority or an explicitly sanctioned construction API;
4. calculators/resolvers do not mutate protected campaign state;
5. cross-aggregate coordinators use typed requests/receipts and prove matching deltas;
6. local validation runs before the authority returns;
7. a deliberate unauthorized mutation has made the gate fail;
8. current behavior and data flow are documented in canonical homes.

Expected aggregate coverage includes force, anti-ship, sealift/fleet, IJFS, map, infrastructure,
mobilization, air insertion, supply, orders, victory, and turn lifecycle. Static definitions and
pure ephemeral budgets are classified explicitly as immutable or calculator-local rather than
silently omitted.

## Final audit

### Source mutation sweep

Run an independent source-first inventory—not merely the authority manifest—and compare it with the
manifest. Search for:

- direct/compound field assignment;
- array and dictionary element assignment;
- `append`, `push_*`, `pop_*`, `erase`, `clear`, and in-place sort on protected containers;
- mutable aliases returned from query methods;
- setters/wrappers that bypass controllers;
- test/tool code accidentally reachable in production;
- untyped metadata carrying authoritative quantities.

Every finding is classified as authority-owned, immutable construction, ephemeral calculator state,
serialized projection, or a violation. “Existing code” is not an exemption.

### Runtime transition sweep

Exercise one or more full games covering:

- sustained sealift and crossing losses;
- IJFS warmup and continuing target/inventory/squadron attrition;
- ground combat, retreat, and ownership;
- mobilization and air insertion;
- infrastructure seizure/JLSF/repair;
- supply depletion and victory.

Collect authority receipts/invariant checks in debug without changing the public record. Confirm every
intended domain authority is invoked and no registered check is vacuous.

### Contract sweep

- JSON schemas match emitted observation/action/event vocabularies.
- `to_dict` remains the sole serialization seam per type.
- examples and game records change only where an earlier USER-approved behavior/contract change
  required it.
- ordinal ids remain version-bounded and unique within a game.
- every runtime record still carries commit/version identity.

## Enforcement hardening

1. Remove all `temporary_legacy_writers` from the mutation manifest.
2. Make any remaining warning/report mode a hard gate failure.
3. Verify newly added mutable fields must be classified before the gate passes.
4. Verify dead model/controller paths and zero-match scans fail.
5. Add/retain deliberate negative fixtures for direct field and nested-container mutation.
6. Ensure Linux and Windows gate runners invoke the same authority validator.
7. Measure validator runtime and keep it suitable for the canonical gate.

Do not add a blanket allowlist for a large phase module. Allowed writers are the narrow authority
files and construction APIs only.

## Architecture cleanup

Only after the audit is green:

- delete obsolete mutation wrappers, one-sided tripwires, dead fields, and duplicate reset paths whose
  replacements have proven red/green coverage;
- keep useful independent backstops such as runtime-index and structural pool enumeration checks;
- remove dormant model classes only with call-site/import evidence;
- normalize controller naming and headers without changing public API;
- update dependency ceilings downward when migration reduced dependencies; never raise a ceiling as
  closeout convenience.

No state-storage relocation or generic framework extraction belongs here. If authorities reveal that
mutable runtime state in `GameData` still creates a concrete correctness problem, open a separate
plan with measured call sites and serialization impact.

## Independent review gate

Before implementation closeout, obtain at least two read-only reviews from different model families.
They must inspect source, not just plans, and answer:

- Is any mutable aggregate or write form missing?
- Can any controller be bypassed through aliases or nested Dictionaries?
- Did a controller become a God object or absorb calculation/phase-order responsibilities?
- Are cross-aggregate transitions genuinely atomic/preflighted?
- Did any authority change RNG draw order, behavior, or JSON contracts unintentionally?
- Are manifest/controller facts duplicated in ways that can drift?
- Should any legacy validator remain as an independent backstop?

Review findings are advisory until the primary agent verifies them. Review agents do not modify files.

## Verification

- `python3 tools/gd_metrics.py --check-ceiling .` passes; lower ceilings where appropriate.
- Every focused authority suite passes twice in isolation.
- Canonical `bash tools/run_all_tests.sh` prints ALL PHASES GREEN.
- Fixture regeneration produces no unreviewed diff.
- Same-seed full games are byte-identical across separate processes.
- `scenario_golden`, `scenario_default`, `roc_full_defense`, and `red_airborne` cover the major state
  shapes; add a focused scenario only if no existing one reaches an authority.
- Mutation gate has been seen red for every protected aggregate and write-form class.
- Research calibration affected by plan 0043 is explicitly identified; no old result is silently
  relabeled as post-change evidence.

## Closeout sequence

1. Complete source/runtime/contract audits and resolve every violation.
2. Run independent read-only reviews; triage findings with source evidence.
3. Run full validation and deterministic multi-game probes.
4. Update each owning systems doc and `docs/STATUS.md` with present behavior.
5. Update `.claude/skills/hexcombat-architecture-contract` with the final proven authority rule and
   procedure; remove provisional wording from 0042.
6. Append a concise `docs/DECISIONS.md` campaign closeout with pointers and measured behavior change.
7. Archive plans 0042–0050 in shipped order and replace the campaign sequencing block in
   `docs/plans/README.md` with a short archived closeout row.
8. Commit the closeout only after the full gate is green.

## Out of scope

- New mechanics, balance changes, or scenario tuning.
- Event sourcing, rollback, save-game migration, or a universal entity-component system.
- One generic controller/base class for all domains.
- Per-instance battalions or ships without a demonstrated research requirement.
- Moving all mutable state out of `GameData` merely for conceptual purity.

## Risks and stop conditions

- **Audit theater:** a green manifest-based gate is insufficient unless an independent source sweep
  agrees. Preserve both proofs.
- **Deleting independent guards too soon:** keep structurally different backstops even when an
  authority should make violations impossible.
- **Campaign fatigue:** do not combine unresolved migrations into one closeout commit. Open focused
  follow-ups and leave this plan blocked.
- **Documentation duplication:** module boundaries belong in code headers, current behavior in STATUS,
  system flow in systems docs, procedure in the architecture skill, and history in DECISIONS.
- Stop on any unexplained golden/fixture drift or same-seed mismatch.

## Dependencies

Final plan. Requires 0042–0049 shipped and their temporary manifest exceptions removed or explicitly
blocked by focused follow-up plans.
