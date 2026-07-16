# 0007 — Offload weight rebalance investigation (agent brief)

**Status:** Sketch · **Priority:** Medium — a ready-to-dispatch brief for another agent to
investigate whether `data/offload_weights.json`'s HexCombat-only BN-type values need re-dialing,
using fresh evidence from 4 overnight LLM-vs-LLM validation games.

> This plan **is** the prompt. Hand the fenced block below to the investigating agent. Scope is
> analysis + sensitivity sweeps + a USER-facing recommendation — it does not change balance values
> unilaterally and does not re-diagnose the sealift livelock (plan 0006, already fixed).

## Why

Plan 0006 (offload capacity gate, shipped 2026-07-15, `docs/archive/0006-offload-capacity-gate.md`)
shipped a data-driven offload cost matrix and left one open item unresolved: the locally-assigned
`offload_weights.json` values for HexCombat-only BN types (Combined Arms 2200, Air Assault/
Recon/helo 1100, Service/Support 2200, Air Defense 2750) are balance knobs the designer may want
to re-dial — surfaced to USER 2026-07-15, not blocking, never actioned.

Four overnight validation games (2026-07-15/16 night, seeds 20260716-20260719, commit
`eb4c8bb9a3214677e4a52c71698e94f7f576f2fb`, scenario `roc_full_defense`, both seats `llm_local`
model `jarvis`/DeepSeek-V4-Flash, 40 turns each) give a first real data point on this question:
in all 4 games, `china_battalions_on_taiwan` (the landed PLA force, from each turn's
`cleanup_summary`) oscillated in roughly a **6–43 band for the full 40 turns and never broke
out**, while Taiwan's defenders (`taiwan_battalions_on_taiwan`) declined steadily from ~122–124
to 26/51/32/41 by turn 40. None of the 4 games reached `game_over` — all hit the 40-turn cap.
Engine health was clean throughout (`all_resolved=true`, `index_violations=[]`, zero forfeited
LLM turns in all 4) — so this is a balance/tuning question, not an engine defect, but the shape
(landed force capped well under a third of the defender total, for 40 turns straight) is exactly
what the open re-dial item was waiting on.

## The brief (dispatch this)

