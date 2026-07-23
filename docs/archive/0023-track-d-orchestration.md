---
status: Shipped
shipped: 2026-07-23
landed_in: docs/DECISIONS.md, docs/systems/llm-api-selfplay.md, docs/STATUS.md
---

# 0023 — Presentation visuals for headless LLM-vs-LLM games

> **CLOSEOUT (2026-07-23).** All three phases shipped. **P1** — front view frames the largest
> connected red/contested cluster (`connectedComponents`/`largestCluster` + `test_clustering.mjs`;
> USER greenlit building against real turn-15 fixture after the precondition scan found only small,
> tight multi-cluster turns — never an ocean-spanning front, so the pager was deferred to plan 0027).
> **P2** — canonical root `ship_stats` block (per_turn + cumulative) in the bundle, gate-guarded by
> `tools/validate_make_game_bundle.py`, plus a per-turn map crossing annotation. **P3** — projector
> turn/phase header + ownership/glyph legend. Verified per phase via Playwright screenshots (visual
> log at `docs/reports/2026-07-23-plan-0023-visual-log.md`) + gate ALL PHASES GREEN. Facts landed in
> STATUS / `llm-api-selfplay.md` §7 / DECISIONS; live-facilitator work is plans 0024–0026.

**Goal:** Make the existing headless-replay presentation surface — the self-contained
`tools/viewer/game_viewer.html` briefing page — good enough to project in a talk about
LLM-vs-LLM games. This is the *immediate-priority* slice of the old Track D graphics wishlist,
reframed around presentation of headless games rather than live-facilitator interaction.

**How the work is done** (USER call 2026-07-23): the primary agent writes the code directly. No
opencode/agy swarm — the view layer is architectural per `CLAUDE.md`. `agy`/Godot-MCP are
verification helpers (visual review of screenshots), not authors. The retired
plan→opencode→verify loop stays retired.

## Why the viewer, not the Godot scene

The presentation target is a *headless* game: a finished LLM-vs-LLM record + JSONL replay.
`game_viewer.html` already renders each replay turn's SVG hex map (terrain fill + red/contested
perimeter borders + beach glyphs + brigade markers, ported from `HexMap.gd`), plus per-turn
charts and SITREPs, from a `<name>.viewer.json` bundle (`tools/make_game_bundle.py`). That is the
presentation surface. `tools/capture_screenshot.gd` only captures the live interactive
`Main.tscn`, not an arbitrary replay turn — Godot-quality stills of replay states are a *separate*
capability, deferred to plan 0026.

