---
title: "0059: Make Red's air inventory readable, then let SAM interception drive aircraft off rather than only kill them"
status: "Sketch"
created: "2026-08-01"
updated: "2026-08-01"
---

# Plan 0059: readable air inventory (step 1), SAM interception and return-to-base (step 2)

**Step 1 is ready to implement. Step 2 is blocked on four USER design calls** and is deliberately left
as a design section — it must not be started until those are answered.

## Preflight (2026-08-01) — four claims in the first draft of this plan are already stale

This plan was written earlier the same day and the tree moved under it. `docs/plans/` sits outside the
doc-anchor gate, so nothing flagged any of it. Corrected here:

1. **`IjfsSquadron` has eight fields, not seven.** `losses_campaign` was added in commit `954f124`.
2. **The manifest no longer forbids a `rtb_today` writer.** Its `_doc` said the field "must not gain
   one"; that sentence was rewritten in the same commit and now names this plan as what lifts it. Step
   2 no longer has to argue with the manifest, only update it.
3. **The `losses_today` work listed under "not in scope" is DONE.** It shipped in `954f124`:
   `losses_today` is per-day, `losses_campaign` is the running total, `air_oob_after` is
   `model_version` 4. The sequencing note ("do the ledger change first") is discharged.
4. **The insertion point named for step 1 was wrong.** The first draft said
   `LLMGameAPI._ijfs_observation`. That function is called from exactly one place —
   `LLMGameAPI.observation()` — which is the seat's PLANNING observation, not the turn record. The
   turn record is `TurnResult`. Traced properly in step 1 below.

## What already exists (measured 2026-08-01, not assumed)

The USER asked for "a fixed inventory of aircraft and UAVs that ticks down over time as they suffer
attrition". **That mechanic is already built.**

- `data/ijfs/red_air_oob.json` declares a fixed establishment of **584 airframes** across 11 classes.
  Joining it to `air_classes.json`'s `kind`: **408 manned** (5th/4.5th/4th Gen, J-16D, JH-7, H-6) and
  **176 unmanned** (Stealth ISR, MALE Armed, HALE Armed, HARM, Decoys). Every OOB class resolves to an
  air-classes entry and every air-classes entry is used — no orphans either way.
- `IjfsSquadron.alive` starts at `initial` and only ever decreases. Exactly two writers exist:
  `IjfsLoaders` (establishment, at build) and `IjfsTransitions.apply_squadron_losses` (`alive -= losses`).
  There is no replenishment path anywhere.
- **It ticks down campaign-long, not per turn.** `FiresPhases.resolve_ijfs_turn` rebuilds the IJFS
  state only when the handle is null, and the sole caller of `reset_ijfs_state` is
  `GameState.reset_to_scenario` — a new game. Losses persist across every turn boundary.

**Air losses are also already recorded.** `red_air_losses` — the turn's total across SEAD return fire,
the free shot and MANPADS — reaches the LLM payload and `GameNarrative`, and appears in the example
fixtures. What is NOT readable is the per-squadron breakdown: how many of the 584 remain, by class.

## Step 1 — surface the air order of battle in the turn record (READY)

**USER call 2026-08-01: the turn record**, so research runs can chart Red's force curve across a
campaign.

### The path, traced

`air_oob_after` is built by `IjfsEngine` and returned inside the `ledgers` dict. It then dies twice
over: `TurnConductor` calls `FiresPhases.resolve_ijfs_turn(state, dice)` and **discards the return
value**, and `FiresPhases` itself keeps only `ledgers["summary"]` (onto `state.last_ijfs_summary`) plus
the writeback. `GameState.play_turn` builds the `TurnResult` by reading `data.last_ijfs_summary` and
`data.last_ijfs_writeback` off the state — it never sees the ledger dict.

So the established seam is **phase writes a report onto `GameStateData`; `play_turn` reads it into
`TurnResult`**, and step 1 follows it rather than inventing a second mechanism. Threading the return
value through `TurnConductor` was considered and rejected: it changes two signatures to avoid one
field, and it would make the air OOB the only phase report that does not travel the way its two
siblings do.

