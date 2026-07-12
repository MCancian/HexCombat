# Decisions changelog

Append-only, newest first. **An entry is a changelog, never a reference**: 3–5 lines — what was
decided, who decided (USER vs agent), and POINTERS to where the durable facts landed. If an agent
would need this entry to act, the fact is filed in the wrong place; put it in its canonical home:

| Fact type | Only home |
|---|---|
| Golden pins / exact validator output | `tools/validate_*.gd` (the PASS line is truth) |
| Module architecture, purity boundaries | code headers (`scripts/resolvers/*.gd`, `GameState.gd`) |
| Cross-module flow, data files, TIV divergence rationale | `docs/systems/<module>.md` |
| Procedures, gotchas | `.claude/skills/` |
| Incident history (root cause, rejected fixes) | `hexcombat-failure-archaeology` |
| What works now | `docs/STATUS.md` |
| Work in flight | `docs/plans/NNNN-*.md` (archived at closeout) |

History before 2026-07-10 lives verbatim in `docs/archive/PLAN.md` (→ "Decisions log" section);
code/doc references to "PLAN.md → Decisions <date>" resolve there.

---

- **2026-07-11 — Viewer map box split into theater + front viewports (USER request).** The map
  pane now shows the whole island (theater) beside a zoom (front) cropped to contested/Red hexes +
  their neighbors. Implemented as two `<svg>` `<use>`-ing one shared `<defs>` render, differing
  only in `viewBox` (chosen over parameterizing every render fn — single source of truth, SVG-
  native crop). Change made in the `tools/viewer/game_viewer.html` template so it carries to all
  future baked reports. Details in `docs/STATUS.md`; non-contiguous-front corner case → BACKLOG.

- **2026-07-11 — Crossing-lethality calibration: dial picked, golden re-baselined (USER, per plan
  0001).** `intel_locked_antiship_strike_bonus` promoted from an ad-hoc sweep-script modifier to a
  named scenario knob; ran an N=30/seed sweep grid across it and
  `exquisite_intel.antiship.initial_count`, USER picked bonus=0.20 / initial_count=36
  (~27.3% mean crossing loss) over a marginally-closer-to-target alternative. Golden scenario
  re-baselined to these values; `validate_cleanup.gd`, `validate_golden_victory.gd`, and the
  `llm_result_after_turn.json` fixture pins moved accordingly (their comments carry the new
  numbers — never repeated here). Facts: `docs/systems/ijfs.md` → "Strike"; knob details in
  `hexcombat-config-and-knobs`; plan (now closed):
  `docs/archive/0001-crossing-lethality-calibration.md`.

- **2026-07-10 — Viewer briefing mode + casualty charts (USER).** Game-report viewer rebuilt
  from scrollytelling to turn-at-a-time briefing (wheel/buttons/keys, in-place narrative swap,
  ghost-future chart reveal) with a new per-side battalion-loss bar chart; bundler gained
  `--from-bundle` re-bake. USER picked the interaction model (wheel+buttons+keys, ghost reveal,
  turn-1 start, paired bars). Facts: `docs/systems/llm-api-selfplay.md` → §7. Verified by
  headless-Chromium (Playwright) pass — new precedent for browser-tool verification.

- **2026-07-10 — Doc-rot guard: dead anchors fail the gate (USER asked for a guard; agent
  design).** `tools/validate_doc_anchors.gd` (auto-globbed into the gate) rejects dead
  paths/scripts/members and `file.gd:123` citations in `docs/systems/*.md`; `(historical)` marks
  intentional dead names. Checkable diff→owning-doc procedure + ownership table:
  `hexcombat-docs-and-writing` step 2. First run caught 89 line-citations + 1 real rename.

- **2026-07-10 — Docs architecture B: one home per fact (USER).** PLAN.md (2,525 lines, ~84%
  historical by its own admission) and six dead docs archived to `docs/archive/`; lore-style
  `docs/plans/` index + numbered ephemeral plans with a closeout rule; this changelog replaces
  PLAN.md's Decisions log. Rules enforced in `hexcombat-docs-and-writing` +
  `hexcombat-change-control`; audit evidence in the two 2026-07-10 survey reports (session
  history). Systems-doc rot repaired same day (resolver decomposition, terrain, MANPADS).

- **2026-07-10 — MANPADS layer (USER; TIV divergence).** Spec: `docs/systems/ijfs.md` →
  "MANPADS layer". Incident that triggered it: `hexcombat-failure-archaeology` → "2,500 Mobile
  SAMs". Calibration evidence: 30-seed batch (session 2026-07-10); USER accepted first-cut
  constants. Full original entry: `docs/archive/PLAN.md` Decisions 2026-07-10.
