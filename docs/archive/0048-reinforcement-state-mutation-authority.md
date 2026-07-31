---
title: "0048: Reinforcement-state mutation authority"
status: "✅ Shipped"
created: "2026-07-26"
rewritten: "2026-07-30"
---

# Plan 0048: Reinforcement-state mutation authority

> **Rewritten 2026-07-30 against the tree.** The 2026-07-26 sketch was written before plan 0044
> shipped, before 0047, and before `hosted_fields` became closed-world (commit 801296a). Three of its
> premises were false when measured. §1 records what changed and why; the rest of the document is the
> plan as it will actually be implemented. Reviewers should review §2 onward and use §1 to check that
> the rescoping is justified rather than convenient.

## 1. Preflight — what the sketch claimed, and what the tree says

Every row below is a measurement, not a recollection.

### 1.1 `MobilizationTransitions` cannot exist as specified

The sketch: *"`MobilizationTransitions` … is the exact only writer for `MobilizationState.pending`,
`released`, and schedule advancement."*

Measured: plan 0044 already made both fields `owned_models` of the **force** aggregate, so
`ForceTransitions` is already their exact only writer.

```
tools/mutation_authority_manifest.json → aggregates[force].owned_models:
  { "class": "MobilizationState", "fields": { "pending": "campaign", "released": "campaign" } }
```

`MobilizationState` declares exactly those two mutable fields (`scripts/model/MobilizationState.gd:26`,
`:31`). Nothing on that model is unclaimed. The only mobilization field left anywhere is the **handle**
`GameStateData.mobilization_state`, which is one assignment.

Creating a `MobilizationTransitions.gd` whose entire content is one rebuild method — for a model whose
every field belongs to a different authority — is an authority in name only. **The handle joins the
force aggregate instead**, which is where plan 0047 put the analogous case: `infrastructure_state` is
claimed by the aggregate that owns the node fields, not by a separate handle-owner.

### 1.2 The air-pool ownership question the sketch flags as a risk is already settled

The sketch's stop condition: *"Two owners for the air pool: settle this explicitly during preflight."*

Measured: `AirInsertionState.pool` and `.landed` are already **force** `hosted_fields` (plan 0044), and
`ForceTransitions` is their only writer — `_remove_pool_bns` (`ForceTransitions.gd:749`) and
`_drop_empty_air_pool_entries` (`:815`), both reached from `_commit_air_insertion` (`:134`). There is no
second writer to arbitrate. **This plan never touches `pool` or `landed`.** The force authority keeps
BN-location truth exactly as it does today; the new authority owns capacity and the log, and the two
have disjoint fields on one shared model — the `SealiftCohort` split pattern the manifest's
`_schema_rules` already sanctions.

### 1.3 The runtime migration is two lines