So this plan touches JS/CSS in one self-contained HTML file (+ possibly the stdlib
`make_game_bundle.py` if a phase needs data the bundle doesn't yet carry). No `.gd` golden-path
code, no RNG, no gate-covered logic.

## Scope — three phases, each independently shippable

Sequence P1 → P2 → P3; each ends with a Playwright screenshot pass and a commit.

### P1 — Front-view clustering (was draft component 5)
**Problem.** `updateZoomViewport(ownerMap)` (`game_viewer.html:832`) accumulates one
`minX/minY/maxX/maxY` bbox over *all* red/contested hexes, then pads it (`ZOOM_PAD_FRAC`,
`:829`). Two separated beachheads → one bbox spanning the ocean between them; the "Front" view
zooms to empty water. (Known follow-up, flagged in the code at `:828` and STATUS.)
**Fix (USER call 2026-07-23: option A, single-frame-of-largest — no pager).** Group the
red/contested set into connected components (odd-r hex adjacency — reuse the same neighbor logic
the border layer uses so the two agree), then frame the **largest** cluster by hex count
(tie-break: most contested hexes). Keep the empty-set fallback to `FULL_VIEWBOX` (`:855`).
A per-cluster pager is explicitly **out** — multiple non-contiguous beachheads are a corner case;
the secondary beachhead stays visible in the Theater view. (Pager is a clean follow-on if a real
talk ever needs per-beachhead close-ups, since the clustering is already done here.)
**Precondition — confirm the disjoint-front state actually occurs (do this BEFORE building P1).**
P1's value *and* its verification both require a single turn where the red/contested set forms
**≥2 spatially-separated clusters**. Existing replays target all 4 beaches over 30–40 turns, but
that is cumulative — it is *unconfirmed* that any single turn shows two separated beachheads
coexisting (fronts usually merge or collapse; end-turn `contested_hexes` is 1–2 hexes). Determining
this needs exactly the clustering P1 builds, so it is unconfirmed by construction. First scan the
`reports/llm/*` replays (per-turn owner map → connected components over `GEO.neighborEdge`
adjacency) for any turn with ≥2 clusters. **If none exists, STOP and surface to the USER**: P1 is
then aimed at a state the sim rarely/never produces (secondary beachhead already stays visible in
Theater view), which makes it a speculative feature, not a fix — a design call, not the agent's.
Only proceed once a real disjoint front is found (use it as the fixture) or the USER greenlights
building against a hand-authored synthetic bundle.
**Regression test (clustering is the real logic here — do not leave it screenshot-only).** The
component-finder is a pure function over `GEO.neighborEdge`; extract it and unit-test it (JS
harness, or mirror the algorithm in a stdlib validator) against a fixture with a known 2-cluster
layout: assert it finds both components and frames the larger by hex count (contested tie-break).
This is the *one* piece of new logic in the plan that carries real algorithmic risk — it earns a
durable test, unlike the low-risk bundler reshuffling P2a already guards.
**Verify.** Build a bundle from the confirmed/authored two-beachhead replay;
Playwright-screenshot the Front view mid-game; confirm it frames one beachhead tightly, not the
ocean gap.

### P2 — Ship activity + losses: map annotation + canonical data home (was draft component 3)
**USER shape (2026-07-23):** on the map, show *where ships are* and *how many were lost each
turn* (textual is fine). Separately — and treated as the **priority** here — store per-turn AND
cumulative ship activity/loss data in one well-defined place, so a future click-through stats
view (separate from the map) can read it. Building that stats view is **not** in scope now; only
the data home + the map annotation are.

**Data is already all present — no engine change, zero golden risk.** Every field needed is
serialized per-turn in `antiship_summary` (`AntishipSummary.to_dict()`, byte-stable per its own
contract) and already flows record → `TurnResult.antiship_summary` → digest → bundle → viewer:
- `sent_by_type` — hulls sailing this turn by ship type (= "where the ships are"/activity)
- `target_beaches`, `target_tos` — where the wave is headed
- `wave_bns` — cohort size (crossing-loss denominator)
- `crossing_casualties.{destroyed, damaged}`, `destroyed_by_ship_type`, `bns_lost_at_sea` — losses
- `mine_status`, `systems_fired_count` — mine encounters / defensive fire

The viewer already charts cumulative `crossing_casualties` client-side (`shipChart`,
`game_viewer.html:1108`) and tabulates `destroyed_by_ship_type` (`renderAntishipTable`, `:1028`),
but `sent_by_type` / `target_*` / `mine_status` are unused, and no per-turn+cumulative ship
dataset is *stored* — cumulative is recomputed on the fly. So the work is all JS/stdlib:

**P2a — Canonical `ship_stats` block in the bundle (priority).** In `make_game_bundle.py`
(stdlib), fold the per-turn `antiship_summary` fields into one documented `ship_stats` block at
the **root** of `<name>.viewer.json` (alongside `meta` and `turns` — not nested inside a turn,
so schema boundaries stay clean; reviewer 2026-07-23):
- `per_turn[]` — one row/turn: turn number, `sent_by_type`, `target_beaches`/`target_tos`,
  `wave_bns`, `crossing_casualties`, `destroyed_by_ship_type`, `bns_lost_at_sea`, `mine_status`.
- `cumulative` — stored rollups (total destroyed/damaged, by ship type, total BNs lost at sea,
  running per-turn cumulative series) so the future stats view reads numbers, not re-derives them.
This is the single home the map annotation (P2b) and the future stats view (P2c) both read.
Document the schema in `docs/STATUS.md` (viewer bullet) and the relevant `docs/systems/` doc so
"where all the ship data is stored" is written down, per USER's explicit ask.

**P2a guardrail — bundler is NOT gate-covered today (reviewer 2026-07-23).**
`tools/make_game_bundle.py` is exercised by nothing in `tools/run_all_tests.py`, so breaking the
new `ship_stats` computation would leave the gate green. Since P2a adds real bundler logic, add
`tools/validate_make_game_bundle.py` (stdlib): build a bundle from a small fixture record+JSONL
(**≥2 turns** — a 1-turn fixture makes the running-sum assertion trivially true), assert the
`ship_stats` block's shape and that `cumulative` equals the running sum of `per_turn` losses.
**Also cross-check the derived block against its source.** `ship_stats.per_turn` is a *copy* of
data that still lives raw in `turns[].digest.antiship_summary`; AGENTS.md makes single-source a
hard convention, so the two representations can silently drift. The validator must therefore also
assert `ship_stats.per_turn[n]` equals the corresponding `turns[n].digest.antiship_summary`
fields — internal consistency (`cumulative == sum(per_turn)`) alone does not catch a per-turn
derivation bug. Wire it into `tools/run_all_tests.py` next to `validate_batch_runner.py` /
`validate_research_knobs.py`: the `subprocess.run([sys.executable, "validate_*.py"])` call plus
its PASS-marker regex + `failures.append` block, mirroring `run_all_tests.py:148-153`/`156-162`.
This turns the ship data home into gate-protected code.

**P2b — Map annotation.** For turns with a crossing, draw a textual annotation near the target
beach(es) on the SVG map: hulls sailed (from `sent_by_type` totals) and losses this turn
(`crossing_casualties.destroyed`/`damaged`, `bns_lost_at_sea`), reading from the `ship_stats`
block. Textual per USER — no lane-glyph geometry required. Keep it legible at projection distance.

**P2c — Separate stats/graph view — DEFERRED (data-ready only).** The clickable stats page is
out of scope now; P2a guarantees its data exists and is documented. Track as a follow-on.

**Verify.** Bundle a game with a live crossing phase; assert `ship_stats.per_turn` +
`cumulative` are populated and match the digests; Playwright-screenshot a crossing turn and
confirm sailed/lost annotation reads at reduced size. Run `bash tools/run_all_tests.sh` (the
bundler is stdlib and, once P2a's validator is wired, tool-exercised) → ALL PHASES GREEN.

### P3 — Projection legibility polish (presentation slice of draft component 1)
**Problem.** The map is tuned for a desktop viewer, not a projector across a room: ownership
colors, phase/turn identification, and a legend need to read at distance.
**Fix.** Within the viewer only: bake a clear turn/phase header and a compact ownership/glyph
legend into the map box; audit the red/contested ramp (`:371`) and terrain fills for
projector contrast; ensure brigade markers and count badges stay legible at the theater zoom.
Interactive camera pan/zoom is explicitly **out** — that's a live-operator need (plan 0026), and
a screenshot sets its own framing.
**Verify.** Screenshot the theater and front views; eyeball at reduced size (simulating
projection); confirm ownership, turn, and unit counts are unambiguous.

## Verification (whole plan)
- The viewer is **not** part of the canonical gate (it's a self-contained HTML tool). Verify each
  phase with a headless-Chromium (Playwright) pass over a rebuilt `game.html` + screenshots, per
  the viewer verification note in `docs/STATUS.md` and `hexcombat-run-and-operate`.
- **The canonical gate does not exercise `make_game_bundle.py` today** (reviewer 2026-07-23) — a
  bundler regression would NOT turn `run_all_tests.sh` red on its own. P2a therefore *adds*
  `tools/validate_make_game_bundle.py` to the gate (see P2a guardrail); after that, run
  `bash tools/run_all_tests.sh` → **ALL PHASES GREEN** to confirm the bundler + `ship_stats`
  computation are guarded. Pure-HTML-only changes (P1, P2b, P3) can't regress the gate — verify
  those by rebuilt-bundle + Playwright screenshot; still run the gate as a smoke check.
- **Coverage is aimed at the risk, not the easy target.** The bundler reshuffling P2a guards is
  low-risk stdlib; the real algorithmic risk in this plan is P1's connected-components clustering.
  That earns its own durable unit test (see P1) — screenshots are not regression protection for
  logic. Do not let the P2a validator be the *only* automated coverage the plan adds.
- Collect the approved screenshots into a short visual log for the USER at plan close (this
  replaces the draft's `track_d_visual_log.md` broker artifact — it's a deliverable, not an
  orchestration mechanism).

## Closeout (per `hexcombat-docs-and-writing`)
- STATUS "Post-game briefing viewer" bullet updated (clustering + crossing viz + polish).
- `docs/DECISIONS.md` 3–5-line entry (reframe to presentation-first; swarm approach dropped).
- Plan gets 3-line closeout header, moves to `docs/archive/`.

## Explicitly deferred (own plans — live-facilitator, not headless presentation)
- **0024** — Order-entry facilitator flow (draft component 2). Interactive; N/A to a headless game.
- **0025** — Front-line polyline-draw UI, D5-D (draft component 4).
- **0026** — Live-play Godot map: camera pan/zoom + interactive HUD + a replay-state screenshotter
  (interactive slice of draft component 1 + the missing "screenshot an arbitrary replay turn from
  Godot" capability, if Godot-quality stills are ever wanted over the HTML viewer's SVG).
