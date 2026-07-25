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
2. Classify the change and its gate per `.claude/skills/hexcombat-change-control`.
3. Implement in the smallest verifiable steps; golden-touching work = one extraction/conversion
   per commit.
4. Verify yourself: `pwsh -File tools/run_all_tests.ps1` → **ALL PHASES GREEN** (verdict rules in
   `hexcombat-validation-and-qa`; flake handling in `hexcombat-debugging-playbook`).
5. **Consult before committing** (USER standing instruction 2026-07-25). Nothing is committed until
   `opencode` and `agy`/`gem-explore` have reviewed it — **review-only, they never implement.** This
   applies to plans *and* to the finished diff; a plan gets reviewed before code is written, the diff
   before it is committed. See "Consultation" below.
6. Record per `hexcombat-docs-and-writing` (STATUS / Decisions / RETROSPECTIVES / backlog
   check-off), then commit. **Push at milestones**, not every micro-commit.
7. Pause and surface to the user on: a genuine design decision, a gate you can't get green after
   a couple of focused attempts, or anything destructive/irreversible.

## Consultation (review-only, before every commit)

The USER is non-coding and cannot review the technical soundness of a plan or a diff themselves, so
two or three independent model reads substitute for that. They are cheap; a wrong plan or a silent
regression is not.

- **Run them in parallel, in the background** — each buffers its output until exit, so there is no
  interim progress to poll. Give each a brief that names the exact files to read and asks for
  numbered findings with severity (blocker/should-fix/nit), `file:line` evidence, and a concrete fix.
- **Every prompt must say REVIEW ONLY — do not modify files.** Only the primary agent writes code.
  This is load-bearing, not belt-and-braces: `--agent explore` is **not honoured by every opencode
  model** — `nemotron-3-ultra-free` prints *"agent 'explore' is a subagent, not a primary agent.
  Falling back to default agent"* and runs under the **writing** `build` agent (observed 2026-07-25).
  So the prompt text is the only thing stopping a reviewer from editing the repo. **Run
  `git status --short` after every consultation round** and treat any unexpected modification as the
  reviewer having gone out of bounds. `gem-explore` has also written a review artifact into the repo
  root despite the instruction (2026-07-25) — delete strays immediately, because a file written by
  one reviewer **contaminates the others**: a concurrently-running model read that artifact off disk
  and returned it verbatim as its own review, which looks like independent corroboration and is not.
  Treat identical findings from two models as one review until proven otherwise.
- **Evaluate, don't obey.** They are frequently wrong or already-handled; verify each finding against
  the code before acting, and say so plainly when one is rejected. Reviewers have caught real
  blockers here (an ordering bug that would have silently collapsed a mechanic) *and* asserted
  problems that did not exist.
- **Models:** `opencode run -m opencode/deepseek-v4-flash-free --agent explore` (fast, good at
  "which files did you miss"); `opencode run -m opencode/nemotron-3-ultra-free --agent explore`;
  `GEM_TIMEOUT=15m gem-explore "…"` (deepest reasoning about semantics and consequences — worth the
  wait). Bare `agy -p` has timed out on multi-file reviews; prefer the `gem-explore` wrapper with an
  extended `GEM_TIMEOUT`. The USER can also run a prompt through `agy` by hand if a review needs more
  room than the wrapper allows.

Commit messages end with the `Co-Authored-By` trailer + session link the harness specifies for
the acting model. Never commit `.mcp.json`.

## Auxiliary tools

- **agy** (Antigravity CLI): Use to run commands or tasks from the terminal. Use `agy -p "task"` to run a single prompt non-interactively and print the response (great for one-off tasks). Use `agy -i "task"` to start an interactive session with an initial prompt. You can also append `-c` to continue your most recent conversation.
- **opencode** (`Bash(opencode *)` is allowed): `opencode run -m opencode/deepseek-v4-flash-free
  "task"` (add `-s <session>` for continuity, `--agent explore` for read-only). Also available:
  `opencode/nemotron-3-ultra-free`. Small free models — suitable for broad file surveys, mechanical
  renames, log mining, and the review pass above; NOT for golden-touching, RNG-adjacent, or
  architectural work. Hand it a self-contained brief; review its diff for scope drift; re-run all
  verification yourself. `opencode models` lists what is available.
- **Godot MCP** (`mcp__godot__*`, config in `.mcp.json`): launch/run the project, read debug
  output — for visual/runtime verification that headless gates can't cover
  (`hexcombat-run-and-operate` has the screenshot path).
- **`pi` CLI is dead on this box** (ENOENT spawning the opencode shim) — call `opencode` directly.

## Known harness facts

- Two boxes. Windows 11: gates run under `pwsh -File tools/run_all_tests.ps1`, Godot at
  `C:\Godot_v4.7-stable_win64.exe`. Linux (Fedora, flatpak Godot 4.7 as `godot` on PATH): gates
  run under `bash tools/run_all_tests.sh`; the flatpak sandbox cannot read scripts outside the
  project dir (copy scratch `-s` scripts into the repo, run, delete). (`hexcombat-build-and-env`
  for environment recovery.)
- Long autonomous runs: prefer finishing a unit and committing over batching; the golden gate is
  cheap — run it often.
