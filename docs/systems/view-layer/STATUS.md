# View Layer — Status

**Brigade marker rendering (`HexMap`)** — brigades are grouped per hex: same-hex stacks render
as a 0.62× ring with a ×N count badge at 3+; a lone brigade shrinks to 0.75× and pins to the
hex center when any neighbor hex is occupied (full-size markers are wider than the hex spacing
and would overlap); an isolated brigade renders full-size with its entry-bearing offset.
Visual-only — headless gates don't cover it; verify by screenshot.

**Post-game briefing viewer** — `tools/make_game_bundle.py` (stdlib-only) merges an
AI-vs-AI game record (`reports/llm/<name>.json`) with its JSONL replay log into one
`<name>.viewer.json` bundle (meta / per-turn digest+actions+observation / per-side 3-line LLM
SITREPs / embedded map data); `--html` bakes it into a single shareable `<name>.game.html`,
and `--from-bundle` re-bakes that HTML from an existing bundle without re-running sitrep LLM
calls. The bundle also carries a canonical **`ship_stats`** block at its root (plan 0023 P2a):
`per_turn[]` (1:1 with `turns[]`, each row — `sent_by_type` / `target_beaches` / `target_tos` /
`wave_bns` / `crossing_casualties` / `destroyed_by_ship_type` / `bns_lost_at_sea` / `mine_status`
— copied verbatim from that turn's `digest.antiship_summary`) plus a stored `cumulative` (running
`series` + rollups). This is the single home for per-turn+cumulative ship activity/loss data that
the map annotation and a future click-through stats view both read; it's gate-guarded against
per-turn drift from its source digests by `tools/validate_make_game_bundle.py` (wired into
`run_all_tests.py` — the bundler was previously exercised by nothing). The map draws a per-turn
crossing annotation (hulls sailed + losses) reading from `ship_stats`. `tools/viewer/game_viewer.html` is a single self-contained briefing page (open
directly, no server): opens at turn 1 and advances one turn at a time (mouse wheel with a
momentum guard, ◀ ▶ / ⏮ ⏭-Final buttons, arrow keys, Home/End) — each advance re-renders the
SVG hex map (terrain fill + red/contested perimeter borders + beach glyphs + brigade markers,
ported from `HexMap.gd`'s projection/border logic) and extends the chart reveal.
The map box holds **two viewports over one shared render** (content lives once
in a `<defs>` group; both `<svg>` `<use>` it, differing only in `viewBox`): a full-island
**theater** view and a **front** view whose `viewBox` crops to the **largest connected cluster**
of contested/Red hexes (+ that cluster's neighbors). Clustering (`connectedComponents` /
`largestCluster`, the pure `<clustering-pure>` block) runs over the same neighbor adjacency the
border layer uses, tie-broken by contested-hex count; a disjoint front no longer yields one bbox
spanning the water between two beachheads (the secondary beachhead stays in the theater view; a
per-beachhead pager is deferred to plan 0027). No landing yet → falls back to the full island.
The clustering has a durable unit test — `node tools/viewer/test_clustering.mjs` loads the real
functions out of the HTML and checks a known two-cluster fixture (not part of the Godot gate).
For projection legibility (plan 0023 P3) the map box bakes in a large high-contrast turn/phase
header (amber "X wins" on the game-over turn) and a compact ownership/glyph legend (Red-held /
Contested / PLA-brigade / ROC-brigade / landing-beach / crossing-this-turn). Advancing also swaps
the
turn's narrative (SITREPs, collapsible transcripts, adjudication prose, phase-detail tables)
in place; the wheel scrolls an overflowing narrative instead of stepping. Charts render
ghost-future (full game faint, turns ≤ current in color): census, cumulative ship losses,
and per-turn battalion losses per side (China stacked ground / drowned-at-sea) derived
client-side from the digests. Tolerates older JSONL logs that lack `observation` (map falls
back to the nearest earlier observed turn / "no map data this turn"). Visual-only tool, not
part of the canonical gate — verify with a headless-Chromium (Playwright) pass over a rebuilt
`game.html` plus screenshots.
