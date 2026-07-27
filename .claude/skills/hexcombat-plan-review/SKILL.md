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

## Models — measured, not assumed

**11 review runs across one long session (plans 0043 + 0051, 2026-07-27):**

| Reviewer | Substantive | What it is good for |
|---|---|---|
| **`agy-explore`** | **4 / 4** | Everything. Every run found something that would otherwise have shipped: clamp-vs-assert on a loss sum; an absent-key bug that would have resurrected state; an inert guard; a filter that would have made a whole mechanic silently no-op. |
| `opencode/nemotron-3-ultra-free` | 1 / 3 | Broad sweeps, "MISSED" sections. Its one success was the FIRST review of the session. **Counts and line numbers are frequently wrong** — re-measure anything numeric. |
| `opencode/deepseek-v4-flash-free` | 0 / 3 as reviewer, **1 / 1 as explorer** | NOT judgement over many files. It IS good at bounded mechanical enumeration — "list every read/write of these 8 fields, with file:line" came back accurate and well-grouped. |

**agy leads; opencode is optional.** The free models appear to **degrade across a session**
(hypothesis, not proof: both successes were early; everything later died in tool traces or a
streaming error). Use them early if at all.

### Flake detection — do this before reading a single finding

A flaked reviewer is **indistinguishable from "reviewed, no findings"**. That is the most dangerous
failure mode in this whole procedure, because it silently converts "nobody looked" into "approved".

- Every substantive `agy-explore` review came back **2.7–4.5 KB**.
- Every flake was **under 1 KB** (died before answering) or **over 10 KB** (dumped tool output —
  one was 123 KB of pasted diff, another was pages of `Grep` traces).
- **No numbered findings ⇒ not a review ⇒ re-run it.** Never record a flake as a clean pass.

Adding *"do not print or quote the diff; findings only"* to the brief helps but does not fix it —
both opencode models ignored it on the retry.

### Spend spare agy capacity on ROLES, not repeats

Running one brief N times gives correlated noise. Give each parallel pass a different job:

1. **Fact-check** — "verify these premises against the current tree; several are counts and
   file:line claims I produced myself and may be wrong."
2. **Consequences** — "what breaks, what did I miss."
3. **Legibility** — "this will be implemented by a LESS CAPABLE agent working alone; what will they
   get wrong despite the plan saying otherwise? Name the sentence that is not explicit enough."
   *This role produced the best finding on plan 0051* — a filter that would have made the mechanic
   do nothing in its headline case while every unit test passed.
4. **Oracle** (`agy-explore -d <upstream repo>`) — "does this match the source it was ported from?"
   *Decisive on plan 0051:* going to the TIV Python reversed the naive reading and turned a judgement
   call into a citation. **Make this standard for any TIV-lineage change** — the oracle is a sibling
   repo, it is cheap to read, and reasoning about it from our port is how ported bugs get preserved.
5. **Method** (`agy-verify`) — see below.

Two passes given the SAME role are one opinion, not two.

### `agy-verify` — the pass that catches what reading cannot

```bash
agy-verify "reproduce <measurement>; is the method sound and does it support the conclusion?"
```

A read-only reviewer cannot catch a **methodology** error, because catching one means running the
thing. Both of the worst errors of the 0043 session were methodology:

- a validator run without the gate's `HEXCOMBAT_SCENARIO`, so its pin never matched — chased through
  three experiments as a phantom code regression;
- a hand-rolled turn loop that looked like 25 turns, actually resolved **one**, and summed a stale
  summary 25 times — two bugs agreeing on the same wrong answer.

`agy-verify` runs against a **throwaway detached git worktree of HEAD** inside the repo (the flatpak
Godot sandbox cannot read a `--path` outside the project dir), removed on exit. **It sees committed
state only — commit or stash first**, or it reviews the wrong tree.

Use it whenever a plan or a diff is justified by a measurement, a benchmark, or a "this is
byte-stable" claim.

### Running them

Background, in parallel; each buffers output until exit, so there is no interim progress to poll.

```bash
SP=<scratchpad>
setsid nohup bash -c "AGY_TIMEOUT=15m agy-explore \"\$(cat \$SP/brief_facts.txt)\"  > \$SP/rev_facts.txt  2>&1" < /dev/null &
setsid nohup bash -c "AGY_TIMEOUT=15m agy-explore \"\$(cat \$SP/brief_weak.txt)\"   > \$SP/rev_weak.txt   2>&1" < /dev/null &
```

Then poll for size to stop changing, and **check each file against the flake band above** before
reading it. `agy-explore` replaced `gem-explore` on 2026-07-27 (`gem` was the superseded CLI name);
`AGY_TIMEOUT` replaced `GEM_TIMEOUT`, which is still honoured. Bare `agy -p` has timed out on
multi-file reviews — prefer the wrapper.

## Reviewer safety — load-bearing, not paranoia

- **`--agent explore` is NOT honoured by every opencode model.** `nemotron-3-ultra-free` and
  `deepseek-v4-flash-free` both print *"agent 'explore' is a subagent, not a primary agent. Falling
  back to default agent"* and run under the **writing** `build` agent. The prompt text is the only
  thing stopping them editing the repo.
- **`agy-explore` is read-only by CONTRACT, not by sandbox** — the wrapper's prompt says so, nothing
  enforces it. (It behaved across all four runs of the 0043/0051 session; it has misbehaved before.)
  `agy-verify` is deliberately NOT read-only, which is exactly why it runs in a throwaway worktree.
- **Run `git status --short` after every round.** Treat any unexpected modification as the reviewer
  having gone out of bounds; revert it.
- **`agy-explore` has previously written a review artifact into the repo root despite the
  instruction.** Delete strays immediately, because a file written by one reviewer **contaminates
  the others**: a concurrently running model read that artifact off disk and returned it verbatim as
  its own review, which looks like independent corroboration and is not.
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
