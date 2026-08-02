---
title: "0030: JLSF as a first-class, labeled cohort — make logistics competition observable"
status: "Sketch"
created: "2026-07-24"
---

# Plan 0030: JLSF first-class cohort (legibility)

## Golden-pin budget

none

## Motivation (found 2026-07-24)

Investigating the port-neutralization result ([[0028-sustained-followon-interdiction]] "Q2 re-run")
surfaced a **crowding-out** effect: `auto_jlsf` logistics cargo shares the scarce, attritable
crossing + capacity-limited offload pipeline with combat battalions and adds no combat census, so
turning the port on can *lower* the PLA's landed combat strength. That effect was nearly invisible —
JLSF cargo travels as **pseudo-entries** through `SealiftResolver` (carry a `cargo` marker; see
`SealiftResolver` ~L198) and never surfaces in any per-turn digest. The only way to find it was to
trace census across seeds by hand.

**Goal (USER 2026-07-24, "legibility/observability"):** make JLSF a first-class, *labeled* cohort
that shows up distinctly in the digests, so logistics-vs-combat pipeline competition is directly
readable in a game record and testable. **Behavior-preserving — golden byte-stable.**

## Scope

- Tag JLSF cohorts through the crossing/offload pipeline so they are distinguishable from combat
  BNs at every stage they already pass through (`JlsfCargo` → `SealiftResolver` sent/offloading
  cohorts → offload drain).
- Surface JLSF as its own line in the per-turn digests: `offload_summary` (e.g. `jlsf_bns_landed`,
  `jlsf_bns_waiting`) and `antiship_summary` (e.g. `jlsf_bns_lost_at_sea`), separate from the
  combat-BN counts — so a reader sees "N combat BNs and M JLSF logistics BNs competed for the
  crossing/offload this turn."
- No change to *what happens* — only to *what is recorded*. The cohort routing, dice draws, and
  victory census are untouched.

## Not in scope

- Changing JLSF's pipeline competition, attrition, or the repair gate (that is balance work; if the
  USER later wants JLSF to stop crowding out combat power, that is a separate design plan).
- Splitting `auto_jlsf`'s two jobs (spawn lift vs gate repair) into separate knobs — related but
  distinct; only do it if [[0031-graduated-port-suppression]] needs the repair job addressable on
  its own (0031 makes repair JLSF-driven, so the split may fall out there).

## Objectives

1. A cohort-level `cargo`/`kind` label that reaches the digest builders; JLSF vs combat is a first-
   class distinction, not an inferred one.
2. Additive JLSF fields in `offload_summary` / `antiship_summary`; a reader (and a metric extractor)
   can separate logistics tonnage from combat tonnage per turn.
3. GdUnit coverage: a game with `auto_jlsf` on shows a nonzero JLSF line in a digest and the combat-
   BN line excludes it; with `auto_jlsf` off the JLSF line is zero/absent.

## Verification

- **Golden byte-stable**: victory outcome and dice-consuming logic untouched, so
  `validate_golden_victory` stays byte-stable. The digest additions change the *record* JSON, so a
  fixture re-baseline is allowed for the new fields **only** (additive, like [[0003-combat-summary-team-attribution]]'s
  team-stamp) — diff the fixture to confirm nothing but the new JLSF fields moved.
- New GdUnit asserting the JLSF/combat split in the digests both on and off.
- Full `run_all_tests` green.

## Dependencies / notes

- Enabler for [[0031-graduated-port-suppression]] (repair is JLSF-driven — being able to see JLSF
  flow makes the port tug-of-war debuggable) and cleanly separable from [[0032-airborne-insertion]].
- Related tooling already reuses `sweep_metrics`; a JLSF-vs-combat digest split lets a future metric
  quantify crowding-out directly instead of by census subtraction.
