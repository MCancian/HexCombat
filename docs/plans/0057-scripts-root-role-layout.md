---
title: "0057: 40 files at scripts/ root sit outside the role layout entirely"
status: "Sketch"
created: "2026-07-31"
---

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

Only **two** root files change campaign state, and both do it legitimately as the façade layer:
`GameState` (13 authority calls) and `GameData` (15). No hidden applier is sitting at root — that
question is settled, and this plan does not need to relitigate it.

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
- The 7 calculation files go to `scripts/calc/`, subject to the same applies/pure scan 0055 uses.
- The 3 autoloads **stay at root**, and root's row in the table becomes exactly that: *the autoload
  singletons and nothing else.* A root that holds three named files is a claim; a root that holds
  forty is an absence of one.

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

1. Settle open question 1 in review. Steps 2–6 proceed regardless; only the 5 holders wait on it.
2. `git mv` one family per commit, sidecar `.uid` with each file. Six commits, not one — a mixed
   40-file move is unreviewable and a bad path lands invisibly inside it.
3. **After the UI family specifically**, update the 5 scene-bound references — `res://scripts/*.gd` in
   `scenes/Main.tscn` (`HexMap`, `GameController`, `InfoPanel`, `CompositionPanel`) and
   `scenes/SymbolPreview.tscn` (`SymbolPreview`). These break at runtime rather than at compile time,
   so the smoke phase is the check that matters, not the compile.
   **`project.godot`'s autoload block is NOT touched.** The three autoloads stay at root, so their
   paths do not change — an earlier draft of this plan scheduled that edit and was self-contradictory.
   Do not "fix" the autoload paths; there is nothing to fix.
4. Sweep for path-keyed references exactly as 0055 does: `tools/*.py`, `tools/*.gd`, `.import`,
   `docs/systems/**`, `.claude/skills/**`. Repoint dead links in `docs/archive/**`; do not restate
   their claims. **`scripts/GameState.gd` and `scripts/GameData.gd` keep their paths**, so the
   `DEP_CEILINGS` entry for `GameState` does NOT go stale from this plan — check the other ceiling
   keys against the families that do move.
5. Add the new rows to the role table in `docs/STATUS.md`, and rewrite root's row from absent to
   "the autoload singletons only".
6. `bash tools/run_all_tests.sh` → ALL PHASES GREEN, with the **smoke phase** given particular
   attention: a broken `.tscn` script path passes compilation and fails at scene load.

## Risk

**Moderate, and higher than 0055 despite being the same kind of change.** 0055 moves files that only
other GDScript refers to, and a `class_name` is path-independent, so a missed reference is loud.
This plan moves files referenced by `.tscn` and `project.godot`, where the binding is a **path
string** — a missed one produces a scene that loads with a null script or an autoload that silently
does not exist. Neither is a compile error. Step 3 and the smoke phase are the entire mitigation.

Second risk: **scope drift into splitting the big files.** `HexMap` at 636 lines and `LLMGameAPI` at
564 will both look like they want breaking up while they are being moved. They may; that is a plan
with a behaviour budget, not a rider on a path move.

## Out of scope

Splitting any file, reducing any file's coupling, renaming any class, and changing what any file does.
The `scripts/model/` base-type convention is *named* here as open question 1 but is only settled, not
implemented, unless the answer is "these five move" — anything broader is its own unit.

## Sequencing

**After 0055.** That plan establishes the vocabulary this one extends — in particular whether the
property-named `scripts/stages/` exists — and it settles the applies/pure question for the 7
calculation files this plan wants to send to `calc/`. Doing them in the other order means inventing
the role vocabulary twice and moving some files twice.

0055 also ships `tools/validate_authority_call_placement.gd`, which enforces the "may this directory
call an authority?" table. **This plan extends that validator rather than inventing one** — each new
directory gets a row when it is created, in the same commit. A family moved without its row is the
failure this sequencing exists to prevent.

**Root needs an exact FILE allowlist, not a directory row.** Of the three autoloads left at root, only
`GameState.gd` and `GameData.gd` call authorities; `EventBus.gd` does not. A row saying "root may call
authorities" would license any future root file to do so — recreating the unpoliced root under a
nominally checked entry. Unknown top-level directories default to DENY; nested directories inherit the
nearest registered role.

**Before 0056.** Both plans key on paths, and 0056 seeds a path-keyed ceiling table. The rationale is
NOT `scripts/GameState.gd` — that file stays at root and its entry survives. It is the roughly
thirty-five files that DO move: any of them at or above 0056's threshold would be seeded under a path
this plan then invalidates, and `PARAM_CEILINGS` keys for their functions would go stale outright.
