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

## 2026-07-27 — plan 0043: anti-ship mutation authority + permanent launch destruction   (implementer: direct)

**What would you do differently (implementer):**
- **Run a validator the way the GATE runs it, or its verdict means nothing.** I ran
  `validate_cleanup.gd` bare while checking a reconstructed commit, got `casualties=6, feba=0.43`
  against a pin of `3, -2.66`, and spent three experiments hunting a code bug that did not exist —
  the gate exports `HEXCOMBAT_SCENARIO=scenario_golden` and I had not. This trap is recorded in that
  validator's own header and in the memory file, and I walked into it anyway because I was running a
  single validator "just to check quickly". There is no quick check: use the gate's environment.
- **Measure the effect through the real harness, not a hand-rolled loop.** My first measurement
  drove `GameState.resolve_turn` in a `for` loop and concluded the campaign contained ONE crossing.
  It contains 4–8. Without `begin_next_turn` every turn after the first fails with "Cannot resolve
  turn outside PLANNING phase", and the probe cheerfully summed a stale summary 25 times. Two
  independent wrongs pointing at the same wrong answer. `run_selfplay_game.gd` existed the whole time.
- **A cumulative source that reports nothing has said nothing — not zero.** The IJFS writeback only
  carries rows it actually destroyed, so `get(key, 0)` on an absent key silently meant "no launchers
  have ever been lost here". Reading absence as zero would have resurrected the whole arsenal by the
  back door, on the very commit that removed resurrection. A reviewer caught it; nothing in the tree
  would have, because the golden scenario never exercises it.
- **Guards that `assert(false)` cannot be tested, so they get shipped unproven.** Switching the
  authority's refusals to `push_error` + change-nothing made all five of them testable with
  `assert_error(...).is_push_error(...)`, and writing those tests immediately found that the
  launch-attrition backwards guard was passing a floor of `0` — inert by construction.
- **Splitting work into commits AFTER the fact costs a full gate run per commit, and re-creating an
  intermediate state is where you introduce the bug you are trying to prove absent.** The separation
  was worth it (an extraction proven inert, then a behaviour change measured against it), but commit
  as you go: I had the byte-stable tree in hand at the time and threw it away.

**Actions:** none outstanding — the absent-key rule and the no-`assert(false)` rule are recorded in
`hexcombat-architecture-contract`; the scenario-env trap is already in `validate_cleanup.gd`'s header.

## 2026-07-26 — plan 0040: the combat-knob threading validator   (implementer: direct)

**What would you do differently (implementer):**
- **A validator that parses source must be written to fail loudly when its own parse breaks, and that
  has to be check ZERO, not a footnote.** Every other check here is vacuous if the anchors stop
  resolving, and a vacuous PASS is indistinguishable from a real one — which is the exact bug class the
  validator exists to close. Plan 0038 moved this very function between files two days earlier, so the
  scenario is not hypothetical. Cheap and load-bearing: assert the parse found what it expected before
  trusting any comparison built on it.
- **Match the DECLARATION shape permissively, the USE shape strictly.** The plan's first-draft regex
  `^var (\w+): (\w+) = (.+)$` looked precise and was the one real hole: a field written
  `var x: float` or `var x := 0.0` would have been missing from the declared list AND the assigned list,
  so the two consistent sets would compare equal and the validator would print PASS over the live bug.
  Both plan reviewers caught this independently; nothing in the tree would have.
- **A tool that reads production source must reach it by path string only.** Naming a class as a bare
  identifier — or `load()`ing its path — pulls it into the `-s` compile closure that
  `validate_tool_script_purity.gd` guards, and `TurnConductor` names an autoload. Writing
  `TurnConductor` once in this validator would have turned the purity gate red with an error pointing at
  someone else's file. `FileAccess.get_file_as_string` on a `const … := "res://…"` avoids both seeding
  mechanisms.
