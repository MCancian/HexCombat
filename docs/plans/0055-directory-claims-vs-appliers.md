---
title: "0055: The directory claims do not track who applies campaign state"
status: "Sketch"
created: "2026-07-31"
rewritten: "2026-07-31"
---

# Plan 0055: The directory claims do not track who applies campaign state

> **This plan was rewritten at preflight on 2026-07-31. Its original proposal — "move all six
> `scripts/resolvers/` files to `scripts/calc/` and delete the directory" — is WRONG and must not be
> implemented.** Two of the six apply campaign state. The measurement that said otherwise answered a
> narrower question than the plan's own test asked. The dead premise is preserved in full below,
> because the *way* it died is the reusable part.

## How the original premise died

The original plan quoted the `scripts/resolvers/` test from `docs/STATUS.md` correctly:

> *"Is it the phase's own logic, **and does it still write campaign state?**"*

and then produced a six-row table concluding **no** for every file. That table came from the
alias-taint scan reused from plan 0050's source sweep: *every write whose receiver is a protected
field name, a function parameter, or a local aliased from live state.*

That scan detects **direct field assignment**. It cannot detect **application through a mutation
authority**, because an authority call is a function call, not an assignment — and after the
0042–0050 campaign, *legitimate* application is the only kind left in the codebase. The scan was
built to find illegal writers in a world that still had them; run over a post-campaign directory it
reports "no writes" for a file that changes campaign state on every turn.

**The generalizable lesson: a measurement inherits the question it was designed for.** 0050's scan
asked "who writes illegally?" The plan needed "who applies at all?" Reusing the instrument without
re-deriving the question is how a plan gets a confidently wrong table.

Counter-scan, comment-stripped so that `##` header prose does not count (it otherwise produces ten
false positives in `calc/` alone):

```
grep -vE '^\s*#' FILE | grep -cE '\b[A-Za-z]+Transitions\.[a-z_]+\('
```

| File | Original table | Applies via an authority? |
|---|---|---|
| `FrontlineResolver.gd` | no writes | **no** — confirmed pure |
| `InfrastructureResolver.gd` | no writes | **no** — confirmed pure |
| `OffloadResolver.gd` | no writes | **no** — confirmed pure |
| `CombatResolver.gd` | no writes | **no** — confirmed pure |
| `CleanupResolver.gd` | no writes | **YES — 2 calls** |
| `IjfsResolver.gd` | no writes | **YES — 4 calls** |

`IjfsResolver` calls `IjfsTransitions.add_targets`, `.apply_activity_posture`, `.retire_target` and
`.set_manpads_remaining` — it adds and retires strike targets and sets MANPADS stock.
`CleanupResolver` calls `AntishipTransitions.reset_transient_flags` and `ForceTransitions.apply_activity`,
the latter latching `moved_last_turn` / `fought_last_turn`, both classified `campaign` in the manifest.

Moving those two into `scripts/calc/` would have made `calc/`'s claim — *"writes NO campaign state at
all"* — false for the directory, which is the exact defect the plan set out to remove.

## The real finding

Widening the counter-scan past `resolvers/` shows the problem is not one stale directory. **Not one
of the three directories tracks the applies/pure line.** Census, 2026-07-31, 32 files:

| Directory | Applies via an authority | Pure |
|---|---|---|
| `scripts/ijfs/` | 6 — `IjfsDetection`, `IjfsEngagement`, `IjfsEngine`, `IjfsManpads`, `IjfsStrike`, `IjfsTargeting` | 1 — `IjfsLoaders` |
| `scripts/calc/` | 1 — `JlsfCargo` | 18 |
| `scripts/resolvers/` | 2 — `CleanupResolver`, `IjfsResolver` | 4 |

There are **nine appliers**, spread across three directories, only six of which sit in the one
directory whose claim actually permits it. And `scripts/ijfs/` — the directory that exists *precisely*
to hold "computes AND applies at its own draw point" — is named after a subsystem rather than after
the property, which is why nothing pulled the other three in.

`scripts/calc/JlsfCargo.gd:103` is the sharpest case. It flips a JLSF deployment marker through
`InfrastructureTransitions.queue_jlsf` inside its queueing loop, and its own header (`:72-76`) gives
the correct justification: whether an entry is emitted depends on state the previous iteration wrote,
so a planner working from a pre-loop snapshot would emit two entries where one is right. **The code is
correct and the reasoning is the `scripts/ijfs/` reasoning verbatim — only the directory is wrong.**

## Proposal

Name the category after the property, and put all nine appliers in it.

Introduce **`scripts/stages/`** — *computes AND applies, at its own draw point, through that
aggregate's authority.* Test: **would deferring its application change how many dice are drawn, or
what a later iteration decides?** Move the nine appliers there. `scripts/ijfs/` dissolves;
`IjfsLoaders` goes to `scripts/loaders/`, whose claim it already satisfies. The four pure resolvers go
to `scripts/calc/`, and `scripts/resolvers/` is deleted as the original plan intended — just not with
the six files it named.

