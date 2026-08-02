# Red-team Round 2 — claude-cli

- feature slug: plan-0061-part1-pass2
- provider: claude
- session id: 14aef4d6-7a0c-4c43-853b-8ffc96f14482
- provider session id: f088502b-526b-4cb2-84d4-3faa03416677
- status: active
- ok: true
- transcript: /var/home/qyfs/.pi/agent/state/redteam-sessions/14aef4d6-7a0c-4c43-853b-8ffc96f14482/transcript.jsonl

## Prompt

```text
Round 2 follow-up. Round 1 synthesis is in docs/red-team/plan-0061-part1-pass2/synthesis.md. Read it and inspect the repo as needed. Return NEW points only; explicitly retract anything you no longer support; challenge the synthesis where evidence warrants. Focus on must-fix implementation hazards for the proposed hybrid Godot-reflection + stdlib-Python source analyser, and distinguish must-fix from nice-to-have. Require wrapper:
<<<REDTEAM_RESPONSE>>>
Remaining must-fix issues
New findings
Retractions or disagreements
Nice-to-have improvements
<<<END_REDTEAM_RESPONSE>>>
```

## Response

## Remaining must-fix issues

**1. The manifest cannot supply effects. Disputed point 1 is not implementable as written.**

Synthesis §Disputed says the analyser should consume the manifest as authoritative and add only small overrides. Measured against the file:

```
$ grep -c "set_manpads_remaining\|apply_squadron_losses" tools/mutation_authority_manifest.json
0
```

The schema has no function level at all — walking every leaf path gives only `aggregates[].authority_class`, `authority_path`, `owned_models[].fields{}`, `hosted_fields[]`, `construction_writers[].{path,fields[]}` (file-level), `legacy_writers`. It answers *"who owns `IjfsTarget.manpads_remaining`"* (the ijfs aggregate, authority `IjfsTransitions`). It cannot answer *"which function writes it"* — and that is the only datum call-site effect propagation needs.

Reconciliation that keeps the synthesis's constraint: **derive** per-function effect sets by scanning the 10 `scripts/transitions/` files, and use the manifest as a **completeness oracle** — every protected `Class.field` must be reached by ≥1 derived effect set, else emit `E_UNREACHED_FIELD`. No second ownership record; the manifest still adjudicates ownership; the derived table is checked *against* it rather than competing with it. Without this the analyser has ownership facts and no way to propagate them.

**2. The Python half has an incumbent the synthesis does not mention — and an in-repo rule about whether to touch it.**

`tools/gd_metrics.py` is **638 lines** of stdlib-only Python that already statically analyses this exact corpus (per-function complexity, per-file deps, magic numbers, duplication), is **gate-run** (`tools/run_all_tests.py:187-190`), and already ships the two primitives the DAG needs: `strip_str_comment` (line 293) and multi-line joining (`_signature_params_and_end` line 300, `const_block_depth` line 495). It has self-tests including `_self_test_path_wiring`, which asserts a normalization is *"still WIRED IN, not merely present"*.

But the house rule against importing it is already written down, in `tools/mutation_ownership.py`:

> *"It is also deliberately NOT part of `tools/validate_mutation_authority.gd` — that file is the gate, this is a reading aid, and a reading aid must not be able to break a gate."*

The DAG generator is a reading aid. So: **copy the two primitives with a citation comment, or extract them to a third module and extend `validate_gd_metrics.py`'s self-tests to cover it — do not import `gd_metrics.py` from the generator.** That closes the synthesis's open question ("best long-term home… remains open") with the repo's own precedent, and it is the same gate-safety argument the synthesis used to reject touching the mutation validator, applied consistently.

**3. Scan-root closure leaks outside the five roots.** `get_global_class_list()` returns `IjfsLoaders` and `IjfsStateBuilder` — `scripts/loaders/`, `scripts/builders/`, outside the reviewed set. Call-site resolution will hit them. Must-fix: **export reflection for all of `scripts/`** (371 global classes), *render* only the five roots. Exporting only the roots turns a resolvable callee into an unresolved diagnostic and inflates the uncertainty counts with noise.

