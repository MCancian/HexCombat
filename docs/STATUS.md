# HexCombat — Current State

**What works today, present tense, no dates.** Per-module detail lives in
`docs/systems/<module>/STATUS.md`. This file covers only cross-cutting concerns
that no single module owns. The full one-home-per-fact map and task-shaped reading lists
live in `AGENTS.md` → Orientation; recording rules in `hexcombat-docs-and-writing`.
Forward work: `docs/plans/`. Why/history: `docs/DECISIONS.md` → `docs/archive/`.
Lessons: per-module `docs/systems/<module>/RETRO.md`.

## Cross-cutting

**Engine.** Godot 4 / GDScript. WeGo turn model in `GameState` (autoload): plan orders →
`resolve_turn(dice)` → `begin_next_turn`. Deterministic via an injectable `Dice` (seeded; no global
RNG — enforced by a validator). RNG is **hierarchical** (`Dice.derive(salt)`): the root turn seed
spawns independent substreams per phase and per contested hex (`ijfs:<turn>:<day>`,
`antiship:<turn>`, `combat:<turn>:<hex_id>`), so a roll-count change in one phase or hex never
scrambles another's dice (`ScriptedDice.derive` returns self, so scripted fixtures are unaffected). `GameData` (autoload) loads hexes, both OOBs (PLA + ROC brigades),
ships, theaters, beaches. `EventBus` for signals. **Every phase's logic lives in a pure
`RefCounted` class** — under `scripts/calc/` when it writes no campaign state (`AirInsertionResolver`,
`MobilizationResolver`, `SealiftResolver` since 0045, `AntishipResolver` since 0050), otherwise under
`scripts/resolvers/` (`FrontlineResolver`, `CleanupResolver`, `OffloadResolver`, `IjfsResolver`,
`CombatResolver`, `InfrastructureResolver`). **The second set is empty in practice as of 2026-07-31**:
the closeout measured all six and none writes campaign state either, so the directory split has
outlived the distinction it encodes — plan 0055 proposes emptying it. (`SupplyResolver` is long gone —
supply is `SupplyBill` + `DosConsumption` in `calc/` applied by `SupplyTransitions`.) Turn orchestration is **`TurnConductor`** (also `RefCounted`, all `static`):
its methods take a `GameStateData` value object as their first argument, own the EventBus emits,
cross-phase field assignment, and combat casualty/FEBA/retreat application (which stays in the
conductor deliberately: per-hex application interleaves with the next hex's contributor
gathering). The four **arrival** phases (sealift, amphibious offload, ROC mobilization, air
insertion) live in **`ReinforcementPhases`**, the two **fires** phases (IJFS, anti-ship + mines) in
**`FiresPhases`**, the end-of-turn accounting pair (supply, cleanup) in **`TurnClosure`**, and the
force-authority seam every brigade placement/activity write and protected roster shrink uses in
**`ForceTransitions`** (which also hosts the pool/roster tripwire; the `RosterMutations` compatibility
wrapper 0038 created was eliminated by 0044) — `TurnConductor.resolve_turn` still holds the whole ordered call list,
so the modules own how a phase resolves and never when it runs (plans 0038/0044). **Directories name the role
(plan 0043/0052)** — see the table below. Runtime state itself is the plain **`GameStateData`** value object
(`scripts/model/`); **`GameState` (autoload) is a thin state-holder** — it owns one
`GameStateData` and exposes delegating wrappers to `TurnConductor` (turns), `OrderValidator`
(order validation), and `GameStateBuilder` (scenario construction), plus typed forwarding
properties for the fields external callers read (plan 0014 / decomposition campaign). New phases
follow `.claude/skills/hexcombat-add-phase-resolver`. Order validation (`add_move_order` /
`add_commit_order`) returns a typed **`OrderResult`** (`ok`/`code`/`message`) rather than
`push_error`, so callers — the LLM API included — can branch on the rejection and surface its
reason (plan 0017).

### Where a file goes

The directory a file lives in is a CLAIM about the file, and each claim has a test you can apply
without reading the file's history. Getting this wrong is how a writer ends up in a directory whose
whole point is that it holds none.

