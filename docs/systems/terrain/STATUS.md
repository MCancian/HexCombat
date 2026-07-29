# Terrain — Status

**Terrain model (Track F)** — every hex in the 466-hex grid (`data/taiwan_hex_grid.json`,
reconciled against the real GSHHG coastline) carries one of 5 terrain classes
(`data/terrain/terrain_types.json` + `data/terrain/hex_terrain.json`, loaded by
`GameData.load_terrain()`): plains, hills, urban, mountain, metropolis (≥50% built-up cover, 9
metro-core hexes). Movement consumes per-class entry cost via weighted Dijkstra
(`GameData._terrain_entry_cost`, `HexMath.find_path`/`find_reachable`: hills/metropolis cost 2,
plains/urban/mountain cost 1) with a min-one-step guarantee (a unit that hasn't moved may always
take one step into an adjacent passable hex); mountains are impassable
(`GameData._with_impassable`). Ground combat's defender gets a per-class strength modifier
(`TurnConductor.defender_combat_modifier` → `CombatResolver.resolve_at`): plains ×1.0, hills ×1.5,
urban ×2.0, mountain ×2.0, metropolis ×3.0 — golden outcome is pinned in
`tools/validate_headless_turn.gd`. Terrain is
surfaced per-hex in the LLM `occupied_hexes` observation and IS the map fill: every classified
hex renders pure `TerrainType.color` (USER call — match `terrain_preview.png`); RED/CONTESTED
ownership renders as a 3px perimeter border around each connected pocket, no interior lines
(`HexMap._build_ownership_borders`), with numbered beach glyphs. Full detail:
`docs/systems/terrain/terrain.md`.
