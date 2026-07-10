# View layer — rendering, UI & input

## 1. Purpose

Renders the hex map, brigade markers, and HUD; handles player click input, selection flow (click →
pick brigade → move/commit), and relays user actions to `GameState` via `EventBus`. Per
`AGENTS.md` architecture this is the View/control layer — it owns projection, drawing, and input
routing but never game-logic state.

## 2. Files & responsibilities

| File | Role |
|------|------|
| `HexMap.gd` (:1) | `Node2D` scene root: owns `MapProjection`, spawns `Polygon2D` hex cells, draws highlight overlays, renders brigade markers with NATO symbols, emits `hex_clicked`/`selection_cancelled`. |
| `GameController.gd` (:1) | Scene controller: wires `HexMap` signals to `GameState` calls, manages selection state, issues move/commit orders, calls `end_turn`. Sits at scene root alongside `$HexMap`, `$UI/*`. |
| `InfoPanel.gd` (:1) | `PanelContainer` with `RichTextLabel`. Reads `GameData` to show hex owner/FEBA and brigade details for the current selection. |
| `CompositionPanel.gd` (:1) | `PanelContainer` listing eligible-commit brigades as buttons, emits `commit_requested`. |
| `SymbolLibrary.gd` (:1) | `RefCounted` library: loads `nato_symbol_map.json`, caches `Texture2D` per `nato_type`. |
| `SymbolPreview.gd` (:1) | `Control` debug scene: enumerates all OOB nato_types and renders each symbol + brigade count in a scrollable grid. |
| `UnitManager.gd` (:1) | Thin compat wrapper forwarding to `GameData` — no logic. |
| `MapProjection.gd`(:1) | `RefCounted` math: fits lat/lon bounds to viewport with uniform aspect-correct scale; `project(lat_lon)` / `project_vertices(...)`. |
| `data/nato_symbol_map.json` | Maps `nato_type` string → SVG filename under `res://assets/symbols/`. |
| `tools/validate_symbol_map.gd` (:1) | Headless validation: asserts every OOB nato_type has a map entry and every entry loads as `Texture2D`. |

## 3. Rendering — HexMap

**Z-order registry.** Every layer's `z_index` in one place — check here before adding a layer,
and update this table when one changes:

| z | Layer | Built by |
|---|-------|----------|
| 0 | Hex fills (+ black hex outlines as children) | `spawn_hex_cells()` |
| 4 | Red/contested region borders | `_build_ownership_borders()` |
| 5 | Reachable-hex overlays + selected-hex border | `highlight_hexes()` |
| 6 | Numbered beach glyphs | `render_beach_markers()` |
| 10 | Brigade markers + stack badges | `render_brigade_markers()` |

**Projection.** `HexMap` creates `MapProjection.new(get_viewport_rect().size)` in `_ready` (`HexMap.gd`).
`MapProjection` fits the Taiwan lat/lon box (21.9–25.3°N, 119.9–122.1°E) into the viewport with a
cos(lat) longitude compression and 6% margin (`MapProjection.gd`). `project(lat_lon)` maps a
`Vector2(lat, lon)` to pixel-space; `project_vertices(...)` batch-maps `PackedVector2Array`.

**Hex cells.** `spawn_hex_cells()` (HexMap.gd) iterates `GameData.hexes`, projects each hex's
lat/lon vertex array into a `Polygon2D` + `Line2D` outline, and stores them in `hex_cells` /
`projected_vertices`. Color is set by `get_hex_color()`: every terrain-classified hex renders
pure `TerrainType.color` (from `data/terrain/terrain_types.json`); unclassified hexes fall back
to the ownership-only color. Ownership renders as **region borders**, not fill: every RED or
CONTESTED hex contributes its polygon edges as a 3px Line2D (z 4, full-alpha red or
contested-ramp color), but edges between two red/contested hexes are skipped, so each connected
pocket gets one perimeter outline — a front-line trace against a pure-terrain map
(`_build_ownership_borders()`, rebuilt on `refresh_all_hex_colors()`; USER call 2026-07-09,
superseding the earlier fill-tint blends). Beaches
render as numbered dark-blue triangle glyphs anchored bottom-left in their `BeachDef.hex_id` hex
(`render_beach_markers()`, z between hex fills and brigade markers).

**Brigade markers.** `render_brigade_markers()` (HexMap.gd) clears existing markers and stack
badges, groups placed brigades by hex (sorted by brigade id for a deterministic layout), then
renders per hex: a single brigade with no occupied neighbor hex gets the classic full-size marker
offset by `entry_bearing`; a single brigade with any occupied neighbor shrinks to 0.75× and pins
to the hex center (a full-size marker is ~1.9× hex radius wide vs ~1.73× hex spacing — adjacent
full-size markers always overlap); 2+ brigades on one hex render as a 0.62× ring around the
center, plus a ×N count badge disc (`_build_stack_badge`) at 3+. Each marker is a `Node2D` with a
team-colored `Polygon2D` backing + `Sprite2D` symbol (`_build_brigade_marker`). Scenario authoring
cannot create same-hex stacks (placement hexes must be unique) — stacks arise mid-game from
movement and landings.

