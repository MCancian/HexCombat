---
title: "0050: Mutation-authority enforcement and campaign closeout"
status: "✅ Shipped"
created: "2026-07-26"
preflighted: "2026-07-31"
shipped: "2026-07-31"
---

# Plan 0050: Mutation-authority enforcement and campaign closeout

## Goal

Close the mutation-authority campaign (0042–0049): resolve the three `GameStateData` fields no
aggregate owns, prove by an **independent source sweep** that the manifest is not the only thing
saying the tree is clean, delete the seams the campaign made dead, and land the durable facts in
their canonical homes so plans 0042–0050 can be archived.

This is an audit/closeout plan. Anything needing substantive migration gets a focused follow-up
plan rather than being hurried in here.

---

## Preflight (2026-07-31) — what the Sketch claimed vs what the tree holds

The Sketch was written 2026-07-26, before 0044–0049 shipped. **Six of its eight "Enforcement
hardening" items are already true**, measured below. Recorded so the implementation does not spend
effort re-proving them and so a reviewer can falsify the claim rather than re-derive it.

| Sketch item | Measured state | Verdict |
|---|---|---|
| 1. Remove all `temporary_legacy_writers` | `legacy_writers` is `[]` for **all 10** aggregates (`python3 tools/mutation_ownership.py --writers`) | **already done** |
| 2. Make any warning/report mode a hard failure | No warn/report/advisory mode exists in `tools/validate_mutation_authority.gd`; every code path is `_fail` | **no such mode** |
| 3. New mutable fields must be classified before the gate passes | `shared_model_policies` closed-world shipped 2026-07-30 (`E_UNCLASSIFIED_FIELD`, `E_UNCLASSIFIED_HOSTED_FIELD`) | **already done** |
| 4. Dead model/controller paths and zero-match scans fail | `E_DEAD_PATH`, `E_DEAD_FIELD`, `E_DEAD_EXCLUSION`, `E_VACUOUS` (7 distinct sites) all present and fixture-proven | **already done** |
| 6a. …with **one exception** | `E_STALE_ALLOWANCE` has a single emission site (`_report_stale_allowances`) and **no proof surface at all** — no `bad_manifest_*` fixture, no `_capture_failures` perturbation. `docs/plans/BACKLOG.md:33-42` already owns this with the reason the existing harness cannot host it | **open, backlogged — not fixed here** |
| 5. Abstract FORM fixtures + generated real-claim pass on every run | Present; `E_REAL_CLAIM_PIN` compares the pin by aggregate/section/`Class.field` | **already done** — this plan only adds the new claims to the pin |
| 6. Fail on unregistered `scripts/transitions/` file, stale allowance, conflicting ownership, vacuous scan | `E_UNREGISTERED_AUTHORITY_FILE`, `E_STALE_ALLOWANCE`, `E_DUPLICATE_CLAIM`, `E_VACUOUS` all emit | **checks present** (proof surface: see 6a) |
| 7. Linux and Windows runners invoke the same authority validator | `tools/run_all_tests.sh` and `.ps1` both `exec` `tools/run_all_tests.py`, which **glob-discovers** `tools/validate_*.gd` (line 108). Neither names a validator | **already true, structurally** |
| 8. Measure validator runtime | **1.79 s** wall (`HEXCOMBAT_SCENARIO=scenario_golden`, flatpak Godot 4.7, Linux box) | **measured; fine** |

Two more Sketch premises corrected:

- **"Remove `scripts/resolvers/` when no mixed file remains" is not reachable here.** Seven files
  still hold per-phase logic that writes campaign state (`CleanupResolver`, `CombatResolver`,
  `FrontlineResolver`, `IjfsResolver`, `InfrastructureResolver`, `OffloadResolver`, and —
  conditionally — `AntishipResolver`). The directory's claim is honest today; emptying it is a
  separate refactor, not a closeout.
