---
title: "0056: The coupling budget is opt-in, so it polices 5 files out of 167"
status: "Sketch"
created: "2026-07-31"
---

# Plan 0056: Make the coupling budget opt-out

## The finding

`tools/gd_metrics.py` enforces two budgets under `--check-ceiling`, and they work in opposite ways.

**Parameter counts are opt-out and therefore universal.** Any function whose parameter count exceeds
`PARAM_HARD_CAP` (5) fails the gate unless it holds a grandfather entry in `PARAM_CEILINGS`. A new
function with eight parameters fails on the commit that introduces it. This is the behaviour you want,
and it is why plan 0052's parameter budget actually holds.

**Dependency counts are opt-in and therefore almost absent.** A file's `ndeps` is checked only if it
has an explicit `DEP_CEILINGS` entry, and there are **five entries against 167 production files**:

| File | Ceiling | Measured |
|---|---|---|
| `scripts/GameState.gd` | 29 | 29 |
| `scripts/phases/ReinforcementPhases.gd` | 22 | 22 |
| `scripts/phases/TurnConductor.gd` | 18 | 18 |
| `scripts/phases/FiresPhases.gd` | 13 | 13 |
| `scripts/phases/TurnClosure.gd` | 7 | 7 |

Every one sits exactly at its ceiling — the ratchet is doing its job on the files it covers. The gate
prints its own scope honestly: `PASS: metric ceilings OK (5 file(s), 36 function(s) checked)`.

**The consequence is that a new file can reach any coupling at all and nothing says so**, and the
codebase already shows it. Measured 2026-07-31 over `scripts/` only:

| `ndeps` ≥ | Files | Of those, uncapped |
|---|---|---|
| 12 | 11 | 7 |
| 10 | 15 | 11 |
| 8 | 18 | 14 |
| 6 | 31 | 26 |

The most-connected file in the entire codebase is **`scripts/transitions/ForceTransitions.gd` at 30**,
uncapped — one above `GameState`, which is capped. That inversion is the finding worth acting on:
the five capped files are all **orchestrators**, whose job is legitimately to touch many things. The
uncapped leader is an **authority**, whose entire design purpose is to own one aggregate narrowly.
Nothing would complain if it reached fifty.

## Why this is not the trap it looks like

The obvious objection is that switching enforcement on forces a decision on ~11 files at once, and
that "grandfather it at today's value" is the cop-out the existing header explicitly warns against:

> *"bumping an existing ceiling to silence a real regression defeats the point — fix the coupling
> instead."*

That warning is about **raising a ceiling that already exists**, which is a regression being waved
through. Seeding a ceiling for a file that has none is the opposite operation: it converts an
unbounded number into a bounded one. `DEP_CEILINGS` is already documented as *"the measured count at
the commit that set it"* — a ratchet that can only fall. Applying that rule by default rather than by
memory changes no existing entry and permits no growth; it only removes the requirement that someone
remember to opt in.

So this plan deliberately **fixes no coupling**. It makes coupling unable to grow silently. Reducing
`ForceTransitions`'s 30 is a separate question with its own risk, and folding it in here would turn a
gate change into a refactor.

## Proposal

Invert the default. A production file whose `ndeps` meets the threshold is checked against a ceiling;
a file with no entry is seeded at its measured value by a one-time generation step, not by hand.

Three decisions the plan must settle, with recommendations:

**Threshold — recommend 10.** Fifteen files in scope, eleven newly seeded. It sits in a natural gap
in the distribution (13 files at ≥11, 15 at ≥10, then 18 at ≥8) and it is high enough that ordinary
files never acquire an entry, so the ceiling table stays a short list of genuinely coupled files
rather than a second copy of the file tree. A threshold of 6 would seed 26 and turn the table into
noise.

**Scope — recommend `scripts/` only.** `tests/` legitimately reaches for many classes to build
fixtures (the top test file is at 19), and capping that discourages thorough tests for no
architectural gain. `tools/` is validators and one-shot scripts. Both should be excluded explicitly
and in the header, not by accident.

**Seeding — recommend generated, then committed.** Add a `--seed-ceilings` mode that rewrites the
`DEP_CEILINGS` block from measurement. Hand-transcribing eleven numbers is exactly the kind of task
that produces one wrong digit which then reads as a deliberate allowance forever.

## Steps

1. Add the threshold constant, the scope filter, and `--seed-ceilings` to `tools/gd_metrics.py`.
   Extend the existing `--self-test` to cover the new mode: seeding a fixture tree must produce
   entries equal to its measured counts, and re-running `--check-ceiling` on it must pass.
2. Run the seeding, commit the generated `DEP_CEILINGS` block **on its own**, so the diff of what
   became enforced is reviewable as a list of numbers rather than buried in a logic change.
3. Verify the ratchet actually bites: pick one seeded file, add a throwaway dependency, confirm the
   gate fails with the ndeps message, revert. **A budget nobody has watched fail is not known to
   work** — the gate's own history has a validator that passed for weeks because its pin never
   matched anything.
4. Record the rule in `hexcombat-code-quality`, which currently documents a dependency ceiling
   without saying that it applies to five files. That gap is why this went unnoticed.
5. `bash tools/run_all_tests.sh` → ALL PHASES GREEN.

## Risk

**Low on behaviour — this touches no game code and cannot move a pin.** The real risks are two.

*A seeded ceiling silently blesses a bad number.* Mitigated by step 2: the seeded block lands as its
own commit, so a reviewer reads eleven numbers rather than diffing them out of a logic change. The
`ForceTransitions` 30 is the one to argue about, and it should be argued about in that review.

*The threshold turns out wrong in six months.* Cheap to change: it is one constant, and raising it
only removes entries, which the stale-entry check already reports as `not found (ceiling entry
stale — file moved/deleted?)`.

## Out of scope

Reducing any file's coupling — including `ForceTransitions`. Changing `PARAM_CEILINGS`, which already
works correctly. Applying ceilings to `tests/` or `tools/`. Any file move (that is plan 0055, and
doing both at once would make every seeded path churn).

## Sequencing

**Last of the three — after 0055 and 0057.** `DEP_CEILINGS` is path-keyed, and both of those plans
move files: 0055 moves thirteen between directories, 0057 moves roughly thirty-five out of
`scripts/` root — including `scripts/GameState.gd`, which is already one of the five existing entries.
Seeding first would produce a table that both plans then invalidate, and a stale key surfaces as a
confusing `KeyError` rather than a clear message. This is the exact failure plan 0050 hit with
`tools/validate_gd_metrics.py`.

Seeding *last* also measures the right thing: the coupling numbers worth freezing are the ones the
role layout leaves behind, not the ones it is about to change.