**4. Two staleness axes, one stamp.** `.gitignore` has `/build/`, so the intermediate symbol JSON is untracked. The pipeline is source → symbols.json → Markdown, and each hop can be stale independently: regenerate the Markdown without re-running Godot and you get a confidently-stamped page built from a stale symbol table. Both hops need their own stamp, and the renderer must refuse (or banner loudly) when the symbol JSON's source stamp ≠ current tree.

## New findings

**5. Godot exits 0 on a runtime error. Measured on this box:**

```
push_error("boom"); print("PARTIAL OUTPUT"); quit()   → EXIT CODE 0
parse error                                          → EXIT CODE 1
```

So the exporter can fail to load one script mid-walk, `push_error`, continue, `quit()`, and hand Python a **truncated symbol table with returncode 0**. The DAG then renders with classes silently missing — the exact "a flake is not a pass" shape. The house already solved this: every gate phase checks `returncode != 0 **or not** re.search(r'(?m)^PASS: <specific sentinel>$')` (`run_all_tests.py:162, 171, 180, 189`). **Must-fix: the exporter prints a unique terminal sentinel plus a declared class count; Python verifies the sentinel, the count, and that the JSON parses — never the exit code alone.**

**6. The exporter must not write JSON to stdout.** Autoloads initialise around a `-s` script and print into the same stream. Measured on every probe run:

```
Loaded 466 hexes / Loaded 5 terrain types / Built neighbor lookup ...
Scenario: scenario_default (no selection — the RESEARCH default). The gate exports HEXCOMBAT_SCENARIO=...
GameData ready: 466 hexes, 149 brigades, ...
```

JSON on stdout is corrupted by construction. Write to a file; print only the sentinel.

**7. Path construction in the exporter is constrained by a gate, and the failure mode is a hang — but the constraint is satisfiable.** `tools/validate_tool_script_purity.gd` seeds its closure from *"every script any `tools/*.gd` pulls in, by `class_name` OR by a literal `preload("res://…")` / `load("res://…")` path"*, and documents the cost of getting it wrong: *"the SceneTree spins forever… Measured 2026-07-25: ~10 minutes per run, twice, with no diagnostic."* 39 of the 131 scripts in the five roots name an autoload — **all 5 of `scripts/phases/`, 7 of 10 `scripts/transitions/`, `IjfsResolver`**.

