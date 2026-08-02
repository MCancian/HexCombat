---
name: hexcombat-code-quality
description: Code-quality budgets and hygiene rules every change must meet — complexity/length/param ceilings, magic-number policy, naming glossary, duplication rule, dependency ceiling, test-quality bar. Apply to TOUCHED code on every change; read before writing any new function, resolver, or test, and when tempted to refactor for style.
---

# HexCombat code quality

Budgets agents must meet on code they **touch** (not retroactive sweeps). Baseline audit +
numbers: `docs/reports/2026-07-16-code-quality-baseline.md`. Re-measure anytime:
`python3 tools/gd_metrics.py . /tmp/m.json` (CC/length/deps/magic/duplication per function/file).
`python3 tools/gd_metrics.py . /tmp/m.json --check-ceiling` enforces dependency ceilings and the
per-function parameter grandfather list in `tools/gd_metrics.py`; lower entries after refactors,
never raise them to hide a breach.

**Both budgets are opt-OUT, and they have deliberately different scopes** (plan 0056). Until
2026-08-01 the dependency budget was opt-IN — checked only where someone had added a `DEP_CEILINGS`
entry, which covered 5 files out of 167 — so the hard cap of 10 in the table below was documented but
unenforced, and a new file could reach any coupling at all with nothing to say so. Now:

| Budget | Scope | Rule |
|---|---|---|
| Dependencies (`ndeps`) | **`scripts/` only** | at or above **10**, a file MUST carry a `DEP_CEILINGS` entry or the gate fails |
| Parameters | **repo-wide**, incl. `tests/` and `tools/` | above `PARAM_HARD_CAP` (5) without a `PARAM_CEILINGS` entry fails |

`tests/` and `tools/` are exempt from the dependency budget on purpose: a fixture legitimately names
many classes (the top test file is at 19) and capping that discourages thorough tests for no
architectural gain. So a `tests/` file at 15 deps is not a hole — it is the design. **Do not "tidy"
`PARAM_CEILINGS` to match the narrower scope**; it grandfathers live `tests/` and `tools/` entries.

## Preflight — run this while you are DESIGNING, before any file exists

The reach-gate lesson (plan 0056): four separate red-gate cycles cost ~6 min each to rediscover
things this command answers instantly — `IjfsEngine` sits near its ceiling,
`scripts/calc/` forbids authority calls, `scripts/loaders/IjfsLoaders.gd` owns the scenario key names.
Run all three before you decide who calls whom:

```bash
python3 tools/gd_metrics.py . /tmp/m.json                 # compute ndeps/CC/params for every file
python3 -c "import json;d=json.load(open('/tmp/m.json'));[print(f\"{k}: ndeps={v['ndeps']}\") for k,v in d['files'].items() if k.startswith('scripts/')]"
python3 tools/gd_metrics.py . /tmp/m.json --check-ceiling # dry-run the gate's own ceiling verdict
```

Then apply two rules, still on paper:

- **Files you will touch:** `ndeps` must stay *below* its `DEP_CEILINGS` entry. Three coordinators
  sit *exactly* at their ceilings — `scripts/phases/TurnConductor.gd` (18/18),
  `scripts/phases/FiresPhases.gd` (13/13), `scripts/phases/TurnClosure.gd` (9/9) — and
  `scripts/interleaved/IjfsEngine.gd` carries a ceiling of 14, close to its measured 13. Naming one
  new `class_name` in any of them is an instant breach. If you must, budget a paid-for dependency
  swap (the two shapes are in `hexcombat-architecture-contract` — "the ceiling is paid for, not
  raised"), never a raise.
- **Files you will create:** a new `scripts/` file's `ndeps` = the count of distinct
  `class_name`/autoload/preload names **you** reference in it (+1 self-reference). Keep it **≤ 9**
  (10 is the hard cap; at/above 10 a file must carry a ceiling it never had). Count while you type
  the header, not at the gate.
- **Placement rules the gate teaches at 6 minutes each:** `scripts/calc/` returns outcomes and may
  make NO authority write; `scripts/loaders/IjfsLoaders.gd` owns the scenario key names resolve the
  ported source oracle for (`docs/systems/ijfs/`). Both are knowable here, before a validator yells.

Adding an entry is not free forgiveness: seed it at the **measured** value and write, next to it, why
that file's coupling is legitimate. If you cannot say why, that is the signal to fix the coupling
instead. Eleven entries seeded in 2026-08-01's baseline carry no rationale yet, deliberately — the
reasoning belongs to whoever first has cause to move one.

Skipping the preflight above has a concrete cost (plan 0047): a mid-plan red gate, plus a step that
could not be committed on its own because the dependency that pays for the new one cannot leave until
a later step. `PARAM_CEILINGS` is keyed by `path::function`, so **moving or renaming a file renders
its entry stale and fails the gate**; re-key it in the same commit as the move.

## Budgets (touched code)

| Axis | Target | Hard cap | On breach |
|---|---|---|---|
| Function cyclomatic complexity | ≤ 10 | 15 | extract helpers named by job |
| Function length | ≤ 40 lines | 60 | split by phase: parse → compute → mutate → report |
| Parameters | ≤ 4 | 5 | pass a typed context object (`scripts/model/`) |
| File class references (preload/class_name/autoload) | ≤ 8 | 10 — **enforced in `scripts/`** | split file, or add a `DEP_CEILINGS` entry at the measured value saying why it is legitimate |
| Copies of a logic block | 2 | 2 | third copy = extract a shared static helper instead |

`GameState` is the sanctioned exception on deps (turn conductor) — but never ADD a dependency
to it without checking whether a resolver/builder should own the reference instead.

**Mutation authorities** (`scripts/transitions/*Transitions.gd`) carry one extra soft budget, set from
the plan-0043 pilot: **≤ 6 public mutation operations**. It is a threshold on public methods that
CHANGE the aggregate, not a cap on total methods — private helpers and read-only queries do not count.
On breach, ask whether the aggregate is really two aggregates; do NOT split the file, because a second
file writing the same fields is the exact failure the convention exists to prevent. Measured pilot:
`AntishipTransitions`, 187 lines, 5 public operations, 3 private helpers, 6 deps.

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
