# Amphibious Offload — Retrospectives

## 2026-07-29 — plan 0045: sealift/fleet authority   (implementer: direct, 3 review rounds)

**What would you do differently (implementer):**
- The planner's `ship_category` stamp into force-owned reserve rows survived my own inventory of
  writers, because I searched for writes to the protected FIELDS and this one went through an untyped
  BN dictionary alias — the validator's documented blind spot. A reviewer found it. When claiming a file
  "writes no campaign state", grep the aliases it was HANDED, not just the fields it names.
- I deferred the `scripts/calc/` move on the belief that it "touches every call site". A GDScript
  `class_name` is path-independent: the move changed no call site at all. Check the cost before pricing
  a deferral on it. The move also could not have happened earlier — the file only qualified once the
  stamp was gone, which is the useful ordering lesson.

**Orchestrator triage:**
- Two reviewers independently reported gate failures that were harness-invocation artifacts: a validator
  run bare, without the gate's `HEXCOMBAT_SCENARIO=scenario_golden`, and a review of the working tree
  taken mid-edit while call-site arities were being updated. Same class as the plan 0043 phantom
  regression → **act now** (done: the rule and both reproductions are recorded in the archived plan).
- Reviewer suggestions to inline a helper, privatise a model check, and drop a defensive `duplicate()`
  were each rejected on the code and recorded with evidence → **record only**, so they are not re-raised.

## 2026-07-15 — plan 0006 C8: research verification + closeout   (implementer: direct)

**What would you do differently (implementer):**
- The C8 research runs caught a total sealift livelock (heavy BNs unlandable in one day; see
  `hexcombat-failure-archaeology` → "Sealift livelock") that C1–C7's 53-suite gate and the
  10-turn smoke could not see. Long-horizon ordered runs should have been part of the C6/C7
  verification, not deferred to a final step — the bug shipped in 3 pushed commits before C8 ran.
- When a per-item cost is drawn from a per-turn budget, check max(cost) > min(budget) at design
  time; the TIV oracle's fractional queue existed precisely because of this case.

**Orchestrator triage:**
- Long-horizon research run at feature-verification time → **act now** (done this session: smoke
  extended to 12 turns + landings-past-turn-10 assertion; carry-over fix + 4 tests committed).
- Budget/cost mismatch design check → **record only** — captured as the archaeology lesson.
