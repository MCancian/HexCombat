---
name: hexcombat-code-quality
description: Code-quality budgets and hygiene rules every change must meet — complexity/length/param ceilings, magic-number policy, naming glossary, duplication rule, dependency ceiling, test-quality bar. Apply to TOUCHED code on every change; read before writing any new function, resolver, or test, and when tempted to refactor for style.
---

# HexCombat code quality

Budgets agents must meet on code they **touch** (not retroactive sweeps). Baseline audit +
numbers: `docs/reports/2026-07-16-code-quality-baseline.md`. Re-measure anytime:
`python3 tools/gd_metrics.py . /tmp/m.json` (CC/length/deps/magic/duplication per function/file).

## Budgets (touched code)

| Axis | Target | Hard cap | On breach |
|---|---|---|---|
| Function cyclomatic complexity | ≤ 10 | 15 | extract helpers named by job |
| Function length | ≤ 40 lines | 60 | split by phase: parse → compute → mutate → report |
| Parameters | ≤ 4 | 5 | pass a typed context object (`scripts/model/`) |
| File class references (preload/class_name/autoload) | ≤ 8 | 10 | split file or justify in the file header comment |
| Copies of a logic block | 2 | 2 | third copy = extract a shared static helper instead |

`GameState` is the sanctioned exception on deps (turn conductor) — but never ADD a dependency
to it without checking whether a resolver/builder should own the reference instead.

## Magic numbers

Gameplay-relevant numeric literals live in `data/*.json` (if the USER may tune them —
`hexcombat-config-and-knobs`, and note change-control non-negotiable #7: no speculative knobs)
or in a named `const` with a unit-bearing name (`EARTH_RADIUS_KM`, not `6371.0`). Inline
literals are acceptable only for: view-layer cosmetics (colors, pixel offsets), array indices,
and mathematical identities. If a reviewer can ask "why this number?", it needs a name.

## Naming

- Functions: `verb_noun`, honest about effects — a function that mutates GameState is
  `apply_*`/`update_*`, never `get_*`/`calculate_*`.
- No new abbreviations. Existing habit (`mf`, `req`, `cap`, `amt`, `asm`, `eff`, `cfg`, …) is
  **fix-on-touch**: when you edit a function, spell out its locals (`minefield`,
  `required_capacity`). Do NOT mass-rename across golden-touching files for style alone.
- Sanctioned domain terms (no spelling-out needed): `q/r/s` (hex coords), `feba`, `dos`,
  `oob`, `ijfs`, `sead`, `manpads`, `pk`, `z_day`/`x_day` (glossary:
  `hexcombat-wargame-domain-reference`).

## Tests

- New resolver/service/builder ⇒ dedicated behavioral suite in `tests/`: feed a minimal
  fixture + `ScriptedDice` (`tests/helpers/`), assert computed outcomes and report shape.
  Patterns: `tests/sealift_resolver_test.gd`, `tests/infrastructure_resolver_test.gd`.
- No trivial tests: never assert getters, constructor defaults, or constant values EXCEPT
  deliberate data-pin regression tests (label them so: `test_plan0006_defaults_regression`).
- View/UI files, data lookups, and research-harness adapters do not require suites; the
  validator+golden layer covers the turn path.

## SRP shape rule for resolvers

A `resolve()` may orchestrate, but each of its jobs — config parse, candidate selection, dice
resolution, GameState writeback, report/ledger shaping — lives in its own private helper.
Prefer helpers that RECEIVE rolled results over helpers that roll (keeps RNG draw order
auditable; see dice-order trap in `hexcombat-change-control`).

## When NOT to clean

- Never refactor golden-touching code for style alone — every extraction there costs a full
  golden byte-stability proof (`hexcombat-change-control`). Bundle hygiene with real work.
- Never rename public API / observation-contract fields for style (breaks
  `docs/LLM_OBSERVATION_SCHEMA.md` consumers).
- Duplication under 3 copies, cosmetic view literals, and legacy abbreviations you're not
  otherwise touching: leave them.
