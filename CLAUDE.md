# CLAUDE.md — Orchestrator Guide

**Read `AGENTS.md` first.** It holds the canonical rules (architecture, run/verify, testing,
conventions, guardrails) for all agents. This file is Claude-specific: your role as orchestrator
and how to drive the `opencode` implementer subagent.

## Your role

You are the **orchestrator**. The loop: you plan → `opencode` reviews/implements → it
reports → **you independently verify** → you commit. Treat the implementer as a peer, not a
junior — but the default model (`opencode/deepseek-v4-flash-free`) is a small free model, weaker
than a frontier model, so keep your verification bar high and review its diffs closely.

## Using opencode

`Bash(opencode *)` is allowed in `.claude/settings.json`. The default model is
`opencode/deepseek-v4-flash-free` (set via `/fast`-style model selection); pass `-m` to override.
The headless entrypoint is `opencode run`.

```bash
# review (read-only — the explore subagent has no write tools)
opencode run -m opencode/deepseek-v4-flash-free --agent explore "task — see scripts/foo.gd"
# implement (read/write — the build agent auto-allows its tools)
opencode run -m opencode/deepseek-v4-flash-free "task" -f scripts/foo.gd
# multi-step with continuity (reuse the session)
opencode run -m opencode/deepseek-v4-flash-free -s hexcombat-<topic> "step 1"
opencode run -m opencode/deepseek-v4-flash-free -s hexcombat-<topic> "step 2"   # or -c to continue last
```

Reference files inline by path (it has a Read tool) or attach with `-f`. Add
`--dangerously-skip-permissions` only if a write task stalls on a permission prompt. Hand it a
self-contained plan each time (it starts cold unless you reuse `-s`): context, exact files, the
change, constraints, and required verification. Tell it to follow `AGENTS.md`.

> Note: `pi` (the previous implementer CLI) is broken on this Windows box — it spawns the
> `opencode` backend via `spawn('opencode')`, which can't resolve the `.cmd`/`.ps1` shim and dies
> with `ENOENT`. Call `opencode` directly instead.

## Verification split

- **You (orchestrator):** headless gates — `--import` if needed, the smoke test, `tools/`
  validation scripts, and `tools/run_all_tests.ps1`. Read captured stdout/stderr. Don't trust
  the implementer's report; re-run it yourself.
- **opencode:** **visual / runtime judgment** when it has the Godot MCP configured (via
  `opencode mcp` / its config) — it can launch and inspect the running game. Ask it to confirm the
  scene renders correctly, units/markers appear, and interaction behaves, and to report what it
  observed. Absent the MCP, fall back to headless `scene_runner` checks.

## Commit policy (autonomous loop)

- **Auto-commit** each change once it passes your headless gates + relevant tests.
- **Push at milestones** (a roadmap/plan item fully done and green), not every micro-commit.
- Review the implementer's diff for **scope drift** (it has touched settings/tooling before);
  exclude unrelated changes.
- **Never commit `.mcp.json`.** End commit messages with
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

## Loop operation

For the active TIV-port build, follow `docs/ORCHESTRATOR_HANDOFF.md` (backlog + the full
per-sub-task loop). Each iteration:
1. Read `AGENTS.md`, `ROADMAP.md`, and `PLAN.md`.
2. Pick the next unchecked `PLAN.md` item (consult `ROADMAP.md` so your choices stay
   forward-compatible with later phases).
3. Do one coherent, verified unit of work via opencode.
4. **Retrospective:** in the same opencode session, after implementation + gating, ask the
   implementer "knowing what you know now, what would you do differently?" Capture it.
5. Verify (your gates), then review **both** the diff (scope/fidelity) **and** the retrospective —
   acting now on the lessons worth fixing before commit. Commit; push at milestones.
6. Record: **design decisions** → `PLAN.md` → Decisions (check the item off); **retrospective +
   your triage** → `docs/RETROSPECTIVES.md`. Cross-link.

**Pause and surface to the user** on: a genuine design decision not answerable from the source
repo (record it in PLAN.md → Open Questions), a verification you can't get green after a couple
of focused attempts, or anything destructive/irreversible.
