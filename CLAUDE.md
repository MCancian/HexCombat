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
6. **Consult before committing** (USER standing instruction 2026-07-25). Nothing is committed until
   **two substantive independent reads** have landed — **review-only, they never implement.** This
   applies to plans *and* to the finished diff; a plan gets reviewed before code is written, the diff
   before it is committed. A reviewer that returned no findings because it FLAKED does not count as
   one of the two. See "Consultation" below.
7. Record per `hexcombat-docs-and-writing` (STATUS / Decisions / RETROSPECTIVES / backlog
   check-off), then commit. **Push at milestones**, not every micro-commit.
8. Pause and surface to the user on: a genuine design decision, a gate you can't get green after
   a couple of focused attempts, or anything destructive/irreversible.

## Consultation (review-only, twice per unit of work)

The USER is non-coding and cannot review the technical soundness of a plan or a diff themselves, so
independent model reads substitute for that. They are cheap; a wrong plan or a silent regression is
not. **Two rounds are required:**

- **Before implementation** — the plan → `.claude/skills/hexcombat-plan-review`
- **Before committing** — the finished diff, gate already green → `.claude/skills/hexcombat-diff-review`

Those skills own the brief format, the measured model-reliability table, flake detection, the
reviewer-safety rules, and how to evaluate findings rather than obey them. **Read the relevant one
before each round** rather than improvising a prompt — an unguided reviewer reads the wrong five
files and returns a summary of your own work.

**Who to invoke, and how, lives in `.claude/REVIEWERS.md`** — the roster, the exact commands, the
read-only flags, and the measured reliability per model. It is the single home for those facts; do not
copy them into a plan or a brief.

Five things are worth knowing before you get there, because they change what you run:

- **Probe reviewer availability BEFORE you implement, not when you are ready to commit.** On
  2026-07-29 `agy` was quota-blocked for an entire session and its reset counter moved the wrong way,
  so an estimate made at the start was worthless by the end. A 30-second probe changes the order you
  do the work in. If every reviewer is down: keep implementing, and **hold the finished work
  UNCOMMITTED as the waiting state** — that is the sanctioned holding pattern. "Reviewers were
  unavailable" must never become "committed unreviewed"; surface the situation to the USER instead,
  who can spin up reviewers you cannot reach.
- **Hand reviewers a FROZEN artifact — a commit SHA or a `git diff > file` snapshot — never the
  working tree.** Measured 2026-07-29: two of three reviewers read the tree while it was being edited;
  one returned an eight-item failure report describing a state that never shipped, and disproving it
  cost a full round. This is the read-only twin of the rule that `agy-verify` sees committed state
  only, and it is worse, because a mid-edit finding looks exactly like a real one.
- **`agy-explore` is the reviewer of record.** Measured 4/4 substantive over the 0043/0051 session
  against 1/3 and 0/3 for the two free opencode models. The others are useful for bounded mechanical
  enumeration ("list every read/write of these fields") — see the roster for which.
- **A flake is not a pass.** Both failure shapes return *something* — under 1 KB (died early) or
  over 10 KB (dumped tool output). No numbered findings means nobody reviewed it. Re-run.
- **Spend the spare agy budget on different ROLES, not repeats:** fact-check the premises /
  consequences / "what will a weaker implementer get wrong" / oracle check against TIV
  (`agy-explore -d ~/Projects/TaiwanInvasionViewer`) / method check (`agy-verify`). Repeats of one
  brief are correlated noise. The oracle and weaker-implementer roles each produced a blocker that
  nothing else caught.

The two rules worth knowing before you get there: **every prompt must say REVIEW ONLY** (`--agent
explore` is not honoured by every opencode model — they fall back to the *writing* `build` agent), and
**run `git status --short` after every round**, because a stray file written by one reviewer
contaminates the others and produces fake corroboration.

Commit messages end with the `Co-Authored-By` trailer + session link the harness specifies for
the acting model. Never commit `.mcp.json`.

## Auxiliary tools

- **agy** (Antigravity CLI) — the primary delegation path, and the USER has spare capacity on it, so
  prefer it over doing token-heavy reading yourself. Two wrappers (full contract in `~/.claude/AGY.md`):
  - `agy-explore "task"` — READ-ONLY. Exploration sweeps, large-file summaries, plan/diff review.
    `-d <dir>` adds a workspace dir, which is how the TIV oracle gets read. `AGY_TIMEOUT=15m` for
    reviews (default 5m). *(Renamed from `gem-explore` 2026-07-27; `gem` was the old CLI name.)*
  - `agy-verify "task"` — MAY RUN COMMANDS, sandboxed to a throwaway git worktree of HEAD that is
    deleted on exit. For "reproduce my measurement; is the method sound?" — the only pass that
    catches methodology errors, which reading cannot. **Sees committed state only.**
  - Raw `agy -p` / `agy -i` / `-c` still available, but bare `agy -p` has timed out on multi-file
    reviews; prefer the wrappers.
- **Weaker models (`pi`, `opencode`)** — roster and invocations in `.claude/REVIEWERS.md`. What to
  give them is decided by the SHAPE of the task, not its subject. Measured over three delegations on
  2026-07-29:
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
  multi-model front end for the reviewer roster: `pi -p --no-session --model <id> "PROMPT"`, plus
  `--tools read,grep,find,ls` to make a review read-only. Commands per model in `.claude/REVIEWERS.md`.

## Known harness facts

- Two boxes. Windows 11: gates run under `pwsh -File tools/run_all_tests.ps1`, Godot at
  `C:\Godot_v4.7-stable_win64.exe`. Linux (Fedora, flatpak Godot 4.7 as `godot` on PATH): gates
  run under `bash tools/run_all_tests.sh`; the flatpak sandbox cannot read scripts outside the
  project dir (copy scratch `-s` scripts into the repo, run, delete). (`hexcombat-build-and-env`
  for environment recovery.)
- Long autonomous runs: prefer finishing a unit and committing over batching; the golden gate is
  cheap — run it often.