- **The role-purity check on the other four directories passes.** Measured by scanning every
  `x.field = …` where `field` is a protected symbol: `scripts/calc/` writes **nothing** protected
  (its two hits are onto a freshly-constructed `AirInsertionResolutionPlan`);
  `scripts/builders/` writes only through registered construction allowances;
  `scripts/transitions/` holds only authority files. `scripts/phases/` has **two** writes to a field
  that is protected *today* (`state.sealift_state = …`, `ReinforcementPhases.gd:125,127`) and **four
  more** to the two fields this plan promotes (`FiresPhases.gd:123,168`,
  `ReinforcementPhases.gd:151,183`). All six move in steps 1–2; after them `scripts/phases/` writes
  no protected field at all.

### What 0050 actually inherits

`python3 tools/mutation_ownership.py --plan 0050` prints three `GameStateData` fields classified
`planned_transitional` and pointing at this plan. They are the whole of the inherited migration:

| Field | Production writers (`file:line`) | Proposed owner |
|---|---|---|
| `sealift_state` | `GameState.gd:65` (façade setter, **zero callers**), `GameState.gd:322` (`_rebuild_sealift_state`), `ReinforcementPhases.gd:125,127` (temporary-sealift swap) | **`sealift_fleet`** |
| `lost_at_sea_accumulator` | `GameState.gd:109` (façade setter, **zero callers**), `GameState.gd:186` (reset), `FiresPhases.gd:123` | **`sealift_fleet`** |
| `pending_lost_at_sea` | `GameState.gd:75` (façade setter, **zero callers**), `GameState.gd:178` (reset), `FiresPhases.gd:139→167` , `ReinforcementPhases.gd:151,183` (read-then-zero) | **`sealift_fleet`** |

Why those owners:

- `sealift_state` is the **exact shape of `air_insertion_state`** (plan 0048): a handle whose model
  is split between two aggregates — `SealiftState.mainland_pool`/`cohorts` belong to `force`,
  `return_pipeline`/`escort_*` to `sealift_fleet`. 0048 settled that the *handle* goes to the
  aggregate the model is named for. Its three siblings `fleet`, `ijfs_state`,
  `infrastructure_state` are already claimed; this is a straight asymmetry, not a design question.
- Both `lost_at_sea` fields are **the BN-equivalent conversion of the crossing's HULL losses**.
  `bn_equiv_lost` is `ShipLoadingModel` applied to the hulls the crossing destroyed, and the
  accumulator is that same conversion's fractional remainder carried across turns. The authority
  that already books those hull losses is `SealiftTransitions.apply_hull_losses`, so this is its
  ledger, not the launcher inventory's.

  **This changed at plan review.** The first draft gave them to `antiship_establishment` because the
  producing phase is anti-ship. The tier-1 reviewer refuted it on a measurement I confirmed:
  `AntishipTransitions` is **ABSENT** from `ReinforcementPhases.gd`, whose dependency ceiling is
  **exactly full at 22** (`tools/gd_metrics.py:67`), so putting `consume_ship_losses` there costs a
  23rd dependency and cannot pass the gate. `SealiftTransitions` is already a dependency of **both**
  coordinators (`ReinforcementPhases.gd:59,65,66,100,176,179` and `FiresPhases.gd:128-138`), so the
  migration costs zero new dependencies anywhere. The cheaper owner is also the more accurate one.

### New finding the Sketch did not know about

**`AntishipResolver.remaining_reserve_after_losses` is dead in production.** The independent source
sweep (below) found exactly one alias-rooted write into a protected container that the gate cannot
see — `AntishipResolver.gd:283`, `entry["bns"] = surviving`, where `entry` is an untyped Dictionary
iterated out of the caller's `ship_reserve` (owned by `force`). Its only remaining caller anywhere
in the repo is `tests/antiship_resolver_test.gd:49`. Production replaced it with
`ForceTransitions.apply_crossing_loss` (`FiresPhases.gd:114`), which does the same pruning as a
preflighted all-or-nothing transaction.

That function is also the **sole documented reason** `AntishipResolver` lives in `scripts/resolvers/`
rather than `scripts/calc/` — its own header says so at lines 17–20.

`docs/archive/0052-legibility-and-dead-seams.md` rejected *moving* this function into
`RosterMutations`, on the grounds that plan 0045 would immediately move it again. 0045 has since
shipped, `RosterMutations` no longer exists, and **deleting** it was never the rejected option. This
is a new conclusion, not a re-fight.

