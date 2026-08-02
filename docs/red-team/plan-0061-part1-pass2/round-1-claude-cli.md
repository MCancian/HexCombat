# Red-team Round 1 — claude-cli

- feature slug: plan-0061-part1-pass2
- provider: claude
- session id: 14aef4d6-7a0c-4c43-853b-8ffc96f14482
- provider session id: f088502b-526b-4cb2-84d4-3faa03416677
- status: active
- ok: true
- transcript: /var/home/qyfs/.pi/agent/state/redteam-sessions/14aef4d6-7a0c-4c43-853b-8ffc96f14482/transcript.jsonl

## Prompt

```text
You are independently red-teaming HexCombat Plan 0061 Part 1 before implementation. Inspect docs/archive/0061-resolution-dag.md and relevant current code under scripts/calc, scripts/interleaved, scripts/phases, scripts/transitions, scripts/model, plus tools/validate_mutation_authority.gd. Context: proposed stdlib-only Python tool generate_resolution_dag.py scans 33 calc + 9 interleaved files, infers model-field reads/writes and transitive authority effects, validates the hand-traced IJFS 18-edge inventory, and renders per-calculator Markdown plus a turn pipeline page. User rulings: on-demand artifact, allowed stale, not a gate, docs/presentations, RNG refactor out of scope. Pass 1 already flagged that line-regex parsing is too weak and needs multi-pass symbols/calls; model schema must be parsed; estimate should grow; phase-coordinator pages and transitions data dictionary are missing. Find NEW or sharper issues, especially: whether headless Godot exposes an AST/reflection adequate to avoid Python parsing; gradual typing/aliases/casts/lambdas/collections; deep nesting; custom properties/setters; graph semantics and whether RAW-only edges are sufficient; node identity/class-vs-call-site; completeness/confidence/fail-loud UX for a non-coding designer. Recommend concrete revised five steps. Cite repository evidence. Do not merely agree with Pass 1. Required response wrapper and sections:
<<<REDTEAM_RESPONSE>>>
Major risks
Questionable assumptions
Missing safeguards
Recommended design changes
Residual uncertainty
<<<END_REDTEAM_RESPONSE>>>
```

## Response

## Major risks

**1. The 18-edge oracle is stale — it describes pre-0060 code, and it is the tool's acceptance test.**

The plan's edge table names a node "E = MANPADS contest" and cites `IjfsManpads.contest_squadrons` (historical) (plan line 99). That method does not exist:

```
grep -rn "func contest_squadrons\|manpads_contest" scripts/   → 0 hits
```

`IjfsDailyState.gd:29` records why: *"Plan 0060 R5 collapsed two MANPADS surfaces into this one; the second ledger, which held the island-wide daily squadron tax, is gone with the contest that produced it."* MANPADS today is `IjfsManpads.engage_package`, called from `scripts/calc/IjfsPackageIngress.gd:71`, **nested inside** the strike passes — not a sixth sibling step. So edges A→E, B→E, **D→E** and E→F reference a node that no longer exists, and D→E is the plan's own bolded headline ("the 'more shooters alive' claim, now specific").

Risk is not "one stale row." It is that Step N of the proposed tool is *"validates the hand-traced 18-edge inventory."* A tool tuned until it reproduces 18 edges is a tool fitted to a wrong oracle. This is the `measurement-inherits-its-question` failure exactly: the instrument was built to answer "does my tracing hold?" and will silently answer "can I reproduce a number I already wrote down?"

**2. Headless Godot exposes no AST — but it exposes the entire symbol table, and the plan's Python tool would be re-deriving it worse.** Measured on this box (Godot 4.7.1 flathub, `-s` script, now deleted):

- `ClassDB.class_exists("GDScriptParser")` → **false**. No AST. `Expression` exists but only evaluates expressions; it cannot parse GDScript statements.
- `ProjectSettings.get_global_class_list()` → **371 entries**, each `{class, base, path, language}`. Complete class→file→superclass registry, exact, free.
- `Script.get_script_property_list()` → every field with its **static type code**, including non-`@export` plain vars (`IjfsDailyState.targets type=28 usage=4096`) and distinguishing `Variant` (`squadron_force type=0 usage=135168`, NIL_IS_VARIANT) from typed.
- `get_script_method_list()` → names, arg counts, **declared return types**. `get_script_constant_map()` → consts.

So: schema, symbol table and signatures need **zero parsing**. Only statement-level read/write extraction needs source. The plan's "model schema must be parsed" (Pass 1's item) is not a Python problem to solve harder — it is a problem to delete.

