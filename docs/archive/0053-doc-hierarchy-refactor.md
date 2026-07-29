# Plan 0053 — Documentation hierarchy refactor (hub-and-spoke)

**Status:** ✅ Shipped (2026-07-29)
**Priority:** Medium (developer-experience / token efficiency)
**Closeout facts:** Monolithic `docs/STATUS.md` and `docs/RETROSPECTIVES.md` fragmented into per-module `STATUS.md` and `RETRO.md` under `docs/systems/<module>/`. Global STATUS.md trimmed to a cross-cutting executive summary hub. Dedicated `docs/systems/research-harness/` directory created for batch runner and sweep tools. Facts: `docs/STATUS.md`, `docs/systems/<module>/STATUS.md`, `AGENTS.md`, `hexcombat-docs-and-writing/SKILL.md`.
**Goal:** Reduce agent orientation tokens by ~85% by fragmenting the monolithic `docs/STATUS.md`
(450 lines, ~10,200 tokens) and `docs/RETROSPECTIVES.md` (200 lines, ~3,700 tokens) into
module-specific files within `docs/systems/<module>/` directories, while preserving the
one-home-per-fact invariant.

## What is already settled (do not relitigate)

- **One home per fact** (`hexcombat-docs-and-writing`): every fact lives in exactly one place.
  This refactor MOVES homes, it doesn't duplicate them.
- **Systems docs stay as single files** — they are already well-scoped (78–324 lines each).
  No ARCHITECTURE/REFERENCE split.
- **Cross-cutting facts** (engine, turn model, RNG hierarchy, gate description, mutation authority
  summary) genuinely have no single-module home. They stay in the global `docs/STATUS.md`, trimmed
  to ~50 lines.
- **`validate_doc_anchors.gd`** will need updates if it validates paths to systems docs.

## Approach

**Modified Hub-and-Spoke.** The global files become slim hubs pointing to per-module silos.
No parsing script — content extraction is manual (STATUS bullets are multi-module prose that
requires human judgment to assign). Safety via a git branch with reviewable diff.

### New directory structure

```
docs/systems/
├── README.md                           (updated: links to module dirs)
├── html/                               (unchanged)
├── ijfs/
│   ├── ijfs.md                         (moved from docs/systems/ijfs.md)
│   ├── STATUS.md                       (IJFS bullets extracted from global)
│   └── RETRO.md                        (IJFS retros extracted from global)
├── antiship-mine/
│   ├── antiship-mine.md
│   ├── STATUS.md
│   └── RETRO.md
├── ground-combat/
│   ├── ground-combat.md
│   ├── STATUS.md
│   └── RETRO.md
├── amphibious-offload/
│   ├── amphibious-offload.md
│   ├── STATUS.md
│   └── RETRO.md
├── supply-dos/
│   ├── supply-dos.md
│   ├── STATUS.md
│   └── RETRO.md
├── frontline-cleanup-victory/
│   ├── frontline-cleanup-victory.md
│   ├── STATUS.md
│   └── RETRO.md
├── hex-grid/
│   ├── hex-grid.md
│   └── STATUS.md
├── terrain/
│   ├── terrain.md
│   └── STATUS.md
├── roc-mobilization/
│   ├── roc-mobilization.md
│   ├── STATUS.md
│   └── RETRO.md
├── air-insertion/
│   ├── air-insertion.md
│   ├── STATUS.md
│   └── RETRO.md
├── turn-engine/
│   ├── turn-engine.md
│   └── STATUS.md
├── llm-api-selfplay/
│   ├── llm-api-selfplay.md
│   └── STATUS.md
└── view-layer/
    ├── view-layer.md
    └── STATUS.md
```

Modules without retrospective entries don't get a `RETRO.md` (created on first use).

### Global hub — `docs/STATUS.md` (target: ~50 lines)

```markdown
# HexCombat — Current State

**What works today, present tense, no dates.** Per-module detail lives in
`docs/systems/<module>/STATUS.md`. This file covers only cross-cutting concerns
that no single module owns.

## Cross-cutting

<engine paragraph, ~15 lines: WeGo model, GameState/GameStateData, pure resolvers,
 TurnConductor, role directories, OrderResult>

<turn resolution order, ~5 lines>

<verification/gate, ~15 lines>

<mutation authority summary, ~5 lines>

## Module index (one-liner + link)

| Module | Link | What |
|---|---|---|
| IJFS | `docs/systems/ijfs/STATUS.md` | D4 air/missile fires |
| Anti-ship & mines | `docs/systems/antiship-mine/STATUS.md` | D3 crossing damage |
| ... | ... | ... |

## What is NOT done

<unchanged 10-line section>
```

