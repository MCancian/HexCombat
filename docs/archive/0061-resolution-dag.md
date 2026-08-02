---
title: "0061: Generate readable resolution dependency maps"
status: "Shipped"
created: "2026-08-01"
updated: "2026-08-02"
---

# Plan 0061 Part 1: resolution dependency maps

**SHIPPED 2026-08-02.** The on-demand builder, focused current IJFS oracle, 93 generated pages,
uncertainty reporting, and transition dictionary landed in `tools/generate_resolution_dag.py`,
`tools/export_resolution_symbols.gd`, `tools/fixtures/resolution_dag/`, `docs/presentations/`, and
`docs/systems/turn-engine/`. Part 2 (per-node RNG substreams) remains deferred and unimplemented.

## Golden-pin budget

none — this adds an on-demand reading aid and does not change the turn path or RNG.

## Progress

- USER split the work: Part 1 is the on-demand artifact builder; Part 2 (per-node RNG substreams) is deferred.
- Review Pass 1 rejected a one-pass Python regex parser.
- Review Pass 2 re-measured the current tree and rejected the old 18-edge IJFS inventory: plan 0060 removed the island-wide MANPADS contest as a sibling daily step. Review artifacts: `docs/red-team/plan-0061-part1-pass2/`.
- Steps 1–5 are implemented. `--validate` passes, two regenerations are byte-identical, and the canonical gate is ALL PHASES GREEN (184 suites, no failures; one acknowledged teardown flake).
- Two implementation-review rounds are complete. Round 2 auto-counted one return; manual adjudication found two additional substantive returns (one malformed its numbered format, one was oversized by tool transcript). The 2-of-3 substantive quorum is met; no third round is permitted by the review cap.

## Goal

`python3 tools/generate_resolution_dag.py` regenerates designer-readable Markdown under
`docs/presentations/`. It explains:

1. the turn timeline;
2. each phase coordinator and each ordering function;
3. where each calculator/interleaved class is called;
4. which typed model fields it may read or write (campaign state and clearly labelled working/result models);
5. which ordering constraints were detected, and how certain the analysis is; and
6. which transition methods are the possible state-changing verbs.

The pages are a reading aid, not executable scheduling, not a runtime graph, and not a gate. They may
be stale between runs, but every page must say exactly which commit/content snapshot generated it.

## USER rulings (do not relitigate)

- On-demand builder, not a runtime graph and not a freshness gate.
- Generated files live in `docs/presentations/`.
- One page per calculator remains required.
- Part 2, including any RNG refactor, is out of scope.

## Review findings accepted into the design

### No public Godot AST

Headless Godot exposes class paths, properties, declared types, methods, constants, and inheritance.
It does **not** expose a stable statement AST or local-variable dataflow API. Reflection therefore
replaces model-schema/signature parsing, but it cannot discover method-body reads, calls, aliases, or
writes by itself.

The implementation is hybrid:

- `tools/export_resolution_symbols.gd` exports reflection facts to a temporary JSON file;
- stdlib-only Python performs conservative source-effect analysis, graph construction, validation,
  and Markdown rendering.

The Python analyser is deliberately a reading aid separate from the gated mutation-authority
scanner. It consumes `tools/mutation_authority_manifest.json` as the ownership oracle and reports
uncertainty; it does not claim to enforce ownership.

### Call sites, not classes, are graph nodes

A class page is an index, not the execution graph. `IjfsStrikePhase.run` is called for both pre-AD and
post-AD strikes, and `IjfsAdHealth.compute_taiwan_ad_health` is called repeatedly for different
snapshots. Ordering pages therefore identify nodes by ordering function + source call site. Per-class
pages enumerate those distinct placements.

### “No edge” never means “safe to reorder”

The analyser records separate constraint kinds:

- **RAW** — a later node reads state an earlier node writes;
- **WAR** — an earlier node reads state a later node overwrites;
- **WAW** — both nodes write the same state;
- **RNG** — both nodes consume the same visible RNG stream, so call order affects later rolls;
- **CALL** — orchestration/call placement, not a state dependency.

The renderer must not merge these into one unlabeled arrow. Potential class-field conflicts are
conservative: two accesses may touch different instances or different branches.

### Deep collections, setters, and gradual typing

- Typed `Array[T]` element types come from Godot's reflected hint metadata and textual declarations.
- Nested access is normalized to the deepest model field the analyser can prove; dictionary keys are
  retained when literal (for example `IjfsTarget.metadata[systems_remaining]`).
- Calls through `Variant`, `Callable`, dynamic `call()`, untyped dictionary values, lambdas, or a
  bounded call-graph cutoff become explicit unresolved diagnostics.
- A write to a custom property is a write to that property. Getter/setter bodies are scanned as
  methods so their additional model accesses propagate when resolvable. Unsupported property syntax
  is diagnosed; it is never silently treated as side-effect-free.
- Transitive effects propagate to a fixed point with a cycle guard, not one arbitrary level.

## Implementation steps

### Step 1 — Current oracle, contracts, and fixtures

- Re-trace `IjfsEngine.run_daily` against the current post-0060 code. Replace the stale “18 edges”
  acceptance premise with a current call-count oracle plus focused, source-reviewed RAW/RNG edges and
  transition effects; preserve the old inventory only as history in git.
- Define JSON contracts for symbols, method effects, call-site nodes, diagnostics, and edge kinds.
- Add self-test fixtures covering comments/strings, multiline calls, aliases, typed/untyped loops,
  casts, nested collection mutation, dictionary keys, transition delegation, repeated call sites,
  property setters/getters, and recursive calls.
