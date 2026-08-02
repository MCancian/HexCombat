# HexCombat — plans index

> **Read budget.** Starting a task? Read **"Next up"** (the next ~45 lines) and stop. The tables
> below are an index of `docs/plans/`, not reading material — open a plan only when you are about to
> work on it. Shipped plans are one row in [ARCHIVE.md](ARCHIVE.md); their reasoning stays in
> `docs/archive/` and is not summarized twice.

Work orders for multi-session efforts. Each plan is a focused doc; **this index is the source
of truth** for status. Status vocabulary: `Sketch` → `Exploring` → `In progress` → `✅ Shipped`
→ `Superseded`.

## ▶ Next up

**The mutation-authority campaign (0042–0050) is CLOSED as of 2026-07-31.** Nothing in this index is
blocked on it any more; pick from the Active table below. If you are about to touch mutable gameplay
state, read `docs/systems/mutation-authority/mutation-authority.md` (the procedure) and the manifest's
`_schema_rules` (nine rules) before you write — adding an aggregate is now an addition to a closed
world rather than a step in an open migration.

The three plans most worth doing next, in the maintainer's judgement, are **0051** (destroyed systems
still fire — a real defect, already planned in detail), **0031** (graduated port suppression, unblocked
by 0047) and **0002** (per-hull escort magazines, unblocked by 0043+0045). All three are USER-facing
mechanics rather than architecture.

**The structural-hygiene chain is COMPLETE (0055 -> 0057 -> 0056, all shipped 2026-07-31/08-01).**
0055 settled the role vocabulary, 0057 made `scripts/` root a 4-file allowlist, and 0056 turned the
dependency budget from opt-in into enforced-over-`scripts/`. The ordering was load-bearing: 0056 seeds
a PATH-KEYED table, and five of the eleven files it seeded got their current path from the first two.

**Preflight killed a premise in all three.** 0055's "six pure resolvers" table came from an instrument
built to answer a different question; 0057's "only two root files apply state" was false; 0056 quoted a
superseded ceiling and justified its own ordering with a move that never happened. `docs/plans/` is
outside the doc-anchor gate, so nothing flagged any of it. Measure before you review, not after.

**Plans are ephemeral by contract.** A plan holds the design, the checklist, and progress notes
*while the work is in flight*. It is not a reference: no durable fact may live only in a plan.

**Closeout rule** (enforced by `hexcombat-change-control` / `hexcombat-docs-and-writing`):
a plan is done only when its durable facts have landed in their canonical homes —
`docs/systems/<module>/<module>.md` updated, `docs/systems/<module>/STATUS.md` bullet current,
`hexcombat-failure-archaeology` entry if there was an incident, a 3–5-line `docs/DECISIONS.md`
entry — and the plan file gets a 3-line closeout header and moves to `docs/archive/`. If a future
agent would need to read the plan to act, the closeout wasn't done.

**Every active plan carries a `## Golden-pin budget`** (enforced by `tools/validate_plan_docs.gd`):
right under the title, a line naming the validators the plan will re-baseline — e.g.
`validate_golden_victory and validate_cleanup` — or `none`. State the *count* and *when* up front
("expect 2 re-baselines, one per stage; measure X and Y together"), so an agent batches the
measurement instead of re-baselining one validator at a time. Set it to the real list the moment a
sketch stops being a sketch (the `none` you seeded at Sketch time is deliberately unproven, not a
license to forget goldens).

## Active