**3. A second, weaker inference engine, disagreeing with the gated one.** `tools/validate_mutation_authority.gd` is 1676 lines that already do the hard part: receiver-type resolution through annotations, `:= T.new()`, declared return types, `Array[T]` loop elements, dotted chains with `[…]` unwrapping, per-function scopes; write-form detection proven by fixtures under `tools/fixtures/mutation_authority/` compared exactly every run. Its header states the measured basis: *"591 receiver-chain assignments in scripts/, of which 19 had no annotation."*

A stdlib-only Python re-implementation will be strictly weaker and will disagree. The weaker one is the one going to the designer as documentation, un-gated. CLAUDE.md's standing rule — harder up front, cleanest code — points the other way.

**4. Almost every write the DAG needs is invisible to a scan of the scanned files.** Mutation authority forbids calculators writing model fields, so the writes live two hops away in `scripts/transitions/`:

```gdscript
# scripts/interleaved/IjfsManpads.gd
static func set_remaining(target: IjfsTarget, value: int) -> void:
	IjfsTransitions.set_manpads_remaining(target, value)

# scripts/transitions/IjfsTransitions.gd:149
static func set_manpads_remaining(target: IjfsTarget, value: int) -> void:
	...
	target.manpads_remaining = value
	target.metadata["systems_remaining"] = value
```

Grep `manpads_remaining =` across the 33 calc + 9 interleaved files: **zero**. Every `manpads_remaining` edge in the plan's table (A→D, A→E, D→E) exists *only* through call-chain resolution across a directory the tool does not scan. Not an enhancement — without it those edges are absent, not approximate.

Conversely the surface is small and that is the leverage: **29 `*Transitions.*` call sites, 22 distinct functions**, across calc+interleaved. Against 124 direct dotted assignments in the same files — i.e. a naive write-scan is ~80% noise (local accumulators, ledger dicts, contexts) and 0% signal on protected fields.

**5. Node identity is a call site, not a class — and "per-calculator Markdown" structurally cannot express the graph.** In `IjfsEngine.run_daily`:

- `IjfsStrikePhase.run(...)` is called **twice** (`PRE_AD_PHASE` L~140, `POST_AD_PHASE` L~167). These are the plan's A and D — two nodes, one file.
- `IjfsAdHealth.compute_taiwan_ad_health(...)` is called **four times**, writing four different fields (`taiwan_ad_health_before`, `_after_missile_phase`, `_after_sead`, `_after`).

One page per calculator gives one `IjfsStrikePhase` page and one `IjfsAdHealth` page. The A/D distinction — the entire subject of plan 0060 — cannot be drawn. Pages must be keyed by **ordering function** (`run_daily`, `TurnConductor.*`), with nodes as call sites.

**6. RAW-only edges will tell the designer that reorderable things are reorderable when they are not.** Three classes of missing constraint, all live:

- **RNG total order.** All six steps draw from one shared `dice` (the plan's own premise, §"Why this is worth doing"). Plus a *second* spine: `ctx.air_engagement_dice = dice.derive("ijfs_air_engagements")`, retained across SEAD, MANPADS and return fire. A page showing only 18 data edges renders A and C as independent. Swap them and every later draw moves and the golden re-baselines. **For a non-coding designer this is the single most dangerous possible output**: the artifact says "free to reorder", the gate says "everything changed."
- **WAW.** `state.contest_log` is *appended* by `IjfsPackageIngress.fly_in` (`scripts/calc/IjfsPackageIngress.gd:64`) during a strike pass, and *assigned wholesale* by `IjfsEngine.gd:153` after the pre-AD pass. Pre-AD rows would be discarded; it is currently harmless only because `IjfsTargeting._filter_by_phase` keeps organic packages out of pre-AD. That is a latent overwrite held off by a filter three files away, and it is invisible to read-after-write semantics.
- **Non-commutative writes.** `IjfsTransitions.apply_squadron_losses` (L196-208) rejects `losses > squadron.alive` with `push_error` and returns. Two loss events that both succeed in one order can have the second refused in the other. Order matters between two *writers* with no reader between them.

**7. A read that writes.** `IjfsManpads.systems_remaining(target)` (L66-70) lazily seeds on first read — it calls `set_remaining`, which writes the field *and* the metadata mirror. A read/write partition that classifies by name, by getter shape, or by "returns a value ⇒ read" gets this exactly backwards, and it means *the first reader of the day mutates state*.

## Questionable assumptions

**"Model fields are the right node currency."** `IjfsTarget.gd:33` documents the counter-case in the code: `metadata["systems_remaining"]` is a live mirror, and `metadata` *"is aliased live into the strike, detection and target-status ledger rows, so dropping the key would change ledger output."* A real dependency through a Dictionary key that no typed-field edge can carry. The manifest's own schema rules name this: *"Values inside an untyped Dictionary/Array are invisible (the validator header's aliased-container blind spot)."* Measured: **337** `["string_key"]` accesses in calc+interleaved. IJFS's whole inter-step protocol is dictionaries — `run_daily` returns one, `phase1["detected_ids"]`, `sead["package"]`, `wc.get("exquisite_intel")`.