### Global hub — `docs/RETROSPECTIVES.md` (target: ~15 lines)

```markdown
# Retrospectives — implementer lessons learned

Per-module retros live in `docs/systems/<module>/RETRO.md`. This file documents the entry format
and the inbox/archive workflow.

## Entry format
<existing template, ~10 lines>

## Module retro files
| Module | File |
|---|---|
| Anti-ship & mines | `docs/systems/antiship-mine/RETRO.md` |
| ...
```

## Checklist

### Step 0: Branch
- [ ] Create branch `docs/hierarchy-refactor` from main.

### Step 1: Scaffold directories (no content moves yet)
- [ ] Create the 13 module directories under `docs/systems/`.
- [ ] `git add` the empty directories (with `.gitkeep` if needed).
- [ ] Commit: "scaffold module directories"

### Step 2: Move systems docs into their directories
- [ ] `git mv docs/systems/ijfs.md docs/systems/ijfs/ijfs.md` (repeat ×13).
- [ ] Update `docs/systems/README.md` links.
- [ ] Run `tools/validate_doc_anchors.gd` — if its glob is `docs/systems/*.md`, update it
  to `docs/systems/**/*.md`.
- [ ] Commit: "move systems docs into module directories"
- [ ] Run full gate — must be green before proceeding.

### Step 3: Extract per-module STATUS bullets
- [ ] For each module, identify the STATUS.md paragraphs/bullets that belong to it.
  Use the ownership table in `hexcombat-docs-and-writing` as the guide.
- [ ] Write each module's `docs/systems/<module>/STATUS.md` with the extracted content.
  Keep present tense, no dates (same house rules as the global).
- [ ] **Assignment map** (paragraph → module):
  - "Ground combat" (lines 53–67) → `ground-combat/STATUS.md`
  - "D1 Amphibious offload" (lines 68–70) → `amphibious-offload/STATUS.md`
  - "Sealift lifecycle" (lines 71–83) → `amphibious-offload/STATUS.md`
  - "Research default vs golden fixture" (lines 80–83) → cross-cutting (stays in hub)
  - "Offload capacity gate" (lines 84–92) → `amphibious-offload/STATUS.md`
  - "D2 Red DOS supply" (lines 93–95) → `supply-dos/STATUS.md`
  - "D3 Anti-ship & mine warfare" (lines 96–122) → `antiship-mine/STATUS.md`
  - "D4 IJFS" (lines 123–146) → `ijfs/STATUS.md`
  - "ROC mobilization" (lines 147–168) → `roc-mobilization/STATUS.md`
  - "PLAAF air insertion" (lines 169–193) → `air-insertion/STATUS.md`
  - "D5 Front-line / cleanup" (line 194) → `frontline-cleanup-victory/STATUS.md`
  - "Victory conditions" (lines 195–208) → `frontline-cleanup-victory/STATUS.md`
  - "AI-readiness (Track E)" (lines 209–213) → `llm-api-selfplay/STATUS.md`
  - "Scenario selection" (lines 214–219) → cross-cutting (hub)
  - "Batch runner" through "Monte Carlo" (lines 220–317) → `llm-api-selfplay/STATUS.md`
  - "roc_full_defense scenario" (lines 318–322) → cross-cutting (hub)
  - "Terrain model" (lines 323–339) → `terrain/STATUS.md`
  - "Default scenario" (lines 340–345) → cross-cutting (hub)
  - "Brigade marker rendering" (lines 346–350) → `view-layer/STATUS.md`
  - "Post-game briefing viewer" (lines 351–390) → `view-layer/STATUS.md` (or
    `llm-api-selfplay/STATUS.md` — USER call on which module owns the viewer)
  - "Verification" (lines 392–398) → cross-cutting (hub)
  - "Gate anti-silence" (lines 400–418) → cross-cutting (hub)
  - "Mutation authority" (lines 420–435) → cross-cutting (hub)
- [ ] Verify: no paragraph appears in both hub AND a module file.
- [ ] Commit: "extract per-module STATUS files"

