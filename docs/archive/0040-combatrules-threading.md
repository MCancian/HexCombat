---
title: "0040: CombatRules — stop hand-threading 26 fields"
status: "Complete (option (c)); option (a) deferred indefinitely"
created: "2026-07-25"
completed: "2026-07-26"
---

# Plan 0040: CombatRules — stop hand-threading 26 fields

> **CLOSEOUT — shipped 2026-07-26.** Option (c) only: `tools/validate_combat_rules_threading.gd`, no
> production code changed, gate ALL PHASES GREEN with no pin moved. Facts landed in
> `docs/systems/ground-combat.md` §"The combat-knob correspondence", `docs/STATUS.md` (gate
> anti-silence properties), `docs/DECISIONS.md` (2026-07-26), `docs/RETROSPECTIVES.md`. Option (a)
> remains deferred indefinitely; option (b) remains blocked by the tool-purity rule. The validator's
> own header is the reference for how it parses and what it deliberately does not check.

## The problem, measured 2026-07-25

`scripts/model/CombatRules.gd` holds **26 fields**. `TurnConductor.resolve_combat_at` assigns **all 26
by hand**, and **22 of them** are copied straight off `GameData`:

```gdscript
var rules := CombatRules.new()
rules.feba_base_km = GameData.feba_base_km
rules.red_supply_pool = pool
rules.red_out_of_supply_effectiveness = GameData.red_out_of_supply_effectiveness
…22 more lines of the same shape…
```

`CombatCalculator` reads 23 of them. So every combat knob costs three edits in three files, in the
right order.

**The failure mode is silence.** Add a field to `CombatRules` and forget the assignment line, and the
field keeps its declared default — combat runs, the gate stays green, and the knob does nothing. There
is no validator watching this. `hexcombat-debugging-playbook` already carries "knob does nothing" as a
recognised symptom, which is evidence this has bitten before.

This is the same shape as the bug family plan 0034/0037 closed: a hand-maintained correspondence
between two lists, with no gate on completeness.

## Options

**(a) Registry-driven population.** A single table mapping `CombatRules` field → `GameData` source,
with `TurnConductor` looping it. Adding a knob becomes one table row. A validator asserts every
`CombatRules` field is either in the table or in an explicit "computed per hex, not from GameData"
allowlist (`red_supply_pool`, `isolated_red_brigade_ids`, `not_ashore_by_type`, `defender_terrain_modifier`).

**(b) `CombatRules.from_game_data(game_data, per_hex_overrides)`** — a named constructor owning the
copy, so `TurnConductor` stops knowing the field list at all. Simpler, no reflection, but adds a
`GameData` dependency to a model class, which `hexcombat-architecture-contract` discourages — and
`CombatRules` is in the `-s` tool compile closure, where naming the `GameData` autoload is fatal
(`tools/validate_tool_script_purity.gd`). It would have to take the values as arguments, which is the
threading problem again.

**(c) Do nothing structural; add only the completeness validator.** Cheapest. Catches the actual
failure (a field that is never assigned) without moving any code.

**Recommendation: (c) first, then (a) if it still feels worth it.** (c) is maybe an hour and removes
the silence, which is the whole risk; (a) is the nicer code but touches the combat path for no
behavioural gain. **This ordering is deliberate** — the risk here is a silent no-op knob, not the
verbosity, and the verbosity is at least honest and greppable.

Option (b) is recorded so it is not re-proposed: it is blocked by the tool-purity rule.

## Shape of (c) — the completeness validator

A `tools/validate_combat_rules_threading.gd` that:

1. Parses `scripts/model/CombatRules.gd` for its `var` names (the same textual approach
   `validate_tool_script_purity.gd` uses — no reflection needed, and it keeps working if the class
   cannot be instantiated headlessly).
2. Parses `TurnConductor.resolve_combat_at` for `rules.<field> =` assignments.
3. Fails naming any field declared but never assigned, unless it is in a documented allowlist in the
   validator itself with the reason.
4. Optionally also fails on a field assigned but never READ by `CombatCalculator` / `CombatResolver` —
   a dead knob is its own bug (report first, promote to failure only if it is clean today).

Verify it by deleting one assignment line and watching it go red, then restoring — per
`hexcombat-diff-review`, a validator that has not been seen to fail proves nothing.

