# Ground Combat — Retrospectives

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
  cost this session two review slots before it was diagnosed. The agy explore wrapper runs fine
  alongside one of them. **Closed 2026-07-30 (plan 0054):** the rule now lives in `.claude/REVIEWERS.md`
  and the launcher `tools/review_fanout.sh` starts exactly one opencode process; the skill's hand-rolled
  launch snippet this line referred to no longer exists (historical).

**Orchestrator triage:**
- Permissive declaration regex + check 0 → **acted now** (both are in the shipped validator; the
  reasoning is in its header and in the plan's "Parsing rules the review round pinned down").
- The serial-opencode requirement → **act now** for the record here, **act later** for the skill: the
  hand-rolled launch snippet then in `hexcombat-plan-review` backgrounded all three models
  simultaneously, which reproduced the failure. Logged to BACKLOG; **done 2026-07-30 in plan 0054** —
  snippet deleted, one opencode process per round, rule recorded in the roster (historical).
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
