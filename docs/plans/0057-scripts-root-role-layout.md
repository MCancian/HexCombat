---
title: "0057: 40 files at scripts/ root sit outside the role layout entirely"
status: "Preflighted — ready for review"
created: "2026-07-31"
---

> **Preflight 2026-07-31, against b726604.** Every count in this plan was re-measured, not inherited.
> Confirmed as written: 40 root files / 5,864 lines; `HexMap` 636, `LLMGameAPI` 564,
> `OffloadCalculator` 353; the 5 scene bindings across 2 `.tscn` files; the 3 autoloads;
> `model/` at 64 `Resource` to 3 `RefCounted` (`GameStateData`, `IjfsDailyState`, `LiftClass`),
> which settles open question 1 as recorded.
> **Corrected:** (a) the "only two root files change campaign state" premise was false — see the
> finding below, and `OffloadCalculator` is dropped from the `calc/` move; (b) Sequencing named
> `scripts/stages/`, a directory that never existed (it is `scripts/interleaved/`); (c) Sequencing
> described the placement validator as deny-by-default, which it is not — making it so is now an
> explicit decision rather than an assumption; (d) the reference sweep is enumerated exactly.
>
> **Round 1 plan review, 2026-07-31 — 2 substantive returns (a plan needs 1).** Sol returned 3
> findings, all verified against the tree and all applied: the smoke phase does not cover
> `scenes/SymbolPreview.tscn` at all (→ new step 3a and a new validator), the deny-by-default scope
> was too broad for a `.gd`-only validator (→ narrowed in Sequencing), and two file headers still
> assert the purity this preflight disproved (→ new step 5a). agy independently re-derived the
> aliasing chain hop by hop and confirmed no `duplicate()` at any of the 6 hops, and swept the other
> 6 `calc/` candidates plus all four new families for handed-state mutation — **ABSENT** everywhere
> else; its two most falsifiable citations were spot-checked and hold.
>
> **DeepSeek's return was 168 KB and was first triaged as a dump; that triage was wrong.** Given a
> bounded enumeration role — its measured strength, 3/3 — it produced the complete, correct
> path-string enumeration, independently confirming the sweep above: exactly **6 real bindings break**
> (the 5 `.tscn` script paths + the one `PARAM_CEILINGS` key `scripts/LLMGameAPI.gd::_action_result`),
> with `.uid` sidecars carrying a `uid://` token and **no** path string. It also caught an off-by-one
> in this plan's own citation (the DEP staleness message is `gd_metrics.py:395`; `:394` is the `.get()`
> line), now fixed. **The lesson is about the triage rule, not the model:** ">10 KB = SUSPECT" scored a
> correct enumeration as junk because the CLI interleaves tool-call echoes with the answer. Size is a
> prompt to read the return, never a reason to discard it — the same trap in the opposite direction
> from "<1 KB looks like a flake", which the roster already warns about.

# Plan 0057: Give `scripts/` root a role layout

## The finding

`docs/STATUS.md` → "Where a file goes" is the mechanism that keeps this codebase legible. It gives
eight directories a claim and a one-question test, and it opens by saying why that matters:

> *"The directory a file lives in is a CLAIM about the file… Getting this wrong is how a writer ends
> up in a directory whose whole point is that it holds none."*

**The table has no row for `scripts/` itself, and 40 files live there** — 5,864 lines, roughly a
quarter of the engine. They make no claim, satisfy no test, and nothing can be wrong about where they
sit because nothing is asserted. Measured 2026-07-31.

This is not a cosmetic gap. It is where the next boundary violation will come from, for the same
reason the two found in plan 0055 were found where they were: a file only gets audited against a claim
if it is in a directory that makes one.

## What is actually there

Categories below are structural (base type, path-binding, and the applies/pure scan), not impressions:

