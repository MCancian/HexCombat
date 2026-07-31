---
title: "0055: Empty scripts/resolvers/ — the directory's claim is no longer true of anything in it"
status: "Sketch"
created: "2026-07-31"
---

# Plan 0055: Empty `scripts/resolvers/`

## The finding

`docs/STATUS.md` → "Where a file goes" gives each directory a claim and a test. `scripts/resolvers/`
claims *"the per-phase resolver — decides what happens in that phase"*, and its test is **"is it the
phase's own logic, and does it still write campaign state?"** The second half is what separates it
from `scripts/calc/`.

**Measured 2026-07-31, during plan 0050's closeout audit: no file in the directory passes it.**

| File | Writes campaign state? |
|---|---|
| `FrontlineResolver.gd` | no |
| `IjfsResolver.gd` | no |
| `InfrastructureResolver.gd` | no |
| `OffloadResolver.gd` | no |
| `CleanupResolver.gd` | no — its only field writes are onto a freshly built `CleanupSummary` (`:90-91`) |
| `CombatResolver.gd` | no — likewise onto a fresh `CombatSummary` (`:91`); its own header says *"It applies NOTHING"* |

Method: the alias-taint scan from 0050's source sweep, run over `scripts/resolvers/` — every write
whose receiver is a protected field name, a function parameter, or a local aliased from live state.
The only two hits are protected NAMES (`game_over`, `winner`, `hex_id`) on unprotected receivers.

How it got here: the mutation-authority campaign moved application out of the resolvers one aggregate
at a time. Nobody re-asked what the directory was claiming after the last one left, because **a
directory claim goes stale without anyone editing the files in it** — the same way
`AntishipResolver`'s did, which is what led to this measurement.

## Proposal

Move all six to `scripts/calc/` and delete `scripts/resolvers/`. `scripts/calc/` would then hold every
write-free calculator, and the role-directory table loses a row that distinguishes nothing.

This is a **path-only change**. A GDScript `class_name` is path-independent, so no call site moves.
The cost is the paths, their `.uid` sidecars, and doc references.

## Why it was NOT folded into 0050

Discovered *after* 0050's diff-review round, from a reviewer finding about the wording I had just
written. Folding a fifteen-file addition into a reviewed thirty-five-file diff would have shipped the
addition unreviewed, which is precisely what that plan's own "campaign fatigue" stop condition
forbids. 0050 corrected the false claim and pointed here.

## Steps

1. Re-run the measurement above and confirm it still holds. **If any file has since acquired a write,
   stop** — that file is correctly placed and this plan is wrong.
2. `git mv` each file and its `.uid` together, one commit for the six.
3. Sweep for path-keyed references — the failure mode 0050 hit was `tools/validate_gd_metrics.py`
   hard-coding `"scripts/resolvers/AntishipResolver.gd::resolve"`, which no call-site grep would find.
   Check `tools/*.py`, `tools/*.gd`, `project.godot`, `.import`, every `docs/systems/*.md`, and
   `.claude/skills/`.
4. Delete the `scripts/resolvers/` row from `docs/STATUS.md`'s table and rewrite the two worked
   examples below it — with the directory gone, the `resolvers/` vs `calc/` boundary they explain no
   longer exists, and what should survive is the LESSON (a directory claim can be invalidated by a
   deletion somewhere else).
5. `bash tools/run_all_tests.sh` → ALL PHASES GREEN. A path-only move must not touch a pin.

## Risk

Low, and the one real risk is step 3: a path-keyed reference that no compiler and no call-site grep
will catch, which fails only when that specific validator runs. The gate does run it, so a missed one
is caught — but it is caught as a confusing `KeyError`, so sweep first.

## Out of scope

Renaming any class, changing any signature, or re-litigating which module owns which phase. This is
the directory, and nothing else.