**"Typed enough for regex."** Half right, and the good half is better than the plan claims: **1206 typed var decls vs 10 untyped** in calc+interleaved. Type-directed inference is credible here. But 50 `as T` casts and 17 lambdas, and the `Variant` fields are load-bearing exactly where the graph is (`ctx.organic_budget`, `ctx.capacity_budget`, `state.squadron_force`, `state.air_classes` — all `Variant` *"because both are inner classes"*, `IjfsStrikePhaseContext.gd`).

**"33 calc + 9 interleaved."** The counts are right and the closure is not. `scripts/model` is **74** `.gd` files, not 67: `scripts/model/ijfs/` holds 7 more — `IjfsTarget`, `IjfsSquadron`, `IjfsMunition`, `IjfsPairing`, `IjfsAirPackage`, `IjfsStrikeContext`, `IjfsStrikePhaseContext`. **Every field in the plan's 18-edge table lives in that subdirectory.** A non-recursive glob resolves zero of them. (The manifest gets this right — `scan_roots: ["res://scripts", "res://tools"]`, recursive.)

**Word-boundary identity.** My own first grep for `class_name IjfsTarget` returned `class_name IjfsTargeting`. Same trap for `IjfsStrike` / `IjfsStrikePhase` / `IjfsStrikeContext` / `IjfsStrikePhaseContext`, and `destroyed` exists on `AntishipSystem`, `ShipState`, `IjfsTarget` and `Brigade` — the validator header calls this out by name as why it resolves receiver type first.

**"Reflection gives you the model."** It gives you more than the plan assumed, and one thing it does not: `Battalion.combat_strength` is a **computed getter** (`Battalion.gd:7`, `UnitStats.strength_for_type(type,1.0) * qty`) and appears in the property list as an ordinary property. A DAG would draw it as a writable node with no writer. `@export` (usage `4102`) vs plain var (`4096`) is distinguishable; **stored vs derived is not**.

**"On-demand, stale-allowed, not a gate" is the safe choice.** It is the cheap choice. It is also the repo's highest-risk documentation shape: authoritative-looking, un-gated, read by someone who cannot check it. The plan already knows this — *"A DAG whose edges are guessed would be worse than no DAG, because it would look authoritative"* — then rules the enforcement away. The ruling is fine; the compensating control is missing.

## Missing safeguards

- **No staleness stamp.** Stale-allowed with no way to tell you are reading a stale page. Free fix: stamp `git rev-parse HEAD` + a hash of the scan roots into the artifact; on regeneration, render *"generated at commit X; scan roots have changed in N commits since"*. No gate, no CI.
- **No unresolved-symbol ledger.** Every `agy`/weaker-model finding in this repo required the `ABSENT`-for-zero-hits discipline. Same here: the artifact must carry counts of what it *could not* resolve (unresolved receivers, Variant-typed carriers, dictionary-mediated flows), per page. A page with no caveats and a page with 40 unresolved receivers must not look alike.
- **No self-test against the existing gate.** Two tools now claim to know which class owns which field. Nothing checks they agree with `tools/mutation_authority_manifest.json` (67 KB of already-curated, already-enforced ownership facts).
- **No negative fixtures.** The mutation validator has `tools/fixtures/mutation_authority/` with `bad_manifest_*.json` cases, compared exactly every run, *"a missed form fails this gate as a false negative."* The DAG tool has none proposed. A silent false negative here is an edge the designer will conclude does not exist.
- **No handling of the `unknown_warmup_keys` pattern.** `IjfsEngine.gd:39-46` documents *"an unrecognized key means a typo that would otherwise silently go dead (the class of bug that left exquisite intel dormant)"*. Same failure mode for a hand-maintained effect table; it needs the same closed-vocabulary assert.

## Recommended design changes

Drop the stdlib-only-Python constraint for **inference**. Keep Python for rendering if you like. There is no environment that has this repo and not Godot — the gate requires it.

