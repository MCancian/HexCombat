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
| `scripts/phases/TurnClosure.gd` | 9 | 9 |

Every one sits exactly at its ceiling — the ratchet is doing its job on the files it covers. The gate
prints its own scope honestly: `PASS: metric ceilings OK (5 file(s), 36 function(s) checked)`.

**The consequence is that a new file can reach any coupling at all and nothing says so**, and the
codebase already shows it. Re-measured at preflight (2026-08-01, commit `1f5bf92`, `scripts/` only —
the first measurement predated 0057 and its ≥8 and ≥6 rows have since moved):

| `ndeps` ≥ | Files | Of those, uncapped |
|---|---|---|
| 12 | 11 | 7 |
| 11 | 13 | 9 |
| 10 | 15 | 11 |
| 8 | 19 | 14 |
| 6 | 30 | 25 |

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

**Threshold — 10, because the project already declared it.** Not a number picked from the
distribution. `.claude/skills/hexcombat-code-quality/SKILL.md:31` has said all along:
`| File class references (preload/class_name/autoload) | ≤ 8 | 10 | split file or justify in the file
header comment |` — a target of 8 and a **hard cap of 10**. So the budget was always documented as
universal at 10; only its *enforcement* was opt-in. That reframes this plan: it is not choosing a new
threshold, it is making the gate agree with the rule the skill already states. (Round-1 finding; the
draft argued from a "natural gap" in the distribution, which was a weaker premise for the same number.)

Fifteen files sit at or above it, eleven newly seeded. The distribution is consistent with the cap
(13 files at ≥11, 15 at ≥10, then 19 at ≥8) and it is high enough that ordinary
files never acquire an entry, so the ceiling table stays a short list of genuinely coupled files
rather than a second copy of the file tree. A threshold of 6 would seed 26 and turn the table into
noise.

**Scope — recommend `scripts/` only.** `tests/` legitimately reaches for many classes to build
fixtures (the top test file is at 19), and capping that discourages thorough tests for no
architectural gain. `tools/` is validators and one-shot scripts, topping out at 10. Both should be
excluded explicitly and in the header, not by accident.

**The two budgets have different scopes on purpose, and that asymmetry must survive this plan.**
`PARAM_CEILINGS` is repo-wide and already grandfathers entries in all three trees — see
`tools/gd_metrics.py:132-138`, which lists `tests/batch_report_test.gd`, `tools/run_selfplay_game.gd`
and `tools/validate_mutation_authority.gd` alongside the `scripts/` ones. A parameter count of nine is
a legibility problem wherever it appears; a dependency count of nineteen is a *structural* problem only
where architecture is claimed. **Do not "tidy" `PARAM_CEILINGS` to match the new `DEP_CEILINGS`
scope** — that would silently drop live grandfather entries and let three trees regress.

**Seeding — generated, committed, STRICTLY ADD-ONLY, and then DELETED.** Add a `--seed-ceilings` mode
that emits entries for files that have none. Hand-transcribing eleven numbers is exactly the kind of
task that produces one wrong digit which then reads as a deliberate allowance forever.

**The generator is scaffolding and ships removed** (round-1 blocker, tier 1). A permanently available
seeder is an opt-out for every future high-coupling file, which is precisely what this plan exists to
close: a new file lands at `ndeps` 30, the gate fails as designed, and the cheapest response becomes
"run `--seed-ceilings`" rather than "fix the coupling". Add-only prevents laundering an EXISTING
breach; it does nothing about a new file being born pre-forgiven. So the sequence is add generator →
seed the baseline → **remove the generator** before closeout, leaving only universal enforcement and
its tests. Anyone adding a ceiling afterwards writes the entry by hand, next to the prose explaining
why — which is the moment the reasoning should be demanded. If a future baseline needs reseeding, the
generator is one `git revert` away in this plan's own history.

Three constraints on that mode while it exists, all load-bearing enough that it is worse than useless
without them:

**It must never raise or replace an existing entry.** A mode that "rewrites the `DEP_CEILINGS` block
from measurement" — the original wording here — becomes the sanctioned way to launder a breach: hit a
ceiling, re-run the generator, and every ceiling silently resets to the newly measured value. That is
precisely what `tools/gd_metrics.py`'s own header forbids. Seeding adds missing keys and refuses to
touch present ones, and the self-test must prove a re-seed cannot bless an existing breach.