| Group | Files | Notes |
|---|---|---|
| Autoload singletons | 3 — `EventBus`, `GameData`, `GameState` | Paths bound in `project.godot`. `GameState` (`ndeps` 29) and `GameData` (25) are the two most-coupled non-authority files. |
| Scene-bound UI | 5 — `GameController`, `HexMap`, `InfoPanel`, `CompositionPanel`, `SymbolPreview` | Paths bound in `.tscn` files. `HexMap` alone is 636 lines. |
| UI support | 2 — `SymbolLibrary`, `MapProjection` | Not scene-bound; free to move. |
| AI policies | 9 — 7 `*Policy` plus `PolicyCatalog`, `PolicyGeometry` | A coherent family with a catalog, sitting loose. |
| Calculation | 7 — `OffloadCalculator`, `ShipLoadingModel`, `Movement`, `HexMath`, `HexOwner`, `VictoryConditions`, `FrontLineService` | `OffloadCalculator` is 353 lines and named for a role that has a directory. |
| Data holders | 5 — `CombatForces`, `AntishipMagazine`, `PendingBattalions`, `UnitStats`, `OffloadRates` | All `RefCounted`. Note `scripts/model/` is 59 `Resource` to 3 `RefCounted`, so these are **not** obviously the same kind of thing as what lives there — see the open question below. |
| Infrastructure | 5 — `Dice`, `SeededDice`, `JsonPath`, `KnobRegistry`, `TurnEventLog` | Cross-cutting utilities that serve no single phase. |
| Research / external API | 4 — `LLMGameAPI` (564 lines, `ndeps` 22), `BatchReport`, `GameNarrative`, `SelfPlayRunner` | The outward-facing surface: LLM play, batch output, narrative. |

Two root files change campaign state through an authority, both legitimately as the façade layer:
`GameState` (13 authority calls) and `GameData` (15). Re-measured 2026-07-31 with the same stripper
the placement validator uses; every other root file makes zero.

**But that scan answers "does it call an authority?", not "does it apply?" — and a third root file
applies.** `OffloadCalculator` writes `offload_progress_tons` into the BN dictionaries it is handed:

- `scripts/OffloadCalculator.gd:259` banks leftover tonnage onto a BN; `:244` erases the field when
  the BN lands; `:241` reads it back on a later turn.
- The dicts are live campaign state, passed by reference the whole way down with no `duplicate()`:
  `ReinforcementPhases.gd:165` hands `state.ship_reserve` to `OffloadResolver.resolve`, which appends
  those same entries into `troop_reserve` (`OffloadResolver.gd:63`) and passes them to
  `OffloadCalculator.resolve_offload_day` (`:68`).
- The field is cross-turn persistent by design — it is the plan 0006 C8 fractional-flow carry-over.

So it fails the `calc/` test on the "**or through arrays/dicts it was handed**" clause, which is
precisely the clause the *applies* vocabulary exists to cover. **The placement validator cannot see
this** — it detects direct authority calls only, and this is a bare dictionary write. Note also that
`OffloadResolver` already sits in `calc/` and applies transitively through this helper: that is a
pre-existing hole, not one this plan opens, and it is the validator's documented blind spot.

This is the 0055 lesson recurring with the polarity reversed. There, a *write* scan was reused to
answer an *applies* question and missed two authority callers. Here an *authority-call* scan was
reused to answer the same question and missed a direct write. **Neither instrument answers it alone.**

## Proposal

Give root a claim per family rather than one dumping ground. The shape follows from the census, but
the plan should be reviewed on the *boundaries*, not the names:

- `scripts/ui/` — the 5 scene-bound files plus the 2 UI support files.
  Test: *does it draw, or exist to be attached to a scene?*
- `scripts/policies/` — the 9 AI-policy files.
  Test: *does it turn a game state into a list of actions for one seat?*
- `scripts/api/` — the 4 research/external files.
  Test: *is its consumer outside the engine — an LLM, a batch run, a reader?*
- `scripts/support/` — the 5 infrastructure utilities.
  Test: *is it a cross-cutting utility that belongs to no phase?*
- **6 of the 7** calculation files go to `scripts/calc/` — `ShipLoadingModel`, `Movement`, `HexMath`,
  `HexOwner`, `VictoryConditions`, `FrontLineService`. All six re-measured clean above.
- **`OffloadCalculator` stays at root**, because it applies (see the finding). Moving it would install
  a file that fails its new directory's own test, in the one directory whose claim is "applies none",
  and the gate would stay green while it did — the exact failure the role layout exists to prevent.
  A tidy lie is worse than an honest exception. The hoist is plan 0058; the file moves when that lands.
- The 3 autoloads **stay at root**. Root's row becomes: *the three autoload singletons, plus
  `OffloadCalculator` pending 0058, and nothing else.* A root that holds four named files with a
  reason each is a claim; a root that holds forty is an absence of one.

The 5 data holders are the genuinely open question — see below.

## Open questions for review