- `--validate` runs these fixtures and a reviewed current IJFS oracle. Any oracle disagreement aborts
  generation; no pages are written from a failed validation.

### Step 2 — Headless Godot symbol export

- Add `tools/export_resolution_symbols.gd`.
- Walk all of `scripts/` at runtime (no literal script preloads that would contaminate the tool-script
  compile closure), while rendering remains scoped to calculator/interleaved/phase/transition pages.
- Export deterministic class/path/base/property/method/constant metadata, including typed-array hint
  strings and inner-class constants where reflection exposes them.
- Write JSON to a file, never stdout. Print one exact terminal `PASS:` sentinel with declared class
  count. Python requires the sentinel, matching count, parsable JSON, and matching source hash;
  process exit code alone is not success.

### Step 3 — Conservative multi-pass effect analysis

- Strip comments and strings before statement joining; join bracket-based and backslash multiline
  statements while preserving starting line numbers.
- Pass 1 indexes classes, methods, parameters, fields, return types, and ordering-function bodies.
- Pass 2 resolves local/parameter/loop aliases from annotations, `new()`, casts, reflected field
  chains, typed array iteration, and declared returns.
- Pass 3 extracts direct reads/writes, literal dictionary-key accesses, container mutators, RNG use,
  and static/local calls.
- Derive transition-method effects from the ten authority source files. Cross-check protected fields
  against the mutation manifest; do not add a hand-maintained competing effect table.
- Propagate effects through the call graph to a fixed point. Emit unresolved reasons with file,
  function, line, and syntax excerpt.

### Step 4 — Call-site graph and designer views

- Build call-site nodes inside ordering functions (`TurnConductor.resolve_turn`, phase coordinator
  methods, and multi-step interleaved orchestrators such as `IjfsEngine.run_daily`).
- Construct RAW/WAR/WAW/RNG edges separately and preserve the source call order as a timeline.
- Generate both zoom levels: ordering-function pages and the USER-required per-calculator pages.
- Generate phase-coordinator pages, `turn_pipeline.md`, and `state_transitions.md` as the mutation data
  dictionary.
- Keep Mermaid identifiers deterministic and labels plain-language; long field lists belong in tables,
  not on arrows.

### Step 5 — End-to-end validation, UX, and closeout

- Every page carries generator version, git commit, source hash, generation time, scan scope,
  unresolved counts, and a plain warning: “No detected edge is not permission to reorder.”
- Generation uses a temporary symbol file and refuses a stale/mismatched symbol snapshot.
- Run `python3 tools/generate_resolution_dag.py --validate`, regenerate all pages twice, and require a
  clean second diff (deterministic output apart from an explicitly controlled timestamp policy).
- Run the canonical full gate, perform the mandatory implementation diff review, update turn-engine
  documentation/STATUS and `docs/DECISIONS.md`, archive this plan, and commit only after review quorum.

## Implementation review findings

Accepted and implemented:

- RNG effects now remap arguments at every transitive call edge; `derive()` creates a stream but does
  not consume one. Exact fixtures prove shared streams order and sibling derived streams do not.
- Chain splitting is bracket-depth-aware, index expressions are scanned as reads, and exact fixtures
  distinguish receiver/container reads from the final nested write.
- The exporter rejects partial class-cache/autoload gaps, not merely a completely empty cache.
- Reflected inner classes produce explicit class-page diagnostics instead of silently empty pages.
- Ordering pages call themselves lexical call-site maps, flag multi-call statements, and warn about
  branches, loops, and nested evaluation rather than pretending every site executes once.
- Master/class pages link across zoom levels; the master filters lifecycle/debug internals; ordering
  pages add a compact protected-state/RNG Mermaid view.
- A computed warning overrides contradictory source purity prose. This exposed one existing violation:
  `IjfsLedgers` reaches lazy MANPADS initialization; the repair is recorded in `BACKLOG.md`.
- IJFS edge/effect expectations are exact, typed-loop/fixed-point tests are non-vacuous, and every
  authority must contribute at least one protected direct write.
- Round 2 replaced RNG expression labels with call-site provenance (same-label derived objects remain
  independent; aliases preserve a shared stream), stopped cloning one statement's assignment onto
  nested argument calls, and suppresses directional same-statement state edges.
- Nested indexes beyond the supported balanced-chain subset now stop with an exact loud diagnostic;
  ordinary generation always runs the IJFS/manifest oracles before writing pages.
- The compact Mermaid includes all four state/RNG edge kinds, inner-class leaves point back to call-site
  evidence, and escaped-backslash masking has its own regression fixture.

Reviewed but deliberately not expanded:

- Inner-class bodies remain out of scope for this conservative first analyser; they are now loud on
  `IjfsFiringCapacity` rather than falsely pure.
- The tool does not implement control-flow execution counts or nested-call evaluation scheduling. The
  output is explicitly lexical, with full state constraints kept separately.
- The standalone Python file remains one source scanner/renderer unit. Functions stay job-shaped and
  the existing mutation scanner is similarly self-contained; splitting solely by line count would add
  import seams without removing analysis coupling.

## Explicitly out of scope

- Runtime scheduling or topological execution.
- Per-node RNG substreams or any golden re-baseline.
- Dynamic dispatch (`call()`), arbitrary `Callable` dataflow, or proof of actual runtime object
  identity. These must appear as uncertainty, not guessed edges.
- Treating generated Markdown as a mutation-authority source or a correctness gate.

## Required reading

- `hexcombat-change-control`
- `hexcombat-code-quality`
- `hexcombat-validation-and-qa`
- `hexcombat-docs-and-writing`
- `docs/systems/turn-engine/turn-engine.md`
- `tools/validate_mutation_authority.gd` header
