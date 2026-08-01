# Hex Grid & Geometry — Status

**466-hex grid topology (`data/taiwan_hex_grid.json`)** — models Taiwan and its immediate waters,
reconciled against the real GSHHG coastline dataset. Hexes use odd-r offset coordinates
(row/col mapping to axial `q`, `r`, `s` coordinates via `HexMath`).

**Grid & Data Services (`GameData.gd`)**:
- Grid data is loaded into `GameData.hex_lookup` (dict of hex_id -> `HexDef`).
- Pre-built neighbor lookup `GameData.neighbor_lookup` maps each hex_id to its 6 adjacent hex_ids (less for boundary/coastal hexes).
- Impassable mountain hexes are filtered via `GameData._with_impassable`.

**Pure Geometry Library (`scripts/calc/HexMath.gd`)**:
- Pure `RefCounted` class for all hex math: distance, line-of-sight, neighbor queries, Dijkstra pathfinding, and reachability.
- Weighted movement pathfinding (`find_path`/`find_reachable`) accounts for entry costs defined in `data/terrain/terrain_types.json`.
- Min-one-step guarantee: a unit that has not moved this turn can always move 1 step into an adjacent passable hex regardless of cost.