Complete inventory of every write to the fields this plan claims, from
`grep -rn` over `scripts/` and `tools/` (the manifest's `scan_roots`):

| # | `file:line` | Verbatim line | Enclosing function | Kind |
|---|---|---|---|---|
| 1 | `scripts/phases/ReinforcementPhases.gd:289` | `state.air_insertion_state.caps = summary.caps_after.duplicate()` | `resolve_air_insertion_turn` | runtime, direct_assign |
| 2 | `scripts/phases/ReinforcementPhases.gd:292` | `state.air_insertion_state.history.append({` | `resolve_air_insertion_turn` | runtime, container_mutate |
| 3 | `scripts/builders/AirInsertionStateBuilder.gd:51` | `state.caps = {` | `build` | construction |
| 4 | `scripts/builders/AirInsertionStateBuilder.gd:55` | `state.initial_caps = state.caps.duplicate()` | `build` | construction |
| 5 | `scripts/GameState.gd:128` | `set(value): data.air_insertion_state = value` | property setter | handle |
| 6 | `scripts/GameState.gd:308` | `data.air_insertion_state = GameStateBuilder.build_air_insertion_state(` | `_rebuild_air_insertion_state` | handle |
| 7 | `scripts/GameState.gd:122` | `set(value): data.mobilization_state = value` | property setter | handle |
| 8 | `scripts/GameState.gd:295` | `data.mobilization_state = GameStateBuilder.build_mobilization_state(` | `_rebuild_mobilization_state` | handle |
| 9 | `scripts/builders/AirInsertionStateBuilder.gd:50` | `state.first_turn = int(config.get("first_turn", DEFAULT_FIRST_TURN))` | `build` | construction |

The table covers every write FORM the gate detects, not only `=`: rows 1, 3, 4, 5, 6, 7, 8 and 9 are
`direct_assign` and row 2 is `container_mutate`. There is no compound assignment, element assignment,
`set("field", …)`, cast write or model-mutator call against any of these fields anywhere in
`scripts/` or `tools/` — `AirInsertionState` and `MobilizationState` declare no mutator method at all,
only read-side queries and `to_dict`/`validate`.

`AirInsertionState.initial_caps` and `.first_turn` have **no runtime writer at all** — rows 3, 4 and 9
are the complete set. `.history` has no direct assignment anywhere; row 2 is its only mutation.

Nothing assigns through the `GameState` forwarding properties: `GameState.air_insertion_state = …`,
`GameState.mobilization_state = …` and their `_game_state()` equivalents are ABSENT from `scripts/`,
`tools/` and `tests/`; every use is a read (`scripts/LLMGameAPI.gd:351`, `:381`;
`tools/validate_mobilization.gd:102`; `tools/validate_air_insertion.gd:100`, `:144`). Rows 5 and 7 can
therefore simply be deleted. `tests/air_insertion_order_test.gd:28` looks like a counter-example and is
not one: its receiver is a standalone `GameStateData.new()` (`:26`), not the autoload, so the setter
deletion does not reach it and that fixture stays as it is.

No writer exists in `tools/`. `scripts/LLMGameAPI.gd:392/393/397` **reads** `caps`, `initial_caps` and
`history` and duplicates them into the observation; it writes none of them.

### 1.4 `first_turn` stays excluded; `initial_caps` is claimed

Both are written only by the builder, so the difference is not measured writers — it is whether the
field participates in an invariant the authority enforces.

- `initial_caps` **is** the ceiling in `0 <= caps <= initial_caps`. Protecting `caps` while leaving
  `initial_caps` writable makes the invariant trivially defeatable: raise the ceiling, and permanent
  lift attrition becomes reversible without a single write to `caps`. It is claimed, with a
  construction allowance for the builder.
- `first_turn` gates order acceptance (`AirInsertionResolver.resolve`, the `turn_number <
  state.first_turn` branch) and participates in no invariant this authority can enforce. Claiming it
  would buy one more construction allowance and nothing else, while claiming the repo-wide field name
  `first_turn`. Its existing `identity_construction_only` classification is accurate and **stays** —
  this plan does not reclassify it.

### 1.5 Every candidate call site is exactly at its dependency ceiling

Measured 2026-07-30 with `tools/gd_metrics.py`: `ReinforcementPhases.gd` 22/22, `GameState.gd` 29/29,
`TurnConductor.gd` 18/18. Zero headroom. §4 is the swap that pays for the one new dependency; it is a
design constraint, not a cleanup, and it lands in the same commit.

### 1.6 Sketch steps that are already done, or are not this plan's

- **Step 2 (typed request/outcome/receipt Resources)** — done. `AirInsertionSummary`,
  `ForceAirInsertionRequest`, `ForceAirInsertionReceipt`, `MobilizationSummary` and
  `ForcePlacementReceipt` all exist and are in use.
- **Step 6 (order-buffer seam)** — `GameStateData.air_insert_orders` is classified `order_buffer`
  pointing at plan **0049**, and `ReinforcementPhases.gd:275` (`state.air_insert_orders = []`) is that
  plan's writer to migrate. This plan leaves both untouched and adds no temporary writer, because the
  field is not this aggregate's and no exclusion for it points here.
- **Steps 3/5 (mobilization authority, pool coordination)** — dissolved by §1.1 and §1.2.

## 2. Settled behavior (unchanged from the sketch, re-verified)

- Air insertion drains ordered packets from its pool up to the current per-class cap.
- Every insertion casualty permanently removes one battalion of lift from that class; caps never rise.
- Airborne and air-assault threat formulas, first-turn gate, target legality, locked follow-up hex,
  supply isolation, and the `air_insertion:<turn>` RNG substream are unchanged.
- Troop roster/location changes stay with `ForceTransitions`; this plan owns lift capacity and the
  insertion log.
- **Timing is preserved exactly.** Caps and history are written only when a packet actually flew
  (`landings` non-empty) **and** the force receipt succeeded — the same two guards as today. Note that
  a packet lost in full still produces a `landings` entry (`AirInsertionResolver._append_drop` appends
  unconditionally), so a total loss erodes caps today and must continue to. §6 pins this.

## 3. Aggregate boundaries

### 3.1 New aggregate `air_insertion` — authority `AirInsertionTransitions`

`scripts/transitions/AirInsertionTransitions.gd`. Registered in
`tools/mutation_authority_manifest.json` in the same commit as the file (an authority file cannot
precede its entry — `E_UNREGISTERED_AUTHORITY_FILE`), status `enforced` from birth, no
`legacy_writers`.

| Section | Class | Fields |
|---|---|---|
| `hosted_fields` | `AirInsertionState` | `caps`, `initial_caps`, `history` |
| `hosted_fields` | `GameStateData` | `air_insertion_state` |
| `construction_writers` | `scripts/builders/AirInsertionStateBuilder.gd` | `AirInsertionState.caps`, `AirInsertionState.initial_caps` |

`pool`, `landed` (force) and `first_turn` (excluded, §1.4) are the rest of `AirInsertionState` — that
is the whole field list, so the closed-world check is satisfied.

**Operations — job-shaped, no setters:**

```
rebuild_air_insertion_state(state: GameStateData, config: Dictionary, brigades: Dictionary) -> void
lift_request(turn_number: int, drops: Array) -> AirLiftRequest        # factory for its own input
can_record_insertions(air_state: AirInsertionState, request: AirLiftRequest) -> bool
record_insertions(air_state: AirInsertionState, request: AirLiftRequest) -> void
```

`rebuild_air_insertion_state` builds a fresh state from scenario content and installs it — the same
shape and the same reason as `InfrastructureTransitions.rebuild_infrastructure`, so the host file earns
no writer exemption.

`record_insertions` is the single runtime job: *these packets flew, so this much lift is gone and these
log rows exist*. It takes a new typed `AirLiftRequest` (`scripts/model/AirLiftRequest.gd`) carrying the
turn number and the resolver's drop rows — the same one-row-per-packet shape
`AirInsertionSummary.drops` already has, deep-duplicated at construction.

**The authority DERIVES the cap erosion; it is never told what the new caps are.** For each drop, in
resolution order, `caps[lift_class] = maxi(0, caps[lift_class] - drop["lost"])` — the identical
arithmetic `AirInsertionResolver._resolve_order` uses, applied to the same rows that become the log.
That is a deliberate change from the sketch's shape and from this plan's first draft, both of which
passed `summary.caps_after` in. Passing a post-state in makes "the cap fell by exactly the reported
losses" a number the authority must trust and check; deriving it makes the equation hold by
construction, and makes it impossible for the log and the erosion to disagree, since they are computed
from one array. `AirInsertionSummary` stays report-only, and `summary.caps_after` remains what the
observation and the LLM payload report — §6 pins that the two agree.

**Invariants enforced by absence, not by a guard a later reader can argue with:**

- **No method raises a cap, and none can.** Erosion is a floored subtraction of a non-negative loss
  count; there is no input through which a higher cap can be expressed at all. This is stronger than
  the guard the first draft proposed, which merely refused one.
- **No method writes `initial_caps` at runtime.** The only writer is the builder's construction
  allowance, so the `0 <= caps <= initial_caps` ceiling cannot move.
- **No method clears, rewrites or reorders `history`.** The only expressible operation appends this
  turn's drops, so the log is append-only by construction (the `IjfsTransitions.destroyed` pattern).
- **No method installs a caller-built `AirInsertionState`.** `rebuild_air_insertion_state` takes
  scenario content and builds internally, so there is no seam for handing the authority a state with
  fabricated caps.

The one remaining refusal is a drop naming a lift class the state does not budget for, or a negative
`lost`/`landed` count: `push_error`, write nothing (a research batch of hundreds of games must not die
on one malformed row, and `push_error` is testable with `assert_error(...)`).

**`can_record_insertions` is the transaction boundary, and it exists because the force authority
commits first.** `ForceTransitions.apply_air_insertion_outcome` irreversibly drains the pool, applies
roster losses, places brigades and appends to `landed` before this authority runs. A refusal *after*
that leaves the roster moved and the lift ledger un-eroded. So the coordinator asks this predicate
BEFORE calling the force authority; if it says no, nothing has been written by anyone and the phase
returns having changed nothing. `record_insertions` still re-checks — the predicate and the guard share
one private helper — but in the real flow the second check can no longer be the first thing to fail.

`lift_request` is a factory ON the authority, mirroring `ForceTransitions.ground_combat_casualty_request`
and `ijfs_casualty_request`. That is not decoration: it means the coordinator never names
`AirLiftRequest`, which is what keeps §4's dependency arithmetic at one new token rather than two.

### 3.2 `GameStateData.mobilization_state` joins the **force** aggregate

Added to the existing `force → hosted_fields → GameStateData` entry alongside `ship_reserve`. Its
writer becomes:

```
ForceTransitions.rebuild_mobilization_state(state: GameStateData, config: Dictionary, holdback: Array) -> void
```

Same shape as `rebuild_air_insertion_state`, and it sits with the model's fields rather than in a
class of its own (§1.1). The force aggregate's existing `MobilizationStateBuilder` construction
allowance already covers `MobilizationState.pending`, so no allowance changes.

### 3.3 Closed-world bookkeeping

The five exclusions currently pointing at this plan are **deleted** in the implementation commit, not
at closeout — each field becomes claimed, and claimed-plus-excluded fails `E_CLAIMED_AND_EXCLUDED`:

```
AirInsertionState.caps            planned_transitional → claimed (air_insertion)
AirInsertionState.initial_caps    planned_transitional → claimed (air_insertion)
AirInsertionState.history         planned_transitional → claimed (air_insertion)
GameStateData.mobilization_state  planned_transitional → claimed (force)
GameStateData.air_insertion_state planned_transitional → claimed (air_insertion)
```

`AirInsertionState.first_turn` keeps its `identity_construction_only` exclusion. After this commit
**no exclusion anywhere points at plan 0048**, so archiving it at closeout cannot turn one red
(`E_STALE_POLICY_PLAN`) — which is exactly the trap the procedure doc's §5 warns about, closed in
advance rather than swept at the end.

No exclusion is added: §4's final shape adds no field to any hosted class.
`AirLiftRequest` is a fresh, caller-owned value object that no aggregate hosts, so it needs no policy
entry — the same standing as `ForceAirInsertionRequest`.

`tools/fixtures/mutation_authority/real_claims_pin.json` gains the five new claim identities in the
same edit.

## 4. Paying for the dependency — the swap

`ReinforcementPhases` must name `AirInsertionTransitions` (its `resolve_air_insertion_turn` is where
the two runtime writes live), which takes it to 23 against a ceiling of 22. The ceiling is paid for,
not raised. Neither rebuild pass-through costs anything: both take `Dictionary`/`Array` parameters, so
they add no type dependency, and `ForceTransitions` and `GameStateData` are already dependencies.

**The dependency that leaves is `AirInsertionStateBuilder`**, whose single use in the file is
`ReinforcementPhases.gd:271`:

```gdscript
AirInsertionStateBuilder.attrition_config(GameData.red_air_insertion),
```

`GameDataStore` gains an on-demand accessor beside the block it reads:

```gdscript
## The air path's attrition coefficients, parsed from this scenario's red_air_insertion block.
func air_insertion_attrition_config() -> Dictionary:
	return AirInsertionStateBuilder.attrition_config(red_air_insertion)
```

- `ReinforcementPhases.gd:271` becomes `GameData.air_insertion_attrition_config()`.
- `LLMGameAPI.gd:406`, the other caller, becomes `_game_data().air_insertion_attrition_config()`.

**Deliberately a method, not a cached field.** The first draft of this plan filled a
`GameDataStore.red_air_insertion_attrition` field at `load_scenario`, on the reasoning that the
coefficients cannot change during a game (all five air-insertion knobs are `scenario:*` paths applied
before the scenario is read). That reasoning is sound and the cache would not have gone stale — but it
would have moved `_validate_keys`' `push_error` on a malformed block from *resolution time* to *load
time*, changing when a researcher sees the complaint and how often, for no reason beyond a dependency
budget. An on-demand accessor frees exactly the same dependency slot and changes no timing at all.
Cheap parse, called once per turn and once per observation, as today.

`AirInsertionResolver.resolve`'s signature and semantics are untouched, so none of its eleven test call
sites move. `AirInsertionStateBuilder` is NOT deleted, moved or emptied — `attrition_config` stays
exactly where it is, and `build()` keeps its construction allowance (§3.1). Only the *caller* moves.

Net: `ReinforcementPhases` 22 → 22 (−`AirInsertionStateBuilder`, +`AirInsertionTransitions`), a
one-for-one swap of the kind plan 0043 used to hold `FiresPhases` at 14. `AirLiftRequest` is
constructed through the authority's own `lift_request` factory (§3.1), so its token never appears in
the coordinator and it costs nothing. `GameState` stays at 29: it loses nothing (it still names
`GameStateBuilder`, `MobilizationState` and `AirInsertionState` for other reasons) and gains nothing.
`GameData.gd` gains `AirInsertionStateBuilder` as a genuinely new dependency and has no ceiling entry.

Verified against the counter rather than assumed: `tools/gd_metrics.py:159/276` counts distinct
`class_name` tokens (plus autoloads) appearing literally in the file's code. Built-in types are not
counted, so the `Dictionary`/`Array` pass-through parameters are free, and a type only ever named as
another file's declared return type is free too.

`GameStateBuilder.build_air_insertion_state` and `build_mobilization_state` lose their only callers and
are deleted; both were one-line pass-throughs to the real builders.

The two `GameState` property setters (rows 5 and 7 of §1.3) are **deleted**, leaving get-only
forwarding properties — exactly what plan 0047 did for `infrastructure_state`, which today is get-only
with a comment pointing at its rebuild method. Nothing in the repo assigns through them (§1.3), so no
caller migrates; `tests/air_insertion_order_test.gd` is untouched.

## 5. Role placement

`AirInsertionResolver` and `MobilizationResolver` both satisfy the `calc/` test in `docs/STATUS.md`
(measured: neither writes anything that outlives the call — `AirInsertionResolver` stages into
`AirInsertionResolutionPlan` locals and returns; `MobilizationResolver` fills a summary and returns),
so they move to `scripts/calc/` with their `.uid` files. `class_name` is path-independent, so no call
site changes. Three anchors move with them: the file rows in
`docs/systems/air-insertion/air-insertion.md` and `docs/systems/roc-mobilization/roc-mobilization.md`,
and the `AirInsertionResolver::resolve` key in `tools/gd_metrics.py`'s `PARAM_CEILINGS` (which fails
loudly as a stale entry if missed). Both headers' purity paragraphs are rewritten in the same edit:
they described a caller that "performs companion updates", which after §3.1 it no longer does.