### What it costs in the manifest — less than first stated

`GameStateData` is a hosted class with a **closed world**: every mutable field must be either claimed
by an aggregate or classified in `shared_model_policies`, or `E_UNCLASSIFIED_HOSTED_FIELD` fires. The
new field is a report, so it takes `"classification": "phase_output"` with a concrete `why`, exactly
like its siblings `last_ijfs_summary`, `last_ijfs_writeback` and `last_antiship_summary`.

**It does NOT need a real-claims-pin entry.** Only *claimed* fields are pinned — verified: the pin
contains `hosted_fields`/`owned_models` claims and no `shared_model_policies` classifications. (An
earlier note in this plan said otherwise.)

### Checklist

*(Revised after the 2026-08-01 plan-review round — see "Review findings folded in" below. Four items
here changed; do not work from an older copy.)*

- [x] `GameStateData.last_ijfs_air_oob: Dictionary = {}`, cleared in `reset_to_scenario` alongside
      `last_ijfs_summary` / `last_ijfs_writeback`. **Do not add a `GameState` façade property for it** —
      `play_turn` reads `data` directly, so a façade would be pattern-matching the siblings past the
      point where the pattern applies.
- [x] `FiresPhases.resolve_ijfs_turn` stores `ledgers["air_oob_after"]` onto it, **deep-copied** —
      `ledgers` is returned to the public `GameState.resolve_ijfs_turn`, so retaining the reference
      would let a caller mutate campaign-record state through it (diff review). **`null` asserts.**
      `IjfsStateBuilder` unconditionally sets `state.squadron_force`, so a null force here is a broken
      invariant; `push_error` alone would log and then publish a record that merely looks empty, and
      the caller cannot rescue it because `TurnConductor` discards this function's return.
- [x] `IjfsEngine`'s squadron row gains `"kind"` (manned/unmanned) read from the air-classes table,
      so aircraft and UAVs are separable without the consumer re-deriving the join. **Hard-indexed,
      not `get`-with-default** — no `dict.get(key, default)` across this boundary (non-negotiable #2;
      the exquisite-intel incident), and a missing class asserts.
- [x] **Keep `model_version` at 4 — do NOT bump to 5.** `kind` is additive and backward-compatible,
      unlike the 3→4 bump, whose recorded rationale was that `losses_today` *changed meaning*. The
      decisive point: no v4 `air_oob_after` payload has ever been persisted anywhere (it reaches no
      fixture, record or API today), so there is no v4 consumer that a silently-widened row could
      mislead. If the project ever wants "every additive revision bumps", that is a policy to state
      once, not to invent here.
- [x] **There are TWO pins on this version, and the earlier draft named only one:**
      `tools/validate_headless_ijfs.gd` and `tests/ijfs/ijfs_engine_test.gd`. Since the version stays
      at 4 neither pin moves — but the GdUnit row-shape assertion in the latter must grow `kind`.
- [x] `TurnResult` gains `air_oob: Dictionary` + its `to_dict()` key; `GameState.play_turn` populates
      it from the state field.
- [x] **Add `air_oob` to `schemas/llm_action_result.schema.json`** under `turn_result.properties`.
      Missing this would pass every existing check silently: the top level is
      `"additionalProperties": true` and `tools/validate_llm_api.gd` only checks top-level result keys.
- [x] `shared_model_policies` entry for the new `GameStateData` field, `"classification": "phase_output"`.
- [x] GdUnit: the OOB reaches `TurnResult.to_dict()`; `initial`/`alive`/both loss counters/`kind` are
      present. End-to-end proof lives in `tools/validate_play_turn.gd`, which checks row SHAPE and not
      row COUNT — a future no-air scenario legitimately carries `squadrons: []`, and asserting
      non-empty would make that validator quietly scenario-dependent (diff review).