| Directory | The claim | The test |
|---|---|---|
| `scripts/phases/` | Coordinates one group of phases: computes nothing itself, applies nothing itself | Does it only ORDER calls and thread results? |
| `scripts/resolvers/` | The per-phase resolver — decides what happens in that phase | Is it the phase's own logic, and does it still write campaign state? **No file in it passes the second half any more** (measured 2026-07-31) — plan 0055 |
| `scripts/calc/` | Write-free calculation: returns outcomes, never applies them | Does it write NO campaign state at all — including through arrays/dicts it was handed? |
| `scripts/ijfs/` | A pipeline stage of one subsystem: computes AND applies, at its own draw point, through that aggregate's authority | Would applying its result later change how many dice are drawn? (if yes, it belongs here rather than in `calc/`) |
| `scripts/builders/` | Builds fresh, unpublished state from content/scenario data | Does anything hold the object before `build()` returns? (must be "no") |
| `scripts/loaders/` | Content files → typed objects | Is its input a data file rather than live state? |
| `scripts/transitions/` | A mutation authority — THE writer for one aggregate | Is it named as an `authority_path` in the manifest? (the directory grants nothing on its own) |
| `scripts/model/` | Data + its own structural self-checks | Does it hold state and validate only itself? |

`scripts/ijfs/` is the one directory whose claim is neither "computes" nor "applies" but both, and it
exists because of a constraint rather than a preference (plan 0046). IJFS stages consume dice
CONDITIONALLY on state an earlier stage just wrote, and later stages choose which targets to iterate by
reading it — so deferring application to the end of the day would change the draw count, which the
golden pins forbid. They call `IjfsTransitions` at the exact point they used to assign. The three IJFS
helpers that genuinely compute nothing else (`IjfsAdHealth`, `IjfsWarmup`, `IjfsFiringCapacity`) moved
to `calc/`; widening `calc/`'s claim to cover the rest would have made it untrue everywhere.

Two worked examples, because the boundary that matters is `resolvers/` vs `calc/`:
`AntishipResolver` stayed under `resolvers/` from 0043 to 0050 for one reason — a single function
rewrote the caller's `ship_reserve` entries in place, which failed the `calc/` test. Plan 0044 replaced
that seam with `ForceTransitions.apply_crossing_loss` and left the function with **no production caller
at all**, so 0050's closeout deleted it and the file moved to `calc/`. The lesson generalizes: a
directory claim can go stale WITHOUT anyone editing the file, because what made it true was deleted
somewhere else. `SealiftResolver` moved TO `calc/` in plan 0045, but only
once it stopped writing anything at all — the last write was a `ship_category` stamp it put straight into
force-owned reserve rows through an untyped alias, invisible to the gate. Moving it before that fix would
have put a writer in `calc/`. Note also that a GDScript `class_name` is path-independent, so relocating a
file changes no call site — the cost of such a move is the path, its `.uid` and doc references, nothing more.