This is sketch step 7 and it is mechanical; it is the last change before the gate so it can be
reviewed separately from the authority itself.

## 6. Characterization first, then the migration

New suite `tests/transitions/air_insertion_authority_characterization_test.gd`, written and green
**before** anything moves, pinning current behaviour:

1. a packet with losses erodes `caps` by exactly the loss count, for that class only;
2. a packet lost **in full** still erodes caps and still appends history (§2);
3. caps never rise across turns, and never exceed `initial_caps`;
4. `initial_caps` is unchanged by any number of resolved turns;
5. history appends one entry per drop, in resolution order, with the six documented keys;
6. no orders, and all-orders-rejected, leave `caps` and `history` untouched and consume no dice;
7. a refused force receipt leaves `caps` and `history` untouched;
8. **the order buffer is emptied on every path** — resolved, all-rejected, and force-refused.
   `ReinforcementPhases.gd:275` clears `air_insert_orders` before both early returns, so an
   implementation that moved the clear inside the success branch would silently re-fly rejected orders
   next turn and cases 1–7 would all still pass;
9. **a successful first landing still recomputes hex ownership** (`ReinforcementPhases.gd:300`) — drop
   onto enemy ground and the hex must read CONTESTED before movement/combat runs. Losing this call
   leaves corridor and combat logic on last turn's map, again invisibly to cases 1–7;
