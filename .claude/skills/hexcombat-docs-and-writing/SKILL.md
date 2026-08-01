---
name: hexcombat-docs-and-writing
description: The HexCombat documentation system — one home per fact, the closeout rule for plans, the tracking rules agents must follow when finishing or planning work, and the entry templates (DECISIONS changelog, retrospective, system doc, plan). Use whenever you finish a feature, make a design choice, plan work, or touch any doc.
---

# HexCombat docs & writing

The user does not code — the docs ARE the project's institutional memory, and agents are both the
writers and the readers. Optimize for a cold-start agent orienting in minutes.

## One home per fact (the load-bearing rule)

Every fact lives in exactly ONE place; everything else points at it. Duplicated facts drift —
the 2026-07-10 audit found three systems docs describing an architecture 8 days dead while the
code headers were correct.

| Fact type | Only home |
|---|---|
| What works today (current behavior) | `docs/STATUS.md` — if another doc disagrees, STATUS wins; fix the other doc |
| Golden pins / exact validator outputs | `tools/validate_*.gd` — no doc or skill ever quotes a pin; "the validator's PASS line is truth" |
| Who may write which aggregate: authority class, protected fields, construction/legacy allowances | `tools/mutation_authority_manifest.json` — headers and systems docs name the aggregate and its authority and then point here; copying the field or writer list creates the second home this rule exists to prevent |
| Module architecture, purity boundaries, wiring | code headers (`scripts/calc/*.gd`, `scripts/interleaved/*.gd`, `GameState.gd`) — docs point at the class by NAME, never file:line (line numbers rot) |
| Per-system data flow, data files, TIV fidelity/divergence rationale | `docs/systems/<module>.md` |
| Procedures (how to build/debug/verify/author) | `.claude/skills/` |
| Incident history (root cause, evidence, rejected fixes) | `hexcombat-failure-archaeology` |
| Why (decision changelog, 3–5 lines + pointers) | `docs/DECISIONS.md`; pre-2026-07-10 history verbatim in `docs/archive/PLAN.md` |
| Work in flight | `docs/plans/NNNN-*.md` + index `docs/plans/README.md`; tech debt: `docs/plans/BACKLOG.md` |
| Lessons + triage | `docs/RETROSPECTIVES.md` (append-only, dated) |
| Dead/finished documents | `docs/archive/` — never in the orientation path |

## Tracking rules (follow exactly)

**When you finish a feature/change:**
1. Update `docs/STATUS.md` — present tense, no date, behavior not history.
2. Update the module's `docs/systems/*.md` if subsystem behavior changed (fidelity notes for any
   TIV divergence). **Checkable procedure, not a vibe:** run `git diff --name-only`, map each
   touched code path through the ownership table below — each owning doc must either be in your
   diff too, or you verify nothing it asserts changed (and can say so if asked).

   | Touched code | Owning doc (`docs/systems/`) |
   |---|---|
   | `scripts/interleaved/Ijfs*.gd`, `IjfsResolver`, `data/ijfs/**` | `ijfs.md` |
   | `AntishipCalculator`, `MineWarfareService`, `AntishipResolver`, `data/antiship/**` | `antiship-mine.md` |
   | `CombatCalculator`, `CombatForces`, `CombatResolver`, `Movement`, `UnitStats` | `ground-combat.md` |
   | `Offload*`, `ShipLoadingModel` | `amphibious-offload.md` |
   | `Supply*` | `supply-dos.md` |
   | `FrontLineService`, `FrontlineResolver`, `CleanupResolver`, `VictoryConditions` | `frontline-cleanup-victory.md` |
   | `HexMath`, `MapProjection`, `data/taiwan_hex_grid.json` | `hex-grid.md` |
   | `data/terrain/**`, terrain hooks in GameData/CombatResolver | `terrain.md` |
   | `LLMGameAPI`, `LLMPolicy`, `llm_sidecar*`, `SelfPlayRunner`, batch/report/bundle tools | `llm-api-selfplay.md` |
   | `HexMap`, `GameController`, scenes | `view-layer.md` |
   | `GameState.resolve_turn` wiring, `EventBus`, cross-phase fields | `turn-engine.md` |
   | `scripts/transitions/**`, `tools/mutation_authority_manifest.json`, `tools/validate_mutation_authority.gd` | `mutation-authority.md` |

   **Mechanical backstop:** `tools/validate_doc_anchors.gd` (in the gate) fails RED when a
   systems doc cites a dead path/script/member or uses a `file.gd:123` line citation — so a
   rename/move that orphans a doc anchor cannot pass the gate. It cannot catch semantically
   wrong prose over valid anchors; that's what this checklist is for. Historical passages that
   cite dead names on purpose: mark the line `(historical)`.
3. Append 3–5 lines to `docs/DECISIONS.md` — what + who decided + POINTERS to where the facts
   landed. **A DECISIONS entry is a changelog, never a reference**: if a future agent would need
   the entry to act, the fact is filed in the wrong place — move it, then point.