| # | Plan | Priority | Status |
| --- | --- | --- | --- |
| 0002 | [Per-hull escort magazines (D3-B3)](0002-per-hull-escort-magazines.md) | Low (needs ship-ammo subsystem) | Sketch |
| 0003 | [Combat-summary team attribution](0003-combat-summary-team-attribution.md) | Low (blocked on USER counterattack call) | Sketch |
| 0024 | [Order-entry facilitator flow (live play)](0024-order-entry-facilitator-flow.md) | Medium (live-facilitator UI) | Sketch |
| 0025 | [Front-line polyline-draw UI (D5-D)](0025-frontline-polyline-draw-ui.md) | Medium (live-facilitator UI; large feature) | Sketch |
| 0026 | [Live-play Godot map: camera, HUD, replay screenshotter](0026-liveplay-map-camera-hud.md) | Low (live-operator polish) | Sketch |
| 0027 | [Front-view per-beachhead pager (ocean-spanning fronts)](0027-front-view-beachhead-pager.md) | Low (build only when a talk needs it AND the sim produces an ocean-spanning front) | Sketch |
| 0028 | [Sustained follow-on interdiction](0028-sustained-followon-interdiction.md) | Medium (research; new mechanic — interdiction is a one-shot toll, follow-on crosses at 3% loss) | Sketch |
| 0029 | [Dynamic ROC defense](0029-dynamic-roc-defense.md) | Medium (research; Tier A policy cheap) | Tier A shipped 2026-07-24 (Red 100%→83.3%) |
| 0030 | [JLSF first-class cohort (legibility)](0030-jlsf-first-class-cohort.md) | Low (refactor; byte-stable observability — enables 0031) | Sketch |
| 0031 | [Graduated port suppression](0031-graduated-port-suppression.md) | Medium (new mechanic) | Sketch |
| 0033 | [Brigade organization](0033-brigade-organization.md) | Medium (new mechanic) | Sketch |
| 0035 | [Scenario variant inheritance](0035-scenario-inheritance.md) | Medium (refactor) | Sketch |
| 0039 | [One truth about where a battalion is](../archive/0039-battalion-location-single-truth.md) | Superseded | **Superseded by 0044** |
| 0040 | [CombatRules — stop hand-threading 26 fields](../archive/0040-combatrules-threading.md) | Medium (risk buydown) | **Complete 2026-07-26** |
| 0041 | [One pattern for reaching an autoload](0041-autoload-access-one-pattern.md) | Low (ergonomics) | Sketch |
| 0043 | [Anti-ship mutation authority + permanent launch destruction](../archive/0043-antiship-mutation-authority.md) | **High — first vertical slice** | **Complete 2026-07-27** |
| 0042 | [Mutation-authority foundation](../archive/0042-mutation-authority-foundation.md) | **High — establishes the controller/API rule** | **Complete 2026-07-26** |
| 0044 | [Force mutation authority](../archive/0044-force-mutation-authority.md) | **High — brigades, battalions, manifests, placement** | **✅ Shipped 2026-07-29** |
| 0045 | [Sealift/fleet mutation authority](../archive/0045-sealift-fleet-mutation-authority.md) | High — hull/cohort/pipeline conservation | **✅ Shipped 2026-07-29** |
| 0046 | [IJFS mutation authority](../archive/0046-ijfs-mutation-authority.md) | High — targets, munitions, squadrons | **✅ Shipped 2026-07-30** |
| 0047 | [Map/infrastructure mutation authority](../archive/0047-map-infrastructure-mutation-authority.md) | High — ownership, FEBA, seizure, repair | **✅ Shipped 2026-07-30** |
| 0051 | [Destroyed coastal launchers get a last salvo away](0051-destroyed-systems-still-fire.md) | Medium (balance) | Sketch |
| 0061 | [Model a resolution day as an explicit DAG, substream per node](0061-resolution-dag.md) | Medium (**SPLIT by USER ruling 2026-08-01**) | Part 1 ready to plan; Part 2 deferred |
| 0060 | [Localize air attrition to engagements](../archive/0060-air-attrition-before-the-strike.md) | Medium-Large | **SHIPPED 2026-08-01** — R10's checkpoint is UNREACHABLE; closure in the plan |
| 0059 | [Readable air inventory; RTB folded into 0060](../archive/0059-sam-interception-and-rtb.md) | Medium | **SHIPPED 2026-08-01** — step 2 shipped inside plan 0060 stage 3 |
| 0052 | [Legibility sweep: unenforced budget, dead seams, half-finished role layout](../archive/0052-legibility-and-dead-seams.md) | Medium (hygiene) | **Complete 2026-07-27** |
| 0036 | [Airborne cost and sortie cadence](0036-airborne-cost-and-cadence.md) | Medium (balance) | Sketch |
| 0053 | [Documentation hierarchy refactor (hub-and-spoke)](../archive/0053-doc-hierarchy-refactor.md) | Medium (developer experience) | **✅ Shipped 2026-07-29** |
| 0054 | [Reviewer tiers, one canonical home, one fan-out command](../archive/0054-reviewer-tiers-and-doc-consolidation.md) | Medium (agent workflow) | **✅ Shipped 2026-07-30** |