- **"Prove it can fail" needs a mutation per CLAIM, not one per validator.** Ten mutations, each
  reverted, and two of them earned their keep: renaming the local `rules` → `r` must still PASS (it does,
  because the identifier is derived), and moving an assignment out into a helper must fail LOUDLY rather
  than silently (it produces two failures whose pairing is the signature of that refactor — now
  documented in the header so the next agent reads it correctly instead of deleting the check).

- **Review the FINAL artifact, not just the one you sent for review — the second pass found the only
  real blocker.** The first diff review looked at a version that was then improved by its own findings;
  a second pass over the finished file found that `_check_no_other_writers` matched only a line-anchored
  plain `=`, so `rules.x += 1.0` in a helper, or `if cond: rules.x = 1.0` on one line, printed PASS over a
  live second writer. My own twelve mutations had not covered a compound or inline write — I had tested
  the shapes I had thought to implement, which is exactly the blind spot an outside read exists to cover.
  Reproduce-then-fix-then-re-reproduce was what made it certain.
- **Run the two opencode reviewers SERIALLY, not in parallel.** Two simultaneous `opencode run`
  invocations make the second die with `database is locked` — the session DB does not tolerate it. That
  cost this session two review slots before it was diagnosed. `agy-explore` runs fine alongside one of
  them. Worth folding into `hexcombat-plan-review`'s launch snippet, which currently backgrounds all
  three at once.

**Orchestrator triage:**
- Permissive declaration regex + check 0 → **acted now** (both are in the shipped validator; the
  reasoning is in its header and in the plan's "Parsing rules the review round pinned down").
- The serial-opencode requirement → **act now** for the record here, **act later** for the skill: the
  launch snippet in `hexcombat-plan-review` backgrounds all three models simultaneously, which
  reproduces the failure. Logged to BACKLOG.
- Diff round delivered two `agy-explore` passes and no opencode write-up (both free models failed
  infrastructurally, twice each) → **recorded** in the plan's "Coverage of the two review rounds" with
  what substituted for the missing reads. Not hidden: a future reader must know how thin the independent
  coverage was — and that the one blocker came from the second pass, not the first.
- `CombatCalculator._normalize_support` is a dead pass-through called nowhere → **act later**, logged to
  BACKLOG (production file; this commit changes no production line).
- "`GameData.DEFAULT_SCENARIO_PATH` is unused" → **rejected**: `GameState` reads it.
- The purity-closure trap → **acted now** (validator header) + **record only**: it is now stated in two
  places for the next tool author, and the gate catches the mistake anyway with a named file:line.
- One reviewer's "check 0 must assert the assignment count equals 26" → **rejected**: a hardcoded count
  that must be edited on every legitimate field addition is the rot pattern this project forbids, and it
  adds nothing over the field-by-field comparison. Recorded in the plan's don't-re-raise section with the
  measurement that refutes it.
- One reviewer's "ship a GdUnit test for the validator" → **rejected** (2 of 3 reviewers agreed):
  no validator in the tree has one, a validator *is* a test, and mocking `res://` source files to
  exercise regexes is brittler than the thing it would test. Recorded in the plan.
- `tools/validate_fixtures.gd` no longer exists — fixture drift is now checked by the git-diff block in
  `run_all_tests.py` — but **four skills still name it as a live gate** (`hexcombat-validation-and-qa`
  golden inventory, `hexcombat-change-control` "item-8 gate", `hexcombat-debugging-playbook` triage row,
  `hexcombat-gamestate-decomposition-campaign`), and a tracked orphan `tools/validate_fixtures.gd.uid`
  remains. A skill telling the next agent to fix a red validator that cannot go red costs it an hour →
  **act later**, logged to BACKLOG. Out of scope here; noticed while mapping validator conventions, and
  worth flagging that `validate_doc_anchors.gd` does not police skill files.

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
- Delegate sweeps must be source-verified before acting: agy-explore invented a 230-line
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
