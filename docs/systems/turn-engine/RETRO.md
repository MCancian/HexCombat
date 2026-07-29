# Turn Engine — Retrospectives

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