10. after a resolved phase, `air_insertion_state.caps` equals `summary.caps_after` — the pin that the
    authority's derived erosion and the resolver's reported budget cannot drift apart (§3.1).

Then `tests/transitions/air_insertion_transitions_test.gd` for the authority itself: a drop naming an
unbudgeted lift class is refused and changes nothing; a negative loss count is refused; a valid record
applies erosion and log together; `can_record_insertions` returns false for exactly the inputs
`record_insertions` refuses; `rebuild_air_insertion_state` installs a fresh state. There is no
"cap raise is refused" case, because after §3.1 there is no input that expresses one.

## 7. Commit sequence

1. **Characterize.** §6's characterization suite only, green against the unmodified tree.
2. **Authority, atomically.** `AirInsertionTransitions.gd` + `AirLiftRequest.gd` + the manifest entry +
   the force manifest edit + the five exclusion deletions + the claim-pin update + both runtime writes
   migrated + both rebuild seams + the setter deletions + the §4 swap + the authority test suite. This
   is one commit because the ordering traps make it one: the file cannot precede its entry, and a
   claimed-and-excluded field fails the gate.
3. **Role placement.** §5's two file moves and their three anchors.
4. **Record and close out.** §9.

## 8. Verification

- `bash tools/run_all_tests.sh` → ALL PHASES GREEN, no golden, pin or fixture drift.
- `HEXCOMBAT_SCENARIO=scenario_golden godot --headless --path . -s res://tools/validate_mutation_authority.gd`
- `python3 tools/gd_metrics.py . /tmp/metrics.json --check-ceiling`
- The `red_airborne` scenario is the only one that exercises a non-empty pool; run it multi-turn and
  confirm caps, history and the observation payload are identical before and after.
