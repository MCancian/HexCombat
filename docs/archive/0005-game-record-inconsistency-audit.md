---
status: Shipped
shipped: 2026-07-17
landed_in: N/A (Agent task completed)
---
# 0005 — Game-record inconsistency audit (agent brief)

**Status:** Sketch · **Priority:** Medium — a ready-to-dispatch brief for another LLM/agent to
audit AI-vs-AI game records for engine/model inconsistencies and queue findings as plans.

> This plan **is** the prompt. Hand the fenced block below to the auditing agent. Scope is triage +
> plan authoring — it changes no engine code. The crossing/follow-on-sealift gap is already owned by
> **plan 0004**, so this audit deliberately excludes it and focuses on *other* inconsistencies.

## Why

One 30-turn game (`roc_full_defense`, seed 20260711) surfaced a real modeling gap by eye (sealift
stops after turn 3 → plan 0004). A systematic pass over the digests is likely to surface more.
Keep the auditor independent: it should reach its own conclusions from the data, then file plans.

## The brief (dispatch this)

```
You are auditing HexCombat AI-vs-AI game records for engine/model inconsistencies and queuing
plans to fix them. Analysis + plan authoring ONLY — change no engine code, run no golden
re-baseline.

## Orient first (project rules override everything)
- Read docs/STATUS.md (what works), docs/plans/BACKLOG.md and docs/plans/README.md (the queue),
  .claude/skills/README.md (task->skill map). CLAUDE.md / AGENTS.md are canonical.
- Load before reasoning about the domain or proposing fixes:
  - hexcombat-wargame-domain-reference — what each mechanic MEANS + its Python source oracle.
  - hexcombat-failure-archaeology — do NOT re-fight a settled battle or re-propose a rejected fix.
  - hexcombat-docs-and-writing — plan template, numbering, README index, closeout rules.

## Already diagnosed — do NOT re-investigate
- Follow-on sealift / "no new forces after ~turn 3": ✅ FIXED by plan 0004
  (../archive/0004-port-ship-crossing-sealift-model.md), shipped 2026-07-12 — cross-turn ship
  lifecycle + follow-on echelons. Was a fixed one-shot ship reserve with no reinforcement. Skip it.
- "Red never issues a crossing order": expected — there is no crossing action in the LLM API
  (LLMGameAPI.gd accepts only move/commit/end_turn). Not a bug.

## Data
- reports/llm/*.viewer.json — per-turn `digest` (antiship_summary, cleanup_summary, ijfs_writeback,
  combat_summaries) + per-side sides.{Red,Green} (actions / raw_reply / observation). Start with
  game_20260711.viewer.json; audit any other reports/llm/*.viewer.json present.
- reports/llm/<name>.game.html — the visual briefing viewer for the same game.

## Task
1. Write a stdlib-Python pass over each bundle that tabulates per-turn: census (both sides),
   battalion losses by cause (ground combat vs IJFS writeback vs at-sea), IJFS strikes
   executed/skipped and targets destroyed, contested hexes, and each side's action count. Look for
   internal contradictions and implausible plateaus/monotonicities.
2. Ranked list of candidate inconsistencies. Check at minimum:
   - Why the ashore census plateaus at a flat value late-game — does ground combat / IJFS simply
     stop, and is that correct? Does either side ever counterattack, or does the front freeze?
   - Green (Taiwan) behavior: does it ever attack, or only defend? Is that engine doctrine
     (attacker=Red hardcoded — see plan 0003) or a policy artifact?
   - IJFS: are strikes/targets internally consistent turn to turn; does anything regenerate or
     deplete implausibly (SAM/radar health, firing capacity)?
   - Any digest field that contradicts another in the same turn (e.g. losses vs census deltas that
     don't reconcile).
   - LLM order quality: rejected/empty actions, warnings, orders with no effect.
3. For each candidate, classify as (a) engine defect (violates its own spec), (b) intended
   simplification / missing mechanic (design gap → USER call), or (c) player-policy/prompt issue,
   with the evidence that decides it. Trace enough source (scripts/, data/) to justify the class —
   don't assert an untraced root cause.

## Deliverable — queue, don't implement
- Engine defect (a): a numbered plan docs/plans/NNNN-*.md per the hexcombat-docs-and-writing
  template (symptom, evidence with numbers, implicated files, root-cause hypothesis, fix approach,
  "done when" + gate). Register in docs/plans/README.md; one-line pointer in BACKLOG.md.
- Design gap (b): a Sketch plan framing the question + options for the USER (do not guess game
  design). Note it in the backlog.
- Report back: the ranked list, each item's class + deciding evidence, and the plan files/backlog
  lines you added.

## Guardrails
- Change ONLY docs/plans/ (+ README) and BACKLOG.md. No scripts/ or data/ edits, no golden
  re-baseline. Verify every claim against the bundle or source. Respect the "already diagnosed"
  list above.
```

## Checklist

- [x] Dispatch the brief above to an auditing agent
- [x] Review the queued plans it produces (classification correct? evidence traced? 0004/0003 not duplicated?)
- [x] Fold accepted items into the backlog priority order