**Turn resolution order** (12-step high-level summary of `TurnConductor.gd`'s actual 16 granular execution steps): IJFS air/missile fires → IJFS maneuver casualties →
**sealift (tick ship returns + embark the crossing wave)** → anti-ship crossing → amphibious offload
→ ROC mobilization → air insertion → movement & commit → ground combat → FEBA retreats → hex
ownership → supply → cleanup (+ victory census). The front-line phase is **not** in this pipeline —
it takes operator-drawn polyline coordinates and is called only through the `GameState` façade.

**Research default vs golden fixture** — `scenario_default.json` is the realistic
deep-pool sustained invasion (research/self-play); the pinned gate runs the frozen
`scenario_golden.json` (one-shot assault) via `HEXCOMBAT_SCENARIO`, keeping golden pins byte-stable
as the default evolves. Deep-pool coverage: `tools/validate_deep_pool_smoke.gd`.

**`roc_full_defense` scenario** — variant placing all 32 ROC brigades (124 battalions) at their
real garrison hexes vs the default's 4 PLA amphibious brigades; select with
`--scenario=roc_full_defense`. Gives AI-vs-AI games a multi-turn fight instead of the default
4-defender beachhead's turn-1 census decision. Its victory census is restricted to the 451-hex
main island (see `docs/systems/frontline-cleanup-victory/STATUS.md`).

**Default scenario = full ROC defense (USER call)** — `data/scenarios/scenario_default.json`
places all 32 ROC brigades (laydown shared with `roc_full_defense`; beaches 1/3/6/9 garrisoned
on-hex, every landing beach covered on-hex or adjacent — pinned by `validate_scenario_data.gd`).
Under empty-orders self-play the default now runs to the 40-turn stalemate census pinned
in `validate_golden_victory.gd` (the 4-brigade landing wave cannot out-census the full ROC defense;
victory FIRING stays covered by `tests/victory_conditions_test.gd`).

## Module status (detail in each module's STATUS.md)

| Module | Status file | What |
|---|---|---|
| Ground combat | `docs/systems/ground-combat/STATUS.md` | BOOTS M0–M7, movement, FEBA, casualties |
| Amphibious offload | `docs/systems/amphibious-offload/STATUS.md` | D1 landing, sealift lifecycle, offload capacity |
| Supply / DOS | `docs/systems/supply-dos/STATUS.md` | D2 Red supply pool, effectiveness |
| Anti-ship & mines | `docs/systems/antiship-mine/STATUS.md` | D3 crossing damage, mine model, off-island strikes |
| IJFS | `docs/systems/ijfs/STATUS.md` | D4 air/missile fires, MANPADS, maneuver attrition |
| ROC mobilization | `docs/systems/roc-mobilization/STATUS.md` | Reserve phase-in |
| Air insertion | `docs/systems/air-insertion/STATUS.md` | PLAAF airborne path onto Taiwan |
| Front-line / cleanup / victory | `docs/systems/frontline-cleanup-victory/STATUS.md` | D5 polyline, cleanup, census |
| Terrain | `docs/systems/terrain/STATUS.md` | 5-class terrain, movement cost, combat modifiers |
| LLM API & self-play | `docs/systems/llm-api-selfplay/STATUS.md` | Observation/action contract, LLM players |
| Research harness | `docs/systems/research-harness/STATUS.md` | Batch runner, sweeps, reports, Monte Carlo |
| View layer | `docs/systems/view-layer/STATUS.md` | Brigade markers, briefing viewer |
| Turn engine | `docs/systems/turn-engine/STATUS.md` | State machine, WeGo model, phase coordinators |
| Hex grid | `docs/systems/hex-grid/STATUS.md` | Grid topology, axial coords, HexMath geometry |

## Verification

The canonical gate — `bash tools/run_all_tests.sh` (Linux; resolves Godot via
`$GODOT_BIN` else `godot` on PATH) or `pwsh tools/run_all_tests.ps1` (Windows) — runs: import → headless smoke →
`tools/validate_*.gd` (golden turn, anti-ship, IJFS, metrics, victory e2e, data validators,
no-global-RNG) → GdUnit4 suites under `tests`. Must end **ALL PHASES GREEN**. A debug-only assert
(`OS.is_debug_build()`-gated) at the end of `resolve_turn` checks `GameData.validate_runtime_indexes()`,
so any silent brigade↔hex index desync fails loud in every debug/test/headless turn (compiled out of
release).

**Gate anti-silence properties.** Three ways the gate could previously lie, now closed:
a validator that exits 0 while printing **no `PASS:` marker** is a failure rather than an OK (a
validator that silently does nothing used to look identical to one that verified everything); every
validator is invoked with `--quit-after`, so a dependency class that fails to compile produces a named
failure instead of an unbounded hang (`_initialize` runs and prints its banner, but the failed call
never reaches `quit()`); and `tools/validate_tool_script_purity.gd` derives its guarded set as the
**transitive compile-time closure of `tools/*.gd`** rather than one named file, so any class a `-s`
tool pulls in is checked for autoload identifiers. `tools/validate_pool_enumeration.gd` closes the
ghost-landing family structurally: it walks live state for anything shaped like an off-map battalion
pool and fails if `GameStateData.pending_battalion_pools()` does not return it, so a new pool is caught
by its **shape** rather than by someone remembering to register it.

`tools/validate_combat_rules_threading.gd` closes the same family for combat knobs: every field
declared on `CombatRules` must be assigned in `TurnConductor.resolve_combat_at`, sourced from the
same-named `GameData` property (or listed as a computed exception with a reason), written nowhere else,
and read by something. A knob added to `CombatRules` without its assignment line used to keep its
declared default silently — combat ran, the gate stayed green, and the knob did nothing. The reader set
is derived from the source rather than hand-listed, and the validator fails if its own anchors stop
resolving, so a refactor cannot turn it into a vacuous PASS.

**Mutation authority (plan 0042 foundation).** `tools/validate_mutation_authority.gd` enforces that a
registered aggregate has exactly one writer. It resolves each write's RECEIVER TYPE (annotations,
`:= T.new()`, declared return types, `Array[T]` element types, dotted chains — scoped per function)
before asking whether that `(class, field)` pair is protected, because `destroyed` alone belongs to
four unrelated models. It detects direct/compound/element assignment, in-place container mutation,
dynamic `set()`, calls to model mutator methods, cast writes, and — as the false-negative backstop —
a write to a protected field name through a receiver it cannot type. Ownership lives in
`tools/mutation_authority_manifest.json`: authority file, protected fields and lifetimes,
construction allowances, and temporary legacy writers each naming the plan that removes it. Dead
paths, dead fields, an unclassified field on an owned model, two aggregates claiming one field, a
stale allowance, an unregistered file under `scripts/transitions/`, and a scan that saw nothing all
fail. Abstract illegal fixtures declare the rule each write FORM must trigger and are compared exactly
on every run. A separate in-memory contract pass generates one typed illegal write per REAL manifest
claim plus every ordered pair of one REAL authority writing another aggregate and scans them against
the REAL type corpus. Its
committed non-authoritative claim pin is compared exactly by aggregate, owned/hosted section and
`Class.field`, so deleting, reassigning or demoting a claim fails instead of also deleting its generated
expectation.

