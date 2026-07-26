---
name: hexcombat-diff-review
description: How to get a finished diff reviewed by independent models BEFORE committing — the brief format, what to focus a diff review on (as opposed to a plan review), verifying findings by measurement, and the reviewer-safety rules. Read when the gate is green and you are about to commit. Its sibling is hexcombat-plan-review, for the plan.
---

# Pre-commit diff review

**USER standing instruction 2026-07-25:** nothing is committed until independent models have reviewed
it. The plan got its own round before code was written (`hexcombat-plan-review`); this is the second
round, on the finished diff, and it is **not optional just because the plan passed**. A correct plan
is routinely implemented incorrectly.

Run it when the gate is **already green**. A diff review is not a substitute for the gate — it looks
for what a green gate cannot see.

## What a diff review is for

The gate proves the pins did not move. It cannot tell you:

- a consumer you **did not update** — the field still read the old way somewhere (this is the single
  most common real finding; ask for it explicitly by name)
- **staleness/timing**: a value cached at one phase boundary and read at another
- an invariant that now holds **only by luck** — correct today, silently wrong after the next change
- a **default that returns the pre-fix answer** (`snapshot_state(pending_pools := [])` silently
  reported whole rosters — the exact bug the change had just fixed)
- **dead code left behind** that a future editor will find and use (`Brigade.to_combat_units` did not
  subtract pools and was a trap)
- **test gaps**: a test that would pass without the fix, i.e. proves nothing

## The brief

Write it to a file; pass via `"$(cat …)"`.

1. **`REVIEW ONLY — DO NOT MODIFY, CREATE, OR DELETE ANY FILE. Do not write a report file into the
   repo.`** First line.
2. **State that the gate is green and no pin moved** (or which pins moved and why). Otherwise
   reviewers spend their budget re-deriving that.
3. **List every file in the diff, with the function names that changed** — reviewers cannot see your
   diff reliably; name the seams.
4. **State the intended rule in one sentence**, precisely. e.g. *"landed(brigade, type) ==
   composition.qty(type) − pool_count(brigade, type), clamped at 0."* Findings against a rule they
   were told are checkable; findings against a rule they inferred are noise.
5. **Focus areas in priority order**, phrased as questions: correctness; timing/freshness; the
   load-bearing invariant; missed consumers ("name the `file:line`"); test gaps.
6. **Output format:** numbered findings, severity (blocker / should-fix / nit), `file:line` evidence,
   concrete fix; "say explicitly if a category is clean; do not restate the diff."

## Running them

Identical mechanics to `hexcombat-plan-review` — serial for opencode models, parallel for `gem-explore`, background, poll for size to stop changing. Consider expected flakes (stall, stream fail) and retry if they occur. Same model table, same strengths and weaknesses.

## Reviewer safety — the same rules apply, and they matter more here

Read the safety section of `hexcombat-plan-review` in full. In short: `--agent explore` is **not**
honoured by every opencode model (they fall back to the **writing** `build` agent), so the prompt text
is the only thing stopping an edit; **run `git status --short` after every round**; delete any stray
file a reviewer writes immediately, because one reviewer's artifact on disk **contaminates** the
others and produces fake corroboration.

## Verify by measurement, not by argument

This is where a diff review differs most from a plan review: the code exists, so **you can just
check**. Prefer a decisive experiment to a debate:

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

Verify each finding against the code before acting; reject plainly and say why. Recorded examples of
both directions:

- **Accepted, and the change was better for it:** the purity-closure missing `preload`-by-path and
  `class_name`-less scripts; a pool probe that recursed one level while its header claimed to be
  structural; a plan whose stated phase order was simply wrong.
- **Rejected on the code:** "IJFS targets at-sea battalions" (Green-only; Green has no pools);
  "widening the purity gate will fail — TurnConductor is in the closure" (no tool names
  TurnConductor); "teardown-flake masking is the top issue" (guarded by `saw_fail` ordering and
  already recorded as a known Godot 4.7 environmental issue).
- **Wrong numbers are common.** `nemotron-3-ultra-free` has mis-stated file line counts by 2x and
  mis-counted duplicated functions. Re-measure anything numeric before you repeat it — including into
  a commit message.

Beware **false corroboration**: if two models agree, check they did not read each other's stray file,
and check they are not both agreeing with a false claim *you* put in the brief. Three models once
agreed a validator harness would fix the gate-hang class; it does not, because a script that fails to
compile never runs at all.

## After the review

1. Apply accepted findings, re-run the **full gate**, and confirm it is still green.
2. Record rejected findings in the commit message or the plan, with the evidence — that is what stops
   them being re-raised.
3. The commit message should say what review changed and what it rejected. A reader six months later
   needs to know the diff was contested, not just that it landed.
4. `git status --short` one last time before `git add`.