4. Lessons → `docs/RETROSPECTIVES.md` with triage.
   - **act now**: Fix it immediately.
   - **act later**: Formally log the issue into `docs/plans/BACKLOG.md`.
   - **Archive**: Once triage actions are complete or logged, **move the entry** from `docs/RETROSPECTIVES.md` to `docs/archive/RETROSPECTIVES_history.md`. (Treat `RETROSPECTIVES.md` as an inbox).
   - Closed investigations → append to `hexcombat-failure-archaeology`.
5. Delete completed items from `docs/plans/BACKLOG.md` / the plan's checklist.

**Plan closeout** (multi-session work orders, `docs/plans/NNNN-*.md`): a plan is done only when
steps 1–5 above are done AND the plan file gets a 3-line closeout header (shipped date, where the
facts landed) and moves to `docs/archive/`. Update the index table in `docs/plans/README.md`
(it is the source of truth for plan status).

**When you plan new work:** small = a BACKLOG bullet; multi-session = the next `NNNN-<slug>.md` +
an index row (status `Sketch`). Blocked design questions for the user = a `Sketch` plan stating
the question. Never into STATUS.md.

**Every plan names its required skills.** A `## Dependencies` section that lists only prior plans
sends the next agent in cold: they frame the job as "implement plan NNNN", which fires no skill
trigger, and re-derive rules that were already written down. Name them — e.g. "Required reading:
`hexcombat-architecture-contract`, `hexcombat-change-control`". Measured cost of omitting it on plan
0047: the architecture contract already stated the exact ceiling rule the implementation then
rediscovered by measurement, and a reviewer had to quote the line back.

**A partially-shipped plan carries a `## Progress` section**, and it is the FIRST thing the next
agent reads — before STATUS.md, before the backlog. It states which steps shipped (with commits),
which remain, and **any deliberately transitional code left behind, naming the step that removes
it**. A half-migrated tree that looks finished is how transitional scaffolding becomes permanent.
The plan keeps status `Ready`/`In progress` until closeout; do not archive it.

**Never** date implemented-state text (dates live in DECISIONS/RETROSPECTIVES/plans).
**Never** rewrite or delete DECISIONS/RETROSPECTIVES entries — append corrections.

## Templates

**DECISIONS entry** (`docs/DECISIONS.md`, newest first, 3–5 lines):
```markdown
- **YYYY-MM-DD — <Title> (USER | agent judgment).** <One-sentence what.> Spec/facts:
  <docs/systems/x.md → §>. Incident: <archaeology entry> (if any). Evidence: <batch/gate>.
  <Divergence note if TIV-lineage math changed.>
```

**Retrospective entry** (`docs/RETROSPECTIVES.md` inbox → `docs/archive/RETROSPECTIVES_history.md`):
```markdown
## YYYY-MM-DD <task-slug>
- **Lesson:** <what would be done differently>
- **Triage:** acted now on <x>; recorded <y> for later (added to BACKLOG); rejected <z> because <why>.
```

**Plan** (`docs/plans/NNNN-<slug>.md`): status header (must match the README index row) → goal →
what is already settled (do-not-relitigate pointers) → approach → checklist. Keep it a work
order: durable analysis belongs in the module doc or DECISIONS pointer trail, not here.

**System doc** (`docs/systems/<module>.md`): purpose → data flow (inputs/outputs per turn) → key
classes by NAME (reader greps; no line numbers) → data files → fidelity/divergence notes → open
questions (pointer to plan if one exists).

## House style

- Written for agents: concrete file paths, class/function names, exact commands. No marketing
  prose. No pinned numbers outside validators.
- State authority explicitly: *USER call* vs agent judgment — future agents must know what they
  may relitigate (agent judgment) vs must not (USER calls).
- Skills hold *procedures*; docs hold *facts*. Point, don't duplicate.
- HTML mirrors (`docs/systems/html/`) are for the human; regenerate when the `.md` changes
  materially, or note that they lag.

### Name a witness for any claim about consumers, boundaries or cost

A MISSING fact costs one lookup. A FALSE one costs a verification round trip plus whatever gets built
on it before someone checks. The false ones found so far were all unfalsifiable as written — no reader
could tell staleness from truth without redoing the search:

- `SealiftState.to_dict()`'s header called itself "the JSON-serialization boundary (golden /
  observation fixtures)". It has no consumer anywhere — not production, not a fixture, not a test. A
  plan built its risk assessment on that claim (plan 0045 D1) before the check was run.
- A plan deferred a file move as "touches every call site". A GDScript `class_name` is
  path-independent, so it touched none. The deferral was priced on a false cost.

So when a doc or header asserts that something IS or IS NOT consumed, serialized, pinned, or expensive,
write the witness inline in the same breath:

    consumer: OffloadCostModel (offload cost matrix)
    consumer: none (checked 2026-07-29 — no production call, no fixture, no test)
    pinned by: tests/transitions/sealift_transitions_test.gd
    cost: 3 files + 1 doc reference (measured, not estimated)

Two rules make this worth the words: the witness must be greppable in one command, and "none" must
carry the date it was checked. A bare "unused" ages into a lie; "none (checked <date>)" ages into a
question, which is the correct thing for a reader to feel.