- Deliberately break one new expectation (raise a cap through the authority; assert the gate catches an
  unregistered write) and observe the failure before restoring the tree exactly.

The abstract `.gdfixture` world is **not** extended: this aggregate introduces no write FORM it does
not already exercise (`direct_assign` and `container_mutate` on a hosted field of a shared typed model,
both already covered). Extend it only if implementation turns up a form that is genuinely new.

## 9. Out of scope

- Air insertion balance from plan 0036; new lift classes, recovery, sortie cadence, cost mechanics.
- Mobilization force structure or release policy.
- Force casualty/placement (0044), IJFS threat (0046), order buffers / turn lifecycle / supply /
  victory latches (0049), sealift and lost-at-sea handles (0050).

## 10. Risks and stop conditions

- **Timing.** Application must stay where the assignment is; no recalculation of losses in the
  authority. §6 case 2 and case 7 are the pins that catch a drift.
- **Summary drift.** `AirInsertionSummary.to_dict` keys and the LLM observation payload must not move;
  the LLM API validator is the gate.
- **Cross-authority partial write.** The force authority commits first and cannot be rolled back, so
  the lift ledger is preflighted before it runs (§3.1). §6 case 7 pins the surviving branch.
- Stop and ask the USER if plan 0036 changes packet/cadence semantics first, if a ceiling can only be
  raised rather than swapped, or if any golden or RNG draw order moves.