```
You are investigating whether HexCombat's data-driven offload cost matrix
(data/offload_weights.json) needs re-dialing, using 4 overnight LLM-vs-LLM validation games as
evidence. Analysis + sensitivity sweeps + a recommendation ONLY — do not edit
data/offload_weights.json, do not run a golden re-baseline, do not decide the balance question
yourself (it is a USER call).

## Orient first (project rules override everything)
- Read docs/STATUS.md (what works), docs/plans/BACKLOG.md and docs/plans/README.md (the queue),
  .claude/skills/README.md (task->skill map). CLAUDE.md / AGENTS.md are canonical.
- Load before reasoning about the domain or proposing anything:
  - hexcombat-config-and-knobs — the knob table; how offload_weights.json / use_offload_weight_matrix
    are wired, and how to change a knob for a sweep without touching committed data.
  - hexcombat-wargame-domain-reference — what offload/beach/port throughput MEANS + its Python
    (TaiwanInvasionViewer) source oracle.
  - hexcombat-research-runs — the sweep tool (`tools/run_sweep.ps1 -Knob <dot.path> -Values a,b,c
    -N 30`) and batch/report tooling; this is analysis over existing artifacts plus new sweeps,
    not a scratch driver.
  - hexcombat-failure-archaeology — "Sealift livelock" entry. That issue is ALREADY FIXED
    (day-N carry-over, `offload_progress_tons`) and re-verified live in the 4 games below
    (landed-force counts fluctuate turn to turn, never freeze at a fixed value) — do not
    re-diagnose it; if your data shows a genuine freeze, that would be a NEW regression, not the
    old bug, and worth flagging as such.
  - docs/systems/amphibious-offload.md §9 — current offload throughput model (durable facts).
  - docs/archive/0006-offload-capacity-gate.md — full design context + the open item's exact
    wording (search "re-dial").
  - hexcombat-docs-and-writing — plan template, numbering, README index, closeout rules.

## Already diagnosed — do NOT re-investigate
- Sealift livelock (C8, 2026-07-15): fixed, re-verified holding in all 4 games below. Skip it
  unless your own data contradicts this.
- LLM duplicate-order warnings (~3-7 per 40-turn game, `llm_sidecar: dropping duplicate order for
  X`): a separate, already-scoped model-quality issue (see docs/systems/llm-api-selfplay.md),
  adds prompt noise but does not explain a 40-turn landed-force plateau. Note it if relevant,
  don't chase it.

## Data
- reports/llm/overnight_s20260716.json .. overnight_s20260719.json — per-game records:
  `turn_digests[].cleanup_summary.{china_battalions_on_taiwan,taiwan_battalions_on_taiwan,
  game_over}`, `turn_digests[].combat_summaries`/`contested_hexes` (front-line activity),
  top-level `census`/`all_resolved`/`index_violations`.
- reports/llm/overnight_s20260716.jsonl .. overnight_s20260719.jsonl — the matching replay logs
  (full observation/action pairs per turn per side; `warnings` field per entry).
- All 4: commit eb4c8bb9a3214677e4a52c71698e94f7f576f2fb, scenario roc_full_defense, both seats
  llm_local/jarvis, 40/40 turns, all_resolved=true, index_violations=[].

## Task
1. From the 4 records, build the per-turn offload throughput trace (BNs landed/turn, held
   beaches vs held ports/airbridges if attributable, operational-state changes over time).
   Reconcile against `OffloadCalculator`/`OffloadResolver` behavior in amphibious-offload.md
   §9 — don't re-derive the math from scratch.
2. Determine WHY `china_battalions_on_taiwan` plateaus in the ~6–43 band across all 4 games.
   Candidates to test, not assume:
   a. `offload_weights.json` cost-matrix values for HexCombat-only BN types are too high →
      throughput-limited landing rate.
   b. `BeachDef.depth`=2 occupancy valve is the binding constraint, not the cost matrix.
   c. Ship/JLSF cycle (sealift lift, not shore offload) is the actual bottleneck — offload
      capacity is never the limiting factor.
   d. Working as intended: landings roughly track combat attrition (a deliberate slow grind),
      not a throughput bug.
   Use `tools/run_sweep.ps1 -Knob <dot.path> -Values ...` over a common seed set (reuse
   20260716-19 or a fresh 10-20 seed set) varying ONE knob at a time (an offload_weights value,
   then BeachDef.depth) to see which one actually moves the `china_battalions_on_taiwan`
   trajectory. Sweeps only cover scenario-file knobs — a knob living in a phase data file
   (offload_weights.json) needs promoting to a scenario key first per hexcombat-research-runs;
   if that promotion itself is nontrivial, say so rather than skipping the test.
3. If the cost matrix is implicated, propose specific re-dialed values with before/after
   sensitivity numbers (win rate / landed-force trajectory / turns-to-decision across the seed
   set) — a recommendation, not a unilateral change.

## Deliverable — queue and recommend, don't implement
- A Sketch plan (update this one, 0007, or a fresh NNNN if the finding reframes the question)
  presenting the USER-facing choice: keep current offload_weights.json values (the grind is
  intended) vs re-dial to specific proposed values, with the sensitivity evidence backing it.
  Per hexcombat-docs-and-writing template.
- If you find a genuine engine defect (not a balance question) en route, file it as its own
  numbered plan per the standard template; don't fold it into this balance question.
- Report back: the throughput trace, which candidate cause(s) the sweeps isolate, and the
  concrete recommendation (or the reframed question) you're leaving for USER.

## Guardrails
- Analysis + sweeps only. Sweep-generated scenario variants and reports live under `reports/`
  (git-ignored) — never edit committed `data/offload_weights.json` or `data/scenarios/*.json`.
  No golden re-baseline. Change only docs/plans/ (+ README) and BACKLOG.md for the plan/backlog
  entries themselves.
```

## Checklist

- [ ] Dispatch the brief above to an investigating agent
- [ ] Review its throughput trace + candidate-cause findings for evidence quality (does the sweep
      actually isolate the claimed cause?)
- [ ] Bring the re-dial question (or reframed finding) to USER with the evidence
- [ ] On a USER decision: apply it, update `docs/systems/amphibious-offload.md` §9 +
      `docs/DECISIONS.md`, close this plan
