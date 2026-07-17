# HexCombat — plans index

Work orders for multi-session efforts. Each plan is a focused doc; **this index is the source
of truth** for status. Status vocabulary: `Sketch` → `Exploring` → `In progress` → `✅ Shipped`
→ `Superseded`.

**Plans are ephemeral by contract.** A plan holds the design, the checklist, and progress notes
*while the work is in flight*. It is not a reference: no durable fact may live only in a plan.

**Closeout rule** (enforced by `hexcombat-change-control` / `hexcombat-docs-and-writing`):
a plan is done only when its durable facts have landed in their canonical homes —
`docs/systems/<module>.md` updated, `docs/STATUS.md` bullet current, `hexcombat-failure-archaeology`
entry if there was an incident, a 3–5-line `docs/DECISIONS.md` entry — and the plan file gets a
3-line closeout header and moves to `docs/archive/`. If a future agent would need to read the
plan to act, the closeout wasn't done.

## Active

| # | Plan | Priority | Status |
|---|------|----------|--------|
| 0005 | [Game-record inconsistency audit (agent brief)](0005-game-record-inconsistency-audit.md) | Medium | Sketch |
| 0008 | [Immortal Support Units in Ground Combat](0008-immortal-support-units-combat.md) | High | Sketch |
| 0002 | [Per-hull escort magazines (D3-B3)](0002-per-hull-escort-magazines.md) | Low (needs ship-ammo subsystem) | Sketch |
| 0003 | [Combat-summary team attribution](0003-combat-summary-team-attribution.md) | Low (blocked on USER counterattack call) | Sketch |

## Archived

| # | Plan | Status |
|---|------|--------|
| 0009 | [Code-quality baseline + remediation](../archive/0009-code-quality-baseline.md) | ✅ Shipped 2026-07-16 — audit + standards skill (`hexcombat-code-quality`) + full remediation (6 splits, 19 tests, const hoists), all golden byte-stable; report in `docs/reports/`, deferred debt in BACKLOG Track F |
| 0007 | [Offload weight rebalance investigation](../archive/0007-offload-weight-rebalance-investigation.md) | ✅ Shipped 2026-07-16 — reframed the plateau to a force-commitment question (matrix was inactive); `roc_full_defense` given `scenario_default`'s deep pool; facts in `docs/systems/amphibious-offload.md`, `docs/DECISIONS.md` |
| 0006 | [Offload capacity gate (beaches + ports)](../archive/0006-offload-capacity-gate.md) | ✅ Shipped 2026-07-15 — infrastructure nodes + JLSF repair + cost matrix + occupancy valve + day-N carry-over; facts in `docs/systems/amphibious-offload.md` §9, `docs/DECISIONS.md` |
| 0004 | [Port TIV ship-count & crossing model (sealift gap)](../archive/0004-port-ship-crossing-sealift-model.md) | ✅ Shipped 2026-07-12 — cross-turn ship lifecycle + follow-on echelons + escort SAM magazine; facts in `docs/systems/amphibious-offload.md` §8, `docs/DECISIONS.md` |
| 0001 | [Crossing-lethality calibration (D3-D)](../archive/0001-crossing-lethality-calibration.md) | ✅ Shipped 2026-07-11 — dial-in facts in `docs/systems/ijfs.md`, `hexcombat-config-and-knobs`, `docs/DECISIONS.md` |

## Track-level forward work

See [BACKLOG.md](BACKLOG.md) — live tracks only (completed tracks live in `docs/STATUS.md` as
present-tense behavior, history in `docs/archive/`).

## Parked refinements (no plan until a concrete need)

One-liners; detail in `docs/archive/port_audit.md`:
- Flotilla composition nuances (unit of allocation for the missile pipeline — only with 0001).
- Front-line distribution at battalion granularity (with the D5-D draw UI, Track D).
- ShipLoadingModel per-type transport weight + amphibious-vs-cargo eligibility (exact-manifest
  calibration only).
- Deliberately NOT ported (TIV-specific): SQL/DB writeback, mine same-day re-preview baseline,
  Streamlit dashboards — list in `docs/archive/port_audit.md` §Intentionally skipped.
