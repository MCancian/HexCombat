---
title: "0059: Make Red's air inventory readable, then let SAM interception drive aircraft off rather than only kill them"
status: "Sketch"
created: "2026-08-01"
---

# Plan 0059: SAM interception and return-to-base

## Motivation (USER call 2026-08-01)

Triaging `docs/plans/BACKLOG.md` surfaced `IjfsSquadron.rtb_today` — a field reported in the
`air_oob_after` ledger every turn as a constant `0`, because **nothing has ever written it**. The
USER's call was not "delete it": *"Some amount of aircraft should be RTB due to SAM interception. We
should have a separate plan to look at the SAM calculator and, if that's not involved, to build it."*

**It is not involved. Measured 2026-08-01, all three air-attrition paths are binary — an airframe is
either killed or untouched.** There is no damaged state, no abort, no mission-kill anywhere in the
IJFS chain:

| Path | Where | Draw |
|---|---|---|
| SEAD return fire | `IjfsEngagement._sead_return_fire` | one Bernoulli per alive airframe → `apply_squadron_losses` |
| Post-phase-2 free shot | `IjfsEngagement.apply_post_phase_2_free_shot` | same shape |
| Island-wide MANPADS | `IjfsManpads.contest_squadrons` | same shape |

All three land in `IjfsTransitions.apply_squadron_losses`, which does `squadron.alive -= losses`.
`_bernoulli_count` returns a kill count and nothing else.

**The asymmetry is the design opening.** A SAM target that gets engaged has *three* outcomes —
destroyed, suppressed, or unengaged (`IjfsEngagement._engage_sam_target`: a destroy roll, then a
suppression roll only if it survived). An aircraft that gets engaged has *two*. RTB is the missing
third outcome on the aircraft side, and it is the mirror of suppression: the airframe survives, but
it stops contributing today. That symmetry is the reason this is a coherent mechanic rather than a
bolt-on, and it is the shape the plan should follow.

## The fixed air inventory already exists — what is missing is reading it (USER 2026-08-01)

The USER asked for "a fixed inventory of aircraft and UAVs that ticks down over time as they suffer
attrition". **Measured 2026-08-01: that mechanic is already built and has been all along.**

- `data/ijfs/red_air_oob.json` declares a fixed establishment — **584 airframes** across 11 classes:
  408 manned (5th/4.5th/4th Gen, J-16D, JH-7, H-6) and 176 unmanned (Stealth ISR, MALE Armed, HALE
  Armed, HARM, Decoys). `air_classes.json` already carries the `kind: manned | unmanned` split, so
  aircraft and UAVs are distinguishable today without new data.
- `IjfsSquadron.alive` starts at `initial` and only ever decreases — `IjfsTransitions.apply_squadron_losses`
  is the sole writer and there is no replenishment path anywhere.
- **It ticks down for the whole campaign, not per turn.** `FiresPhases.resolve_ijfs_turn` rebuilds the
  IJFS state only when the handle is null, and the only caller of `reset_ijfs_state` is
  `GameState.reset_to_scenario` — a new game. Losses therefore persist across every turn boundary.

