# 0007 — Offload weight rebalance investigation (agent brief)

**Status:** ✅ Shipped 2026-07-16 — investigated, USER decided, applied. Facts:
`docs/systems/amphibious-offload.md` → "Sealift lifecycle"; decision: `docs/DECISIONS.md` 2026-07-16;
scenario change: `data/scenarios/roc_full_defense.json`. **Priority:** Medium.
Investigation finding (2026-07-16): the offload cost matrix is **not implicated** — `roc_full_defense`
(the scenario all 4 overnight games used) never turns `use_offload_weight_matrix` on, so
`offload_weights.json`'s values were never exercised in the evidence that motivated this plan. The
real driver is the scenario's **fixed, finite invasion-force commitment** (14 of 111 PLA brigades /
126 battalions total, no deep pool) fully landing by turn ~15–30 and then having nothing left to
reinforce against 32 ROC brigades. See "Findings" below for the USER-facing choice this reframes to.

> Original brief (for provenance) below the findings. Scope was analysis + sensitivity sweeps + a
> USER-facing recommendation — no balance-value edits, no golden re-baseline, no re-diagnosis of the
> sealift livelock (plan 0006, already fixed). That scope was honored; nothing in `data/` was changed.

## Findings (2026-07-16 investigation)

**Method.** `TurnResult`/the digest shape has no `offload_summary` — the `OffloadResolver` manifest
(landed/deferred BN counts + deferral reasons) is computed every turn but never surfaced past
`EventBus.offload_resolved`. So the 4 overnight records can only be read *indirectly*: per-turn
`china_battalions_on_taiwan` deltas, reconciled against `combat_summaries` (PLA battalion losses,
attacker or defender role) and `antiship_summary.bns_lost_at_sea`. That reconstruction is internally
inconsistent by ~15–20 BNs across all 4 games (implied total-ever-landed + total-lost-at-sea exceeds
the known 126-BN pool) — likely a reconstruction artifact (no `PLA`-prefixed-brigade double count
found in the raw `combat_summaries`), not a verified engine bug; flagged below as a telemetry gap,
not filed as a defect. To get ground truth, a temporary instrumented probe (`EventBus.offload_resolved`
listener + `SelfPlayRunner`, deleted after use, no committed code) replayed `roc_full_defense` seed
20260716 with two deterministic policies (`inland_clear`, `selfplay_default` — both registered in
`PolicyCatalog`); its manifests are ground truth and cross-checked internally consistent
(landed + lost_at_sea ≤ 126 in every run).