---

## Definition of done for the campaign

For every mutable aggregate in the plan-0042 inventory:

1. one exact authority file/class is named in `tools/mutation_authority_manifest.json`;
2. protected state has no production writer outside that exact authority;
3. builders initialize only fresh unpublished state through the authority or an explicitly
   sanctioned construction API;
4. calculators/resolvers do not mutate protected campaign state;
5. cross-aggregate coordinators use typed requests/receipts and prove matching deltas;
6. local validation runs before the authority returns;
7. a deliberate unauthorized mutation has made the gate fail;
8. current behavior and data flow are documented in canonical homes.

Items 1–3 and 5–7 are satisfied by 0042–0049 plus the preflight table above. **Item 4 is satisfied
by step 2 of this plan; item 8 by step 6.**

---

## Implementation steps

Each step is one commit. Every step ends with `bash tools/run_all_tests.sh` → **ALL PHASES GREEN**.
No pin may move: every step here is a byte-stable refactor.

### Step 1 — `sealift_state` and the crossing ledger join `sealift_fleet`

`GameState.gd` is at **29/29** and `ReinforcementPhases.gd` at **22/22**, so every edge below is
routed to cost zero new dependencies. That constraint is why the shapes are what they are.

1. `SealiftTransitions` gains five narrow edges:
   - `install_campaign_state(state, built: SealiftState)` — scenario reset: publish the handle
     **and** clear the crossing ledger. One transition, because a fresh campaign sealift with last
     scenario's drowned-BN count is not a state the game can be in.
   - `swap_state(state, replacement: SealiftState) -> SealiftState` — replaces the handle and
     **returns the previous one**, for the temporary-sealift façade. Ledger untouched.
   - `record_crossing_carryover(state, accumulator: float)` — replaces `FiresPhases.gd:123`.
   - `register_ship_losses(state, bn_equiv_lost: int)` — replaces the body of
     `FiresPhases.register_ship_losses`, which disappears (its only caller is `FiresPhases.gd:139`).
   - `consume_ship_losses(state) -> int` — returns the pending value **and zeroes it**, replacing
     the read-then-zero pairs at `ReinforcementPhases.gd:149-151` and `182-183`. Read-with-clear is
     deliberate and matches `SealiftTransitions.tick_returns` and `ForceTransitions.free_emptied_cohorts`
     (both mutate and return); splitting it would permit a forgotten or duplicated consumption.
2. `ReinforcementPhases.install_sealift_state(state, built)` — a thin pass-through, the same shape as
   `FiresPhases.reset_ijfs_state`, so `GameState` reaches the sealift state **through** the phase
   module rather than naming `SealiftTransitions` itself (which it cannot afford).
   `GameState._rebuild_sealift_state` keeps the `GameStateBuilder.build_sealift_state(...)` call —
   both names are already dependencies there — and hands the result to it.
3. `ReinforcementPhases.resolve_unopposed_offload_turn` uses `swap_state` both ways.
4. `GameState.reset_to_scenario` lines **178** and **186** are deleted, not rerouted: the ledger
   clear now rides on `_rebuild_sealift_state()` at line 169. Verified safe — lines 170–186 rebuild
   fleet/supply/infrastructure state, reset the IJFS handle and clear five summaries; **nothing in
   that window reads either scalar**, and no signal or callback fires in it.
5. **Delete** the `GameState.sealift_state`, `pending_lost_at_sea` and `lost_at_sea_accumulator`
   setters (zero callers each; a forwarding setter is a public door the scan cannot see, because the
   receiver resolves to `GameStateType`). Add the read-only façade comment their siblings carry.
6. Manifest: move all three fields out of `shared_model_policies` into `sealift_fleet`'s
   `hosted_fields`, lifetime `campaign` for each — `pending_lost_at_sea` is **not** `transient`
   because it survives a turn in which no wave crosses (`FiresPhases.gd:107`). Widen the aggregate
   `summary` to say it owns the crossing's BN-equivalent ledger. Update the real-claim pin.
