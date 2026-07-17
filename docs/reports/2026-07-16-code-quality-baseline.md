# Code-quality baseline — 2026-07-16

Point-in-time audit snapshot. **Not** an orientation doc: current behavior lives in
`docs/STATUS.md`; the standards this audit produced live in
`.claude/skills/hexcombat-code-quality`. Re-measure with `python3 tools/gd_metrics.py . out.json`.

## Method

- Custom static analyzer `tools/gd_metrics.py` (regex-based; CC = 1 + branches (`if`/`elif`/
  `for`/`while`/match arms) + boolean operators; approximate but stable across runs).
- Duplication = normalized 6-line sliding windows repeated anywhere in repo.
- Dependencies = distinct `preload`/`load` + `class_name` token references + autoload references
  per file.
- Qualitative sweeps: gem-explore (SRP/naming) and opencode (test triviality), both spot-verified
  against source before inclusion; one gem claim was rejected as hallucinated
  (a "230-line `LLMGameAPI._build_observation`" that does not exist).
- No line-coverage tool exists for headless GDScript here; coverage is reported file-level.

Scope: 196 `.gd` files, 25,035 LOC total. `scripts/` = 12,673 LOC / 594 funcs;
`tests/` = 520 funcs; `tools/` = 337 funcs.

## The eight questions

### 1. Functions doing more than one thing (SRP)

Proxy = union of (CC > 15, length > 60, delegate-flagged-and-verified): **~30 of 594 scripts/
functions ≈ 5%**. The violating shape is consistent: phase-resolver `resolve()` orchestrators
that mix config-parse + compute + GameState mutation + report/ledger shaping in one body.
Named offenders (all verified): `AntishipResolver.resolve`, `OffloadResolver.resolve`,
`MineWarfareService.resolve_ship_losses`, `IjfsEngagement.resolve_sead_engagement`,
`IjfsResolver.compute_writeback` (three independent domain sweeps in one function),
`IjfsLoaders._build_ground_targets` (iterate/compute/override/instantiate/MANPADS).

### 2. Classes with >10 dependencies (coupling)

**4 of 103 classes**: `GameState` (47), `GameData` (18), `LLMGameAPI` (14), `IjfsEngine` (12).
Verdict: coupling is concentrated exactly where the architecture puts orchestration —
GameState is the turn conductor *by design* (post-decomposition it delegates math to resolvers
but still wires everything). 47 is nonetheless the number to watch; it can only grow unless a
ceiling is enforced. Everything else is clean: median deps ≈ 3.

### 3. Cyclomatic complexity

| Threshold | scripts/ funcs | % |
|---|---|---|
| CC > 10 | 45 | 7.6% |
| CC > 15 | 17 | 2.9% |
| CC > 20 | 5 | 0.8% |
| CC > 30 ("unmaintainable") | **0** | 0% |

Worst five: `resolve_sead_engagement` 27, `_validate_ijfs_config_blocks` 27,
`OffloadResolver.resolve` 25, `validate_combat_catalog` 24, `resolve_ship_losses` 22.
**Zero functions cross the classic unmaintainable line (30+).** ~17 warrant splitting.

### 4. Duplicated logic

**3.4%** of scripts/ lines sit in a repeated 6-line window (433 / 12,673; industry "healthy"
is <5%). Hotspots: `GameState` 66 lines, `IjfsDetection` 37 (satellite/aircraft detection are
near-clones), `IjfsManpads` 33. Tests: 4.5% (fixture setup boilerplate — acceptable).
No large copy-pasted subsystems exist.

### 5. Unclear / misleading names

Misleading: none found. Unclear: a systematic **abbreviation habit** — `df`, `req`, `cap`,
`amt`, `mf`, `asm`, `ask`, `eff`, `atk`, `neut_probs`, `cfg`, `rep` — roughly **5–8% of local
variable names** in the resolver/service layer (function names themselves are good:
verb_noun, honest about effects). Policy answer: glossary + fix-on-touch, not a mass rename
(renames in golden-touching files are churn risk for zero behavior gain).

### 6. Rewrite-% for "current best practices"

**~6–8% of scripts/ LOC needs surgery; ~0% needs rewrite.** The union of all flagged functions
is ≈ 900 LOC of 12,673. The architecture already follows the practices that matter (pure static
resolvers, injected RNG, typed GDScript, data-driven content, fail-loud). This is a
post-decomposition codebase; the debt is local fat functions, not structure.

### 7. Magic numbers / hardcoded values

First pass counted **209 non-const numeric literals in scripts/** (excluding 0/1/2/±1.0/0.5/
100/1000 and `const` lines) — but 74 of those were false positives: literals inside multi-line
`const` tables (`UnitStats.TYPE_DEFS`, `SUPPORT_MULTIPLIERS`, …) that the first analyzer pass
did not recognize as consts, plus `1e-9`-style epsilons. Corrected count (analyzer fixed in the
same session): **135**, of which:
- `HexMap.gd` 93 — view-layer colors/offsets (cosmetic, low priority),
- `CombatCalculator.gd` had ~16 real formula constants (loss-rate model, FEBA scaling,
  advantage thresholds) — hoisted to named consts under plan 0009 phase D,
- `FrontLineService.gd` had an unlabeled `6371.0` — now `EARTH_RADIUS_KM`,
- remainder: config-keyed defaults with source comments and math identities (acceptable).
The data-driven rule holds better than the raw count suggested: gameplay tuning values were
already const tables or `data/*.json`; the debt was ~20 unlabeled formula constants.

### 8. Test coverage and triviality

386 GdUnit tests; **15 trivial (3.9%)**, 371 behavioral — the suite is genuinely good, the
inverse of the usual pathology. Coverage gaps (file-level; no line tool):
24 scripts/ files lack a dedicated suite — mostly view/UI (`HexMap`, `InfoPanel`, …),
data constants, research-harness adapters (acceptable), but 6 were flagged actionable:
`OffloadResolver`, `AntishipResolver`, `SupplyStateBuilder`, `ShipReserveBuilder`,
`FleetBuilder`, `AntishipSystemsBuilder`. On top of tests, the gate's validator+golden layer
covers the turn path end-to-end.

## Remediation (executed under plan 0009, same session)

Shipped: (1) 19 behavioral tests over the 6 uncovered builders/resolvers; (2) all 6 oversized
functions split into job-named helpers (golden byte-stable, one file per commit); (3)
CombatCalculator/FrontLineService formula constants named. Post-remediation measurement:
**zero functions >100 lines** (was 6); CC>20 down to 2 (both JSON-config validators, whose
branch chains are their job). Deferred to BACKLOG: GameState dep ceiling campaign, HexMap
cosmetic literals, any const→data/*.json knob promotion (USER design call required).

## Standards home

Budgets and procedures for future work: `.claude/skills/hexcombat-code-quality/SKILL.md`
(wired into `.claude/skills/README.md` and `AGENTS.md` Conventions).
