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

**The structural-hygiene chain is 0057 → 0056; 0055 shipped 2026-07-31 and the order still binds.**
All three are path-keyed. **0055 settled the role vocabulary** — the property-named directory exists
and is **`scripts/interleaved/`**, `scripts/resolvers/` and `scripts/ijfs/` are gone, and
`tools/validate_authority_call_placement.gd` now enforces the checkable half. 0057 applies that
vocabulary to the 40 unclassified files at `scripts/` root, and 0056 freezes the coupling numbers the
layout leaves behind. **0056 must still go last**: seeding its path-keyed ceiling table before 0057
moves files guarantees stale keys — the `KeyError` failure plan 0050 already hit once. **0056 and 0057
were both drafted against the pre-0055 layout and cite paths that no longer exist** (`docs/plans/` is
excluded from the doc-anchor gate, so nothing flagged it); preflight each against the tree before
implementing, which is the standing rule anyway. Each plan states this in its own Sequencing section.

**Plans are ephemeral by contract.** A plan holds the design, the checklist, and progress notes
*while the work is in flight*. It is not a reference: no durable fact may live only in a plan.

**Closeout rule** (enforced by `hexcombat-change-control` / `hexcombat-docs-and-writing`):
a plan is done only when its durable facts have landed in their canonical homes —
`docs/systems/<module>/<module>.md` updated, `docs/systems/<module>/STATUS.md` bullet current,
`hexcombat-failure-archaeology` entry if there was an incident, a 3–5-line `docs/DECISIONS.md`
entry — and the plan file gets a 3-line closeout header and moves to `docs/archive/`. If a future
agent would need to read the plan to act, the closeout wasn't done.

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
| 0029 | [Dynamic ROC defense](0029-dynamic-roc-defense.md) | Medium (research; Tier A policy cheap, Tier B counterattack deep — blocked on 0003 + USER call) | Tier A shipped 2026-07-24 (Red 100%→83.3%); Tier B gated on USER call |
| 0030 | [JLSF first-class cohort (legibility)](0030-jlsf-first-class-cohort.md) | Low (refactor; byte-stable observability — enables 0031) | Sketch |
| 0031 | [Graduated port suppression](0031-graduated-port-suppression.md) | Medium (new mechanic; ROC-only, continuous port capacity, 0%-start default w/ deliberate golden re-baseline + deck refresh, JLSF repair vs off-island fires + IJFS-attritable HIMARS; DataOverrides wiring absorbed as step 0 — design calls settled) | Sketch |
| 0033 | [Brigade organization](0033-brigade-organization.md) | Medium (new mechanic; USER intends to build on it — currently a monotonic decay to zero that nothing reads and the observation misdescribes; design calls open) | Sketch |
| 0035 | [Scenario variant inheritance](0035-scenario-inheritance.md) | Medium (refactor; variants are full copies of the default, so "differs only in X" is unchecked — comparability is the research product) | Sketch |
| 0039 | [One truth about where a battalion is](0039-battalion-location-single-truth.md) | Superseded — a derived ledger cannot catch the historical one-sided transition bug | **Superseded by 0044** |
| 0040 | [CombatRules — stop hand-threading 26 fields](../archive/0040-combatrules-threading.md) | Medium (risk buydown; a field added but not threaded is a silently-inert knob, no gate watches it. Recommended path was the completeness validator ALONE — not the restructure) | **Complete 2026-07-26** — completeness validator shipped; deferred (a)/(b) |
| 0041 | [One pattern for reaching an autoload](0041-autoload-access-one-pattern.md) | Low (ergonomics; the failure is already CAUGHT by validate_tool_script_purity — this makes the correct pattern obvious rather than remembered) | Sketch |
| 0043 | [Anti-ship mutation authority + permanent launch destruction](../archive/0043-antiship-mutation-authority.md) | **High — first vertical slice + USER-ruled permanent launch destruction** | **Complete 2026-07-27** — `AntishipTransitions` sole writer; permanent launch destruction; no pin moved, no rebalance |
| 0042 | [Mutation-authority foundation](../archive/0042-mutation-authority-foundation.md) | **High — establishes the controller/API rule and staged enforcement gate** | **Complete 2026-07-26** — enforcement gate + manifest; anti-ship in migration mode; no production code moved |
| 0044 | [Force mutation authority](../archive/0044-force-mutation-authority.md) | **High — brigades, battalions, manifests, placement; replaces 0039** | **✅ Shipped 2026-07-29** — `ForceTransitions` sole writer |
| 0045 | [Sealift/fleet mutation authority](../archive/0045-sealift-fleet-mutation-authority.md) | High — hull/cohort/pipeline conservation and one writer | **✅ Shipped 2026-07-29** — `SealiftTransitions` sole writer; typed `SealiftCohort`; zero legacy writers; no behavior/RNG/golden change |
| 0046 | [IJFS mutation authority](../archive/0046-ijfs-mutation-authority.md) | High — targets, munitions, squadrons, typed stocks and writeback | **✅ Shipped 2026-07-30** — `IjfsTransitions` sole writer; typed MANPADS stock; zero legacy writers; no behavior/RNG/golden change |
| 0047 | [Map/infrastructure mutation authority](../archive/0047-map-infrastructure-mutation-authority.md) | High — ownership, FEBA, seizure, repair and JLSF lifecycle | **✅ Shipped 2026-07-30** — `MapTransitions` + `InfrastructureTransitions` sole writers; sticky ownership enforced by having no owner setter; zero legacy writers; no behavior/RNG/golden change |
| 0051 | [Destroyed coastal launchers get a last salvo away](0051-destroyed-systems-still-fire.md) | Medium (balance; a ported TIV mechanic that has never once fired — needs a USER dial + a crossing-calibration re-run) | Sketch |
| 0052 | [Legibility sweep: unenforced budget, dead seams, half-finished role layout](../archive/0052-legibility-and-dead-seams.md) | Medium (hygiene; documented parameter budget now enforced; dead seams removed; role directories completed) | **Complete 2026-07-27** — parameter budget enforced; dead seams removed; role directories completed; typed `AntishipResolver` context |
| 0036 | [Airborne cost and sortie cadence](0036-airborne-cost-and-cadence.md) | Medium (balance; USER call 2026-07-25 answering the plan-0032 dial — double baseline attrition + 1 sortie per 2 days;`red_airborne` only, golden untouched, `validate_air_insertion` pin re-baselines) | Sketch |
| 0053 | [Documentation hierarchy refactor (hub-and-spoke)](../archive/0053-doc-hierarchy-refactor.md) | Medium (developer experience; ~85% orientation token reduction) | **✅ Shipped 2026-07-29** — per-module STATUS/RETRO hierarchy; hub-and-spoke |
| 0054 | [Reviewer tiers, one canonical home, one fan-out command](../archive/0054-reviewer-tiers-and-doc-consolidation.md) | Medium (agent workflow; USER tier model + 2-of-3 quorum on plan implementations) | **✅ Shipped 2026-07-30** — `.claude/REVIEWERS.md` canonical; `tools/review_fanout.sh` runs a round; `tools/validate_reviewer_facts.gd` gates one-home + launcher drift |

| 0016 | [Separate State Data from Autoload](0016-separate-state-data.md) | Medium (hygiene/architecture) | Superseded by 0014 |
| 0022 | [Red reactive beach-opening (feasibility first)](0022-red-beach-switching.md) | Medium (research; new mechanic, gated on a feasibility spike) | Sketch |
| 0057 | [Give `scripts/` root a role layout](0057-scripts-root-role-layout.md) | Medium (hygiene; 40 files / 5,864 lines sit outside the role table entirely, so nothing can be wrong about where they are. Path-only but riskier than 0055 — 8 files are bound by path in `.tscn`/`project.godot`, where a miss fails at scene load, not compile) | Sketch |
| 0056 | [Make the coupling budget opt-out](0056-coupling-budget-opt-out.md) | Medium (risk buydown; dependency ceilings police 5 files of 167 because they are opt-in, while the parameter cap is opt-out and universal. Enforces only — fixes no coupling) | Sketch |

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