The negative result matters as much: with paths built at **runtime** (`DirAccess` walk + concatenation — the validator's documented blind spot), I loaded all 131 and got `TOTAL=131 NULLS=0`. **Must-fix as a coding constraint, not a blocker: the exporter walks directories at runtime and must contain zero literal `res://scripts/...` load paths.** A single literal added later for convenience re-arms a ten-minute silent hang in an unrelated gate phase.

**8. Reflection is blind to inner classes, and one of the blind spots is load-bearing.**

```
IjfsFiringCapacity  → 0 methods, ≤1 property   (reflects EMPTY)
get_script_constant_map() → [&"FiringCapacityBudget", &"OrganicStrikeBudget"]
```

Those two are exactly `ctx.capacity_budget` and `ctx.organic_budget` — declared `Variant` in `IjfsStrikePhaseContext.gd` *"because both are inner classes"*, and `organic_budget` is the one field that differs between the pre-AD and post-AD strike passes, i.e. the A→D carrier. A property/method-only export drops the type entirely. **Must-fix: recurse `get_script_constant_map()` for inner classes and enums; and treat "class reflects empty" as a diagnostic requiring a recorded reason** — it is 3 of 131 (`HexOwner.gd`, `IjfsFiringCapacity.gd`, `OffloadRates.gd`), small enough to adjudicate by hand, large enough to hide a real gap.

**9. Line-oriented scanning is arithmetically out.** In `scripts/calc` + `scripts/interleaved` (7,425 lines), **936 lines — 12.6% — end in `(` or `,`**, i.e. are continuations. `run_daily`'s free-shot call spans seven lines. `gd_metrics.py` solved this only for `func` signatures and `const` literals, not call statements. **Must-fix: a statement joiner runs before any pattern matching, and the analyser reports statements, not lines.**

**10. False-edge budget from prose, quantified.** 1,183 of 7,425 lines are comments (16%). Of those, **50 contain a `Class.method` token** and 78 string literals contain `ident.ident`. Both existing scanners strip first — `validate_tool_script_purity.gd`: *"Comments and string literals are stripped first, so prose about GameData — including this header — is fine."* Skip it and the DAG invents up to ~128 candidate edges out of documentation, in a repo whose doc comments deliberately name the fields and methods they discuss (`IjfsTarget.gd:33`: *"Read this field; never read the mirror"*). Strip order matters: strings before comments, as `gd_metrics.py:293` does — and its own comment calls the implementation *"crude"*, so the DAG needs it hardened, not merely borrowed.

## Retractions or disagreements

**Retracted — "write the inference in GDScript, reuse the mutation validator's resolver."** I argued this in round 1 as the harder-but-cleaner option. The synthesis rejected it as too risky, and the repo backs the synthesis, not me: 25 tracked Python tools, `gd_metrics.py` doing gated GDScript static analysis in Python already, and `mutation_ownership.py`'s explicit *"a reading aid must not be able to break a gate."* My "no environment has the repo but not Godot" point was true and irrelevant — gate blast radius, not portability, is the deciding axis. **Hybrid Godot-reflection + stdlib-Python is the right call.**

**Retracted — "declare a transition effect table" as a standalone artifact.** The synthesis is right that it would become a second ownership record. Superseded by must-fix 1: derive the effect sets, check them against the manifest. Same data, no rival authority.

**Retracted in part — my round-1 framing that per-calculator pages "structurally cannot express the graph."** Overstated. The synthesis's both-zoom-levels ruling works *provided* a calculator page enumerates its call sites rather than aggregating them: the `IjfsStrikePhase` page must list `run(PRE_AD_PHASE)` and `run(POST_AD_PHASE)` as separate rows with separate effect sets, and `IjfsAdHealth` must list its four. The constraint is on page content, not on page keying, and I conflated the two.

**Disagreement — synthesis clarification "Generation itself may fail validation or render conspicuous uncertainty" is too weak as an *or*.** Given finding 5 (exit 0 on runtime error), "may fail validation" has to be mandatory and specific, or the tool's silent-truncation mode produces a page with *zero* uncertainty markers precisely when it is most wrong. Make it: generation aborts on sentinel/count mismatch, and renders uncertainty otherwise. Never a choice between them.

**Not retracted, and worth restating because it survives the design change:** the stale 18-edge oracle (accepted point 1) is still the highest-value item, and it is a *prerequisite*, not a parallel task. Every calibration decision in steps 3-4 will be judged against it.

## Nice-to-have improvements

- **Deterministic ordering everywhere.** `get_script_constant_map()` returns a Dictionary and `get_global_class_list()` an engine-ordered array. Sort every collection before serialising, or each regeneration of a stale-allowed artifact produces a diff the USER cannot read. Also normalise `StringName` (`&"FiringCapacityBudget"`) to plain strings at the JSON boundary.
- **Diff the unresolved counts, not just the graph.** A regeneration where edges are unchanged but unresolved-receiver count jumped from 4 to 40 is a signal; a graph diff alone hides it.
- **A `--self-test` mode mirroring `validate_gd_metrics.py`.** Not a gate — but the DAG generator is the only proposed tool in `tools/` without one, and `gd_metrics.py`'s self-tests exist precisely because a metric that silently stops measuring looks identical to a clean result.
- **Make `IjfsManpads.systems_remaining`'s read-that-writes (round 1, `IjfsManpads.gd:66-70`) a named diagnostic category** rather than a one-off note — "function classified as read, resolves to a write" is worth surfacing wherever else it occurs.
- **Scenario independence.** The exporter boots `GameData` under `scenario_default` unless `HEXCOMBAT_SCENARIO` is set (its own banner says so). Reflection shouldn't depend on it, but assert that nothing in the export varies with the env var, once.
