---
name: hexcombat-docs-and-writing
description: The HexCombat documentation system — which doc of record holds what, the tracking rules agents must follow when finishing or planning work, and the entry templates (Decisions log, retrospective, system doc). Use whenever you finish a feature, make a design choice, plan work, or touch any doc.
---

# HexCombat docs & writing

The user does not code — the docs ARE the project's institutional memory, and agents are both the
writers and the readers. Optimize for a cold-start agent orienting in minutes.

## Docs of record (one job each)

| Doc | Holds | Tense/dates |
|---|---|---|
| `docs/STATUS.md` | What works today + where. **Single current-state source of truth** — if another doc disagrees, STATUS wins and you fix the other doc. | Present tense, **no dates** |
| `docs/plans/BACKLOG.md` | The forward plan (tracks, scope, done-when) | Future intent |
| `PLAN.md` → Decisions log | *Why* each choice was made, one dated entry per choice | **Append-only**, dated |
| `PLAN.md` → Open Questions | Blocked design questions for the user | Dated updates |
| `docs/RETROSPECTIVES.md` | Per-task lessons + triage of them | **Append-only**, dated |
| `docs/systems/*.md` | Per-system reference: data flow, key funcs, files, fidelity notes | Present tense |
| `AGENTS.md` / `CLAUDE.md` | Rules for all agents / Claude-harness specifics | Reference |
| `.claude/skills/` | Procedures: how to act (this library) | Reference |
| `ROADMAP.md`, `docs/plans/*_audit.md` | Historical milestone map + audit records | Historical reference |

## Tracking rules (follow exactly)

**When you finish a feature/change:**
1. Update `docs/STATUS.md` — present tense, no date, describe the behavior not the history.
2. Check the item off in `docs/plans/BACKLOG.md` (or the active campaign/handoff doc).
3. Append the *why* (design choices, judgment calls, rejected alternatives) to `PLAN.md` →
   Decisions — one dated entry.
4. If lessons emerged, append to `docs/RETROSPECTIVES.md` with your triage (act now / record /
   reject, and why).
5. If a subsystem's behavior changed, update its `docs/systems/*.md`.

**When you plan new work:** it goes in `docs/plans/` — never into STATUS.md.

**Never** date implemented-state text; dates live only in the two append-only logs.
**Never** rewrite or delete Decisions/RETROSPECTIVES entries — append corrections.

## Templates

**Decisions entry** (PLAN.md → Decisions log, newest first):
```markdown
- **YYYY-MM-DD — <Title> (<scope/authority: USER call | max-autonomy | via opencode>).**
  <What was decided/built and where.> **Judgment calls:** (1) <choice + why>; (2) ….
  <Verification: gate state, golden state.> <Cross-refs: commits, docs, skills.>
```

**Retrospective entry** (docs/RETROSPECTIVES.md):
```markdown
## YYYY-MM-DD <task-slug>
- **Lesson:** <what would be done differently>
- **Triage:** acted now on <x>; recorded <y> for later; rejected <z> because <why>.
```

**System doc** (docs/systems/<system>.md): purpose → data flow (inputs/outputs per turn) → key
functions with file:line → data files → fidelity/divergence notes → open questions.

## House style

- Written for agents: concrete file paths, function names, pinned values, exact commands. No
  marketing prose.
- State authority explicitly: *USER call* vs agent judgment — future agents must know what they
  may relitigate (agent judgment) vs must not (user calls).
- Skills hold *procedures*; docs hold *facts*. Don't duplicate a fact into a skill when a pointer
  will do — duplicated facts drift.
- HTML mirrors of system docs (`docs/systems/html/`) are for the human; regenerate them when the
  `.md` changes materially, or note that they lag.
