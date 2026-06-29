# HexCombat — Forward Backlog

The active forward plan. Five tracks, in **audit-first** order. Each track has a scope, its
dependencies, and how "done" is verified. Pick the next unstarted track; finish one coherent unit at
a time; verify before moving on.

> **Doc-structure intent (Track 1 will formalize this).** Going forward: documentation of *what is
> already implemented* lives under `docs/`; *future plans* live under `docs/plans/` (this file);
> per-task lessons in `docs/RETROSPECTIVES.md`. The goal is **agent readability** — a new agent should
> orient and start a task (feature, playtest, graphics) with minimal archaeology.

---

## Sequencing

1. **Track 2 — Port-leftover audit** (read-only)
2. **Track 4 — Refactor/cleanup audit** (read-only)
3. **Track 1 — Documentation restructure** (folds in the audit findings)
4. **Track 3 — Victory conditions + end-to-end golden test**
5. **Track 5 — Graphics**

Rationale (user call): the two audits are read-only and surface findings that the doc restructure
(Track 1) should absorb and that Track 3/5 build on — so audit first, then reorganize, then build.

---

## Track 1 — Documentation restructure (agent readability)

**Goal:** make the docs efficient for *new agents*, not historians. The current planning docs
(`ORCHESTRATOR_HANDOFF.md`, `PLAN.md`) mix completed history, live state, and future intent with heavy
date-stamping — high archaeology cost per task.

**Scope:**
- **Separate implemented from planned.** Move "what has been built / how it works" into `docs/`
  (per-system or a single `IMPLEMENTED.md` map); keep forward intent in `docs/plans/`.
- **Drop dates from implemented-feature docs.** Once something is done, the date is noise; describe the
  *current* behavior in present tense. (Dates stay useful only in append-only logs like
  `RETROSPECTIVES.md` / the Decisions log, which are history by design.)
- **Establish tracking rules** — a short, explicit convention for: where a new feature gets recorded,
  how an item is marked done, and where the single "current state" summary lives (one source of truth,
  not three). Write the rules down so agents follow them without re-deriving.
- **Prune & consolidate** the long-lived planning docs: archive completed sections, dedupe overlapping
  status text, and leave one authoritative current-state entry point.
- Fold in the findings from Tracks 2 and 4 (do this track *after* the audits).

**Done when:** a new agent can answer "what works today?" and "what's next?" from one short doc each,
with no date spelunking.

---

## Track 2 — Port-leftover audit (TIV + TaiwanDefenseRefactor)

**Goal:** a categorized list of features still unported from the two source repos, each tagged
*port / adapt / skip* with a one-line rationale.

**Sources:**
- TIV (the original BOOTS oracle — see `ROADMAP.md` for file/line refs).
- `C:\Users\mdogg\My Drive\Projects\TaiwanDefenseRefactor` (the Python wargame; anti-ship missile
  pipeline mapped in `docs/antiship_missile_pipeline_ref.md`).

**Known candidates to evaluate (not exhaustive — the audit produces the full list):**
- Anti-ship **missile pipeline** depth (launches → allocate → leakers → missile_damage), tied to the
  deferred **strike-coverage** calibration lever (memory `antiship-strike-coverage-lever`).
- **Ground-casualty IJFS↔OOB linkage** (open half of the D4-H writeback — no shared ID bridge yet).
- **Per-hull escort magazines** for the crossing (D3-B3 open question — needs a ship ammo/readiness
  subsystem HexCombat lacks).
- **Per-ship-type mine neutralization likelihood** (current model uses a per-category table; the source
  data varies within a category — see RETROSPECTIVES 2026-06-29 mine-geometry).
- Any TIV mechanics not in the BOOTS scope that the playtest (Track 3) shows are needed.

**Done when:** `docs/plans/` has a port-audit list the user can triage into concrete backlog items.

---

## Track 4 — Refactor / cleanup audit

**Goal:** a prioritized list of code refactors and cleanups, with risk/payoff notes. Read-only —
proposes, does not change.

**Seed inputs:** `docs/REFACTOR_NOTES.md` and the RETROSPECTIVES "act later" items. Known candidates:
- Typed `Resource` migrations for `HexState` / `CombatSummary` (touches many call sites — golden-
  regression risk; do with attention).
- Typed `WarmupContext` (or a key-allowlist assert) to kill the `warmup_context` silent-dead-config
  fragility (RETROSPECTIVES 2026-06-28 D3-D warmup).
- Debug-gated runtime-index auto-assert in the mutators / end of `resolve_turn` (deliberately deferred —
  can surface benign desyncs).
- Mine geometry: per-ship-type likelihood field on `ShipDef`; optional closed-form dangerous-count.

**Done when:** a triaged refactor list exists; the user picks which to action.

---

## Track 3 — Victory conditions + end-to-end golden test  *(DONE 2026-06-29)*

**Status:** implemented + gated. `VictoryConditions.evaluate` + end-of-cleanup census + `game_over`/
`winner` on GameState/TurnResult/LLM observation; `tools/validate_golden_victory.gd` plays the golden
scenario to a deterministic terminal (turn 1, China win). Two follow-ups remain: **census counts OOB,
not present, battalions** (`refactor_audit.md` item 2b) and **main-island land-hex data** (blocked on
the terrain phase; `taiwan_hexes` config is the hook). Detail: `PLAN.md` → Victory conditions.

**Depends on:** victory conditions being *implemented* (they are designed but not built).

**3a — Implement victory conditions** (per the settled 2026-06-28 design, `PLAN.md` → Open Questions →
"Victory conditions"): two end-of-cleanup checks on **Taiwan main-island land hexes** — **China loses**
if 0 Chinese BNs remain on Taiwan; **China wins** if Chinese BNs > Taiwanese BNs. Loss check
**unconditional by default**, with a configurable arm (`unconditional` / `after_first_landing` /
`after_turn:N`). Confirm the `winner` / `game_over` field shape at implementation; surface it through
`TurnResult` + the LLM observation.

**3b — End-to-end golden test:** a deterministic headless validator that runs the golden scenario
(seed 20260624) **from first landing through to a terminal win/loss**, asserting the game reaches a
victory state and that the run is reproducible. Extends the existing self-play harness
(`tools/validate_headless_selfplay.gd`) past a fixed turn count to a terminal condition.

**Done when:** the golden scenario plays to a deterministic, asserted victory/defeat in the gate.

---

## Track 5 — Graphics

Broad track — **all four sub-areas** are in scope (priority to be set when we start). Graphics need
**visual verification** (Godot MCP / opencode visual judgment per `CLAUDE.md`), not headless-only gates.

- **Anti-ship / mine visualization** — the naval crossing, minefields, swept lanes, decoy/screen losses,
  BNs lost at sea (makes the new D3 mechanics legible).
- **Front-line UI (D5-D)** — the deferred polyline-draw front-line tool (the one remaining D5 piece;
  needs human visual verification).
- **Units & HUD polish** — brigade markers, unit info panels, turn/phase/combat HUD, ownership coloring.
- **Map / terrain polish** — hex grid rendering, terrain/theater visuals, beaches, overall readability.

**Done when:** each sub-area renders correctly in the running game and is confirmed visually.