**Reachable-hex highlight.** The `_on_reachable_hexes_changed` callback stores `_reachable_hexes`
and calls `_refresh_highlights()` (line 272). This first calls `clear_highlights()`, then draws
translucent blue overlays on reachable hexes (z-index 5, below markers at 10) and a yellow
border on the selected hex (`highlight_hexes`, line 243).

## 4. Input & control — GameController

**Click flow.** `HexMap._input` (HexMap.gd) converts left-click →
`get_hex_by_point(local_mouse)` (point-in-polygon via `Geometry2D.is_point_in_polygon`, line 234)
and emits `hex_clicked(hex_id)`. Right-click emits `selection_cancelled`.

**GameController._on_hex_clicked** (GameController.gd):
1. If a brigade is selected and clicked hex is in `current_reachable` → issues a move order via
   `GameState.add_move_order`, emits `EventBus.move_order_issued`, clears reachable hexes.
2. Otherwise → sets `selected_hex`, emits `EventBus.hex_selected`, then looks up brigades in
   that hex via `GameData.get_brigades_in_hex`. If one exists, sets `selected_brigade` and emits
   `EventBus.brigade_selected`, then calls `_update_reachable()`.

**Move mode.** `move_mode_option` (OptionButton) in the scene UI toggles between
`Movement.MODE_TACTICAL` / `Movement.MODE_ADMINISTRATIVE`. `set_move_mode` emits
`EventBus.move_mode_changed` and recalculates reachable hexes.

**Commit flow.** `_emit_commit_options` (GameController.gd) queries
`GameState.eligible_commit_brigades(team, target_hex)` for both teams and emits
`EventBus.commit_options_changed`. `CompositionPanel` receives this, draws buttons; each button
emits `commit_requested` which `GameController.commit_brigade` (line 93) routes to
`GameState.add_commit_order` and emits `EventBus.brigade_committed`.

**End turn.** `end_turn()` (line 104): calls `GameState.resolve_turn()`, then `begin_next_turn()`,
re-renders markers, emits `EventBus.turn_advanced`.

**EventBus signals consumed by the view layer:**
- `hex_selected` → `HexMap`, `InfoPanel` (rebuild details)
- `brigade_selected` → `InfoPanel` (show brigade stats)
- `selection_cleared` → `HexMap`, `InfoPanel`, `CompositionPanel` (clear state)
- `reachable_hexes_changed` → `HexMap` (highlights)
- `turn_advanced` → `HexMap` (refresh hex colors)
- `combat_resolved` → `GameController` (status line)
- `commit_options_changed` → `CompositionPanel` (commit buttons)

## 5. UI panels

**InfoPanel** (`InfoPanel.gd`): connected to `hex_selected`, `brigade_selected`, `selection_cleared`.
`_render()` builds a `RichTextLabel` string with hex ID, owner, FEBA km; then lists brigades in the
hex. If a brigade is also selected, appends brigade ID, name, team, NATO type, battalion count, and
composition breakdown (`_append_brigade_section`, line 71).

**CompositionPanel** (`CompositionPanel.gd`): receives `commit_options_changed` — clears existing
children and adds a title plus one `Button` per eligible-commit brigade. Each button emits
`commit_requested(team, brigade_id, target_hex)`. When `selection_cleared` fires, shows
"No eligible commitments". Commit-brigade eligibility is computed by `GameState`, not the panel.

## 6. NATO symbols

**SymbolLibrary** loads `data/nato_symbol_map.json` at `_init()` (SymbolLibrary.gd). The JSON
has `symbol_dir` (default `res://assets/symbols/`) and `nato_type_to_symbol` dict (11 types:
air-defense, amphibious, area-command, armor, artillery, aviation, infantry, mech-infantry,
motorized-infantry, reserve, special-forces → SVG filenames). `texture_for_nato_type(nato_type)`
lazy-loads and caches the `Texture2D`.

**validate_symbol_map.gd** runs headless: (1) every map entry loads as `Texture2D`, (2) every
nato_type used by `pla_ground_forces.json` + `roc_ground_forces.json` has a map entry. Exit code 0
on pass.

**SymbolPreview** is a debugging Control scene that renders every distinct nato_type with its
symbol and brigade count in a scrollable VBox.

## 7. Fidelity note

This is the **HexCombat-original Godot view** — there is no TaiwanInvasionViewer line-by-line port
here (TIV had a Flask/HTML/JS web UI with Leaflet hex overlays, completely different stack). The
Godot view was built from scratch.

**Pending per STATUS.md Track 5 (Graphics):**
- Anti-ship & mine visualization (ship icons, minefield hex overlays, transit animations)
- Front-line draw UI (D5-D): polyline → hex redistribution needs a visible front-line renderer
- Unit/HUD polish: brigade HP bars, AP counters, combat-result popups
- Map/terrain polish: terrain-class overlay is done (§3, Track F stage 6); elevation tint and
  additional labels remain open
- All visual items are not headless-gateable and deferred to Track 5
