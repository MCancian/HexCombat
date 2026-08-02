# Red-team synthesis: Plan 0061 Part 1

## Scope reviewed

The proposed on-demand resolution-DAG generator, current `IjfsEngine.run_daily`, the calculator/interleaved/phase/transition/model surfaces, and the existing mutation-authority source scanner.

## Round artifacts

- `round-1-claude-cli.md` — substantive repository-backed review.
- `round-1-gemini-agy.md` — provider timed out with no response.
- `round-2-claude-cli.md` and `round-2-gemini-agy.md` — follow-up critiques of the hybrid design.

## Accepted points

1. The hand-traced “18-edge” oracle is stale after plan 0060: the former island-wide MANPADS contest is no longer a sibling daily step. It cannot be the acceptance target.
2. Godot exposes class paths, properties, methods, constants, and declared types through reflection, but no stable statement AST. Reflection can replace schema/signature parsing, not method-body analysis.
3. Graph nodes must be call-site instances inside ordering functions. One calculator can be called more than once with different placement and effects.
4. Read-after-write edges alone are unsafe. Write-after-read, write-after-write, container effects, and shared RNG streams also constrain reordering.
5. The existing mutation-authority scanner is the strongest repository evidence for writes. A new analyser must consume its manifest and match its receiver/type conventions rather than invent a competing field-ownership truth.
6. Generated pages need a commit/content stamp, unresolved-analysis counts, explicit confidence labels, and a warning that missing edges do not prove reorderability.
7. Deep collections, `Variant`, dictionary values, casts, lambdas, custom getters/setters, and transitive helper calls require either supported analysis or a loud unresolved record; silent omission is unacceptable.
8. Symbol export must write to a file, print an exact success sentinel, reject zero global classes, include typed-array hints/inner-class metadata, and carry a source hash checked by Python.
9. The analyser must scan all `scripts/` for closure even though it renders only selected roles, and must preserve multiline comment/string masking offsets.

## Disputed points

- A hand-maintained transition-effect table should not become a second ownership record. Transition method effects are derived from authority source; the manifest is the completeness/ownership oracle. Small overrides are acceptable only for untyped dictionary keys or semantic distinctions the manifest cannot express, and each must cite a source method.
- Refactoring the 1,600-line mutation-authority validator into a shared library before this tool ships is too risky. The first implementation may share its rules and cross-check its outputs without destabilising the gate; extraction can follow only if duplication proves costly.
- Per-ordering-function pages should be added, but not replace the USER-ruled per-calculator pages. Both zoom levels are needed.

## Clarifications

- “On demand, allowed stale, not a gate” does not mean “allowed to look authoritative when uncertain.” Generation itself may fail validation or render conspicuous uncertainty.
- The master turn page is a timeline/call graph. State-conflict edges form a dependency graph. The renderer must label these as different views instead of calling every arrow a DAG edge.
- Runtime tracing cannot discover reads comprehensively; it can only supplement static analysis on exercised scenarios.

## Recommended changes

1. Re-measure the current IJFS pipeline and replace the stale 18-edge inventory with a reviewed current oracle.
2. Add a headless Godot symbol exporter for class/schema/signature reflection; keep Python stdlib-only for orchestration, source-effect analysis, graph construction, and Markdown rendering.
3. Use multi-pass, fixed-point call/effect propagation with call-site node identity, recursive model discovery, authority-manifest integration, and explicit handling/diagnostics for unsupported syntax.
4. Model RAW, WAR, WAW, container-key, and RNG-order constraints separately. Never present “no detected edge” as permission to reorder.
5. Generate the USER-ruled calculator pages plus ordering-function pages, phase-coordinator pages, a transition data dictionary, and a turn overview. Stamp every artifact with commit/content hashes and uncertainty counts.

## Unresolved questions

- Whether reflection behaves identically on the Windows Godot 4.7 build should be smoke-tested there later; it is not a Linux implementation blocker.
- Exact automatic support for inline property setters/getters depends on current corpus use. Unsupported property bodies must be diagnosed rather than guessed.
- The best long-term home for reusable source-scanner code remains open; the initial implementation should avoid modifying the green mutation-authority gate solely for reuse.

## Residual risk

GDScript is gradually typed and Godot exposes no public AST. Any source analyser remains conservative. The safe product is therefore an evidence report with visible uncertainty, not a proof of reorderability.

## Provider/tool failures

Gemini/AGY timed out in round 1 but returned a substantive follow-up in round 2. Both panel sessions were closed after round 2.
