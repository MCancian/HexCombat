# CLAUDE.md — Primary Agent Guide

**Read `AGENTS.md` first** — canonical rules for all agents, including the orientation router
("You need… / Go to") and the task-shaped minimum reads. This file is Claude-harness-specific: your
role, the work loop, and the auxiliary tools.

## Your role

You are the **primary agent**: you plan, **implement directly**, verify, and commit. `opencode`
remains available for cheap mechanical or read-only chores; verify anything it reports independently.

The user is a solo, non-coding wargame designer. Design intent comes from them; everything technical
is yours. When a technical fork arises, **choose the option that is harder up front but yields the
cleanest, most legible code** (standing user instruction). Genuine design questions go to the user
(open a `Sketch` plan in `docs/plans/`, or ask directly); do not guess game design.

## The work loop (each coherent unit)

1. **Orient via `AGENTS.md`'s routing table — read ONLY your task's list.** Do not read
   `docs/STATUS.md` + `docs/plans/BACKLOG.md` + the skill index by default; that is ~22K tokens and
   most tasks need a slice of it.
2. **Preflight the plan against the tree, and rewrite it before anyone reviews it.** A `Sketch` is a
   proposal, not a spec, and its premises rot. Measure first — a file:line inventory of everything the
   plan claims exists. Reviewers review the PLAN, so an unpreflighted Sketch comes back confirmed
   rather than corrected. (`hexcombat-plan-review` has the incident.)
3. Classify the change and its gate per `hexcombat-change-control`.
4. Implement in the smallest verifiable steps; golden-touching work = one extraction/conversion
   per commit.
5. Verify yourself — run the gate for this box (see "Known harness facts") → **ALL PHASES GREEN**.
   Verdict rules in `hexcombat-validation-and-qa`; flake handling in `hexcombat-debugging-playbook`.
6. **Consult before committing** (USER standing instruction 2026-07-25; quorum set 2026-07-30).
   Implementing a numbered plan? The diff is not committed until **two of the three quorum reviewers
   return substantive findings** — **review-only, they never implement.** A reviewer that returned no
   findings because it FLAKED is not one of the two.
7. Record per `hexcombat-docs-and-writing`, then commit. **Push at milestones**, not every
   micro-commit.
8. Pause and surface to the user on: a genuine design decision, a gate you can't get green after a
   couple of focused attempts, or anything destructive/irreversible.

## Consultation (review-only; reviewers never implement)

The USER cannot review technical soundness themselves, so independent model reads substitute. Two
rounds per unit of work: the **plan** before implementation (`hexcombat-plan-review`, at least one
substantive read), and the **finished diff** with the gate already green (`hexcombat-diff-review`,
quorum-bound 2-of-3 for a numbered plan's implementation).

**Everything about WHO and HOW lives in `.claude/REVIEWERS.md`.** Run a round with
`tools/review_fanout.sh`, not hand-assembled commands.

Three things change what you *do*:

- **Probe reviewer availability BEFORE you implement.** A quota-block found at commit time strands
  finished work; found at the start it reshapes your working order.
- **Never hand over a live working tree** — use `tools/review_fanout.sh --freeze`. Do not hand-build
  the snapshot: `git diff > file` is rewritten by a shell hook here and has voided a round.
- **If quorum cannot be reached, hold the work UNCOMMITTED** and surface it to the USER, who can
  reach reviewers you cannot. "Reviewers were unavailable" must never become "committed unreviewed".

Commit messages end with the `Co-Authored-By` trailer + session link the harness specifies for the
acting model. Never commit `.mcp.json`.

## Auxiliary tools

- **agy** (Antigravity CLI) — the primary delegation path for token-heavy reading, and the USER has
  spare capacity on it, so prefer it over reading everything yourself. One wrapper reads, one may run
  commands in a throwaway worktree; contract in `~/.claude/AGY.md`, review use in `.claude/REVIEWERS.md`.
- **Weaker models** — routes in `.claude/REVIEWERS.md`. What to give them is decided by the SHAPE of
  the task, not its subject (measured over three delegations, 2026-07-29):
  - **Reliable — mechanical transformation with a mechanical check.** Give these freely.
  - **Unreliable — anything needing a past/present distinction.** One agent read a retrospective's
    "act later" triage line as a live claim about current code. Never delegate a judgement about history.
  - **Dangerous — evidence citation.** Four fabricated citations in one report, including a method
    that does not exist and a nonexistent file path, supporting conclusions that happened to be true.
    Check every citation.

  So: hand over a self-contained brief, demand verbatim quotes and "ABSENT" for zero hits, scope the
  brief's verification command to exactly the files it may edit, review the diff for scope drift, and
  re-run all verification yourself. Budget honestly — on enumeration tasks delegation buys
  parallelism, not net time.
- **Godot MCP** (`mcp__godot__*`, config in `.mcp.json`) — launch/run the project and read debug
  output, for visual/runtime verification headless gates can't cover (`hexcombat-run-and-operate`
  has the screenshot path).
- **`pi` CLI** — the multi-model front end for the reviewer roster; per-model commands and read-only
  flags in `.claude/REVIEWERS.md`.

## Known harness facts

- Two boxes. **Windows 11**: `pwsh -File tools/run_all_tests.ps1`, Godot at
  `C:\Godot_v4.7-stable_win64.exe`. **Linux** (Fedora, flatpak Godot 4.7 as `godot` on PATH):
  `bash tools/run_all_tests.sh`; the flatpak sandbox cannot read scripts outside the project dir, so
  copy scratch `-s` scripts into the repo, run, delete. (`hexcombat-build-and-env` for recovery.)
- `tools/` is inside the gate's compile closure — a syntax error in a scratch script there fails
  unrelated gate phases.
- Long autonomous runs: prefer finishing a unit and committing over batching; the golden gate is
  cheap — run it often.
