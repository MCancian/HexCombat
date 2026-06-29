# Hex Grid & Geometry Subsystem

## 1. Purpose

Defines the hex-grid coordinate system, geometric computations (distance, neighbor lookup, BFS pathfinding), and the geographic-to-pixel projection that renders the Taiwan map on screen. The grid itself is pre-generated offline by the TIV Python toolchain and consumed as a static JSON snapshot — this subsystem only provides runtime geometry and rendering.

## 2. Files & Responsibilities

| File | Responsibility |
|---|---|
| `scripts/HexMath.gd` | Axial coordinate math: directions, distance, BFS pathfinding |
| `scripts/MapProjection.gd` | Lat/lon → pixel projection with aspect-correct uniform fit |
| `scripts/model/Hex.gd` | `Hex` Resource — id, axial coord, center lat/lon, vertex array |
| `scripts/HexOwner.gd` | Ownership string constants: `RED`, `GREEN`, `CONTESTED`, `NONE` |
| `scripts/GameData.gd` | Loads JSON into `Hex` objects, builds neighbor index, exposes `get_distance`/`find_path`/`find_reachable` wrappers |
| `data/taiwan_hex_grid.json` | Pre-generated grid snapshot (~17K lines, 455 hexes) |

## 3. Data Model

**`Hex`** (`scripts/model/Hex.gd:1-9`) — a typed `Resource`:
- `id: String` — e.g. `"hex_3_9"`
- `coord: Vector2i` — axial coordinate `(row, col)` where `row` is q and `col` is r
- `row: int`, `col: int` — redundant with `coord`
- `center: Vector2` — `(lat, lon)` of hex center
- `vertices: PackedVector2Array` — 7 `(lat, lon)` pairs (first == last, closed polygon)

**Coordinate system:** Pointy-top axial (q = row, r = col). `AXIAL_DIRECTIONS` order at `scripts/HexMath.gd:4-11`:
```
(0,-1), (1,-1), (1,0), (0,1), (-1,1), (-1,0)
```

## 4. Key Functions

| Signature | Line | Purpose |
|---|---|---|
| `static func distance(a: Vector2i, b: Vector2i) -> int` | `HexMath.gd:21` | Cube-distance formula on axial coords |
| `static func neighbor_coords(coord: Vector2i) -> Array[Vector2i]` | `HexMath.gd:14` | Returns all 6 axial neighbors |
| `static func find_path(start_id, goal_id, get_neighbors: Callable, blocked: Array = []) -> Array` | `HexMath.gd:27` | BFS shortest path by hex ID (returns `[start, ..., goal]` or `[]`) |
| `static func find_reachable(start_id, max_distance: int, get_neighbors: Callable, blocked: Array = []) -> Array` | `HexMath.gd:54` | BFS within radius (inclusive of start) |
| `func project(lat_lon: Vector2) -> Vector2` | `MapProjection.gd:40` | Single lat/lon → pixel (y inverted: north = lower y) |
| `func project_vertices(lat_lon_vertices: PackedVector2Array) -> PackedVector2Array` | `MapProjection.gd:48` | Batch vertex projection for hex polygon drawing |

## 5. Data Flow

1. **`GameData.load_hex_grid()`** (`GameData.gd:55-99`) reads `data/taiwan_hex_grid.json`. Each entry is parsed into a `Hex` Resource: `id`, `coord = Vector2i(row, col)`, `center = Vector2(lat, lon)`, `vertices` as `PackedVector2Array` of `(lat, lon)` pairs. Stored in `hexes: Array[Hex]`, `hex_lookup: Dictionary` (id→Hex), and `coord_lookup: Dictionary` (Vector2i→id).

2. **`GameData.build_neighbor_lookup()`** (`GameData.gd:102-110`) iterates all hexes, calls `HexMath.neighbor_coords(hex.coord)`, filters against `coord_lookup`, and stores `neighbor_lookup: Dictionary` (id→Array[String]).

3. **`GameData` wrappers** (`GameData.gd:245-262`) — `get_distance`, `find_path`, `find_reachable` — forward to `HexMath` static methods using the pre-built neighbor index.

4. **`HexMap.gd`** creates a `MapProjection` in `_ready()` and calls `project_vertices(hex.vertices)` / `project(hex.center)` to convert every hex's lat/lon data to screen-space pixel coordinates for rendering.

## 6. Constants (`MapProjection.gd:4-10`)

| Constant | Value | Meaning |
|---|---|---|
| `LAT_MIN` | `21.9` | Southern map bound (degrees) |
| `LAT_MAX` | `25.3` | Northern map bound (degrees) |
| `LON_MIN` | `119.9` | Western map bound (degrees) |
| `LON_MAX` | `122.1` | Eastern map bound (degrees) |
| `MARGIN` | `0.06` | Fractional viewport margin on each side |

`_lon_scale = cos(mean_lat)` (line 24) corrects for longitude degree compression at Taiwan's mean latitude. `_scale = min(avail.x / content_w, avail.y / content_h)` (line 29) picks the uniform pixel-per-degree that fits within the viewport minus margins.

## 7. TIV-Port Fidelity Notes

- **TIV source** is `TaiwanInvasionViewer/src/core/hex_grid.py` — an **offline grid generator** that uses Haversine `get_distance` to compute 10 km side-to-side hex spacing, generates pointy-top vertex geometry, and writes `data/taiwan_hex_grid.json`.
- **HexCombat does NOT re-implement grid generation.** It consumes a pre-generated snapshot (`data/taiwan_hex_grid.json`) and re-implements only runtime geometry: axial distance (cube formula, not Haversine), neighbor enumeration, and BFS pathfinding — all in `HexMath.gd`.
- **`MapProjection.gd` has no TIV equivalent.** It is a HexCombat-original render concern (lat/lon → pixel) that does not exist in the Python backend.
- **✅ FIXED 2026-06-29 — coordinate system now matches TIV (was a confirmed bug; see `/DECISIONS.md`).**
  The grid JSON stores **offset (odd-r, pointy-top)** `row`/`col` (TIV's generator shifts odd rows
  right by half a hex), and TIV's runtime `get_hex_neighbors` (`src/core/hex_grid.py`) uses
  **parity-dependent odd-r offsets**. HexCombat originally applied **fixed axial directions** to the
  same `row`/`col`, matching true geometry on only **23/308** interior hexes (odd-r: 308/308). Now
  `HexMath.neighbor_coords` selects an odd-r offset table by `coord.x` (row) parity, and
  `HexMath.distance` converts odd-r→cube (`x = col - (row - (row&1))/2`, `z = row`, `y = -x-z`) before
  taking cube distance — matching the TIV oracle. The golden combat invariant was re-baselined as a
  result (`casualties=2, feba=0.76` → `casualties=3, feba=-0.55`).