7. **Characterization tests first**, per `docs/systems/mutation-authority/mutation-authority.md:54`:
   `tests/transitions/sealift_transitions_test.gd` gains install/reset, swap-returns-previous,
   carryover recording, negative-loss clamping, and **consume-then-consume-again returns 0**.

### Step 2 — the dead crossing-prune seam goes, and `AntishipResolver` becomes a calculator

1. **Delete `AntishipResolver.remaining_reserve_after_losses`.** Zero production callers; superseded
   by `ForceTransitions.apply_crossing_loss`.
2. **Port its coverage before deleting the test.** `ForceTransitions.gd:794` carries the identical
   `entry["bns"] = surviving` prune, but `tests/transitions/force_transitions_test.gd:760` only
   covers an entry whose *sole* BN is removed. Move the deleted test's **mixed** case — one entry
   keeps a surviving BN while another is emptied and dropped — into that suite. The behaviour was
   relocated, not removed, so the coverage moves with it.
3. **Move `AntishipResolver` to `scripts/calc/`** (it then writes nothing at all) and rewrite the
   header paragraph naming the deleted function as the reason it stayed. `class_name` is
   path-independent, so no call site changes — but two path-keyed references do:
   - `tools/validate_gd_metrics.py:96` hard-codes
     `"scripts/resolvers/AntishipResolver.gd::resolve"` and would raise `KeyError`;
   - the `.uid` sidecar moves with the file, value preserved (`uid://dyvcjn2l1pen` appears nowhere
     else).
4. **Watch for the 0046 name-collision trap.** `AntishipResolutionContext` declares its own
   `lost_at_sea_accumulator`, and a protected field NAME is claimed repo-wide. The receiver at
   `FiresPhases.gd:103` types cleanly to `AntishipResolutionContext`, so the write should resolve
   and pass — but if the backstop reports it, the fix is to rename the **context's** field, never to
   widen the allowance.

### Step 3 — runtime, contract and determinism sweep

**Already run, on the pre-change tree (2026-07-31).** Results recorded here as the campaign's
baseline; re-run after step 2 and require the same verdicts.

- **Determinism: PASS.** `tools/run_selfplay_game.gd`, seed 20260731, 40 turns, two separate
  processes each: `scenario_golden` and `scenario_default` records **byte-identical**
  (877 KB and 638 KB respectively).
- **Runtime coverage:** four full games — `scenario_golden` (40 turns), `scenario_default`
  (22, red victory), `roc_full_defense` (15, red victory), `red_airborne` (22). Across them the
  digests show sustained sealift and crossing losses (7 crossing turns in the default), mine
  transit, IJFS fires with warmup and squadron attrition, ground combat, offload every turn, and the
  cleanup/victory census every turn. `index_violations` is `[]` in **all four**, so the debug
  runtime-index tripwire ran clean on every turn.
  **Gap, recorded honestly:** the self-play default policy issues no air-insert or mobilization
  orders, so neither phase does work in any of the four records. Those two phases are exercised by
  `tools/validate_air_insertion.gd` and `tools/validate_mobilization.gd` in the canonical gate
  instead — the coverage exists, it just is not in the self-play records.
- **No authority is vacuous** is enforced statically by `E_INERT_AUTHORITY` (an authority writing
  none of its protected fields fails the gate). Recorded rather than re-proved at runtime.
- **Contract:**
  - commit/version identity — **PASS**: every record carries `commit`, `record_version` (2) and
    `knobs_registry_version` (2).
  - ordinal ids — **PASS**: events carry `seq`, dense from 0 and strictly increasing within each
    turn, unique when paired with `turn_number`, in all four records. (There is no symbol named
    `ordinal` anywhere in the tree; `seq` is what the Sketch meant.)
  - schemas vs emitted vocabulary — owned by `tools/validate_llm_api.gd`, which reads all three
    files under `schemas/` and is in the gate.
  - `to_dict` as the sole serialization seam — **one exception, and it is dead.** 21 types declare
    `to_dict`; `scripts/model/CombatResult.gd:19` declares `to_dictionary()` instead, and it has
    **zero callers**. Deleted in step 4.