## 10a. Checked, rejected — do not re-raise

### From the diff-review round (2026-07-30, 3 of 3 reviewers returned)

Accepted and shipped: the authority now stages BOTH the eroded budget and the log rows in locals and
assigns them only after staging succeeds (a malformed row could otherwise raise AFTER `caps` was
written); `_drops_are_legal` checks `REQUIRED_DROP_KEYS` presence, which is what makes that staging
safe to complete; the coordinator refuses when `summary.drops.size() != landings.size()` before either
authority commits; and two test gaps were closed — history `turn` is now pinned across turns 1 and 2
(a hardcoded `"turn": 1` would have survived all 21 original cases), and the resolver's one-drop-per-
landing invariant is pinned directly. Three closeout misses were fixed: `docs/plans/README.md`'s
"Next up" heading still named 0048, its campaign item 7 carried no shipped marker, and the procedure
doc still listed 0048 among the plans that must update it.

Turned down:

- **"Reconcile packet count, order, brigade, hex and landed/lost manifest counts across BOTH requests
  before either commits."** (tier-1 reviewer, full form of the finding.) The COUNT check was accepted
  and shipped. The rest is rejected: `ForceTransitions._validate_air_pool_prefix` already validates the
  landings against the pool it owns, and having the coordinator re-check an authority's input would put
  cross-aggregate validation in the one place the campaign is trying to remove it from. The count is
  the part neither authority can see.