**Throughput trace (ground truth, flat-cost path — matrix off, matches the real evidence).**
Both policies land the *entire* 126-BN pool within ~14–18 turns: Day-1 assault lands 23–41 BNs
turn 1 (bypass rule) with ~20 lost at sea; turns 2–9 land in a `throughput_limited`-only cadence of
2–9 BN/turn (matches §9's documented "~5 BN/turn over beaches alone" and the beach-slot rate math —
no `offload_in_progress` carry-over ever fires, because every flat cost is a multiple of 2200, per
§9's carry-over note); `ship_reserve` empties completely (0 entries) for 1–2 turns mid-game while the
next follow-on cohort embarks and crosses, then a new 30+ BN batch lands in a burst once it arrives —
a **sealift-cadence gap**, not a beach-capacity cap. By the point `ship_reserve` is empty for good, all
126 BNs have landed or been lost at sea. The 4 overnight LLM games show the same shape at the same
timescale (full-pool exhaustion by roughly turn 20–30, thereafter pure decline) — the LLM policy
clears beaches adequately (via combat-driven FEBA advance, not necessarily explicit orders) to avoid
a permanent lock.

**Candidate causes, tested:**
- **(a) Cost-matrix values too high — RULED OUT for this evidence.** `data/scenarios/roc_full_defense.json`
  has no `use_offload_weight_matrix` key (defaults `false` — `hexcombat-config-and-knobs`), so
  `offload_weights.json` is never read; the flat `TONS_PER_BN=2200` path ran throughout all 4 games.
  Confirmatory test: cloning the scenario with `use_offload_weight_matrix: true` (variant under
  `reports/`, not committed) measurably slows the same seed's buildup — `offload_in_progress`
  carry-over now fires every turn 2+, and full-pool landing stretches from turn ~18 to ~23 (both
  `inland_clear`) — so the matrix's current values *would* matter if the scenario turned it on, but
  it does not, in evidence or in the shipped scenario file.
- **(b) `BeachDef.depth` occupancy valve — a measurable but secondary effect, not the plateau's cause.**
  Depth is a `data/beaches.json` constant (`GameData.BEACHES_PATH` hardcoded), not a scenario knob —
  promoting it would need the same code-plumbing lift as (a); not done, per the brief's
  "say so rather than force it" instruction. Tested instead via an in-memory override in the temp
  probe (no data-file edit): `depth=1` (stricter) visibly stalls turn 2 (0 BNs land, vs 4–12 at
  depth=2/6) — the valve is real and can bind — but `depth=6` (much looser) does not reach full-pool
  landing meaningfully faster than the shipped `depth=2`; combat's FEBA advance evidently clears
  landed brigades off beach hexes fast enough at the default that the valve rarely closes for long
  in this matchup. Not the plateau driver at the shipped value.
- **(c) Ship/JLSF sealift cadence — a real, secondary pacing effect.** The multi-turn gaps where
  `ship_reserve` goes to 0 and stays there for 1–2 turns (waiting on the next cohort's embark +
  crossing) are visible in every probe run. This paces *when* batches land, but every BN still lands
  or is lost within the horizon — it delays, it doesn't cap.
- **(d) Working as intended, reframed — CONFIRMED as the actual driver.** The `126`-BN pool
  (`red_ship_reserve` 4 brigades + `red_followon_reserve` 10 brigades, `auto_seed_followon_pool`
  absent/false) is **fully consumed (landed or lost at sea) by roughly turn 15–30** in every
  measurement (ground-truth probes and the 4 real games alike). After that point there is *nothing
  left to send* — `china_battalions_on_taiwan`'s "6–43 plateau" is the tail of a battalion-attrition
  fight against 32 ROC brigades (~124+ BNs) with a fixed, exhausted invader, not a throughput
  bottleneck. This is not the offload-cost-matrix question the brief was framed around; it's a
  **scenario force-commitment** question.

**USER-facing choice this reframes to** (no change made — bring to USER):
1. **Keep `roc_full_defense` as-is** (14 committed brigades, no deep pool) — the 40-turn LLM games
   are then a legitimate depiction of a numerically overmatched invasion grinding down after its
   force is spent; the "plateau" is correct behavior, not a bug or a mistuned knob.
2. **Give `roc_full_defense` a deep pool** (`auto_seed_followon_pool: true`, as `scenario_default`
   already does) or a larger explicit `red_followon_reserve`, if the intent is a sustained invasion
   that can out-build ROC's defense over 40 turns — this is a scenario-authoring change
   (`hexcombat-scenario-authoring`), not an `offload_weights.json` edit.
3. **Separately, if/when `roc_full_defense` (or any scenario) turns `use_offload_weight_matrix` on**,
   the current weight values are confirmed to bite (measured ~5-turn stretch-out on one seed) —
   re-dialing them is a legitimate future exercise at that point, with a proper multi-seed sweep;
   nothing in this investigation's evidence calls for a re-dial today, because the matrix isn't in
   the loop.

**Telemetry gap (not a defect, a backlog item):** `TurnResult`/turn digests have no `offload_summary`
— add one (surfacing `bns_sent/landed/waiting/lost_at_sea` + a deferral-reason histogram, mirroring
`OffloadResolver`'s manifest) so future research runs can read offload activity directly from game
records instead of reconstructing it from census deltas + combat summaries (which was measurably
unreliable — see Method above). Logged to `docs/plans/BACKLOG.md`.

---

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
    not a scratch driver. **This box has no `pwsh` and no `.sh` equivalent of `run_sweep.ps1`/
    `run_batch.ps1`** — read what they generate (a per-value scenario-JSON variant with one dot-path
    knob changed, then `godot --headless --path . -s res://tools/run_selfplay_game.gd --
    --seed=S --scenario=<variant path> --turns=T --out=file.json` per seed) and replicate that
    directly in bash; don't get stuck trying to invoke the `.ps1` files.
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

- [x] Dispatch the brief above to an investigating agent
- [x] Review its throughput trace + candidate-cause findings for evidence quality — ground-truthed
      via a temporary instrumented probe (not committed) against the real 4-game census
      reconstruction; candidate (a) ruled out (matrix inactive in the evidence's scenario),
      (d) confirmed reframed to force-commitment exhaustion, (b)/(c) secondary pacing effects only.
      See "Findings" above.
- [x] Bring the reframed finding to USER with the evidence: keep `roc_full_defense`'s fixed 14-brigade
      commitment (grind is intended) vs give it a deep pool / larger follow-on reserve (sustained
      invasion intent) — see "USER-facing choice" above. Not an `offload_weights.json` question today.
- [x] USER decided: give `roc_full_defense` a deep pool (`auto_seed_followon_pool: true`, emptied
      `red_followon_reserve`), same shape as `scenario_default`. Applied 2026-07-16: verified
      `validate_scenario_data.gd` PASS, deterministic self-play (byte-identical repeat seed), landed
      force climbs continuously instead of plateauing (44→81 BNs over 12 turns, one seed check), full
      gate green. `docs/systems/amphibious-offload.md` updated (2 stale `roc_full_defense`-as-explicit-
      follow-on references corrected); `docs/DECISIONS.md` 2026-07-16 entry added.