**Step 1 — Reflection export (`tools/export_symbol_graph.gd`, `-s`) (historical) (rejected name).** Emit `build/symbol_graph.json` from `get_global_class_list()` + `get_script_property_list()` + `get_script_method_list()` + `get_script_constant_map()`: class → path → base; field → static type, `Variant` flag, `@export` flag; method → arity + declared return type. Cross-check every `class_name` in the scan roots appears; abort loudly on a gap. Mark getter-only properties by one source probe (`^\tvar X: *$` followed by `get:`) so `Battalion.combat_strength` renders as derived, not writable. **This deletes "parse the model schema" entirely.**

**Step 2 — Declare the transition effect table, don't infer it.** `tools/resolution_effects.json` (historical) (rejected proposal): 22 functions × `{writes: ["IjfsTarget.manpads_remaining"], writes_container: ["IjfsTarget.metadata[systems_remaining]"], commutative: false}`. Validate it by pointing the **existing** `validate_mutation_authority.gd` resolver at `scripts/transitions/` — any write it finds that the table does not declare is `E_UNDECLARED_EFFECT`. Ten files to declare instead of forty-two to infer, and the check is real.

**Step 3 — Call-site node extraction in GDScript, reusing the resolver.** Nodes = call sites within a named **ordering function**, not classes. `IjfsStrikePhase.run` at `PRE_AD_PHASE` and at `POST_AD_PHASE` are two nodes; `compute_taiwan_ad_health` is four. Per node emit reads (`recv.field` where `recv` resolves to a model type), writes (via Step 2's table, transitively through call chains — `expend` → `set_remaining` → `set_manpads_remaining` is three hops and must resolve), and an explicit `unresolved[]`. Bound recursion depth and record where you truncated.

**Step 4 — Four edge kinds plus the RNG spine.** `RAW` (plan's semantics), `WAW` (both write, non-commutative or wholesale-vs-append — catches the `contest_log` case), `WAR`, and `RNG` — a hard total-order chain over every node touching `dice`, plus a second chain over `ctx.air_engagement_dice`. Render RNG as the spine of the page with the data edges hung off it. Legend must say plainly: *"nodes on the same RNG chain cannot be reordered without changing every later roll, even with no data edge between them."*

**Step 5 — Render per ordering function; re-derive the oracle; ship the caveats.** Pages: one per ordering function (`IjfsEngine.run_daily`, `TurnConductor.*`, `FiresPhases.*`), plus a turn pipeline page, plus the `scripts/transitions/` effect table as the data dictionary. Each page carries the commit stamp and the unresolved counts. **And the acceptance test is not "reproduces 18 edges" — it is: re-trace the day by hand against current `run_daily` first, then diff the tool against that.** Where they differ, the tool is a hypothesis, not a verdict; every difference gets adjudicated by reading, and the adjudication is what gets recorded.

**On the estimate.** It should grow, but the shape changes more than the size. Step 1 is now hours, not days (reflection replaces a parser). Step 2 is a curation task with a real check. Steps 3-4 are the cost centre and they are GDScript-against-an-existing-resolver, not Python-from-scratch. Net: less total code than the Python plan, more design work up front, and one answer about field ownership in the repo instead of two.

## Residual uncertainty

- I did not read all 33 calc files. My write-surface claim rests on the 29 `*Transitions.*` call sites and the 124 direct dotted assigns; I sampled the latter rather than classifying all of them, so the "~80% noise" split is an estimate, not a count.
- The `state.contest_log` overwrite (`IjfsEngine.gd:153` vs `IjfsPackageIngress.gd:64`): I traced that pre-AD organic packages are filtered out by `IjfsTargeting._filter_by_phase` and `ctx.organic_budget` is null pre-AD, so I believe it is currently unreachable and **not** a live bug. I did not execute a case to prove that. Worth a five-minute check by someone before it is either dismissed or filed.
- I verified reflection on Godot 4.7.1 flathub on this Linux box only. `get_script_property_list()` behaviour on the Windows box (same 4.7 line) I assume matches but did not test.
- Whether the four `compute_taiwan_ad_health` snapshots are genuinely four DAG nodes or one node observed four times is a modelling question I do not think the plan has decided, and it changes what the page looks like.
- I have not costed how much of `validate_mutation_authority.gd`'s resolver is extractable without destabilising a gate that is currently green. If it turns out to be entangled, the "reuse, don't rewrite" recommendation weakens — though "port it deliberately, in GDScript, with its fixtures" still beats a Python re-derivation.
- Pass 1's phase-coordinator and transitions-data-dictionary gaps are real and I have folded both into Step 5 rather than re-arguing them; I did not independently survey `scripts/phases/` (5 files) to size that work.