### Step 4 — architecture cleanup

- Lower `scripts/phases/FiresPhases.gd`'s dependency ceiling from **15 to its measured value**
  (13 before step 2; re-measure after). Ratchet down only — never up.
- Re-measure the other four ceilings (`GameState` 29/29, `TurnConductor` 18/18,
  `ReinforcementPhases` 22/22, `TurnClosure` 7/7 — all exactly full today) and lower any that the
  two migrations freed.
- Delete `CombatResult.to_dictionary()` (step 3's contract finding: zero callers, and the only type
  in the repo whose serialization seam is not named `to_dict`).
- Nothing else is deleted in this step without call-site evidence. `AntishipMagazine` /
  `IndividualShip` stay: `docs/archive/0052` records them as dormant **by design**, owned by plans
  0002 and 0045.

### Step 5 — stale-fact reconciliation

`RosterMutations` was deleted by plan 0044 (`docs/DECISIONS.md:146`), but five live locations still
describe it as present tense (the fourth and fifth were found by reviewers, not by me):

- `docs/STATUS.md:29` — "with `RosterMutations` kept as a compatibility wrapper…";
- `docs/systems/turn-engine/turn-engine.md:68, 75, 80`;
- `docs/systems/amphibious-offload/amphibious-offload.md:149`;
- `docs/systems/ground-combat/ground-combat.md:120` — "sends the casualty reports through
  `RosterMutations.apply_casualty`";
- `tests/landed_battalions_test.gd:38` — a comment naming
  `RosterMutations.pending_pool_roster_violations` as the tripwire. It is
  `ForceTransitions.pending_pool_roster_violations` now, and the same test file calls it under that
  name at lines 186 and 198.

Each names the real call today (`ForceTransitions.apply_crossing_loss`,
`ForceTransitions.apply_casualty`, `ForceTransitions.pending_pool_roster_violations`). Historical
records in `docs/archive/`, `docs/plans/ARCHIVE.md` and the failure-archaeology skill keep their
past-tense mentions untouched — they are describing what was true then.

### Step 6 — closeout

1. Every systems doc carries its short numbered **State & authority** section. Present in **12** docs;
   **add to the three that lack one** — `llm-api-selfplay`, `research-harness`, `view-layer`, none of
   which owns a protected runtime aggregate, and each says so and says what that means for it. Widen
   `amphibious-offload` §10's `sealift_fleet` block to cover the handle and the crossing ledger. No doc
   duplicates protected-field or writer lists.

   **Correction, and a lesson.** This plan first said 11 and four, naming `antiship-mine` as lacking
   the section. It does not — its heading is `## 10. State & Authority`, capital A, and my grep was
   case-sensitive. The plan-review round **CONFIRMED the wrong number**, because the brief asserted it
   and the reviewer checked the claim rather than re-deriving the count. That is the failure mode
   `.claude/REVIEWERS.md` § Safety names exactly: agreement with a false premise the brief supplied is
   not corroboration. Counts in a brief should be given as the COMMAND that produced them, not as the
   result.
2. `docs/STATUS.md`: the aggregate index table gains no rows (it is capped at one line per
   aggregate); the `sealift_fleet` row's `Covers` text widens to name the handle and the crossing
   ledger, and the `RosterMutations` sentence is corrected per step 5.
3. `.claude/skills/hexcombat-architecture-contract`: the final proven authority rule and procedure;
   remove 0042's provisional wording.
4. `docs/DECISIONS.md`: one concise campaign-closeout entry with pointers and the measured
   behaviour change (**none** — every step here is byte-stable).
5. Archive plans 0042–0050 in shipped order; replace the campaign sequencing block in
   `docs/plans/README.md` with a short archived closeout row. **0050 may not be archived until its
   three exclusions are gone** — a `planned_transitional` policy naming an archived plan fails
   `E_STALE_POLICY_PLAN` by design, which is the mechanism that makes step 1+2 non-optional.
6. Check off the BACKLOG item that owns the three fields.

---

## Verification