Resulting role table: `phases/` orders, `calc/` computes, `stages/` computes-and-applies,
`transitions/` owns, `builders/` + `loaders/` construct, `model/` holds.

### Considered and rejected

- **Keep `scripts/ijfs/` and add a sibling per subsystem.** Directory proliferation, and it repeats
  the original error: the name would again describe the subsystem rather than the property, so the
  next applier lands outside it too.
- **Widen `calc/` to permit authority calls.** Foreclosed by `docs/STATUS.md`'s own reasoning from
  plan 0046: widening `calc/`'s claim to cover appliers "would have made it untrue everywhere". It
  also destroys the only cheap, greppable way to ask "what can change the game?"
- **Refactor the appliers to return outcomes and hoist application to their callers.** This is the
  purist option and it is wrong here for a measured reason: for at least `JlsfCargo` and the IJFS
  stages, deferral changes the result (dice count, or duplicate entries). It would be a behaviour
  change wearing a refactor's clothes, and the golden pins would catch it as drift.

## The moves are half of it — the other half is a gate

**Without a gate this plan is a cleanup that rots, and we know that because it already did.**
`docs/STATUS.md` records the lesson from `AntishipResolver` — *a directory claim can go stale WITHOUT
anyone editing the file, because what made it true was deleted somewhere else* — and then three more
misplacements accumulated after that sentence was written, unnoticed, until someone happened to
measure. Making the claims true on the day this ships changes nothing structural if nothing keeps them
true.

The placement rule is the only load-bearing invariant in this repo with **no enforcement surface**.
Ownership has the manifest and a source gate. Coupling and parameters have ceilings. Doc anchors,
skill references and reviewer facts each have a validator. Stale *exemptions* have error codes. Where
a file lives has prose.

### The checkable half

"May this directory call a mutation authority?" is a fixed table, and the scan is a `grep`. Measured
2026-07-31, authority calls by directory — the rule is **already satisfied everywhere but one file**:

| Directory | May call an authority | Measured |
|---|---|---|
| `scripts/builders/` | no | 0 ✅ |
| `scripts/loaders/` | no | 0 ✅ |
| `scripts/model/` | no | 0 ✅ |
| `scripts/transitions/` | they *are* the authorities | 0 ✅ |
| `scripts/calc/` | **no** | **1 — `JlsfCargo`, the violation this plan moves** |
| `scripts/stages/` (new) | yes — that is its claim | 16 + 6 on arrival |
| `scripts/phases/` | yes — ordering those calls is the job | 64 |

So the validator is green the moment step 2 lands. It costs one file and locks in the whole plan.

### The half that is NOT checkable — say so plainly

A validator that implied full coverage would be worse than none. It cannot decide *"does this apply at
its own draw point?"* (requires knowing whether deferral changes the dice), nor *"does `phases/` only
order calls?"*, nor whether a pure file is in `calc/` versus somewhere else sensible. Those stay prose,
and the validator's header must say which half it owns — the same way the mutation gate's header names
its aliased-container blind spot rather than letting a reader assume completeness.

### Shape

A self-contained `tools/validate_role_directories.gd`, auto-discovered by the gate's
`tools/validate_*.gd` phase — no wiring, unlike a Python validator, which needs its own block and
`PASS:` regex in `tools/run_all_tests.py`.

It will carry its own comment/string stripper, making a fifth copy. **That is deliberate and already
adjudicated** — the backlog records the 2026-07-26 decision NOT to unify the four existing strippers,
revisit only on new evidence. Do not "fix" it here; adding a fifth is following the standing decision,
not violating it.

It scans source as **text**, so it names no `class_name` and stays clear of the tool-script compile
closure that plan 0040 hit.

## Scope note

A GDScript `class_name` is path-independent, so **no call site moves and no signature changes**. The
moves remain a `git mv` + reference sweep with zero behaviour change and no pin permitted to move; the
validator is new code but touches no game code and cannot move a pin either. What changed from the
original plan is the *size* (13 files across four directories, not 6 across two), that it now creates a
directory and a role-table row rather than only deleting one, and that it ships a gate.

## Steps

1. **Re-run both scans and confirm the census still holds.** The alias-taint scan (illegal direct
   writes — expect zero) *and* the comment-stripped authority-call scan above. If any file has changed
   category since 2026-07-31, re-derive the table before moving anything.
2. Create `scripts/stages/`. `git mv` the nine appliers and their `.uid` sidecars together, one commit.
3. `git mv` the four pure resolvers to `scripts/calc/`, `IjfsLoaders` to `scripts/loaders/`, and delete
   `scripts/resolvers/` and `scripts/ijfs/`. One commit.