- [x] Regenerate `docs/examples/llm_result_after_turn.json` via `tools/LLMFixtures.gd`; diff to confirm
      only the new keys moved. **Measured: 281 insertions, 0 deletions, every added key inside the new
      `air_oob` block; independently reproduced by a second reviewer.**

**Correction to a claim this plan repeated three times:** a wiped-out force does NOT serialize as
`squadrons: []`. Attrition only ever does `alive -= losses` and the ledger appends every squadron, so
total destruction is 25 rows with `alive: 0` — which keeps each squadron's campaign history and is the
better record. `squadrons: []` means an establishment with no squadrons at all, which only a no-air
scenario would produce. Separately, `{}` means "no turn has resolved yet" and nothing more:
`begin_next_turn` does not clear the field, so during a planning phase it still holds the previous
turn's ledger.

### Verification

- **No golden re-baseline.** Nothing consumes RNG and no behaviour changes — `validate_headless_turn`
  must stay byte-stable. If it moves, the change is wrong.
- **The fixture-drift phase WILL fire** on `llm_result_after_turn.json`, because `turn_result` grows.
  That is intended contract growth: review the diff, then commit the regenerated JSON.
- Full `bash tools/run_all_tests.sh` → ALL PHASES GREEN.

### What step 1 does and does not give the seat

**Corrected by the review round — the first draft of this section was wrong.** It claimed an LLM seat
would see the OOB in its post-turn feedback "for free". It will not, in this repository:

- `SelfPlayRunner` calls each policy through `_seat_actions`, which passes only
  `LLMGameAPI.observation(perspective_team)`. The action result is appended to `turn_digests` and
  **never fed back to a policy**. `LLMPolicy`'s only entry point is `build_actions(observation)`.
- `LLMGameAPI._action_result` does return `turn_result` to a *direct* API caller, so an external agent
  driving the API by hand would see it — but no seat in this repo consumes that path.

So step 1 delivers exactly what the USER asked for and nothing more: **the research record**, via
`turn_digests`. That is coherent for charting a force curve. It is NOT a step toward an LLM seat
planning around its own attrition — that needs the OOB in `_ijfs_observation`, which is deliberately
out of scope here.

### Review findings folded in (round 1, 2026-08-01)

Three reviewers, all substantive; agy re-measured all seven premises and returned CONFIRMED on every
one, so the preflight held. What changed above came from the other two:

1. **The seat-visibility claim was false** (Sol) — corrected in the section above, verified against
   `SelfPlayRunner._seat_actions` and `LLMPolicy`.
2. **`null` → `{}` was the wrong design** (Sol) — now fails loud, with the empty-force payload spelled
   out.
3. **The action-result schema was missing from the checklist** (Sol) — now a step. Measured further
   while confirming it: **the schema has ALREADY drifted from `TurnResult`** — `air_insertion_summary`,
   `mobilization_summary`, `offload_summary`, `game_over` and `winner` are all declared on the model and
   absent from the schema, and nothing gates the pair. Logged to `docs/plans/BACKLOG.md`; not fixed here,
   because repairing five pre-existing omissions is not this plan's work.
4. **`model_version` should stay at 4, and there are two pins not one** (Sol; the second pin
   independently enumerated by DeepSeek) — both folded into the checklist.
5. **The seam choice survived** (Sol), with a caveat now recorded: unlike `last_ijfs_summary` and
   `last_ijfs_writeback`, which later phases genuinely consume, the new field has **no later-phase
   consumer** — it is transport-only shared state. Sol's stronger alternative was neither this nor
   threading one value, but a typed turn-resolution outcome carrying *all* phase reports. That is a
   real improvement and explicitly out of scope for step 1; if it is ever done, this field folds into it.

## Step 2 — SAM interception and return-to-base (BLOCKED)

### The asymmetry that makes this coherent

All three air-attrition paths are binary — an airframe is killed or untouched. There is no damaged,
aborted or mission-killed state anywhere:

| Path | Where | Draw |
|---|---|---|
| SEAD return fire | `IjfsEngagement._sead_return_fire` | one Bernoulli per alive airframe → `apply_squadron_losses` |
| Post-phase-2 free shot | `IjfsEngagement.apply_post_phase_2_free_shot` | same shape |
| Island-wide MANPADS | `IjfsManpads.contest_squadrons` | same shape |

An engaged SAM target has **three** outcomes — destroyed, suppressed, or unengaged
(`IjfsEngagement._engage_sam_target`: a destroy roll, then a suppression roll only if it survives). An
engaged aircraft has **two**. RTB is the missing third outcome and the mirror of suppression: the
airframe survives but stops contributing today. That symmetry is why this is a mechanic rather than a
bolt-on, and it is the shape the implementation should follow.

### The four design calls — USER, before any code

1. **What does RTB cost?** Natural reading: aborted the sortie, alive, unavailable for the rest of
   today, back tomorrow — a strike-capacity effect with no campaign attrition. Alternatives:
   unavailable for N days (battle-damage repair), or a follow-on chance of being written off.
2. **Does an aborting aircraft still contribute to SEAD?** Organic strike capacity is computed from
   the aircraft that survived SEAD, so an airframe that aborts during return fire has already flown
   its SEAD leg but is gone for the strike leg. Probably the realistic answer; it should be a decision,
   not an accident of where the roll sits.
3. **How likely is an abort relative to a kill?** Symmetric with suppression would be
   `p_rtb = p_loss * RTB_FACTOR`, `RTB_FACTOR > 1` — being driven off is commoner than being downed.
   The USER dials it.
4. **Do all three sources produce aborts?** MANPADS at low altitude plausibly yields more aborts and
   fewer kills than a long-range SAM. One shared factor is simpler; per-source factors are more
   expressive.

### Scope once unblocked

- A per-day availability concept distinct from `alive` — "alive but not flying today" does not exist.
  New field vs derived `alive - rtb_today` is an implementation call for the plan-review round.
- Give `rtb_today` a writer in `IjfsTransitions`, and update the manifest `_doc` that currently points
  here as the plan that lifts the no-writer rule.
- Draw the abort in whichever paths call (4) selects. **A new roll inserted mid-sequence changes every
  subsequent draw** — draw order is stated three times in `IjfsEngagement` as the port's contract — so
  a golden re-baseline is expected and unavoidable, not a smell.
- Reset `rtb_today` per day in `IjfsTransitions.carry_to_next_day`, which already resets `losses_today`.

### Verification once unblocked

- Golden re-baseline justified, not assumed: show the diff is confined to what the mechanic explains,
  and re-run the crossing/campaign studies that depend on Red air strength before treating any prior
  number as comparable.
- GdUnit: an abort leaves `alive` unchanged; `rtb_today` resets across a day boundary while
  `losses_campaign` does not; and **with the RTB factor at zero the game is byte-identical to today** —
  the cleanest proof the mechanic is off by default.

## Not in scope

- Aircraft repair/replacement pipelines. RTB returns an airframe to availability; it does not model a
  maintenance queue.
- Rebalancing SAM lethality. If aborts make air attrition feel wrong, that is a dial the USER turns
  afterwards, on evidence.
- Surfacing the OOB in the seat's PLANNING observation (see step 1's closing note).

## Dependencies / notes

- **The Python oracle is not on this box.** `IjfsEngagement` is a port of `ijfs_standalone/engagement.py`,
  and RTB does not exist upstream — a deliberate divergence, which per `hexcombat-wargame-domain-reference`
  means the port's oracle stops being the arbiter for this path. Record it in the closeout so a future
  agent checking against upstream does not read it as drift.
- Naming caution from plan 0046: a **generic protected field name poisons the whole repo** —
  `IjfsMunition.name` produced 22 false gate failures. If step 2 adds a field, do not call it `available`.
- Related: [[0036-airborne-cost-and-cadence]] also dials air attrition and cadence; if both are in
  flight, sequence them so only one moves the air pins at a time.