| 0016 | [Separate State Data from Autoload](../archive/0016-separate-state-data.md) | Medium (hygiene/architecture) | Superseded by 0014 |
| 0022 | [Red reactive beach-opening (feasibility first)](0022-red-beach-switching.md) | Medium (research; new mechanic, gated on a feasibility spike) | Sketch |
| 0057 | [Give `scripts/` root a role layout](../archive/0057-scripts-root-role-layout.md) | Medium (hygiene) | **COMPLETE** (2026-07-31) |
| 0056 | [Make the coupling budget opt-out](../archive/0056-coupling-budget-opt-out.md) | Medium (risk buydown) | **COMPLETE** (2026-08-01) |

## Mutation-authority campaign — ARCHIVED (0042–0050, complete 2026-07-31)

| | |
|---|---|
| **What it did** | Gave every mutable gameplay aggregate exactly one named authority under `scripts/transitions/`, enforced by a source gate that resolves each write's RECEIVER TYPE. Ten aggregates, ten authorities, **zero** legacy-writer allowances. Eight of the nine plans were byte-stable; **plan 0043 is the exception** — it carried one separately committed, USER-approved behaviour correction (launchers destroyed while firing used to be alive again at the next crossing), and research records straddle that boundary. |
| **Where the record is** | Per-plan reasoning in `docs/archive/0042-…` through `docs/archive/0050-…`, one row each in [ARCHIVE.md](ARCHIVE.md). The lessons that generalize are in `.claude/skills/hexcombat-architecture-contract` § Mutation authority and `docs/systems/mutation-authority/mutation-authority.md`. |
| **Where the FACTS are** | `tools/mutation_authority_manifest.json` — the only home for ownership. `docs/STATUS.md` indexes which authority covers what, one line per aggregate. `python3 tools/mutation_ownership.py` queries it. |
| **What is still open** | `E_STALE_ALLOWANCE` is the one manifest check with no proof surface — tracked in [BACKLOG.md](BACKLOG.md) with the reason the existing fixture harness cannot host it. |

The campaign's own sequencing rules, readiness gates and serial-agent protocol are **deleted rather
than archived here**: they governed an in-flight migration that is over, and a future agent reading
them as live guidance would be following instructions for work that no longer exists. What survives
them — one authority per aggregate, calculators return outcomes, ceilings are paid for and never
raised, one migration family per commit — is in the architecture-contract skill, where it applies to
any change rather than only to this campaign.

### Interaction with existing plans (still current)

- **0039 is superseded by 0044.** Do not implement its derived-ledger step.
- **0033 brigade organization** may proceed; it must add no new `Brigade` writer outside `ForceTransitions`.
- **0002 per-hull escort magazines** is UNBLOCKED: the aggregate per-type magazine has one named writer (`SealiftTransitions`) to grow per-hull granularity behind.
- **0031 graduated port suppression** is UNBLOCKED: node transitions have one named writer (`InfrastructureTransitions`) and a typed `InfrastructureNodeState` to grow a graduated status behind. Its mechanic is still a USER design call.
- **0036 airborne balance** may proceed as data/balance work; air-state mutation goes through `AirInsertionTransitions`.
- **0041 autoload access** remains independent low-priority filler.

**Standing research caveats:** studies before the landed-only/census corrections over-state Red, and
studies before 0043 will also reflect resurrecting launch-attrition losses. Records remain identified
by commit/version; do not combine pre/post populations without naming the behavior boundary.

## Archived

See [ARCHIVE.md](ARCHIVE.md) for the list of completed and superseded plans, as well as parked refinements.

## Tech Debt & Hygiene

See [BACKLOG.md](BACKLOG.md) for a running list of technical debt, hygiene issues, and refactor observations logged by agents.

## Parked refinements (no plan until a concrete need)

One-liners; detail in `docs/archive/port_audit.md`:

- Flotilla composition nuances (unit of allocation for the missile pipeline — only with 0001).
- Front-line distribution at battalion granularity (with the D5-D draw UI, Track D).
- ShipLoadingModel per-type transport weight + amphibious-vs-cargo eligibility (exact-manifest
  calibration only).
- Deliberately NOT ported (TIV-specific): SQL/DB writeback, mine same-day re-preview baseline,
  Streamlit dashboards — list in `docs/archive/port_audit.md` §Intentionally skipped.
