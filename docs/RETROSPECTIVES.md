# Retrospectives — implementer lessons learned

Per-sub-task "what would you do differently, knowing what you know now" notes.
Per-module retros live in `docs/systems/<module>/RETRO.md`. This file documents the entry format
and the inbox/archive workflow. Once triage actions are implemented or backlogged, **move the
entry to `docs/archive/RETROSPECTIVES_history.md`**.

## Entry format

```
## <date> — <sub-task id>: <title>   (implementer: <model> | direct)

**What would you do differently (implementer):**
- <specific, concrete lesson — fragility, tech debt, surprise, what'd make the next task easier>

**Orchestrator triage:**
- <lesson> → act now | act later (→ docs/plans/ plan or backlog) | record only — <note>
```

## Module retro files

| Module | File |
|---|---|
| Anti-ship & mines | `docs/systems/antiship-mine/RETRO.md` |
| Ground combat | `docs/systems/ground-combat/RETRO.md` |
| Turn engine | `docs/systems/turn-engine/RETRO.md` |
| Amphibious offload | `docs/systems/amphibious-offload/RETRO.md` |
| Research harness | `docs/systems/research-harness/RETRO.md` |