**1. ~~Do the 5 `RefCounted` data holders belong in `scripts/model/`?~~ ANSWERED in round 1 — yes.**
The concern was that `model/` is overwhelmingly `Resource` subclasses (64 to 3 counting
`model/ijfs/`), implying an unstated "serializable `Resource`" convention these five would violate.
A reviewer checked the three existing `RefCounted` members — `GameStateData`, `IjfsDailyState`,
`LiftClass` — and they are structural holders, exactly what the five root files are. So `model/`
already admits both base types and the five move there. The role table should state that explicitly,
since the de-facto convention was invisible enough to stall this question once.

**2. Is `LLMGameAPI` one file or three?** At 564 lines and `ndeps` 22 it is the third most-coupled
file in the codebase, and it is on the backlog for a separate reason (order-kind dispatch lives in
three places, one of which is inside it). Moving it is fine; splitting it is not this plan.

**3. Does `scripts/ui/` want a `HexMap` at 636 lines?** Noted, not solved here.

## Steps

1. ~~Settle open question 1 in review.~~ **Done — the 5 data holders move to `scripts/model/`.**
   Answered in round 1 and re-measured during preflight: `model/` is 64 `Resource` to 3 `RefCounted`,
   and all three `RefCounted` members (`GameStateData`, `IjfsDailyState`, `LiftClass`) are structural
   holders, exactly what the five root files are. No step now waits on anything; 2–8 all proceed.
2. `git mv` one family per commit, sidecar `.uid` with each file. Six commits, not one — a mixed
   40-file move is unreviewable and a bad path lands invisibly inside it.
3. **After the UI family specifically**, update the 5 scene-bound references — `res://scripts/*.gd` in
   `scenes/Main.tscn` (`HexMap`, `GameController`, `InfoPanel`, `CompositionPanel`) and
   `scenes/SymbolPreview.tscn` (`SymbolPreview`). These break at runtime, not at compile time.
   **`project.godot`'s autoload block is NOT touched.** The three autoloads stay at root, so their
   paths do not change — an earlier draft of this plan scheduled that edit and was self-contradictory.
   Do not "fix" the autoload paths; there is nothing to fix.

   **3a. The smoke phase does NOT cover all five, and an earlier draft of this plan claimed it was
   "the entire mitigation" (review finding, Sol, 2026-07-31 — verified).** Smoke boots only the
   configured main scene: `project.godot:15` is `run/main_scene="res://scenes/Main.tscn"`, and
   `tools/run_all_tests.py:89-95` asserts four content markers plus absence of `SCRIPT ERROR`.
   **`SymbolPreview` appears in neither `scenes/Main.tscn` nor `project.godot` — both ABSENT,
   measured — and `scenes/SymbolPreview.tscn` is referenced by nothing outside `docs/`.** So the one
   binding with NO coverage at all is the one whose file this plan moves. Nothing in the gate would
   ever go red; the scene would simply be dead the next time a human opened it.
   Worse, the four `Main.tscn` bindings are only *incidentally* covered: smoke would catch a null
   script via a missing marker or a `SCRIPT ERROR`, but nothing asserts the five nodes still HAVE
   scripts, so coverage is a side effect of what those scripts happen to print.
   **Therefore add `tools/validate_scene_script_bindings.gd` in the same commit as the UI move:** it
   loads every `.tscn` under `scenes/`, walks the node tree, and fails if any node that should carry a
   script has a null one — or, more cheaply and with no scene instantiation, parses each `.tscn` for
   `ext_resource type="Script" path="..."` and asserts each path resolves to an existing file. The
   second form is preferable here: it needs no display server, catches exactly the failure mode
   (a path string that no longer resolves), and cannot be defeated by a scene that fails silently.
   This is the mitigation the plan needs; the smoke phase is integration coverage on top of it.