- **"`record_insertions` should return a success receipt rather than `void`."** (tier-1 reviewer.)
  `can_record_insertions` already gives the caller the same answer BEFORE anything is written, which is
  strictly more useful than a receipt afterwards, and the sibling authorities that apply a plan rather
  than a transaction — `MapTransitions`, `InfrastructureTransitions.apply_node_plan` — return `void`
  too. A receipt here would be a third way to learn one fact.
- **"`docs/STATUS.md` copies ownership facts out of the manifest."** (tier-2 reviewer, offered as its
  most important finding.) The row names `caps`/`initial_caps`/`history`, but so does every other row
  in that table — `map` names `hex_owner`/`feba_km`, `ijfs` names three model classes and two handles,
  `infrastructure` names the node lifecycle and its handle — and the table's own preamble says "the
  manifest is the authoritative record, **this table is the index**". Singling out the new row would
  make the index inconsistent without making anything less likely to rot. The archived plan doc is a
  historical record of one change, which is the one place per-plan narrative is supposed to live.

### From the plan-review round (2026-07-30)

Findings measured and turned down, with the evidence:

- **"Merge `caps`/`initial_caps`/`history` into the `force` aggregate so one authority commits the
  whole packet."** (tier-1 reviewer, alternative fix for the atomicity finding.) Rejected in favour of
  the two-stage protocol in §3.1, which removes the same failure mode. `ForceTransitions.gd` is already
  the largest authority in the tree at 37 KB and its invariants are about battalion LOCATION; a
  scenario-dialled lift budget is not force placement. The manifest's `_schema_rules` explicitly
  sanction one model split across two aggregates by disjoint fields — it is how `SealiftCohort` already
  splits troops from hulls. The atomicity concern itself was ACCEPTED and is fixed.
- **"The two `AirInsertionResolver.gd:<lines>` citations in
  `docs/plans/0036-airborne-cost-and-cadence.md:73` and `:124` go stale when the file moves."** (tier-2
  reviewer.) Measured: those are basename-plus-line citations, not paths, so a directory move does not
  affect them, and `tools/validate_doc_anchors.gd` bans `file.gd:123` citations only under
  `docs/systems/` (its check 1) while requiring backticked *paths* to exist (check 2). The three
  anchors in §5 remain the complete set of path references. The line numbers were already stale-prone
  and are 0036's business.
- **"The plan contradicts itself: `AirInsertionStateBuilder` is deleted and also gained as a
  dependency."** (tier-2 reviewer, offered as its most important finding.) The plan says the opposite
  and always did — §4: *"`AirInsertionStateBuilder` is NOT deleted, moved or emptied."* Nothing in this
  plan removes that class or moves any of its logic into `GameData.gd`. Recorded here because a
  confident, fully-formed misreading is exactly what the next agent would otherwise re-derive.

## 11. Closeout homes

`docs/STATUS.md` (mutation-authority summary table); `docs/systems/air-insertion/air-insertion.md` and
`docs/systems/roc-mobilization/roc-mobilization.md` **State & authority** sections (aggregate,
authority, outcome/receipt types, manifest link — no ownership lists);
`docs/systems/mutation-authority/mutation-authority.md` §5/§6 if a trap or authority shape generalizes;
`docs/DECISIONS.md`; `docs/plans/BACKLOG.md` check-off; plan archived to `docs/plans/ARCHIVE.md`.

## 12. Dependencies

Requires 0042, 0044, 0046; follows 0047 under the campaign's serial execution rule. Plan 0036 may land
first only if it adds no unsanctioned mutation path.
