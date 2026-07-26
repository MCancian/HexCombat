---
name: hexcombat-plan-review
description: How to get a plan reviewed by independent models BEFORE writing any code — the brief format, which models to use, the reviewer-safety rules, and how to evaluate findings rather than obey them. Read when a plan is drafted and before implementation starts. Its sibling is hexcombat-diff-review, for the finished diff.
---

# Pre-implementation plan review

**USER standing instruction 2026-07-25:** every plan is reviewed by independent models before code is
written. This is not belt-and-braces. The USER is a non-coding wargame designer and cannot judge a
plan's technical soundness themselves, so two or three independent reads substitute for that judgement.
They are cheap; a wrong plan implemented in full is not.

The sibling procedure for the finished diff is `hexcombat-diff-review`. **Both are required** — a plan
review before code, a diff review before commit.

## What a plan review is for

Catching, while it is still free to change:

- a premise that is **false in the current code** (plan 0032's premise "the OOB has airborne brigades"
  was false — it had zero; plan 0034 called a failure hypothetical that was already live)
- a step that **cannot work** as written (plan 0037's `apply_casualty` assert would have fired on
  correct behaviour, because the invariant is transiently false by design mid-turn)
- a **missed consumer** — the thing you did not know also reads that field
- a **fix that does not fix it** (plan 0038: extracting the roster trio to buy dependency headroom
  buys none, and would break the ceiling — caught by measurement after a reviewer raised it)
- an ordering or dependency that makes the plan unbuildable in the sequence given

It is NOT for wording, structure, or enthusiasm. Say so in the brief.

## The brief

Write it to a file and pass it via `"$(cat …)"`. A brief that just says "review this plan" produces
a summary of the plan, which is worthless.

Required elements:

1. **`REVIEW ONLY — DO NOT MODIFY, CREATE, OR DELETE ANY FILE.`** First line. See safety below.
2. **The exact files to read**, with paths — the plan itself, plus every file it proposes to touch.
   Reviewers do not know the repo; an unguided one reads the wrong five files.
3. **The plan's claims, restated as checkable propositions.** "Verify (a) that the evidence is
   actually true in the current tree — several claims are counts or diffs I produced myself and may
   be wrong." Invite them to check your arithmetic; they will find errors in it.
4. **Named focus areas**, in priority order, each phrased as a question with a wrong answer:
   correctness, timing/freshness, missed consumers, test gaps, ordering.
5. **The constraints that make an answer right here:** golden byte-stability is the acceptance test;
   `tools/gd_metrics.py` forbids raising a dependency ceiling to silence a breach; new mechanics
   default OFF; the USER is non-coding so legibility counts.
6. **"Name anything IMPORTANT I MISSED."** This reliably returns the best finding.
7. **Output format:** numbered findings, each with a verdict
   (`CONFIRMED` / `WRONG` / `PARTIALLY-WRONG` / `RESHAPE`), severity
   (blocker / should-fix / nit), `file:line` evidence, and a concrete fix.
8. **"Be blunt where I am wrong. Do not restate my plan back to me."**

## Models

Run them **in parallel, in the background** — each buffers output until exit, so there is no interim
progress to poll.

```bash
SP=<scratchpad>
setsid nohup bash -c "opencode run -m opencode/deepseek-v4-flash-free --agent explore \"\$(cat $SP/brief.txt)\" > $SP/rev_deepseek.txt 2>&1" < /dev/null &
setsid nohup bash -c "opencode run -m opencode/nemotron-3-ultra-free --agent explore \"\$(cat $SP/brief.txt)\" > $SP/rev_nemotron.txt 2>&1" < /dev/null &
setsid nohup bash -c "GEM_TIMEOUT=15m gem-explore \"\$(cat $SP/brief.txt)\" > $SP/rev_gem.txt 2>&1" < /dev/null &
```

Then poll for size to stop changing (all three), rather than guessing a duration.

| Model | Good at | Watch for |
|---|---|---|
| `gem-explore` (Gemini, `GEM_TIMEOUT=15m`) | deepest reasoning about semantics and consequences; best "what breaks" | states blocking objections confidently and sometimes wrongly — always verify its blockers |
| `opencode/deepseek-v4-flash-free` | "which files did you miss"; careful about threat models | may answer in Chinese; sometimes stops at tool traces with no final answer |
| `opencode/nemotron-3-ultra-free` | broad sweeps, "MISSED" sections | **counts and line numbers are frequently wrong** — re-measure anything numeric it asserts |

Bare `agy -p` has timed out on multi-file reviews; prefer the `gem-explore` wrapper. The USER can also
run a prompt through `agy` by hand if a review needs more room than the wrapper allows.

## Reviewer safety — load-bearing, not paranoia

- **`--agent explore` is NOT honoured by every opencode model.** `nemotron-3-ultra-free` and
  `deepseek-v4-flash-free` both print *"agent 'explore' is a subagent, not a primary agent. Falling
  back to default agent"* and run under the **writing** `build` agent (observed 2026-07-25, twice).
  The prompt text is the only thing stopping them editing the repo.
- **Run `git status --short` after every review round.** Treat any unexpected modification as the
  reviewer having gone out of bounds; revert it.
- **`gem-explore` has written a review artifact into the repo root despite the instruction.** Delete
  strays immediately, because a file written by one reviewer **contaminates the others**: a
  concurrently-running model read that artifact off disk and returned it verbatim as its own review,
  which looks like independent corroboration and is not.
- **Treat identical findings from two models as ONE review until proven otherwise.**

## Evaluate, don't obey

Reviewers are frequently wrong, or right about something already handled. **Verify every finding
against the code before acting**, and say plainly in your response to the USER when one is rejected
and why. Both have happened repeatedly:

- **Real blockers caught:** an ordering bug that would have silently collapsed a mechanic; the
  contributor-filter hole where a brigade with nobody ashore would still fight.
- **Confident falsehoods:** "IJFS targets at-sea battalions" (it is Green-only, and Green has no
  pools); "widening the purity gate will fail because TurnConductor is in the closure of
  validate_headless_turn" (no tool names TurnConductor at all).

Where a finding is numeric or structural, **measure it** rather than reasoning about it. Cheap
experiments beat argument: a scratch probe, a `grep -c`, a temporary revert to see the gate go red.

## After the review

1. Fold accepted findings into the plan **before** writing code; the plan is the artifact of record.
2. Record rejected-on-the-code findings **in the plan**, under an "explicitly out of scope
   (checked, don't re-raise)" heading, with the evidence. This is what stops the next agent
   re-proposing them.
3. Report to the USER: what was accepted, what was rejected and why, in a couple of sentences.
4. Then implement. The diff gets its own round — `hexcombat-diff-review`.