### Measured before implementation (2026-07-26, commit `dc8df7e`)

Confirms the plan's premises and settles the two open questions in it.

- `scripts/model/CombatRules.gd`: **26 `var`s**, all declared `var <name>: <Type> = <default>` at
  column 0, no `const`/`func`/`@export`/`setget`.
- Population is still `resolve_combat_at`, **`scripts/resolvers/TurnConductor.gd:199-257`** — plan 0038
  moved the file, not the function. Construction at :206, assignments a contiguous **:207-232**, one
  per field, in declaration order. 26 declared, 26 assigned — complete today.
- Sources: **22 `GameData.<same-name>`**, 2 from `state.` (`isolated_red_brigade_ids` ←
  `state.isolated_air_landed_brigades` — the one name mismatch; `not_ashore_by_type`), 1 turn-scoped
  local (`red_supply_pool` ← `pool`), 1 per-hex call (`defender_terrain_modifier` ←
  `defender_combat_modifier(hex_id)`). The plan's 4-entry "computed, not from GameData" allowlist is
  exactly right.
- **All 26 fields are read**, as literal `rules.<field>`, by exactly two files:
  `scripts/CombatCalculator.gd` and `scripts/resolvers/CombatResolver.gd`. `CombatForces.gd` never
  mentions `CombatRules`. **So plan item 4 (dead-knob detection) can ship as a hard FAIL, not a
  report** — it is clean today.

### Constraints discovered that the sketch did not know