**Shared models are closed-world too** (2026-07-30). `owned_models` was always exhaustive, but
`hosted_fields` was not, so a field added to a model two aggregates share — `GameStateData` above all —
arrived unprotected and nothing said so. Every class any aggregate hosts must now account for **every**
mutable field it declares: claimed by exactly one aggregate, or listed under the manifest's
`shared_model_policies` with a classification from a closed vocabulary and a concrete reason. 112 fields
across 6 hosted classes were classified; the gate fails on an unclassified field, a field both claimed
and excluded, an exclusion for a field that no longer exists, a policy naming a class no aggregate
hosts or a path its host disagrees with, a duplicate policy, and a missing/unknown classification or
reason. A classification that is a **promise** (`planned_transitional`, `order_buffer`) must also name
a plan; that pointer has to sit under the manifest's `plan_dir` and still resolve, so a shipped plan
being archived turns its exclusion red exactly when the reason expires, while a pointer at some other
existing file — which could never go stale — is rejected outright. The section is not a second
ownership list: claims are derived from `hosted_fields`, and repeating one inside a policy is an error.
The same change widened the member-declaration scan **both** exhaustiveness checks enumerate: it now
matches any annotation prefix and `static var`, because `@export_range(0, 10) var x` used to be
matched by nothing at all — neither protected nor reported.

**Registered aggregates.** All are `enforced` with zero legacy writers and zero golden movement; the
manifest is the authoritative record, this table is the index. Procedure for adding one:
`docs/systems/mutation-authority/mutation-authority.md`.

**This table is an INDEX, capped at one line per aggregate.** It exists so you can see the shape of
the campaign without opening the manifest; it is not the ownership record and must never grow field
lists or rationale. For anything more specific run `python3 tools/mutation_ownership.py`
(`--fields`, `--exclusions`, `--plan NNNN`, `--writers`, `--check-pin`).