- `python3 tools/gd_metrics.py --check-ceiling .` passes, with ceilings lowered where freed.
- Canonical `bash tools/run_all_tests.sh` prints **ALL PHASES GREEN** after every step.
- Same-seed self-play records byte-identical across separate processes (step 3).
- No golden/fixture pin moves at any step. Any movement stops the plan.
- `python3 tools/mutation_ownership.py --plan 0050` prints **zero** owed fields.
- `python3 tools/mutation_ownership.py --check-pin` agrees after each manifest edit.
- The mutation gate reproduces every abstract write FORM, every generated real-manifest claim and
  every wrong-authority boundary on each run (already true; this plan only extends the claim set).

## Independent review

Per `.claude/REVIEWERS.md`: one substantive read of this plan before implementation; the finished
diff is **quorum-bound, 2 of 3**, because this is a numbered plan's implementation. Routes probed
alive 2026-07-31: sol OK, agy OK, deepseek OK.

### Round 1 (plan), 2026-07-31 — 2 substantive returns, all findings verified and acted on

| # | Finding | Verified | Action |
|---|---|---|---|
| sol P1 | `antiship_establishment` is the wrong owner: it would add a 23rd dependency to `ReinforcementPhases`, whose ceiling is exactly 22 | CONFIRMED (`AntishipTransitions` ABSENT from that file; `SealiftTransitions` present at 6 call sites) | **Owner changed to `sealift_fleet`.** Rewrote the rationale |
| sol P1 | Moving `AntishipResolver` breaks `tools/validate_gd_metrics.py:96`, which hard-codes the `scripts/resolvers/…` key | CONFIRMED | Added to step 2 |
| sol P2 | Deleting the resolver test loses the mixed-case prune, which still exists at `ForceTransitions.gd:794` | CONFIRMED — `force_transitions_test.gd:760` covers only the sole-BN case | Port the test rather than delete it |
| sol P2 | New authority edges need `tests/transitions/` characterization first | CONFIRMED (procedure doc line 54) | Step 1.7 |
| agy 1 | The preflight over-claimed: `E_STALE_ALLOWANCE` is fixture-proven | CONFIRMED REFUTED — one emission site, no proof surface; `BACKLOG.md:33` owns it | Row 6a added; explicitly **not** fixed here |
| agy 3 | "`scripts/phases/` has exactly two protected writes" is misleading | CONFIRMED — two protected today, four more to fields this plan promotes | Wording corrected |
| agy 5 | Two more live `RosterMutations` references missed | CONFIRMED — `ground-combat.md:120`, `tests/landed_battalions_test.gd:38` | Added to step 5 |
| agy 2, 4, 6 | Writer inventory complete; dead function confirmed dead; 11/15 docs have the section | CONFIRMED | No change |

DeepSeek returned 79.7 KB of raw tool trace with no lists — **FLAKE**, not counted. Its raw greps
happened to agree with the inventory I had already produced, which is not corroboration.

### Round 2 (diff, gate already green), 2026-07-31 — 3 substantive returns; quorum met

**No reviewer found a behaviour change.** Sol probed all five paths I asked about and returned ABSENT
on each: the install/swap split is right, nothing between the moved reset points reads either ledger
field, both former read-then-zero pairs were adjacent, a production accumulator cannot be negative,
and no caller of the old `FiresPhases.register_ship_losses` survives. agy independently verified all
four deletions and compared the deleted prune line-by-line against `ForceTransitions` including three
edge cases (empty `lost_ids`, an id matching nothing, an entry with no `bns` key).

Everything they DID find was documentation that had gone stale — which is the honest result for a
byte-stable closeout, and the reason the round was worth running:

