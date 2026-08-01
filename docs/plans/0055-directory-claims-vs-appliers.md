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
- **Refactor ALL the appliers to return outcomes and hoist application to their callers.** The purist
  option, and wrong as a blanket rule: for the IJFS stages deferral changes the dice count. But it is
  right for at least one file — see the `CleanupResolver` decision below — so this is rejected as a
  *policy*, not case by case.

### Two naming calls, one settled and one open

**The `*Resolver` class names do NOT get renamed. Settled.** Ten files carry the suffix and after this
plan eight sit in `calc/` and two in `stages/`, which looks like the suffix has stopped meaning
anything. Round 1 pushed back and is right: "Resolver" names a *phase endpoint* — the thing that
decides what happens in a phase — and it never encoded purity. Renaming would touch every call site and
doc for no gain, and unlike a file move a class rename is not free. **The directory carries the
application policy; the suffix carries the phase role.** Say that in the role table so the next reader
does not re-open this.

**`scripts/stages/` is an OPEN name question.** "Stage" is already in this repo's vocabulary — ~21
matches under `scripts/` including the pure anti-ship pipeline in `AntishipCrossing`, ~101 across
source and docs — and it reads as *ordering*, which is `phases/`'s job, rather than as *interleaved
application*. `scripts/interleaved/` was proposed as more precise. Decide before step 2; the plan does
not depend on which wins, but renaming the directory afterwards costs the whole sweep again.

## `CleanupResolver` qualifies for neither directory — the one open decision

Round 1 found this from both sides and both are right, which is what makes it a real hole rather than a
disagreement:

- It **does** mutate campaign state — `ForceTransitions.apply_activity` latches `moved_last_turn` /
  `fought_last_turn`, both classified `campaign` in the manifest. So it cannot go to `calc/`.
- It **fails `stages/`'s own test** — nothing in the function reads either mutation, and deferring both
  to its caller would change neither a decision nor a die. So it is not a draw-point applier either.

It applies for no draw-point reason. That is a fourth category, and it has exactly one member: the
IJFS stages and `JlsfCargo` all have a real ordering constraint, `CleanupResolver` does not.

**Recommendation: make it pure, and hoist both mutations into `TurnClosure`.** Measured cost —
`resolve()` has four call sites (`TurnClosure.gd:49` plus three tests); `census()` is already pure and
separate so its callers are untouched; `census()` reads neither the reset nor the latched fields, so
ordering inside the function is free. `TurnClosure` already applies through three authorities and its
claim ("orders calls and threads results") covers this exactly. Its own comment at `:47` already
describes the flag reset and activity latch as *"Pure work"* — the same write/apply confusion this plan
is fixing, sitting in a code comment on this exact code.

**Why not defer it.** Deferring leaves three bad options: put a file in `stages/` that fails the
directory's test on day one, keep a one-file `scripts/resolvers/` alive, or knowingly misfile it in
`calc/`. The first is worst — the new directory would be born with the exact defect this plan exists to
cure, and the validator (which checks only *may* it call an authority, not *must* it be a draw-point
applier) would not catch it.

**The cost is honest: this makes the plan no longer purely path-only.** It is a behaviour-neutral
hoist of six lines plus three test call sites, fully covered by the golden pins — but it is a code
change, and if it is deferred the plan must say which of the three bad options it is taking.

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

### It must check BOTH directions

A one-directional check ("forbidden directories make zero calls") does not close the failure mode this
plan cites. The historical case — `AntishipResolver` — was a file that STOPPED applying and became
misplaced without anyone editing it. A file going pure inside an *allowed* directory stays legal under
a one-directional rule, so the exact defect walks straight through.

So: forbidden directories must have **zero** direct authority calls, **and every `scripts/stages/` file
must have at least one.** A stage that stops applying fails the gate and gets re-homed, which is the
case that actually rotted.

Derive the authority names from `tools/mutation_authority_manifest.json` rather than from a
`[A-Za-z]+Transitions` regex. The manifest is the single home for that list; a regex is a second,
silent one that drifts the moment an authority is renamed.

### The half that is NOT checkable — say so plainly

A validator that implied full coverage would be worse than none, and this one's blind spot is bigger
than "some things are judgement calls": **it sees only DIRECT calls.** `IjfsResolver` calls
`IjfsEngine.run_daily`, which calls authorities — so application through a helper is invisible, and a
file can apply transitively while reading as pure. Transitive closure is not worth building here (it
would need call-graph analysis over a dynamically-typed language), but it MUST be stated, because the
name is what a future agent trusts.