**It must preserve the comments.** The `DEP_CEILINGS` block is not a list of numbers; it carries
per-file prose explaining *why* each file's coupling is legitimate — that `TurnConductor` depends on
every phase resolver it orchestrates is cohesion, not lamination, and so on. `tools/gd_metrics.py:24-93`
is 70 lines of dict, of which the great majority is that prose. A generated number cannot reconstruct
it, and it is exactly the reasoning a future agent needs before deciding whether a ceiling may move.
Test that existing comments stay byte-identical.

**The mechanism is therefore named, not left to taste** (round-1 blocker). `--seed-ceilings` must
APPEND, by locating the closing `}` of the `DEP_CEILINGS` literal and inserting new lines above it.
It must **not** import the module and re-serialise the dict, and must not `ast.parse` / `ast.unparse`
the block: both discard every comment, which is how a reviewer predicted a weaker implementer would
attack this. Emitting the candidate lines to stdout for manual paste is an acceptable fallback; a
round-trip through a Python object is not.

**Each seeded entry carries a provenance comment, not a `TODO`.** The reviewer asked for
`# TODO: explain why this coupling is legitimate` above every generated entry. Same intent, better
form: an unenforced `TODO` committed eleven times is a marker that rots in place, and this repo has a
standing rule against hand-maintained lists that rot. Emit instead a factual one-liner —
`# Seeded <date> by --seed-ceilings at its measured value; rationale not yet written.` — which is true
on the day it is written and stays true. The rationale gets added when someone first has cause to move
that ceiling, which is the moment they actually know it.

## Steps

0. **Know where this actually runs before touching it.** The gate does NOT invoke
   `gd_metrics.py --check-ceiling`. `tools/run_all_tests.py:187` runs `tools/validate_gd_metrics.py`,
   which at `:91-93` runs `--check-ceiling` against the real repo root and asserts both `returncode == 0`
   and the literal substring `"PASS: metric ceilings OK"` in stdout. Two rules follow, and neither is
   obvious from the file being edited:
   - **Keep the `PASS: metric ceilings OK` prefix byte-exact.** The counts inside the parentheses may
     change freely (they will: 5 files becomes ~16). Rewording the prefix turns the gate red in a file
     nobody edited.
   - That validator is also **path-keyed** — `:97` looks up
     `scripts/calc/AntishipResolver.gd::resolve` in the metrics JSON and would `KeyError` if that file
     moved. It is the same failure mode this plan's Sequencing section cites, in the same file, still
     live. Do not move anything here.
   (Found by the round-1 enumeration pass and confirmed by reading; the plan previously named neither file.)
1. **Normalize the path separator FIRST — this is probably an existing bug, not just new risk.**
   `tools/gd_metrics.py:271` is `rel = os.path.relpath(f, ROOT)` and nothing normalizes it anywhere in
   the file. On Windows that yields `scripts\GameState.gd`, while every `DEP_CEILINGS` and
   `PARAM_CEILINGS` key uses `/`. The lookup at `:393` is `result["files"].get(rel)`, so on the Windows
   box **every one of the five entries should report `not found (ceiling entry stale)` and
   `--check-ceiling` should fail** — which means either the ceiling gate has never been exercised there,
   or something outside this file compensates. **Verify on the Windows box before building on it**; if
   it does fail, that is a separate defect to fix first, and this plan's scope filter would have
   inherited it. Canonicalize `rel` to forward slashes at the point of measurement, before metrics
   storage, scope filtering and ceiling lookup, and cover it with a Windows-style path case. Do **not**
   write a bare `rel.startswith("scripts/")` against OS-native paths. (Round-1 finding, tier 1.)
2. Add the threshold constant, the scope filter, and `--seed-ceilings` to `tools/gd_metrics.py`.
   **Make it testable without touching the real table or the real file** (round-1 finding): extract the
   checking and the source insertion into helpers that take an explicit ceiling mapping and explicit
   source text, rather than reading the module-level `DEP_CEILINGS` and rewriting `gd_metrics.py` in
   place. Otherwise a fixture either inherits the production table — every real entry then reporting
   stale against a fixture tree — or the test edits the live tool.
   Extend the existing `--self-test` to cover the new mode with **four** cases, not one — seeding that
   only proves "seeded values pass" proves nothing interesting:
   - seeding a fixture tree produces entries equal to its measured counts, and `--check-ceiling` passes;
   - an UNLISTED fixture file at or above the threshold **fails** (this is the whole feature);
   - a listed file that has grown past its entry **fails**, and re-running `--seed-ceilings` does NOT
     silence it;
   - existing comments in the block survive seeding byte-identically.
   These must run under `CHECK_CEILING`, not only under `--self-test` — `:264` is
   `if SELF_TEST or CHECK_CEILING:`, and `--check-ceiling` is the mode the gate actually invokes.
