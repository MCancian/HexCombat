---
name: hexcombat-plan-review
description: How to get a plan reviewed by independent models BEFORE writing any code — what a plan review catches, the brief format, and what to do with the findings. Read when a plan is drafted and before implementation starts. Its sibling is hexcombat-diff-review, for the finished diff. The roster, routes and quorum rule live in .claude/REVIEWERS.md.
---

# Pre-implementation plan review

**USER standing instruction 2026-07-25:** every plan is reviewed by independent models before code is
written. The USER is a non-coding wargame designer and cannot judge a plan's technical soundness
themselves, so independent reads substitute for that judgement. They are cheap; a wrong plan
implemented in full is not.

**The round, the roster, the read-only flags, flake triage and reviewer safety are all in
`.claude/REVIEWERS.md`.** Do not restate them here or in a brief — `tools/validate_reviewer_facts.gd`
fails the gate if a model id or invocation appears outside that file. Run the round with:

```bash
tools/review_fanout.sh --brief BRIEF.txt --freeze \
    --role sol=ROLE_A.txt --role agy=ROLE_B.txt --role deepseek=ROLE_C.txt --out DIR
tools/review_fanout.sh --report DIR
```

`--freeze` snapshots the tree itself; never hand-build the snapshot (see the roster for what that cost).
A role per quorum reviewer is required, not advised — the script refuses without them.

**Quorum:** the mandatory 2-of-3 applies to the **implementation** of a numbered plan, not to the plan
document (USER call 2026-07-30). A plan needs **at least one** substantive read; fan out anyway, since
it is one command, and take the extra coverage when it lands.

The sibling procedure for the finished diff is `hexcombat-diff-review`. **Both rounds happen** — a plan
review before code, a diff review before commit.

## Preflight first — a Sketch is not reviewable

Per `CLAUDE.md`'s work loop: **measure the plan's premises against the tree and rewrite it before anyone
reviews it.** Plan premises rot — plan 0045's sketch described a split that plan 0044 had already
half-removed. Reviewers review the PLAN, so a stale Sketch comes back *confirmed* rather than corrected,
which is the expensive failure: you pay for a round and learn nothing.

## What a plan review is for

Catching, while it is still free to change:

- a premise that is **false in the current code** (plan 0032's premise "the OOB has airborne brigades"
  was false — it had zero; plan 0034 called a failure hypothetical that was already live)
- a step that **cannot work** as written (plan 0037's `apply_casualty` assert would have fired on
  correct behaviour, because the invariant is transiently false by design mid-turn)
- a **missed consumer** — the thing you did not know also reads that field
- a **fix that does not fix it** (plan 0038: extracting the roster trio to buy dependency headroom buys
  none, and would break the ceiling — caught by measurement after a reviewer raised it)
- an ordering or dependency that makes the plan unbuildable in the sequence given

It is NOT for wording, structure, or enthusiasm. Say so in the brief.

## The brief

Write it to a file and pass it with `--brief`. A brief that just says "review this plan" produces a
summary of the plan, which is worthless. Required elements beyond the invariants in
`.claude/REVIEWERS.md`:

1. **The exact files to read**, with paths — the plan itself, plus every file it proposes to touch.
   Reviewers do not know the repo; an unguided one reads the wrong five files.
2. **The plan's claims, restated as checkable propositions.** "Verify that the evidence is actually true
   in the current tree — several claims are counts or diffs I produced myself and may be wrong."
   Invite them to check your arithmetic; they will find errors in it.
3. **Named focus areas**, in priority order, each phrased as a question with a wrong answer:
   correctness, timing/freshness, missed consumers, test gaps, ordering.
4. **The constraints that make an answer right here:** golden byte-stability is the acceptance test;
   `tools/gd_metrics.py` forbids raising a dependency ceiling to silence a breach; new mechanics default
   OFF; the USER is non-coding, so legibility counts.
5. **"Name anything IMPORTANT I MISSED."** This reliably returns the best finding.
6. **Output format:** numbered findings, each with a verdict
   (`CONFIRMED` / `WRONG` / `PARTIALLY-WRONG` / `RESHAPE`), severity (blocker / should-fix / nit),
   `file:line` evidence, and a concrete fix. **Number every finding, nil included** — a clean read is
   the numbered entry *"1. No defect found — here is what I checked and what I concluded"*. A return
   without numbered findings is scored FLAKE and does not count toward the quorum; a nil return with
   that one numbered entry is read and judged like any SHORT (settled rule 2026-08-03).
7. **"Be blunt where I am wrong. Do not restate my plan back to me."**

If the plan is justified by a **measurement**, add the method pass (`agy-verify` — see the roles section
of `.claude/REVIEWERS.md`). A read-only reviewer cannot catch a methodology error, because catching one
means running the thing.

## Evaluate, don't obey

Reviewers are frequently wrong, or right about something already handled. **Verify every finding against
the code before acting**, and tell the USER plainly when one is rejected and why. Both directions
recur:

- **Real blockers caught:** an ordering bug that would have silently collapsed a mechanic; the
  contributor-filter hole where a brigade with nobody ashore would still fight.
- **Confident falsehoods:** "IJFS targets at-sea battalions" (it is Green-only, and Green has no pools);
  "widening the purity gate will fail because TurnConductor is in the closure of
  `validate_headless_turn`" (no tool names TurnConductor at all).

Where a finding is numeric or structural, **measure it** rather than reasoning about it. Cheap
experiments beat argument: a scratch probe, a `grep -c`, a temporary revert to see the gate go red.

## After the review

1. Fold accepted findings into the plan **before** writing code; the plan is the artifact of record.
2. Record findings rejected on the code **in the plan**, under an "explicitly out of scope (checked,
   don't re-raise)" heading, with the evidence. That is what stops the next agent re-proposing them.
3. Report to the USER: what was accepted, what was rejected and why, in a couple of sentences.
4. Then implement. The diff gets its own round — `hexcombat-diff-review` — and that one is quorum-bound.
