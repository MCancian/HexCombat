# Red-team Round 2 — gemini-agy

- feature slug: plan-0061-part1-pass2
- provider: agy
- session id: 1b49f152-dbe9-4c7c-b66c-fb575b6ab17a
- provider session id: 0363237f-cb5d-4eab-8e11-ca1e80426ce8
- status: active
- ok: true
- transcript: /var/home/qyfs/.pi/agent/state/redteam-sessions/1b49f152-dbe9-4c7c-b66c-fb575b6ab17a/transcript.jsonl
- provider log: /var/home/qyfs/.pi/agent/state/redteam-sessions/1b49f152-dbe9-4c7c-b66c-fb575b6ab17a/agy.log

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

Remaining must-fix issues
1. **The Contradiction of Python Source-Effect Analysis:** The synthesis correctly admits Godot provides "no stable statement AST" and reflection cannot perform method-body analysis. Yet, it simultaneously assigns "source-effect analysis" to the Python stdlib tool. This is a fatal contradiction. If Python handles source effects, it must parse method bodies to trace local variables, loops, and aliases (`var x = state.targets`). This guarantees you will have to rewrite the 1,600-line type-inference regex engine (`TypeMap`, receiver resolution) in Python, creating a brittle, divergent parser. *Fix:* Source-effect analysis must remain in GDScript (e.g., by having the headless Godot script run a decoupled copy of the validator's parsing logic and emit a JSON dictionary of reads/writes). Python should *only* consume this JSON for graph construction and rendering.
2. **Read-Tracking Regex Explosion:** The synthesis demands tracking RAW (Read-After-Write) and WAR (Write-After-Read) edges. However, the existing GDScript validator *only tracks mutations* (`=`, `.append`, `.set`). It has zero foundation for tracking reads. Parsing reads via regex (in either language) is exponentially harder than writes because a read can be embedded anywhere in an expression (e.g., `if compute(obj.field + 1):`). *Fix:* The analyser must explicitly separate "Proven Writes" from "Heuristic Reads" in its uncertainty counts, and the generated artifact must loudly disclaim that read-dependencies (and thus RAW/WAR edges) are best-effort only, otherwise the DAG will silently drop dependency edges.
3. **Reflection Type Stripping for Collections:** If the headless Godot symbol exporter replaces textual schema parsing with reflection (`get_script_property_list()`), it must rigorously unpack `PROPERTY_HINT_ARRAY_TYPE` from `hint_string`. If it merely exports the base `TYPE_ARRAY`, the downstream body analyser will lose the element types (e.g., `Array[IjfsTarget]`), completely breaking loop variable type inference and causing a massive spike in "unresolved analysis" counts.

New findings
1. **Validator Read Blindness:** As noted above, the repository's strongest evidence for dataflow (`validate_mutation_authority.gd`) provides exactly zero code or regex patterns for tracking reads. The engineering cost of building a read-tracker from scratch will severely exceed the cost of adapting the write-tracker.
2. **Textual vs. Runtime Schema Mismatch:** The current validator deliberately uses regex for `_declared_fields` to preserve textual types (e.g., `Array[IjfsTarget]`) because its body analyser relies on that exact string matching. Splitting the tool into a Godot reflection exporter and a separate body analyser introduces a new failure mode: the textual types expected by the body analyser will mismatch the runtime schema types if formatting, enums, or hints are not perfectly translated back to their textual equivalents.

Retractions or disagreements
1. **Retraction (Stale Oracle):** I explicitly retract my Round 1 assertion that the 18-edge inventory must serve as the gold-standard acceptance test. The synthesis correctly highlights that Plan 0060 relocated the MANPADS contest, rendering that specific oracle stale.
2. **Disagreement (Python Reimplementation):** I strongly challenge the synthesis's claim that "The first implementation may share its rules and cross-check its outputs without destabilising the gate." You cannot "share rules" between a GDScript validator and a Python stdlib source-effect analyser; Python must blindly reimplement them. Rebuilding a 1,600-line type-inference regex engine across languages is not a mere "duplication cost"—it is an architectural hazard that guarantees divergent, unreliable outputs.

Nice-to-have improvements
1. **LSP-style Output:** Design the headless Godot symbol exporter's JSON output to loosely mirror Language Server Protocol (LSP) definitions rather than a bespoke dictionary. This transforms the exporter from a single-use script into a highly reusable asset for future Python-based HexCombat tooling.
2. **Cross-Platform Smoke Testing:** Since Windows compatibility was flagged as an unresolved question, add a lightweight automated GitHub Action (or local CI script) to run the headless Godot symbol exporter on Windows early in development. This ensures line-ending differences or reflection quirks don't silently break the schema generation before significant downstream logic is built.