So this plan must NOT build an inventory. What it must add is the **surface**: today the standing
inventory cannot be read. `red_air_losses` (this turn's total, all sources) does reach the LLM payload
and the narrative, but the per-squadron order of battle — how many of the 584 remain, by class —
lives in `air_oob_after`, which `FiresPhases` drops on the floor: it keeps `ledgers["summary"]` and
nothing consumes the rest except `tools/validate_headless_ijfs.gd`. `grep air_oob_after
docs/examples/*.json` is empty.

**This is step 1 of the plan, and it comes before the mechanic.** RTB adds a third number to that
ledger, and a mechanic whose effect cannot be observed cannot be dialled — the USER would be tuning
an abort rate blind. Surfacing it should report at least `initial`, `alive` and both loss counters per
squadron, and should preserve the manned/unmanned split so "aircraft" and "UAVs" can be read
separately rather than summed.

**SURFACE DECIDED (USER 2026-08-01): the turn record.** So research runs can chart the force curve
across a campaign. Traced to its concrete insertion point, with three consequences worth knowing
before implementation:

1. **The turn record IS `turn_result`.** `SelfPlayRunner` builds `turn_digests` by appending
   `result["turn_result"]` per turn, and that is the dict `LLMGameAPI` assembles — the same one
   captured in `docs/examples/llm_result_after_turn.json`. So the insertion point is the IJFS block of
   that dict, built by `LLMGameAPI._ijfs_observation`.
2. **It reaches the seat's post-turn feedback for free, but NOT its planning observation.**
   `_ijfs_observation` feeds both the result and the observation payloads, so the OOB will appear in
   what a seat is told after a turn resolves. The planning-time observation is a separate document; if
   the USER later wants a seat to plan around its own remaining airframes, that is a further decision,
   not something this step silently grants.
3. **`FiresPhases` must start retaining the ledger, which is a state decision, not a formatting one.**
   `resolve_ijfs_turn` currently keeps only `ledgers["summary"]` on `state.last_ijfs_summary` and drops
   the rest; `_ijfs_observation` can only read what is on the state. So step 1 needs a new
   `GameStateData` field holding the air OOB — which makes it a **mutation-manifest decision** with a
   real-claims pin entry, exactly like `IjfsSquadron.losses_campaign` was. Budget for that; it is the
   step's only non-trivial part.

**Correction to this plan's earlier claim that step 1 needs no re-baseline:** no GOLDEN re-baseline —
nothing consumes RNG or changes behaviour — but `turn_result` grows, so
`docs/examples/llm_result_after_turn.json` WILL move and the gate's fixture-drift phase will fire.
That is intended contract growth: regenerate via `tools/LLMFixtures.gd` and commit the result, having
diffed it to confirm only the new keys moved.

## The design calls — USER, before implementation

These are game questions, not technical ones, and the plan cannot be specified without them.

1. **What does RTB cost?** The natural reading is "aborted the sortie: alive, unavailable for the
   rest of today, back tomorrow." That makes RTB a *strike-capacity* effect with no campaign
   attrition. Alternatives: RTB aircraft are unavailable for N days (battle damage repair), or RTB
   carries a follow-on chance of being written off.
2. **Does an aborting aircraft still contribute to SEAD?** Ordering matters. Organic strike capacity
   is computed from the aircraft that survived SEAD (`IjfsEngine`, "Organic strike capacity depends
   on the aircraft that survived SEAD, so it is only known here"). If RTB is drawn during SEAD
   return fire, an aborting airframe has already flown its SEAD leg but is gone for the strike leg.
   That is probably the realistic answer; it should be a decision, not an accident of where the roll
   is placed.
3. **How likely is an abort relative to a kill?** SAM suppression uses `p_suppress = p_destroy *
   SUPPRESSION_FACTOR`. The symmetric answer is `p_rtb = p_loss * RTB_FACTOR` with `RTB_FACTOR > 1`
   — being driven off is more common than being shot down. The USER dials the factor.
4. **Do all three attrition sources produce RTB, or only some?** MANPADS at low altitude plausibly
   produces more mission-aborts and fewer kills than a long-range SAM; the free shot may be a
   different case again. One shared factor is simpler; per-source factors are more expressive.

## Scope

- **Step 1 — surface the air order of battle in the turn record** (see the section above): the
  standing inventory becomes readable, manned and unmanned separable. Additive; no mechanic change;
  lands on its own and is useful before any RTB work starts. Carries a `GameStateData` field, a
  manifest entry + real-claims pin, and an additive fixture regen.
- A per-day availability concept distinct from `alive`. `IjfsSquadron` currently has exactly six
  fields — `squadron_id`, `aircraft_class`, `role`, `initial`, `alive`, `rtb_today`, `losses_today`
  (seven) — and `alive` is the only strength number. RTB needs "alive but not flying today", which does not
  exist yet. Whether that is a new field or a derived `alive - rtb_today` at the read sites is an
  implementation call for the plan-review round.
- Give `rtb_today` a writer in `IjfsTransitions`, alongside `apply_squadron_losses`.
- Draw the abort in whichever engagement paths call (4) selects, preserving draw order — **the RNG
  contract is that draw order is the port's contract** (stated in `IjfsEngagement` three times). A
  new roll inserted mid-sequence changes every subsequent draw, so a golden re-baseline is expected,
  not avoidable.
- Reset `rtb_today` per day in `IjfsEngine.carry_to_next_day` (or `IjfsTransitions.carry_to_next_day`,
  which currently touches targets only), unlike `losses_today`.
- Update the mutation manifest. `tools/mutation_authority_manifest.json` currently carries an
  explicit prohibition in the `IjfsSquadron` `_doc`: *"rtb_today has no runtime writer at all and
  must not gain one."* That sentence was correct when written and this plan lifts it; leaving it
  would make the manifest contradict the code. The characterization tests it names
  (`tests/ijfs/ijfs_authority_characterization_test.gd`) pin the current constant-0 behaviour and
  must be changed deliberately, not deleted.

## Not in scope

- The `losses_today` ledger change decided in the same 2026-08-01 triage (report both per-day and
  campaign-cumulative losses). It is a separate, smaller unit of work with its own golden
  re-baseline, and it must not ride on a mechanic change — see BACKLOG. If both land, do the ledger
  change first so this plan's re-baseline is the only behavioural one.
- Aircraft repair/replacement pipelines. RTB returns an airframe to availability; it does not model
  a maintenance queue.
- Rebalancing SAM lethality. If adding aborts makes air attrition feel wrong, that is a dial the
  USER turns afterwards, on evidence.

## Verification

- **Golden re-baseline is expected and must be justified, not assumed.** Any new `dice` draw shifts
  the stream. Follow `hexcombat-change-control`'s re-baseline rules: show the diff is confined to
  what the mechanic explains, and re-run the crossing/campaign studies that depend on Red air
  strength before treating any prior number as comparable.
- New GdUnit coverage asserting: an abort leaves `alive` unchanged; `rtb_today` resets across a day
  boundary while `losses_today` does not; and with the RTB factor at zero the game is byte-identical
  to today (the cleanest proof the mechanic is off by default).
- Full `bash tools/run_all_tests.sh` → ALL PHASES GREEN.

## Dependencies / notes

- **The Python oracle is not on this box.** `IjfsEngagement` is a port of
  `ijfs_standalone/engagement.py`, and RTB does not exist upstream — this is a deliberate divergence
  from the ported model, which per `hexcombat-wargame-domain-reference` means the port's oracle
  stops being the arbiter for this path. Record that in the plan's closeout so a future agent
  checking against upstream does not read it as drift.
- Naming caution from plan 0046: a **generic protected field name poisons the whole repo** —
  `IjfsMunition.name` produced 22 false gate failures. If this plan adds a field, do not call it
  `available`.
- Related: [[0036-airborne-cost-and-cadence]] also dials air attrition and cadence; if both are in
  flight, sequence them so only one moves the air pins at a time.