It also cannot decide *"does this apply at its own draw point?"* (requires knowing whether deferral
changes the dice), nor *"does `phases/` only order calls?"*, nor whether a pure file is in `calc/`
versus somewhere else sensible.

### Shape

**Name it `tools/validate_authority_call_placement.gd`, not `validate_role_directories.gd`.** It checks
where direct authority calls may appear — not role correctness, and not application. The broader name
invites exactly the over-confidence the section above warns about, and a name is the only part of a
validator most agents ever read.

Self-contained, auto-discovered by the gate's `tools/validate_*.gd` phase — no wiring, unlike a Python
validator, which needs its own block and `PASS:` regex in `tools/run_all_tests.py`.

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
   **`tools/mutation_authority_manifest.json:816` holds `"path": "res://scripts/ijfs/IjfsLoaders.gd"`**
   — a `construction_writers` allowance consumed by the mutation-authority gate. Moving that file
   without updating this breaks the OWNERSHIP gate, which is the one guarantee this repo most relies
   on. It was missing from this list until the round-1 enumeration found it; it is first here because
   it is the highest-consequence reference in the sweep.

   **`tools/gd_metrics.py` — twelve `PARAM_CEILINGS` keys name moving files.** A stale key fails the
   gate with *"not found (ceiling entry stale — function moved/renamed?)"*. Enumerated, so nobody has
   to re-derive them:
   - `:99` `scripts/calc/JlsfCargo.gd::queue_deployments`
   - `:112`–`:114` `scripts/ijfs/IjfsDetection.gd::` `_log_detection`, `_run_detection_phase`,
     `aircraft_detect_target_ids`
   - `:115` `scripts/ijfs/IjfsEngagement.gd::resolve_sead_engagement`
   - `:116` `scripts/ijfs/IjfsManpads.gd::intercepted_strike_log`
   - `:117` `scripts/ijfs/IjfsStrike.gd::resolve_strike`
   - `:118`–`:119` `scripts/ijfs/IjfsTargeting.gd::` `apply_exquisite_intel`,
     `select_munition_with_doctrine`
   - `:121`–`:123` `scripts/resolvers/` `CleanupResolver.gd::resolve`,
     `IjfsResolver.gd::build_warmup_context`, `OffloadResolver.gd::resolve`

   `DEP_CEILINGS` names no moving file — all five entries are `GameState` and `phases/`. Its *comments*
   do name several (`:38`, `:46`, `:47`, `:49`, `:60`, `:61`) and will describe a dead layout
   afterwards; comments are gated by nothing, so fix them here or they rot silently.

   Remaining references, all documentation:
   - `docs/STATUS.md:21`, `:24`, `:55`, and the `scripts/ijfs/` rows at `:59`, `:65`
   - `docs/ARCHITECTURE.md:90`; `docs/DECISIONS.md:129`, `:624`
   - `docs/systems/turn-engine/STATUS.md:16`; `docs/systems/ijfs/ijfs.md` (many);
     `docs/systems/ground-combat/ground-combat.md:20`, `:120`, `:138`;
     `docs/systems/amphibious-offload/amphibious-offload.md:19`, `:22`;
     `docs/systems/air-insertion/air-insertion.md:64`;
     `docs/systems/roc-mobilization/roc-mobilization.md:29`; `docs/systems/terrain/terrain.md:137`
   - `.claude/skills/` — `hexcombat-architecture-contract` (`:31`, `:42`, `:105`),
     `hexcombat-add-phase-resolver` (`:9`, `:53`), `hexcombat-structure-map` (`:77`),
     `hexcombat-docs-and-writing:22`
   **These are stale PROSE, not gate failures.** `tools/validate_skill_references.gd`'s pattern
   requires a concrete `.gd` path, so a bare `scripts/resolvers/` directory reference is not matched
   and the gate stays green with every one of them wrong. Do not rely on a red gate to find them.

   **`project.godot`, `*.tscn`, `*.tres`, `*.import`, `*.cfg`: ABSENT.** No engine or config file
   references either directory — the only path-bound scripts are at `scripts/` root and none moves
   here. (That is what makes this plan materially safer than 0057, which moves eight of them.)
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
6. **Add `tools/validate_authority_call_placement.gd`** with the permission table above, as its own commit
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

**A validator that over-claims.** If it reads as "placement is now
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