### Step 4: Extract per-module RETRO entries
- [ ] Assignment map (by `##` heading):
  - "plan 0043: anti-ship mutation authority" → `antiship-mine/RETRO.md`
  - "plan 0040: combat-knob threading validator" → `ground-combat/RETRO.md`
  - "plan 0038: TurnConductor phase extraction" → `turn-engine/RETRO.md`
  - "plan 0009: quality baseline + remediation" → `ground-combat/RETRO.md` (USER call pending)
  - "plan 0006 C8: research verification" → `amphibious-offload/RETRO.md`
  - "plan 0012: unified sweep extraction" → `llm-api-selfplay/RETRO.md`
- [ ] Trim global `docs/RETROSPECTIVES.md` to hub + entry format template.
- [ ] Commit: "extract per-module RETRO files"

### Step 5: Trim global STATUS.md to hub
- [ ] Replace the full content with the hub format (cross-cutting + module index table).
- [ ] Verify every extracted paragraph is in exactly one module file.
- [ ] Commit: "trim STATUS.md to hub"
- [ ] Run full gate — must be green.

### Step 6: Update all references
- [ ] **`AGENTS.md`** — update the orientation table:
  ```
  | What works today | `docs/STATUS.md` (hub) → `docs/systems/<module>/STATUS.md` |
  | How a module works | `docs/systems/<module>/` (system doc + STATUS + RETRO) |
  ```
  Update the task-shaped minimum reads to point at module STATUS files.
- [ ] **`hexcombat-docs-and-writing/SKILL.md`** — update:
  - One-home-per-fact table: STATUS row gains "(hub for cross-cutting; per-module for subsystems)"
  - Tracking rules: step 1 "update `docs/systems/<module>/STATUS.md`" instead of global.
  - Step 4 retrospectives: "append to `docs/systems/<module>/RETRO.md`"
  - Plan closeout rule: update STATUS bullet → module STATUS file.
- [ ] **Other skills** that reference `docs/STATUS.md` or `docs/RETROSPECTIVES.md`:
  - `hexcombat-architecture-contract`
  - `hexcombat-change-control`
  - `hexcombat-debugging-playbook`
  - `hexcombat-research-runs`
  - `hexcombat-failure-archaeology`
  - Skills `README.md`
- [ ] **`docs/plans/README.md`** — closeout rule reference.
- [ ] **`docs/STATUS.md` header** — self-referencing text.
- [ ] **`validate_doc_anchors.gd`** — if it scans `docs/systems/*.md`, update the glob.
- [ ] Commit: "update all references to new doc hierarchy"
- [ ] Run full gate — **must be ALL PHASES GREEN**.

### Step 7: Final verification
- [ ] `git diff main..HEAD --stat` — confirm no content was deleted, only moved.
- [ ] Spot-check: for 3 modules, confirm the module STATUS.md matches the original STATUS.md
  paragraph verbatim (minus any cross-cutting prefix sentences).
- [ ] Merge to main.

## Open USER calls

1. **Post-game briefing viewer** (STATUS lines 351–390): does it belong to `view-layer/` or
   `llm-api-selfplay/`? It's a tool (`tools/viewer/`, `tools/make_game_bundle.py`) that renders
   AI game data — arguably research tooling, not the Godot view layer.

2. **Plan 0009 retro**: it's mostly about `CombatResolver` quality, but touches cross-cutting
   concerns (delegate verification, coverage tooling). File in `ground-combat/RETRO.md`?

3. **Research harness tools** (batch runner, sweep, narrative, Monte Carlo): these span multiple
   modules. Keep their STATUS bullets in `llm-api-selfplay/STATUS.md` (since that doc already
   covers the harness), or create a `research-harness/` silo?

## Risks

- **`validate_doc_anchors.gd` glob change** is the only code-level risk. Easy to verify.
- **Skill prose** references to `docs/STATUS.md` are NOT validated by the gate. Must be found by
  grep and updated manually. Step 6 covers this.
- **Future plan closeout** workflow must remember to update module STATUS, not global.
  The skill update in step 6 covers this.

## Won't do

- **No parsing script** — STATUS bullets are multi-module prose requiring judgment.
- **No ARCHITECTURE/REFERENCE split** of systems docs — they are already well-scoped.
- **No `docs/modules/` rename** — `docs/systems/` is the established name in 13+ references.