| Aggregate | Authority (`scripts/transitions/`) | Plan | Covers |
|---|---|---|---|
| `antiship_establishment` | `AntishipTransitions.gd` | 0043 | Surviving launchers, permanent losses, temporary suppression, and the container projection IJFS targets |
| `force` | `ForceTransitions.gd` | 0044 | Brigade/Battalion runtime fields, placement, roster memberships, and who is ABOARD a cohort (`bn_ids`) |
| `sealift_fleet` | `SealiftTransitions.gd` | 0045, 0050 | `ShipState` fleet projection, cohort hulls and legs, return/reload pipeline, escort SAM magazines, the `sealift_state` handle, and the crossing's BN-equivalent loss ledger |
| `ijfs` | `IjfsTransitions.gd` | 0046 | `IjfsTarget`/`IjfsMunition`/`IjfsSquadron`, the three cross-day `IjfsDailyState` containers, the `ijfs_state`/`_ijfs_day` handles |
| `map` | `MapTransitions.gd` | 0047 | `HexState.hex_owner`/`feba_km` and the `GameDataStore.hex_states` container. **Zero allowances** — construction routes through the authority too |
| `infrastructure` | `InfrastructureTransitions.gd` | 0047 | `InfrastructureNodeState` lifecycle (status, repair clock, JLSF marker), the `nodes` container, the `infrastructure_state` handle |
| `air_insertion` | `AirInsertionTransitions.gd` | 0048 | `AirInsertionState.caps`/`initial_caps`/`history` — the airframe ledger and the drop log — plus the `air_insertion_state` handle. Who is in the pool and who has landed stay with `force`: one model, two authorities, disjoint fields |
| `supply` | `SupplyTransitions.gd` | 0049 | The DOS pool, its append-only `day_history` ledger, and the `supply_state` handle |
| `order_buffers` | `OrderTransitions.gd` | 0049 | The four request queues: `orders`, `commitments`, `air_insert_orders`, `jlsf_orders` |
| `turn_lifecycle` | `TurnLifecycleTransitions.gd` | 0049 | `turn_number`, `phase`, and the `game_over`/`winner`/`_china_has_landed` latches |

Two lessons from 0046 generalize and are now in the procedure doc. First, **a protected field NAME is
claimed repo-wide**, so registering a generic one poisons unrelated code — `IjfsMunition.name` turned
22 innocent view-layer lines into unresolved-write failures and had to become `munition_name` (the
manifest's `_schema_rules` already ask for distinctive names; this is what ignoring that costs).
Second, **`status: "migration"` and an existing authority file are mutually exclusive** — a file in
`scripts/transitions/` must be some aggregate's `authority_path`, and a migration aggregate may not
declare one — so an aggregate goes straight to `enforced` and `legacy_writers` carries the migration.

Plan 0047 added the technique that makes an invariant unbreakable rather than merely documented:
**enforce it by ABSENCE.** `MapTransitions` has no `set_owner` at all — ownership is derived from
occupancy and applied by iterating only the OCCUPIED hexes, so the sticky rule (an emptied hex keeps
its last owner, which is what keeps a seized port seized after Red moves inland) cannot be written
away by a later "tidy-up" that defaults every hex. Pre-0047 that rule was a missing `else` branch.
The same plan deleted two generic setters at review rather than migrating them: a `set_x(target,
value)` whose only caller was a scripted validator lets any caller express nearly every forbidden
assignment through the permitted file.

Plan 0045 also settled how ONE object can belong to two aggregates: a sealift cohort binds troops to
hulls, so it became a typed `SealiftCohort` whose `bn_ids` is registered to `force` and whose
`hulls_by_type`/`cohort_state` are registered to `sealift_fleet`. As an untyped dictionary neither half
was enforceable — the gate resolves the receiver's TYPE, and `cohort["hulls_by_type"][t] = n` names no
type at all. A phase that moves troops and hulls together now calls each authority in turn; neither
reaches into the other's fields. `ShipState.sent_original` was deleted in the same plan: the projection
assigned it `= surviving_sent` every turn, which made its own invariant vacuous, and nothing read it.

## What is NOT done (see `docs/plans/`)

- **Graphics** (Track 5): anti-ship/mine visualization, front-line draw UI (D5-D), unit/HUD polish.
  Needs visual verification (not headless-gateable).
- **Beach first-landing ×2 defender penalty** — deferred design call; the seam is
  `TurnConductor.defender_combat_modifier`'s `* 1.0` situational-modifier slot. See
  `docs/plans/BACKLOG.md`.
- **Deferred ports** — anti-ship missile pipeline depth (strike-coverage lever), ground-casualty
  IJFS↔OOB linkage; **per-hull** escort magazines (aggregate per-type magazines shipped,
  plan 0004; per-hull granularity + damage-driven repair delay still deferred). See `docs/plans/README.md` (plan index) and
  `docs/archive/port_audit.md`.
- **Refactors** — see `docs/archive/refactor_audit.md` (e.g. victory census should count *present*, not
  OOB, battalions; typed `WarmupContext`/`HexState`).