4. Sweep for path-keyed references. **The full surface, measured 2026-07-31 — it is small and
   bounded, because GDScript resolves `class_name` path-independently:**
   - **`tools/gd_metrics.py` — 3 keys go stale, and a stale key FAILS loudly** (`"not found (ceiling
     entry stale)"`, `gd_metrics.py:395,406`), so this cannot be missed silently:
     `scripts/LLMGameAPI.gd::_action_result` (→ `api/`), `scripts/OffloadCalculator.gd::_resolve_day_n`
     and `::resolve_offload_day`. **The last two do NOT move** — `OffloadCalculator` stays at root —
     so only the `LLMGameAPI` key changes. Re-key it in the same commit as the `api/` move.
   - **`DEP_CEILINGS["scripts/GameState.gd"] = 29` survives**; `GameState` stays at root.
   - **Survives, needs no edit:** `tests/scenario_loader_test.gd:3` and
     `tools/validate_combat_rules_threading.gd:49` both `preload` / name `res://scripts/GameData.gd`,
     which stays. These are the only two path-string loads of a root script outside `scenes/`.
   - **`docs/**` and `.claude/skills/**`** cite moved files as backticked `scripts/X.gd` paths in
     ~10 files (`ARCHITECTURE.md`, `LLM_OBSERVATION_SCHEMA.md`, `docs/systems/hex-grid/`,
     `frontline-cleanup-victory/`, `ground-combat/`, `roc-mobilization/`, `supply-dos/`, …).
     `validate_doc_anchors.gd` enforces these (rule 2, backticked repo path must resolve) and
     excludes only `docs/archive/`, `docs/plans/`, `docs/reports/` and `RETRO.md`.
   - **`docs/DECISIONS.md` is NOT excluded** and carries 3 hits (`HexMap.gd`, `JsonPath.gd`,
     `KnobRegistry.gd`). It is a changelog of past decisions, so mark those lines **`(historical)`** —
     the literal token, not prose that reads historical — rather than rewriting what a past entry said.
   - `PolicyCatalog` dispatches policies by `class_name`, not path: **no policy-id or catalog edit.**
5. Add the new rows to the role table in `docs/STATUS.md`, rewrite root's row from absent to the
   four-file claim, and state explicitly that `scripts/model/` admits `RefCounted` structural holders
   as well as `Resource` (open question 1 — the de-facto convention was invisible enough to stall the
   question once).
5a. **Correct the two headers that currently assert the purity this preflight disproved** (review
   finding, Sol, 2026-07-31). Comment-only, no behaviour, and they should not wait for 0058 — a file
   that says it is pure is how the next agent stops checking.
   - `scripts/OffloadCalculator.gd:11` reads `# Pure RefCounted lib — no Node dependency,
     headless-testable.` In fairness its own clause scopes "pure" to *no Node dependency*, so this is
     misleading rather than false — but "pure" is now a loaded word in this repo's role vocabulary
     and this file is the one counter-example. Add a line naming the aliased write and 0058.
   - `scripts/calc/OffloadResolver.gd:4-5` reads `## Pure resolver … without changing reserve or
     cohort membership.` Strictly that clause is about *membership*, which the aliased write does not
     change — but the file sits IN `calc/` and applies transitively through the helper, which is the
     validator's documented blind spot. Add a note saying so explicitly.
6. Convert `tools/validate_authority_call_placement.gd` to **deny-by-default over `scripts/`** (see
   Sequencing) with the root FILE allowlist. Extend its `_self_test()` in the same commit — a new
   failure mode that no case asserts is a validator whose green run proves less than it looks like it
   does, and that file's own header says a pin that never matched has already shipped here once.
   Minimum new cases: an unclassified directory FAILS; an unlisted root file FAILS; a permitted root
   file with an authority call PASSES.
7. `bash tools/run_all_tests.sh` → ALL PHASES GREEN, with the **smoke phase** given particular
   attention: a broken `.tscn` script path passes compilation and fails at scene load.
8. Each of the six move commits must be **independently gate-green**, since the reference sweep is
   what makes a move pass — do not promise six commits and discover the families are entangled.

## Risk

**Moderate, and higher than 0055 despite being the same kind of change.** 0055 moves files that only
other GDScript refers to, and a `class_name` is path-independent, so a missed reference is loud.
This plan moves files referenced by `.tscn` and `project.godot`, where the binding is a **path
string** — a missed one produces a scene that loads with a null script or an autoload that silently
does not exist. Neither is a compile error. **The mitigation is step 3 plus the new
`validate_scene_script_bindings` gate of step 3a — NOT the smoke phase**, which does not load
`scenes/SymbolPreview.tscn` at all and covers the other four only incidentally. An earlier draft of
this plan named smoke as the entire mitigation; that was the single most dangerous sentence in it,
because it pointed the implementer's attention at a check that cannot fail for the file most at risk.

Second risk: **scope drift into splitting the big files.** `HexMap` at 636 lines and `LLMGameAPI` at
564 will both look like they want breaking up while they are being moved. They may; that is a plan
with a behaviour budget, not a rider on a path move.

## Out of scope

Splitting any file, reducing any file's coupling, renaming any class, and changing what any file does.
**Hoisting `OffloadCalculator`'s banked-progress write is explicitly out of scope and is plan 0058.**
It is a behaviour-adjacent change to the offload path with golden exposure, and folding it into a
40-file path move would destroy the one property that makes this plan reviewable — that no file's
behaviour changes. 0058 must first settle whether `ordered_ids` can repeat a brigade id, since a
repeat means a BN's banked value is read back within the same call and the write is not freely
deferrable; that question needs measuring, not reasoning.
The `scripts/model/` base-type convention is *named* here as open question 1 but is only settled, not
implemented, unless the answer is "these five move" — anything broader is its own unit.