3. Run the seeding, commit the generated `DEP_CEILINGS` block **on its own**, so the diff of what
   became enforced is reviewable as a list of numbers rather than buried in a logic change.
4. Verify the ratchet actually bites — **on the NEW code path, which is the one the obvious test
   misses** (round-1 finding). Once seeding has run, every `scripts/` file at or above the threshold
   HAS an entry, so pushing a *seeded* file over its ceiling exercises only the pre-existing
   dictionary lookup; the new "unlisted and at/above threshold" branch stays dormant and could be
   broken while the check goes green. Do both, in this order:
   - take an unlisted file and push it to EXACTLY the threshold. Pick one measured at `ndeps` 9 so a
     single dependency does it, or add exactly `10 - current_ndeps` **distinct** classes — one
     `preload` of a class the file already names moves the count by zero, and an `ndeps` 8 file needs
     two. **Re-measure and confirm the count is 10 before reading the verdict**, then assert the
     specific missing-ceiling diagnostic rather than "the gate went red": a wrong-reason failure looks
     identical here. (Round-1 finding — the draft said "8 or 9 … add a throwaway dependency", which
     silently assumed one dep moves any file to the threshold.)
   - then push a seeded file over its own ceiling, confirm the gate fails with the ndeps message,
     revert.
   Read the verdict from the direct `python3 tools/gd_metrics.py . /tmp/m.json --check-ceiling`, which
   is safe to run bare, and run the full gate afterwards.
   **A budget nobody has watched fail is not known to work** — the gate's own history has a validator
   that passed for weeks because its pin never matched anything.
5. **Remove `--seed-ceilings` and its scaffolding**, in its own commit, keeping the enforcement, the
   threshold, the scope filter and every test that does not exercise the generator. This is the step
   that stops the plan from shipping its own opt-out; skipping it leaves the hole open under a new
   name. The three seeding self-test cases go with it; the "unlisted file at/above threshold fails"
   case stays, because that one tests enforcement rather than generation.
6. Record the rule in `hexcombat-code-quality`, which currently documents a dependency ceiling
   without saying that it applies to five files. That gap is why this went unnoticed. State the scope
   explicitly there — `scripts/` only — so that a `tests/` or `tools/` file breaching 10 without a
   warning reads as designed rather than as a hole.
   (Preflight also found five stale ceiling numbers in `docs/archive/source-of-truth-sweep-brief.md`,
   three of them wrong. **No longer actionable:** that brief was archived on 2026-08-01, and a stale
   ceiling NUMBER in `docs/archive/` is correct by policy rather than a defect — note that a dead doc
   LINK there is not, and the doc-anchor gate does check those everywhere. Recorded here only so the next
   agent does not go looking for it. The general lesson stands and is not fixed by this plan —
   `docs/plans/` sits outside the doc-anchor gate, so a live plan CAN carry rotted numbers unflagged;
   that is what preflight is for.)
7. `bash tools/run_all_tests.sh` → ALL PHASES GREEN.

## Risk

**Low on behaviour — this touches no game code and cannot move a pin.** The real risks are two.

*A seeded ceiling silently blesses a bad number.* Mitigated by step 2: the seeded block lands as its
own commit, so a reviewer reads eleven numbers rather than diffing them out of a logic change. The
`ForceTransitions` 30 is the one to argue about, and it should be argued about in that review.

*The threshold turns out wrong in six months.* **This paragraph used to say "cheap to change: it is
one constant, and raising it only removes entries". That is WRONG** (round-1 finding, verified).
`tools/gd_metrics.py:393-395` stales an entry only when `result["files"].get(rel)` is `None` — i.e.
when the FILE is gone. An entry whose file still exists but now sits below a raised threshold is not
stale, is not reported, and stays enforced at its old value forever. Raising the threshold therefore
needs a **reviewed pruning migration**, not a constant edit. Cheap mitigation: have `--check-ceiling`
report listed entries now below the threshold, so the pruning candidates are visible rather than
inferred. Lowering the threshold remains genuinely cheap — it only adds candidates.

