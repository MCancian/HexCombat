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
| Module architecture, purity boundaries, wiring | code headers (`scripts/resolvers/*.gd`, `GameState.gd`) — docs point at the class by NAME, never file:line (line numbers rot) |
| Per-system data flow, data files, TIV fidelity/divergence rationale | `docs/systems/<module>.md` |
| Procedures (how to build/debug/verify/author) | `.claude/skills/` |
| Incident history (root cause, evidence, rejected fixes) | `hexcombat-failure-archaeology` |
| Why (decision changelog, 3–5 lines + pointers) | `docs/DECISIONS.md`; pre-2026-07-10 history verbatim in `docs/archive/PLAN.md` |
| Work in flight | `docs/plans/NNNN-*.md` + index `docs/plans/README.md`; track-level: `docs/plans/BACKLOG.md` |
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
   | `scripts/ijfs/**`, `IjfsResolver`, `data/ijfs/**` | `ijfs.md` |
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

   **Mechanical backstop:** `tools/validate_doc_anchors.gd` (in the gate) fails RED when a
   systems doc cites a dead path/script/member or uses a `file.gd:123` line citation — so a
   rename/move that orphans a doc anchor cannot pass the gate. It cannot catch semantically
   wrong prose over valid anchors; that's what this checklist is for. Historical passages that
   cite dead names on purpose: mark the line `(historical)`.
3. Append 3–5 lines to `docs/DECISIONS.md` — what + who decided + POINTERS to where the facts
   landed. **A DECISIONS entry is a changelog, never a reference**: if a future agent would need
   the entry to act, the fact is filed in the wrong place — move it, then point.
4. Lessons → `docs/RETROSPECTIVES.md` with triage; closed investigations → append to
   `hexcombat-failure-archaeology`.
5. Check off `docs/plans/BACKLOG.md` / the plan's checklist.

**Plan closeout** (multi-session work orders, `docs/plans/NNNN-*.md`): a plan is done only when
steps 1–5 above are done AND the plan file gets a 3-line closeout header (shipped date, where the
facts landed) and moves to `docs/archive/`. Update the index table in `docs/plans/README.md`
(it is the source of truth for plan status).

**When you plan new work:** small = a BACKLOG bullet; multi-session = the next `NNNN-<slug>.md` +
an index row (status `Sketch`). Blocked design questions for the user = a `Sketch` plan stating
the question. Never into STATUS.md.

**Never** date implemented-state text (dates live in DECISIONS/RETROSPECTIVES/plans).
**Never** rewrite or delete DECISIONS/RETROSPECTIVES entries — append corrections.

## Templates

**DECISIONS entry** (`docs/DECISIONS.md`, newest first, 3–5 lines):
```markdown
- **YYYY-MM-DD — <Title> (USER | agent judgment).** <One-sentence what.> Spec/facts:
  <docs/systems/x.md → §>. Incident: <archaeology entry> (if any). Evidence: <batch/gate>.
  <Divergence note if TIV-lineage math changed.>
```

**Retrospective entry** (`docs/RETROSPECTIVES.md`):
```markdown
## YYYY-MM-DD <task-slug>
- **Lesson:** <what would be done differently>
- **Triage:** acted now on <x>; recorded <y> for later; rejected <z> because <why>.
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
