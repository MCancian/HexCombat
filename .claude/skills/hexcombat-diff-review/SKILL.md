---
name: hexcombat-diff-review
description: How to get a finished diff reviewed by independent models BEFORE committing — what a diff review catches that a green gate cannot, the brief format, and verifying findings by measurement. Read when the gate is green and you are about to commit. Its sibling is hexcombat-plan-review, for the plan. The roster, routes and quorum rule live in .claude/REVIEWERS.md.
---

# Pre-commit diff review

**USER standing instruction 2026-07-25, quorum set 2026-07-30:** the implementation of a numbered plan
(`docs/plans/NNNN-*.md`) is not committed until **two of the three quorum reviewers have returned
substantive findings**. This is the second round; the plan got its own before code was written
(`hexcombat-plan-review`), and passing that one does not excuse this one. A correct plan is routinely
implemented incorrectly.

Run it when the gate is **already green**. A diff review is not a substitute for the gate — it looks for
what a green gate cannot see.

**The round, the roster, the read-only flags, flake triage and reviewer safety are all in
`.claude/REVIEWERS.md`.** Do not restate them here or in a brief — `tools/validate_reviewer_facts.gd`
fails the gate if a model id or invocation appears outside that file.

```bash
tools/review_fanout.sh --brief BRIEF.txt --freeze \
    --role sol=ROLE_A.txt --role agy=ROLE_B.txt --role deepseek=ROLE_C.txt --out DIR
tools/review_fanout.sh --report DIR                # bytes + findings per reviewer, quorum verdict
```

**Use `--freeze`; do not build the snapshot yourself.** A hand-built `git diff > file` is what voided a
round on 2026-07-30 — see `.claude/REVIEWERS.md` and `hexcombat-failure-archaeology`.

**If quorum is not reached, the work stays UNCOMMITTED** and the situation goes to the USER. That is the
sanctioned holding pattern, not a reason to commit.

## What a diff review is for

The gate proves the pins did not move. It cannot tell you:

- a consumer you **did not update** — the field still read the old way somewhere (this is the single most
  common real finding; ask for it explicitly by name)
- **staleness/timing**: a value cached at one phase boundary and read at another
- an invariant that now holds **only by luck** — correct today, silently wrong after the next change
- a **default that returns the pre-fix answer** (`snapshot_state(pending_pools := [])` silently reported
  whole rosters — the exact bug the change had just fixed)
- **dead code left behind** that a future editor will find and use (`Brigade.to_combat_units` did not
  subtract pools and was a trap)
- **test gaps**: a test that would pass without the fix, i.e. proves nothing

## The brief

Write it to a file; pass it with `--brief`. Beyond the invariants in `.claude/REVIEWERS.md`:

1. **State that the gate is green and no pin moved** (or which pins moved and why). Otherwise reviewers
   spend their budget re-deriving that.
2. **List every file in the diff, with the function names that changed** — name the seams.
3. **State the intended rule in one sentence**, precisely. e.g. *"landed(brigade, type) ==
   composition.qty(type) − pool_count(brigade, type), clamped at 0."* Findings against a rule they were
   told are checkable; findings against a rule they inferred are noise.
4. **Focus areas in priority order**, phrased as questions: correctness; timing/freshness; the
   load-bearing invariant; missed consumers ("name the `file:line`"); test gaps.
5. **Output format:** numbered findings, severity (blocker / should-fix / nit), `file:line` evidence,
   concrete fix; "say explicitly if a category is clean; do not restate the diff."

Give the three quorum reviewers **different roles** (the list is in `.claude/REVIEWERS.md`). Two matter
most on a diff:

- **Missed consumers.** "Name the `file:line` of anything still reading the removed field / old
  signature / old path — scripts, tools, tests, scenes, docs." Ask BY NAME; it is the most common real
  finding and reviewers do not volunteer it.
- **Correctness + timing.** The rule the diff implements, stated in one sentence, plus the freshness
  question: is anything read on the wrong side of a phase boundary?

Add the **method** pass if the diff is justified by a measurement, and the **oracle** pass if the code is
a port from TIV. Both are in the roles list; both have produced blockers nothing else caught. Note the
method pass sees **committed state only**, so on a pre-commit review either commit to a scratch branch
first or point it at the previous commit and describe the delta.

## Verify by measurement, not by argument

This is where a diff review differs most from a plan review: the code exists, so **you can just check**.
Prefer a decisive experiment to a debate:

- Claim "these two functions produce identical output"? Write a scratch script that runs both over the
  real OOB and diffs them. (Done for `split_units`: 450 cases, 0 mismatches.)
- Claim "this test would pass without the fix"? **Temporarily revert the fix and watch the test fail.**
  A test not verified this way proves nothing.
- Claim "this validator catches the bug"? Reintroduce the bug and watch it go red.
- Claim "X hangs / X does not hang"? Run it with a `timeout` and read the exit code.

Delete scratch scripts afterwards and confirm with `git status`. The flatpak Godot sandbox cannot load
`-s` scripts from outside the project dir, so scratch scripts must be written into the repo, run, and
deleted — see `hexcombat-build-and-env`.

## Evaluate, don't obey

Verify each finding against the code before acting; reject plainly and say why.

- **Accepted, and the change was better for it:** the purity-closure missing `preload`-by-path and
  `class_name`-less scripts; a pool probe that recursed one level while its header claimed to be
  structural; a plan whose stated phase order was simply wrong.
- **Rejected on the code:** "IJFS targets at-sea battalions" (Green-only; Green has no pools); "widening
  the purity gate will fail — TurnConductor is in the closure" (no tool names TurnConductor);
  "teardown-flake masking is the top issue" (guarded by `saw_fail` ordering and already recorded as a
  known Godot 4.7 environmental issue).
- **Wrong numbers are common** from tier-3 reviewers — mis-stated file line counts by 2x, mis-counted
  duplicated functions. Re-measure anything numeric before repeating it, including into a commit message.

Beware **false corroboration**: if two models agree, check they did not read each other's stray file, and
check they are not both agreeing with a false claim *you* put in the brief. Three models once agreed a
validator harness would fix the gate-hang class; it does not, because a script that fails to compile
never runs at all.

## After the review

1. Apply accepted findings, re-run the **full gate**, and confirm it is still green.
2. Record rejected findings in the commit message or the plan, with the evidence — that is what stops
   them being re-raised.
3. The commit message says what review changed, what it rejected, and the quorum count (e.g. "review:
   2/3 substantive — sol, agy; deepseek returned 0 bytes"). A reader six months later needs to know the
   diff was contested, not just that it landed.
4. `git status --short` one last time before `git add`.
