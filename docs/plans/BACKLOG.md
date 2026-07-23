# HexCombat — Tech Debt & Hygiene Backlog

This document is strictly a place for agents to dump observations of tech debt, hygiene issues, and necessary refactors encountered during development. 

Focused multi-session efforts (features, content, balancing) get a numbered plan in the `docs/plans/` directory and are tracked in [README.md](README.md).

## Deferred Debt & Hygiene Items

**Code-quality debt deferred from the 2026-07-16 baseline** (report:
`docs/reports/2026-07-16-code-quality-baseline.md`; actionable items worked under plan 0009):

- [x] **GameState dependency ceiling** — shipped as plan 0014 (2026-07-19): state → `GameStateData`
  value object, orchestration/construction/validation → `static` `TurnConductor`/`GameStateBuilder`/
  `OrderValidator` taking `GameStateData`; deps 48→24, ceiling enforced via
  `gd_metrics.py --check-ceiling`. See `docs/archive/0014-gamestate-dependency-ceiling.md`.
- [x] **HexMap cosmetic literals**: 93 view-layer color/offset literals — hoisted opportunistically.
- [x] **Const→data knob promotion**: any const hoisted under 0009 the USER wants tunable moves to
  `data/*.json` per `hexcombat-config-and-knobs` — one USER call per knob (change-control #7).

*(Agents: append new technical debt and hygiene observations here)*
