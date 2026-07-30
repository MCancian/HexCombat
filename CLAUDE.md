# CLAUDE.md — Primary Agent Guide

**Read `AGENTS.md` first** — canonical rules (mission, architecture, run/verify, testing,
conventions, guardrails) for all agents. Then use the skill library: task→skill map in
`.claude/skills/README.md`. This file is Claude-harness-specific: your role, the work loop, and
the auxiliary tools.

## Your role

You are the **primary agent**: you plan, **implement directly**, verify, and commit.
(User call 2026-07-02: the old plan→opencode-implements→verify loop is retired — the frontier
model writes the code. `opencode` remains available for cheap mechanical or read-only exploratory
chores; verify anything it reports independently.)

The user is a solo, non-coding wargame designer. Design intent comes from them; everything
technical is yours. When a technical fork arises, **choose the option that is harder up front but
yields the cleanest, most legible code** (standing user instruction). Genuine design questions go
to the user (open a `Sketch` plan in `docs/plans/` — index in its README — or ask directly); do
not guess game design.

## The work loop (each coherent unit)

1. Orient: `docs/STATUS.md` (what works) → `docs/plans/BACKLOG.md` (what's next) → the relevant
   skill(s) for the task type.
2. **Preflight the plan against the tree, and rewrite it before anyone reviews it.** A `Sketch` is a
   proposal, not a spec, and its premises rot: plan 0045's sketch described a split that plan 0044 had
   already half-removed. Measure first — the artifact that made that implementation safe was a
   file:line inventory of every writer the plan claimed existed, several of which did not. This step
   is not optional busywork: reviewers review the PLAN, so a Sketch sent to review comes back
   confirmed rather than corrected.
3. Classify the change and its gate per `.claude/skills/hexcombat-change-control`.
4. Implement in the smallest verifiable steps; golden-touching work = one extraction/conversion
   per commit.
5. Verify yourself: `pwsh -File tools/run_all_tests.ps1` → **ALL PHASES GREEN** (verdict rules in
   `hexcombat-validation-and-qa`; flake handling in `hexcombat-debugging-playbook`).
6. **Consult before committing** (USER standing instruction 2026-07-25; quorum set 2026-07-30).
   Implementing a numbered plan? The diff is not committed until **two of the three quorum reviewers
   return substantive findings** — **review-only, they never implement.** A reviewer that returned no
   findings because it FLAKED is not one of the two. See "Consultation" below.
7. Record per `hexcombat-docs-and-writing` (STATUS / Decisions / RETROSPECTIVES / backlog
   check-off), then commit. **Push at milestones**, not every micro-commit.
8. Pause and surface to the user on: a genuine design decision, a gate you can't get green after
   a couple of focused attempts, or anything destructive/irreversible.

## Consultation (review-only; reviewers never implement)

The USER is non-coding and cannot review the technical soundness of a plan or a diff themselves, so
independent model reads substitute for that. Two rounds happen per unit of work:

- **Before implementation** — the plan → `.claude/skills/hexcombat-plan-review`. At least one
  substantive read.
- **Before committing** — the finished diff, gate already green → `.claude/skills/hexcombat-diff-review`.
  For a numbered plan's implementation this is **quorum-bound: 2 of 3**.

**Everything about WHO and HOW lives in `.claude/REVIEWERS.md`** — the round, the tiers, the exact
invocations, read-only flags, measured route reliability, brief invariants, flake triage, safety, roles.
It is the single home for those facts. `tools/validate_reviewer_facts.gd` gates the mechanical half —
a copied **invocation or model id** fails the gate anywhere but the roster; duplicated *prose* is
convention, not enforced. Run a round with **`tools/review_fanout.sh`** rather than
hand-assembling commands.

Three things change what you *do*, so they are here and not only there:

- **Probe reviewer availability BEFORE you implement, not at commit time.** A quota-block discovered at
  the end strands finished work; discovered at the start it reshapes the order you work in.
- **Never hand over a live working tree** — use `tools/review_fanout.sh --freeze`, which snapshots the
  tree itself and refuses to launch otherwise. Do not hand-build the snapshot: `git diff > file` in this
  session is rewritten by a shell hook into a compacted summary, which voided a round on 2026-07-30.
- **If quorum cannot be reached, hold the work UNCOMMITTED** and surface it to the USER, who can spin up
  reviewers you cannot reach. "Reviewers were unavailable" must never become "committed unreviewed".

Commit messages end with the `Co-Authored-By` trailer + session link the harness specifies for
the acting model. Never commit `.mcp.json`.

## Auxiliary tools

- **agy** (Antigravity CLI) — the primary delegation path for token-heavy reading, and the USER has
  spare capacity on it, so prefer it over reading everything yourself. One wrapper reads, one may run
  commands in a throwaway worktree; which is which, what each can see, and how to invoke them are in
  `~/.claude/AGY.md` (CLI contract) and `.claude/REVIEWERS.md` (review use).
- **Weaker models** — tiers, routes and invocations in `.claude/REVIEWERS.md`. What to give them is
  decided by the SHAPE of the task, not its subject. Measured over three delegations on 2026-07-29:
  - **Reliable — mechanical transformation with a mechanical check.** A 16-reference path sweep came
    back 16/16 correct, every diff path-only, and it escalated its one ambiguous case instead of
    guessing. Give these work freely.
  - **Unreliable — anything needing a past/present distinction.** One agent read a retrospective's
    triage line ("→ act later, logged to BACKLOG") as a live claim about current code, and
    "rediscovered" a rejection printed on the next line. Never delegate a judgement about history.
  - **Dangerous — evidence citation.** At least four fabricated citations in one report, including
    `dice.substream(...)` as proof (no such method exists here) and a nonexistent file path, in
    support of conclusions that happened to be true. Every citation needs checking.
  So: hand over a self-contained brief, demand verbatim quotes and "ABSENT" for zero hits, keep the
  brief's verification command scoped to exactly the files it may edit, review the diff for scope
  drift, and re-run all verification yourself. Budget honestly — on enumeration tasks delegation buys
  parallelism, not net time: verifying the sweep costs about what doing it would have.
- **Godot MCP** (`mcp__godot__*`, config in `.mcp.json`): launch/run the project, read debug
  output — for visual/runtime verification that headless gates can't cover
  (`hexcombat-run-and-operate` has the screenshot path).
- **`pi` CLI works** (v0.82.1 via linuxbrew, verified 2026-07-29 — an earlier note here claimed it was
  dead on this box from an ENOENT spawning the opencode shim; that is no longer true). It is the
  multi-model front end for the reviewer roster; the per-model commands and read-only flags are in
  `.claude/REVIEWERS.md`.

## Known harness facts

- Two boxes. Windows 11: gates run under `pwsh -File tools/run_all_tests.ps1`, Godot at
  `C:\Godot_v4.7-stable_win64.exe`. Linux (Fedora, flatpak Godot 4.7 as `godot` on PATH): gates
  run under `bash tools/run_all_tests.sh`; the flatpak sandbox cannot read scripts outside the
  project dir (copy scratch `-s` scripts into the repo, run, delete). (`hexcombat-build-and-env`
  for environment recovery.)
- Long autonomous runs: prefer finishing a unit and committing over batching; the golden gate is
  cheap — run it often.