4. **Sweep for path-keyed references** — the failure mode plan 0050 hit was
   `tools/validate_gd_metrics.py` hard-coding `"scripts/resolvers/AntishipResolver.gd::resolve"`,
   which no call-site grep finds. Measured live references, 2026-07-31:
   - `tools/gd_metrics.py` — `DEP_CEILINGS` and `PARAM_CEILINGS` keys are path-keyed; a stale key
     fails the gate with *"not found (ceiling entry stale — file moved/deleted?)"*
   - `docs/STATUS.md:21`, `:24`, `:55` — the role table and the two worked examples
   - `docs/ARCHITECTURE.md:90`
   - `docs/systems/turn-engine/STATUS.md:16` (also cites this plan by its old filename)
   - `.claude/skills/hexcombat-docs-and-writing/SKILL.md:22`
   - `project.godot`, `.import`
   **`docs/archive/**` takes a narrower rule, learned by getting it wrong during this rewrite.** Ten
   hits live there and they are the historical record — do **not** restate them as if they described
   current code. But a dead *link* is not history, it is a broken pointer: when the referent still
   exists under a new path, repoint it (the doc-anchor gate fails otherwise), and where the archived
   claim is now known false, append a dated correction rather than editing the original sentence.
   Only mark a line `(historical)` when the thing it names is genuinely gone.
5. Rewrite the role table in `docs/STATUS.md`: delete the `scripts/resolvers/` row, replace the
   `scripts/ijfs/` row with the `scripts/stages/` row and its property-based test, and correct the
   `scripts/calc/` row. The two worked examples below it explain a `resolvers/` vs `calc/` boundary
   that will no longer exist — what must survive is **the lesson**: a directory claim can be
   invalidated by a deletion somewhere else, and a measurement can be invalidated by reusing an
   instrument built for a different question.

   **Settle the vocabulary while rewriting, because the ambiguity is what caused this plan's original
   error.** "Write" and "apply" are each doing two jobs: *direct field assignment* and *changes
   campaign state by any route*. Before the 0042–0050 campaign those were the same act; authorities
   split them, and the docs kept the old word. Three live casualties: this plan's original test said
   "still **writes** campaign state" and was answered with an assignment scan; the `calc/` row said
   "**writes** NO campaign state" while `JlsfCargo` writes no field and changes the game every turn;
   the `phases/` row says "**applies** nothing itself" while `ReinforcementPhases` makes 34 authority
   calls — correct under the intended reading, a flagrant violation under the plain one. Fix the whole
   table to one vocabulary: **writes** = assigns a field directly; **applies** = changes campaign state
   by any route, including through an authority. Every row states which it means.
6. **Add `tools/validate_role_directories.gd`** with the permission table above, as its own commit
   after the moves. Its header states which half of the placement rule it owns and which half it
   cannot. Then **prove it bites**: temporarily add an authority call to a file in `scripts/calc/`,
   confirm the validator fails and names the file, revert. A gate nobody has watched fail is not known
   to work — the repo has already shipped a validator whose pin never matched anything, and it passed
   for weeks.
7. Point `docs/STATUS.md`'s role table at the validator, so the next reader learns the claims are
   checked rather than asserted. One line, not a restatement of the table.
8. `bash tools/run_all_tests.sh` → ALL PHASES GREEN. The moves must not touch a pin.

## Risk

Low on behaviour — nothing here changes what any code computes. Three real risks.

**Path-keyed references (step 4).** Caught by no compiler and no call-site grep; surfaces as a
confusing `KeyError` when one specific validator runs. The gate does run it, so a miss is caught —
sweep first so it is caught by reading rather than by debugging.

**A validator that over-claims.** If `validate_role_directories.gd` reads as "placement is now
enforced", the next agent trusts it for the questions it cannot answer, and the unpoliced half becomes
*more* dangerous than before because it now looks covered. Mitigated only by the header and by step 6's
failure demonstration — a gate whose scope is stated but never observed failing tends to get believed
beyond its scope.

**Scope drift into a real refactor.** If any applier looks like it "should" return an outcome instead,
that is a separate plan with a behaviour budget and a golden re-baseline conversation. Not here. The
validator makes this temptation worse, not better: adding one more rule always looks cheap while the
file is open.

## Out of scope

Renaming any class, changing any signature, changing what any file computes, or re-litigating which
module owns which phase. This is where files live, and nothing else. The 40 unclassified files at
`scripts/` root are a known, larger problem and are deliberately not touched.

## Why it was NOT folded into 0050

Discovered *after* 0050's diff-review round, from a reviewer finding about wording that had just been
written. Folding an addition of this size into a reviewed thirty-five-file diff would have shipped it
unreviewed, which that plan's own "campaign fatigue" stop condition forbids. 0050 corrected the false
claim and pointed here.
