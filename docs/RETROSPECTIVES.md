# Retrospectives — implementer lessons learned

Per-sub-task "what would you do differently, knowing what you know now" notes.
This file serves as an **inbox**. Agents append their lessons here, perform triage, and once the actions are implemented or backlogged, they **move the entry to `docs/archive/RETROSPECTIVES_history.md`**.

## Entry format

```
## <date> — <sub-task id>: <title>   (implementer: <model> | direct)

**What would you do differently (implementer):**
- <specific, concrete lesson — fragility, tech debt, surprise, what'd make the next task easier>

**Orchestrator triage:**
- <lesson> → act now | act later (→ docs/plans/ plan or backlog) | record only — <note>
```

---

## 2026-07-16 — plan 0009: quality baseline + remediation   (implementer: direct)

**What would you do differently (implementer):**
- Delegate sweeps must be source-verified before acting: gem-explore invented a 230-line
  `LLMGameAPI._build_observation` that does not exist (the file is ~20 small builders), and the
  first analyzer pass miscounted UnitStats const-table values as magic numbers. Numbers from
  the parser beat prose from a delegate; every claim that drives a change gets a grep first.
- `tests/combat_resolution_test.gd` is order-dependent: it fails standalone on a fresh autoload
  state (with or without any of this session's changes) but passes inside the full gate. Cost
  half an hour of false-alarm bisecting mid-refactor.
- No line-coverage tooling exists for headless GDScript; coverage claims stay file-level.

**Orchestrator triage:**
- Delegate-verification rule → **act now** (written into `hexcombat-code-quality` and the plan
  0009 record; also the report's method section).
- Order-dependent combat_resolution_test → **act later** (logged in BACKLOG Track F).
- Coverage tooling gap → **record only** (report states file-level basis explicitly).

## 2026-07-15 — plan 0006 C8: research verification + closeout   (implementer: direct)

**What would you do differently (implementer):**
- The C8 research runs caught a total sealift livelock (heavy BNs unlandable in one day; see
  `hexcombat-failure-archaeology` → "Sealift livelock") that C1–C7's 53-suite gate and the
  10-turn smoke could not see. Long-horizon ordered runs should have been part of the C6/C7
  verification, not deferred to a final step — the bug shipped in 3 pushed commits before C8 ran.
- When a per-item cost is drawn from a per-turn budget, check max(cost) > min(budget) at design
  time; the TIV oracle's fractional queue existed precisely because of this case.

**Orchestrator triage:**
- Long-horizon research run at feature-verification time → **act now** (done this session: smoke
  extended to 12 turns + landings-past-turn-10 assertion; carry-over fix + 4 tests committed).
- Budget/cost mismatch design check → **record only** — captured as the archaeology lesson.
