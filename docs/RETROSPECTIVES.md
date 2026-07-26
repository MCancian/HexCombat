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

## 2026-07-25 — plan 0038: TurnConductor phase extraction   (implementer: direct)

**What would you do differently (implementer):**
- **Plan the module split around the SHARED MUTATION SEAMS, not just the resolver fan-out.** The
  plan's per-step dep arithmetic was right, but it did not ask which functions BOTH sides of a split
  call. `apply_casualty` is called by ground combat and by air insertion; the moment air insertion
  left, the two files would have referenced each other. That forced `RosterMutations` into step 1's
  commit — a change the plan had explicitly filed as separate and optional. Cheap fix next time: for
  each candidate module, grep the callees the *remainder* still uses, before writing the step list.
- **A per-commit ceiling rule can make a two-part change unsplittable.** `RosterMutations` alone
  takes `TurnConductor` to 39 of 38 — it only comes in under the ceiling combined with the extraction
  it enables. Worth checking whether a prerequisite is red on its own before promising one change per
  commit.
- **`tools/validate_doc_anchors.gd` earned its keep three times** — it caught a dead
  `TurnConductor.consume_jlsf_orders`, `register_ship_losses` and `active_red_battalion_units`
  anchor at each step, and the plan-file link the archive move broke. Move code, then run the gate
  before writing any prose: it tells you which docs to fix.
- **Reviewer numbers still need re-measuring.** On the same file, one reviewer said 80 lines and the
  other 82; it is 81. Both were confident.

**Orchestrator triage:**
- Shared-seam check before planning a split → **act now** (recorded here and in the plan closeout's
  deviation note; the DECISIONS entries state it as the reason the plan deviated).
- Front-line phase still in `TurnConductor` (raised by both diff reviewers) → **act later**
  (`docs/plans/BACKLOG.md`).
- `docs/systems/turn-engine.md` was ~8 months stale (pre-plan-0014 architecture, a 3-phase pipeline
  that had 16 steps) → **acted now**: §1/§2/§4 rewritten against the code as part of this work.

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

## 2026-07-18 — plan 0012: unified sweep extraction on the batch backend   (implementer: direct)

**What would you do differently (implementer):**
- The plan's premise ("the CRBM cell runner completely skips ground combat") was wrong — its
  empty-orders full turns still produced beach combat from offload landings. One 40-turn parity
  game caught it (43 vs 40 killed) before any spec shipped on `disable_phases`. Lesson: run the
  cheapest end-to-end parity probe BEFORE building on a plan's characterization of legacy
  behavior; the plan is a design, not evidence.
- Regenerating the LLM fixtures for `wave_bns` exposed that the gate's fixture-drift check had
  been vacuous since f37170f (missing `--` separator; exporters wrote to `reports/`). A guard
  that has never been seen failing should be distrusted — deliberately break a new guard once.

**Orchestrator triage:**
- Vacuous drift gate → **act now** (fixed both gate scripts, honest re-baseline, archaeology
  entry).
- Orphan fixture `docs/examples/llm_observation_after_turn.json` (nothing generates or checks
  it) → **act later** (flagged to USER in the session report).
- 14.8 MB per-cell aggregate JSONs (full records × 24 seeds) → **record only** (works; trim to
  digest-only samples if sweep disk use ever matters).