1. **The validator must reach every file it parses by path string, and read it with `FileAccess`.**
   `validate_tool_script_purity.gd` seeds its compile closure two ways
   (`validate_tool_script_purity.gd:133-146`): the `class_name` identifiers appearing in each
   `tools/*.gd` after comments and string literals are stripped, **and** literal
   `preload("res://….gd")` / `load("res://….gd")` paths in the raw source. Either one would pull
   `TurnConductor.gd` into the `-s` compile closure, where it names `GameData` — and the purity gate
   would go red, exactly as its header promises ("TurnConductor may name GameData freely: no tool names
   it. If a tool ever does, this gate fails"). So: no bare `TurnConductor` / `CombatRules` /
   `CombatCalculator` / `CombatResolver` / `GameData` identifier, **and** no `load()`/`preload()` of
   those paths either. `FileAccess.get_file_as_string` triggers neither mechanism.
   Naming `ValidatorHarness` is safe, but **not** for the reason the first draft of this plan gave: it
   is not "already in the closure". `class_paths` is built only from `SCRIPT_DIRS = ["res://scripts"]`
   (`validate_tool_script_purity.gd:40,95`), so no `tools/` class is in the identifier scan at all.
2. **Do NOT assert default parity between `CombatRules` and `GameData`.** Two defaults deliberately
   differ from the `GameData` value that overwrites them: `feba_base_km` 2.0 vs 3.5,
   `red_out_of_supply_effectiveness` 1.0 vs 0.5. The `CombatRules` value is the neutral-for-unit-tests
   default. A parity check would false-positive on both.
3. **`CombatRules` defaults are golden-adjacent.** `tests/combat_golden_test.gd:12,43` and four other
   test sites construct `CombatRules.new()` and use the **bare defaults**. Changing any default is a
   golden-drift event even though production overwrites all 26. The validator must not tempt anyone
   into "aligning" them (hence constraint 2).
4. **Use `tools/ValidatorHarness.gd`** (`ValidatorHarness.new(label)` → `.fail()` / `.check()` →
   `.finish(self)`). It is the current convention for a *new* validator; its `finish()` emits the exact
   `PASS: <label> succeeded` / `FAIL: <label> found N issue(s):` wording the gate greps for.
5. **No registration anywhere.** `run_all_tests.py:108` globs `tools/validate_*.gd` non-recursively.
   Filename + directory is the whole contract. It runs under `--quit-after 300` with
   `HEXCOMBAT_SCENARIO=scenario_golden`.

### The checks, final list

Anchor integrity first, because every other check is vacuous if the parse missed:

0. **Anchors resolve** — the rules file yields ≥1 field, the populator function is found, its
   assignment block is non-empty. FAIL naming the anchor otherwise. Without this, plan 0038-style file
   moves turn the validator into a silent no-op that still prints PASS — the exact failure class this
   plan exists to close.
1. **Declared but never assigned** → FAIL. (Allowlist mechanism kept, documented, **empty today**.)
2. **Assigned but not declared** → FAIL (stale field name after a rename).
3. **Assigned twice** → FAIL (the copy-paste transposition in a 26-line block of near-identical lines
   drops a different field, which check 1 catches — but naming the duplicate is the useful diagnostic).
4. **`rules.X = GameData.Y` with `X != Y`** → FAIL, and `Y` must exist as a `var` in
   `scripts/GameData.gd` → FAIL otherwise. This is the transposition/rename catch. Needs no exemption
   list: the 4 computed fields do not match the `GameData.` RHS pattern at all. Safe as a static check
   because `GameData.gd` has no `_get`/`_set`/`_get_property_list` hooks.
5. **A field whose RHS is not `GameData.*` must be in the documented computed-source allowlist**, and
   an allowlist entry that IS sourced from `GameData` → FAIL. Keeps the allowlist honest in both
   directions; a new locally-computed field has to be justified in writing once.
6. **Dead knob** — a declared field never read as `<ident>.<field>` by any consumer → FAIL. Consumers
   are **derived, not hardcoded**: every `.gd` under `res://scripts` that names the identifier
   `CombatRules`, minus the declaring file and the populator. Hand-listing the two readers would rot
   the first time a third appears (the "derived not hand-maintained" principle
   `validate_tool_script_purity.gd` states in its header).

### Parsing rules the review round pinned down

These are the ways a text-scanning validator quietly becomes a no-op. Each is a requirement on the
implementation, not a nice-to-have — a validator that misses a declaration and prints PASS is a
*worse* version of the bug this plan closes.

- **Declaration regex must be permissive, not shape-matching.** `^var (\w+): (\w+) = (.+)$` would miss
  `var x: float` (no default), `var x := 0.0` (inferred type), and `@export var x: float = 0.0`. A
  field declared in any of those forms and never assigned would be absent from *both* lists, so the
  completeness check would compare two consistent sets and pass. Use
  `^(?:@\w+(?:\([^)]*\))?\s+)?var\s+([A-Za-z_][A-Za-z0-9_]*)` and capture the name only.
- **Godot `RegEx` is not multiline by default.** A bare `^…$` against a whole file body matches only
  from offset 0. Every pattern is either applied per-line or carries `(?m)`.
- **Strip comments and string literals before matching**, or a commented-out
  `# rules.foo = GameData.foo` counts as an assignment.
- **Derive the local variable name** from `var <ident> := CombatRules.new()` rather than hardcoding
  `rules`, so renaming the local does not blind the assignment scan.
- **Reject the write forms the scan cannot verify** — `rules.set("field", v)` and compound assignments
  (`+=`) — with a FAIL that says so, instead of reading past them.
- **Scope is `res://scripts` only.** `tests/combat_terrain_modifier_test.gd:52-55` assigns four fields
  on a test-local `CombatRules`, and six test sites use the bare defaults; test code is deliberately
  outside the check and the validator header says so, so nobody later reads the omission as a bug.

### Proving the validator can fail

Per `hexcombat-diff-review`, a validator never seen red proves nothing. Each mutation was applied to
the real tree, the validator run standalone, then `git checkout --` on the file. **Done 2026-07-26 —
all nine behaved as required:**

| Mutation | Expected | Result |
|---|---|---|
| delete `rules.combat_min_loss_rate = …` from the block | check 1 names the field | FAIL, named `CombatRules.gd:27` |
| feed `combat_max_attacker_loss_rate` from `GameData.combat_max_defender_loss_rate` | check 4 | FAIL, named the transposition |
| add an unassigned, unread `var probe_knob: float = 0.0` | checks 1 + 6 | FAIL ×2 |
| the same as `var probe_knob := 0.0` (inferred type, no default given) | checks 1 + 6 | FAIL ×2 — the relaxed declaration regex holds |
| rename the populator function | check 0 | FAIL, told the reader which const to update |
| rename the local `rules` → `r` throughout the block | **PASS** — the local is derived | PASS |
| replace a `GameData` copy with a literal `1.0` | check 5 | FAIL, pointed at `COMPUTED_SOURCES` |
| convert one line to `rules.set("feba_base_km", …)` | rejected, not read past | FAIL ×2 (unverifiable form + the field now unassigned) |
| add a second writer in another function of the populator's file | second-writer check | FAIL, named the line |
| move one assignment out into a helper called from the populator | **loud, not silent** | FAIL ×2 (unassigned + second writer) |
| rename a computed field so its `COMPUTED_SOURCES` entry goes stale | allowlist-liveness check | FAIL ×4, the first naming the dead exception |
| declare the unassigned field as `@export var probe_knob: float = 0.0` | checks 1 + 6 | FAIL ×2 — the annotation prefix is consumed |
| `rules.feba_base_km += 1.0` in a helper (compound write) | second-writer check | **PASS before the fix — the blocker**; FAIL after |
| `if true: rules.feba_base_km = 9.0` on one line in a helper | second-writer check | **PASS before the fix**; FAIL after |
| `rules.set("feba_base_km", 9.0)` in a consumer | dynamic-write check | FAIL, says the name is unresolvable |

`git status --short` clean after each revert, and before the gate run that counts.

Gate: **ALL PHASES GREEN** (1 pre-existing `validate_knob_registry` teardown-flake warning). The golden
turn and cleanup pins are untouched, as they must be — no production code changed.

### Explicitly out of scope (checked, don't re-raise)

- **A GdUnit test for the validator.** Both reviewers independently said no, and the precedent agrees:
  `validate_no_global_rng.gd` and `validate_tool_script_purity.gd` ship without one. A validator *is* a
  test; check 0 is its self-verification against structural drift; the four mutations above are the
  evidence. Mocking source files to exercise regexes would be brittle.
- **An exemption mechanism for check 4** (`rules.X = GameData.Y` with `X != Y`). Both reviewers
  confirmed there is no legitimate reason for a differently-named source. Any mismatch is an incomplete
  rename, which is the failure being hunted.
- **Default parity between `CombatRules` and `GameData`.** See constraint 2 above — two defaults differ
  on purpose.
- **Option (a), registry-driven population.** Deferred indefinitely per `docs/plans/README.md:52-54`.
- **"Check 0 must require the assignment count to equal 26."** One reviewer called this a blocker. It is
  the rot pattern this project forbids — a hardcoded count that must be edited on every legitimate field
  addition, and which says nothing the field-by-field comparison does not already say. The concern
  behind it (an assignment moved into a helper being invisible) is real but produces a **loud double
  failure**, not a silent pass; that was mutation 10 above, and the validator header explains the
  signature so the next agent recognises it.
- **Line-range matching for the assignment block.** Never proposed and never used: the function body is
  found by name and delimited by indentation, so a file move like plan 0038's does not rot it.

### Coverage of the two review rounds — read this before trusting the count

- **Plan round: full.** All three models delivered (`gem-explore`, `deepseek-v4-flash-free`,
  `nemotron-3-ultra-free`); their accepted findings are in "Parsing rules the review round pinned down"
  and the rejected one is below.
- **Diff round: one complete review, not three.** `gem-explore` delivered five findings, all evaluated
  below. **Both free opencode models failed to produce a write-up**, twice each, for infrastructural
  reasons rather than review verdicts: `nemotron` hit `database is locked` when run concurrently with
  `deepseek` (the opencode session DB does not tolerate two simultaneous runs — **run them serially**),
  then died on `Streaming response failed`; `deepseek` twice stopped after its tool traces with no final
  message, which `hexcombat-plan-review` already records as its known failure mode. A second
  `gem-explore` pass over the final file hung past its timeout and was killed. Their traces are not
  worthless — both independently ran the validator and confirmed it passes, and both re-derived the
  26/26 field-and-assignment counts and the derived-locals behaviour — but neither produced findings.
- **What substitutes for the missing reads:** the twelve mutations in the table above, each proving one
  claimed check actually fires, plus a control-flow audit of `_initialize` confirming that no recorded
  failure can be discarded (failures accumulate on the harness; both early-return paths call `finish`)
  and that the empty-alternation crash path is unreachable because `locals.is_empty()` fails at check 0
  before any regex is built from it.

### Diff-review findings, rejected on the code (don't re-raise)

- **"`\b` in the type-annotation regex is a backspace character, so the check never matches."** Called a
  blocker; the source has `\\b`, correctly escaped. Refuted by measurement rather than by reading:
  `CombatCalculator.gd` contains no `CombatRules.new()`, so it is discovered as a reader ONLY through
  that typed-parameter regex — if the regex were dead, 24 of the 26 fields would report as unread and
  the validator could not pass. It passes.
- **"End the function body at the next `func`/`var`/`const` instead of at any column-0 content."** This
  trades a loud failure for a silent one. An early end makes a field look unassigned (loud); a late end
  keeps the block open past the function, and because block lines are the sanctioned write site, that
  would *silence* a second-writer failure. Rationale now recorded at `_function_lines`.
- **"Let the assignment right-hand side be empty so a value continued on the next line still counts."**
  It would register the field as assigned from an unreadable source — which either fails confusingly or,
  once someone silences that with a `COMPUTED_SOURCES` entry, passes silently. A split value reports the
  field as unassigned, which is loud and accurate about what the parser can see.
- **"`docs/systems/ground-combat.md` and `docs/STATUS.md` quote golden pins in prose."** Half right and
  not this diff's: `ground-combat.md` has no such text, and the two real instances in `STATUS.md`
  pre-date this work — no numeric pin is added by this commit. Logged to `docs/plans/BACKLOG.md` instead
  of being fixed inside an unrelated commit.

### Accepted from the diff review

- **The one real blocker, found on a second pass over the FINAL file and worth the extra round.**
  `_check_no_other_writers` matched only `^\s*<ident>.<field> =` — anchored to the line start, plain `=`
  only. Two shapes walked straight past it and the validator printed PASS over a live second writer:
  `rules.feba_base_km += 1.0` in a helper, and `if cond: rules.feba_base_km = 9.0` on one line. **Both
  reproduced as mutations before the fix and re-run after it.** The pattern is now unanchored and accepts
  every mutating operator, and a companion check fails on a `set()` write whose field name is a runtime
  string this validator cannot resolve at all. Note what this says about the first pass: the reviewer
  that had already produced five findings on an earlier version found the actual hole only when asked
  again about the finished file. A second read of the FINAL artifact is not redundant.
- The annotation prefix in the declaration regex became `*` rather than `?`, so multiple annotations
  cannot hide a field. Proven with an `@export var` mutation.
- Independently found while re-reading the diff: a `COMPUTED_SOURCES` / `UNASSIGNED_ALLOWED` entry naming
  a field that no longer exists was dead text that still read as a considered decision.
  `_check_allowlists_are_live` now fails on it.
- Two out-of-scope nits, both in production files this commit does not touch: `CombatCalculator`'s
  `_normalize_support` is a dead pass-through to `normalize_support` and is called nowhere (**confirmed**,
  logged to BACKLOG); `GameData.DEFAULT_SCENARIO_PATH` was called unused and is **not** — `GameState`
  reads it — so that one is rejected.

## Verification

- Gate ALL PHASES GREEN. For (c), **no production code changes at all**, so no pin may move; if one
  does, something is very wrong.
- For (a), byte-stability is the whole test — the values fed to `CombatCalculator` must be identical.
  Prove it with a scratch script that builds `CombatRules` both ways and diffs all 26 fields across
  several turns, rather than trusting inspection.

## Design calls for the USER — none

No rules change, no balance change.

## Risks

- **(a) touches the combat path.** It is golden-touching by classification even though it is intended
  to be a pure move. One commit, gate green, no pin moved.
- **Reflection in (a).** `get_property_list()` on a `Resource` also returns engine properties; the
  loop must filter to script variables or it will try to assign `resource_name`.
- **Over-engineering.** If (c) lands and no knob is ever silently dropped again, (a) may simply not be
  worth doing. Revisit only when a knob is actually added.

## Dependencies / notes

- Measured at commit `ac571c5`: 26 fields declared, 26 assigned, 22 from `GameData`, 23 read by
  `CombatCalculator`.
- An earlier report of this issue said "35-field clump". That number came from a reviewer and was
  repeated without checking; the real count is 26. Recorded so the wrong figure does not propagate.
- Independent of plans 0038 and 0039. Can be done at any time; (c) does not touch `TurnConductor`, so
  it is not blocked by the dependency ceiling.
