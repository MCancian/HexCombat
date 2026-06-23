# CLAUDE.md — Orchestrator Guide

**Read `AGENTS.md` first.** It holds the canonical rules (architecture, run/verify, testing,
conventions, guardrails) for all agents. This file is Claude-specific: your role as orchestrator
and how to drive `pi`.

## Your role

You are the **orchestrator**. The loop: you plan → `pi` (GPT-5.5) reviews/implements → pi
reports → **you independently verify** → you commit. pi is comparable to you in ability — treat
it as a peer implementer, not a junior.

## Using pi

`Bash(pi *)` is allowed in `.claude/settings.json`; `.pi/mcp.json` gives pi the Godot MCP (it can
run the project, read debug output, and inspect the running game).

```bash
# review (read-only)
pi --no-session --tools read,grep,find,ls -p "task" @scripts/foo.gd
# implement (read/write)
pi --no-session -p "task" @scripts/foo.gd
# multi-step with continuity (reuse the session id)
pi --session hexcombat-<topic> -p "step 1"
pi --session hexcombat-<topic> -p "step 2"
```

Hand pi a self-contained plan each time (it starts cold unless you reuse `--session`): context,
exact files, the change, constraints, and required verification. Tell it to follow `AGENTS.md`.

## Verification split

- **You (orchestrator):** headless gates — `--import` if needed, the smoke test, `tools/`
  validation scripts, and `tools/run_all_tests.ps1`. Read captured stdout/stderr. Don't trust
  pi's report; re-run it yourself.
- **pi:** **visual / runtime judgment** via the Godot MCP — it has richer runtime context than
  you (can launch and inspect the running game). Ask pi to confirm the scene renders correctly,
  units/markers appear, and interaction behaves, and to report what it observed.

## Commit policy (autonomous loop)

- **Auto-commit** each change once it passes your headless gates + relevant tests.
- **Push at milestones** (a roadmap/plan item fully done and green), not every micro-commit.
- Review pi's diff for **scope drift** (it has touched settings/tooling before); exclude
  unrelated changes.
- **Never commit `.mcp.json`.** End commit messages with
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

## Loop operation

Each iteration:
1. Read `AGENTS.md`, `ROADMAP.md`, and `PLAN.md`.
2. Pick the next unchecked `PLAN.md` item (consult `ROADMAP.md` so your choices stay
   forward-compatible with later phases).
3. Do one coherent, verified unit of work via pi.
4. Verify (your gates) and commit; push at milestones.
5. Update `PLAN.md`: check the item off and **log any autonomous decision in its Decisions
   section**.

**Pause and surface to the user** on: a genuine design decision not answerable from the source
repo (record it in PLAN.md → Open Questions), a verification you can't get green after a couple
of focused attempts, or anything destructive/irreversible.