| # | Finding | Verified | Action |
|---|---|---|---|
| sol | `docs/plans/README.md` claimed "zero behaviour change across nine plans" — **0043 carried a deliberate, USER-approved behaviour correction** | CONFIRMED against `docs/archive/0043-…:30` | Row rewritten to name 0043 as the exception and warn that research records straddle it |
| sol | The architecture skill listed `last_ijfs_writeback` among fields "owned by exactly one authority"; the manifest classifies it `phase_output` | CONFIRMED | Rewritten to distinguish protected fields from `last_*` reports that are still cross-phase edges |
| sol | Three canonical docs still described deleted seams: `AntishipResolver`'s own header, `amphibious-offload.md:82`, `antiship-mine.md:176` | CONFIRMED | All three rewritten |
| sol | My replacement wording claimed the `scripts/resolvers/` files "still write campaign state" — `CombatResolver`'s header literally says *"It applies NOTHING"* | CONFIRMED, **and worse than reported** — see below | Wording corrected; **plan 0055 opened** |
| sol | The archived plan still said `status: "In progress"` | CONFIRMED | Closeout header |
| agy | The ported test dropped the deleted test's mixed-BRIGADE case: both reserve entries used one `brigade_id`, so a prune attributing the survivor to the wrong entry would still pass | CONFIRMED | Test rebuilt with two brigades; now also asserts each drowned BN came off its own roster |
| deepseek | `tools/gd_metrics.py:47` — a comment describing `TurnConductor`'s CURRENT fan-out still named `SupplyResolver`, dissolved in 0049 | CONFIRMED | Rewritten. **Found by nothing else in either round** |

**The finding behind the finding.** Chasing sol's fourth item, I measured all six remaining
`scripts/resolvers/` files instead of just the two it named. **None of them writes campaign state.**
The directory's distinguishing test — "does it still write campaign state?" — is now false of
everything in it, and my own preflight had asserted the opposite ("seven files still hold per-phase
logic that writes campaign state") without measuring. Both round-1 reviewers passed over that claim.
It is not folded in here: it is a fifteen-file path move discovered *after* this diff was reviewed,
and folding it in would ship it unreviewed, which this plan's own campaign-fatigue stop condition
forbids. Opened as `docs/archive/0055-directory-claims-vs-appliers.md` with the measurement (shipped 2026-07-31).
**That measurement was wrong, and this paragraph records what was believed on 2026-07-31, not what is
true** — the write-scan reused here detects direct field assignment, and after this campaign the only
application left is via authority CALLS, which it cannot see. `CleanupResolver` and `IjfsResolver` do
change campaign state. Plan 0055 was rewritten at preflight the same day; see it for the census.

**Counting note.** `tools/review_fanout.sh --report` auto-counted 1 of 2. I counted three, and the
reasons are mechanical: sol's return (2986 B, healthy band) uses `### [P2]` headings rather than a
numbered list, so the findings detector missed a review I read in full; deepseek's (32.5 KB, SUSPECT
band) contains no "findings" because its role asked for three verbatim enumerations, which it
delivered — and per `.claude/REVIEWERS.md` an enumeration role is judged by whether the lists are
verbatim and scoped, not by size. Both judgements are recorded rather than assumed.

Round 2 asked: is any mutable aggregate or write form still missing? Can any controller be
bypassed through aliases or nested Dictionaries? Did any authority absorb calculation
or phase-order responsibility? Did any step change RNG draw order, behaviour or a JSON contract? Are
manifest/controller facts duplicated in a way that can drift?

## Out of scope

- New mechanics, balance changes, scenario tuning.
- Event sourcing, rollback, save-game migration, a universal ECS.
- One generic controller/base class for all domains.
- Emptying `scripts/resolvers/` (condition unmet — see preflight).
- Moving mutable state out of `GameData` for conceptual purity, or recording that move as a settled
  deferred destination, without a separate USER-ratified plan.

## Risks and stop conditions

- **Audit theater.** A green manifest-based gate is insufficient on its own; the independent source
  sweep is preserved above as a separate proof with its own method and its own finding.
- **Deleting guards too soon.** Keep structurally different backstops (`validate_pool_enumeration`,
  `validate_runtime_indexes`, `validate_combat_rules_threading`) even where an authority should make
  the violation impossible.
- **Campaign fatigue.** Do not combine an unresolved migration into the closeout commit. Open a
  focused follow-up and leave this plan blocked instead.
- Stop on any unexplained golden/fixture drift or same-seed mismatch.

## Dependencies

Final plan of the campaign. 0042–0049 shipped; all their manifest exceptions are already removed.