## Round 1 — plan review, 2026-08-01

**Three substantive returns.** A plan needs one; the diff round that follows is quorum-bound at two.

- **Sol (tier 1)** — 10 findings, all verified against the tree before acting. It found the blocker
  (a permanent seeder is an opt-out for every future high-coupling file), the probable Windows path
  defect, the untestable-without-injection structure, and **two places this plan was simply wrong**:
  the Risk section's "raising the threshold only removes entries", and the Sequencing enumeration,
  which named four candidates and gestured at a non-existent "rest of the `interleaved/` set" instead
  of `scripts/ui/HexMap.gd`. It also regrounded the threshold on the hard cap the quality skill had
  declared all along, replacing an argument from the distribution.
- **agy (tier 2)** — the seeding mechanism, and step 4's wrong code path.
- **DeepSeek (tier 2, bounded enumeration)** — the missed consumer chain now in step 0. Scored
  `FLAKE` by `--report` for having no numbered findings, which was a format artefact of its
  enumeration role; read and counted by hand.

## Explicitly out of scope (checked — do not re-raise)

- **A `# TODO: explain why this coupling is legitimate` marker above each seeded entry.** Raised in
  round 1 and deliberately reshaped rather than adopted: eleven unenforced TODOs in a gated table are a
  hand-maintained list that rots, which this repo has a standing rule against. Replaced with a factual
  provenance comment — see the seeding section.
- **Tightening a ceiling that has become slack** (a file seeded at 10 that later drops to 4 keeps 10).
  Real, and left alone on purpose. `DEP_CEILINGS` is documented as a ratchet that only falls *when
  someone lowers it deliberately*, and auto-lowering would make every unrelated refactor rewrite this
  table — the exact churn that makes a gated file untrustworthy. Revisit only if slack is ever measured
  to have hidden a regression.
- **Reducing `PARAM_CEILINGS`' scope to match.** It is repo-wide by design and holds live `tests/` and
  `tools/` entries; see the Scope decision.

## Out of scope

Reducing any file's coupling — including `ForceTransitions`. Changing `PARAM_CEILINGS`, which already
works correctly. Applying ceilings to `tests/` or `tools/`. Any file move (0055 and 0057 did those;
doing another here would make every seeded path churn).

## Sequencing — the hazard is SPENT

**This is the last of the three, and 0055 and 0057 both SHIPPED on 2026-07-31.** `DEP_CEILINGS` is
path-keyed, so seeding before them would have produced a table they then invalidated, and a stale key
surfaces as a confusing `KeyError` rather than a clear message — the exact failure plan 0050 hit with
`tools/validate_gd_metrics.py`. Nothing now blocks implementation; the layout the table must key
against is final.

**Correction from preflight (2026-08-01): the ordering was right, the stated reason was not.** This
plan claimed 0057 would move `scripts/GameState.gd`, "already one of the five existing entries". It did
not — `GameState.gd` is one of the four files 0057 deliberately KEPT at `scripts/` root, and none of
the five existing entries moved in either plan. That is why `--check-ceiling` reports no stale entries
today.

The hazard was real, but it applied to the **files about to be seeded**, not to the ones already
listed. Exactly five of the eleven seeding candidates received their current path on 2026-07-31:

| Candidate | `ndeps` | Repathed by |
|---|---|---|
| `scripts/api/LLMGameAPI.gd` | 22 | 0057 |
| `scripts/interleaved/IjfsEngine.gd` | 14 | 0055 |
| `scripts/interleaved/IjfsResolver.gd` | 12 | 0055 |
| `scripts/loaders/IjfsLoaders.gd` | 11 | 0055 |
| `scripts/ui/HexMap.gd` | 10 | 0057 |

Seeded a day earlier, nearly half the new table would have been dead keys. (The count of five was
right in the preflight draft but its enumeration was not: it named four and gestured at "the rest of
the `interleaved/` set", which does not exist — only `IjfsEngine` and `IjfsResolver` from that
directory are candidates, and the actual fifth is `HexMap.gd`. Corrected on a round-1 finding, and
listed in full here so the next reader can check it rather than trust it.)

Seeding *last* also measures the right thing: the coupling numbers worth freezing are the ones the
role layout left behind, not the ones it was about to change.
