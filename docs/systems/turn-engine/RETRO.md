# Turn Engine — Retrospectives

## 2026-07-31 — plan 0055: directory claims vs who applies campaign state   (implementer: direct)

**What would you do differently (implementer):**
- **Re-derive the QUESTION before reusing an instrument, not just the numbers.** The plan's original
  table said all six `scripts/resolvers/` files were pure. It was produced by plan 0050's alias-taint
  scan, which finds illegal *direct field writes* — a question that stopped being the right one the
  moment the mutation-authority campaign made every legal state change a *function call*. Two of the
  six changed campaign state every turn. Two independent reviewers confirmed the table, because
  reading cannot catch a measurement error. The check that worked took one command: run the
  counter-scan and see whether the answers agree.
- **A word already in the codebase can be the wrong name precisely because it is familiar.** The
  directory was nearly called `scripts/stages/`. The disqualifier was not the 37 prose uses of
  "stage" — those were genuinely split — but one line of code: `InfrastructureTickPlan.stage()`, the
  repo's own verb for recording a change so it can be applied LATER. Naming the
  deferral-is-impossible directory after the deferral primitive is an inversion, not a shade. Grep
  the candidate name as CODE, not only as prose.
- **The dependency ceiling caught the hoist and was right to.** Moving `CleanupResolver`'s two
  applications into `TurnClosure` took it 7 → 11. Rather than bump to what the first attempt
  produced, hosting the roster-wide latch inside `ForceTransitions` as a batch (plan 0048's pattern)
  kept `Brigade` and `ForceActivityRequest` off the budget, landing at 9. Bump to the number that
  buys the property, not the number the first draft happened to measure.
- **`(historical)` is a literal token, and prose that reads historical is not.** Eight doc lines
  legitimately name the dead directories; the doc-anchor gate skips a line only for the exact string
  `(historical)`. Writing "(historical — dissolved by 0055)" fails. Cheap, but it cost a gate cycle.

**Orchestrator triage:**
- The manifest cited `TurnClosure.gd:72-75` for behaviour living at `:52-55`; the file was 62 lines.
  Stale before this plan touched it → **acted now** (repointed). Line citations in the manifest are
  gated by nothing, so this class of rot is silent.
- The new validator sees DIRECT calls only — `IjfsResolver` applies through `IjfsEngine`, so a file
  can apply transitively and read as pure → **deliberately not fixed**; stated in the validator's
  header and in `docs/STATUS.md` rather than closed, because transitive closure needs call-graph
  analysis over a dynamically-typed language. The risk of a validator that over-claims is that the
  unpoliced half becomes MORE dangerous for looking covered.

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