## Sequencing

**After 0055 — which SHIPPED 2026-07-31 (b726604), so this is now satisfied.** That plan established
the vocabulary this one extends. The property-named directory it created is **`scripts/interleaved/`**
(computes AND applies at its own draw point); an earlier draft of this section guessed the name
`scripts/stages/`, which never existed. `docs/plans/` is excluded from the doc-anchor gate, so that
dead path sat here unflagged — a reminder that nothing mechanical checks this file.

0055 also shipped `tools/validate_authority_call_placement.gd`. **This plan extends that validator
rather than inventing one** — each new directory gets its entry in the same commit that creates it.
A family moved without its entry is the failure this sequencing exists to prevent.

**Read the shipped validator before designing against it; an earlier draft of this section described
one that does not exist.** What it actually does (header at `tools/validate_authority_call_placement.gd:1-47`):

- It holds an explicit `FORBIDDEN_DIRS` list (`calc/`, `builders/`, `loaders/`, `model/`,
  `transitions/`) plus one `REQUIRED_DIR` (`interleaved/`). **Anything unlisted is simply not scanned**
  — including `scripts/` root today. It is an allow/deny list, **not deny-by-default**.
- The scan **recurses**, so a nested directory inherits its parent's claim (fixed in b726604).

So "unknown directories default to DENY" is **a design change, not a row addition**, and this plan
makes it deliberately:

**Decision: convert the validator to deny-by-default over the `scripts/` subtree.** An unclassified
directory **fails the gate**. The alternative — adding four rows and leaving the default open —
reproduces the exact defect this plan exists to close: a directory that asserts nothing is a directory
nothing can be wrong in, and the next family added would silently land unchecked. Deny-by-default is
the harder half-day and the only version that is self-enforcing.

**Scoped precisely (review finding, Sol, 2026-07-31 — verified).** An earlier draft said "every
directory under `scripts/`", which would have this validator fail for things it does not own: its
scanner only ever collects `.gd` files (`validate_authority_call_placement.gd:188-193`), and its
header is deliberate that it owns direct authority calls and nothing broader (`:30-34`). A future
`scripts/shaders/` or a scratch directory would then fail a gate that has no opinion about it. So:

- Deny-by-default applies to **directories under `scripts/` that CONTAIN at least one `.gd` file**,
  directly or nested. A directory with no GDScript in it is not this validator's business.
- **Nested directories inherit the nearest classified ancestor** — matching the recursion already
  shipped in b726604, so `scripts/model/ijfs/` needs no entry of its own.
- The root allowlist is **exact root-level `.gd` filenames**, not sidecars (`.uid`) or other assets.
- The validator's header and its PASS line must state the new classification guarantee. A validator
  whose printed verdict overstates what it checked is the failure its own header warns about.

Classification of what will exist after this plan: `calc/`, `builders/`, `loaders/`, `model/`,
`transitions/`, `ui/`, `policies/`, `api/`, `support/` **FORBID**; `interleaved/` **REQUIRES**;
`phases/` **PERMITS** (ordering authority calls is its job — it makes 66 and that is correct, so it
must be named as permitted rather than left unlisted, which is how it reads today).

**Root needs an exact FILE allowlist, not a directory row** — this part of the draft was right, and
deny-by-default is what makes it necessary rather than optional. `GameState.gd` and `GameData.gd` are
PERMITTED to call authorities; `EventBus.gd` and `OffloadCalculator.gd` are FORBIDDEN; **any other file
appearing at root fails the gate.** A row saying "root may call authorities" would license any future
root file to do so, recreating the unpoliced root under a nominally checked entry.

Note the allowlist does **not** catch `OffloadCalculator`'s actual violation, which is a bare dict
write and invisible to this validator. That is what plan 0058 is for; the allowlist only stops it
acquiring an authority call as well.

**Before 0056.** Both plans key on paths, and 0056 seeds a path-keyed ceiling table. The rationale is
NOT `scripts/GameState.gd` — that file stays at root and its entry survives. It is the roughly
thirty-five files that DO move: any of them at or above 0056's threshold would be seeded under a path
this plan then invalidates, and `PARAM_CEILINGS` keys for their functions would go stale outright.
