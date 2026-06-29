# Front-line, cleanup & victory (D5 + victory census)

## 1. Purpose

Three related end-of-turn systems that run after ground combat resolves:

- **Front-line redistribution (D5-A):** Redistribute Red maneuver brigades evenly along a user-drawn polyline (the "front line").
- **Cleanup ownership (D5-C):** Normalize hex ownership by brigade presence, reset anti-ship per-turn flags.
- **Victory census (D5-C tail):** Count PLA vs ROC battalions on Taiwan; check win/loss conditions.

Front-line is user-driven (requires a drawn polyline). Cleanup + victory are automatic at the tail of every `resolve_turn`.

## 2. Files & responsibilities

| File | Role | TIV oracle |
|---|---|---|
| `scripts/FrontLineService.gd` | `static func` lib: polyline → hex sequence, even spacing of units along hexes. | `services/front_line_service.py` — `find_hexes_for_polyline`, `distribute_battalions_along_line`, `_interpolate_along_line`, `_polyline_cumulative_lengths` |
| `scripts/VictoryConditions.gd` | Pure `static func evaluate()`: win if China majority; if armed + 0 China BNs → Taiwan win. | No TIV equivalent (HexCombat design, settled 2026-06-28). |
| `scripts/HexOwner.gd` | Constants: `RED`, `GREEN`, `CONTESTED`, `NONE`. | TIV `CleanupHexService.OWNER_MAP` maps same four values. |
| `scripts/GameData.gd` | `recompute_hex_ownership()` (line 290), `hex_states` dict, `victory_config` from scenario. | TIV `cleanup_hex_service.py` — `update_hex_ownership` per hex (DB persistence). |
| `scripts/GameState.gd` | Orchestrator: `resolve_frontline_phase()` (line 917), `resolve_cleanup_phase()` (line 843), `_taiwan_battalion_census()` (line 884). Holds `game_over`/`winner` (lines 67–68). | TIV `cleanup_application_service.py` + `cleanup_calculator.py` (system reset). |
| `scripts/model/TurnResult.gd` | `game_over: bool`, `winner: String` (lines 13–14). | N/A |
| `scripts/LLMGameAPI.gd` | Exposes `game_over`/`winner` in observation (lines 42–43). | N/A |
| `data/scenario_default.json` | `victory` block: `loss_check_arm`, `taiwan_hexes` (lines 7–11). | N/A |

## 3. Front-line service (`FrontLineService.gd`)

**`find_hexes_for_polyline(polyline_coords, hex_centers, sample_interval_km=2.0)` (line 82)**
Samples a polyline every `2.0 km` (including original vertices) and maps each sampled point to the nearest hex center via `point_to_hex` (haversine nearest-neighbor, line 49). Returns a de-duplicated ordered hex sequence.

- `sample_polyline` (line 65): for each segment, splits at `sample_interval_km` intervals.
- `point_to_hex` (line 49): brute-force nearest among all `hex_centers` entries (no spatial index).

**`distribute_units_along_hexes(unit_ids, hex_sequence)` (line 98)**
Evenly spaces `N` units across `M` hexes in order. Each unit `k` maps to hex index `floor(k × M / N)`. Returns `{brigade_id: hex_id}`.

**`GameState.resolve_frontline_phase(polyline_coords)` (line 917)**
Called externally (not from `resolve_turn` — user draws a line during planning). Finds RED brigades currently in the hex sequence, calls `distribute_units_along_hexes`, applies moves via `GameData.set_brigade_hex`, emits `frontline_resolved`.

Port fidelity: `_polyline_cumulative_lengths`, `_interpolate_along_line`, and `find_hexes_for_polyline` are direct ports. HexCombat uses brigade-level (not battalion-level) distribution and skips TIV's `_get_polyline_coords_in_hex` / `_nearest_point_on_polyline` (no per-hex polygon clipping — all affected hexes in the sequence share one even distribution). Support-battalion HQ offset is not ported (no sub-hex positioning).

## 4. Cleanup / ownership

**Hex owner normalization** — `GameData.recompute_hex_ownership()` (line 290):
Iterates all hexes; sets owner to `CONTESTED` (both teams present), `RED`, `GREEN`, or leaves `NONE` (unset — initialized to `GREEN` in `load_hex_grid` line 95). Only non-destroyed brigades count.

Also called after offload (line 363) and in cleanup (line 857), so ownership is up-to-date before the victory census.

**`resolve_cleanup_phase()` (line 843):**
1. Resets per-turn flags on all anti-ship systems: `fired`, `expended`, `destroyed_this_turn` → 0; `suppressed`, `active` → false.
2. Calls `GameData.recompute_hex_ownership()`.
3. Runs `_taiwan_battalion_census()` → `VictoryConditions.evaluate()`.

TIV port: `cleanup_calculator.py` resets `Fired`/`Destroyed_This_Turn`/`Final_Attrition_Pct` and also restores `Quantity_Moved`/`Quantity_Unavailable` → `Quantity_Available`. HexCombat has no moved/unavailable split (`AntishipSystem.quantity` is recomputed each turn from `original_quantity` minus IJFS-cumulative destroyed), so the restore is skipped.

## 5. Victory conditions (`VictoryConditions.gd`)

**`evaluate(china_bn, taiwan_bn, arm, turn_number, china_has_landed) → {game_over, winner, reason}` (line 5)**

Two checks, evaluated strictly in order:

1. **China win:** `china_bn > taiwan_bn` → `{game_over: true, winner: "red", reason: "china_majority"}`.
2. **Armed China loss:** if `arm` is active AND `china_bn == 0` → `{game_over: true, winner: "green", reason: "china_eliminated"}`.

Otherwise `{game_over: false}`.

**`loss_check_arm` config** (from `scenario.victory.loss_check_arm`, default `"unconditional"`):
- `"unconditional"` — always armed (loss check applies every turn.
- `"after_first_landing"` — armed after `_china_has_landed` latches true (any Red BN on Taiwan, per census).
- `"after_turn:N"` — armed when `turn_number > N`.

**Census caveat — `taiwan_hexes: null` (line 885):**
`_taiwan_battalion_census()` counts all brigades with a non-empty `hex_id`. The scenario config hook `taiwan_hexes` can restrict to a hex-id array, but defaults to `null` (= every placed hex counts). This is correct for the main-island-only scenario because offshore islands cannot be distinguished until terrain/land classification data exists. Brigades still at sea (`hex_id == ""`) are excluded, so China reads 0 until it lands.

**`game_over` / `winner` propagation:**
- `GameState.gd` lines 67–68 hold the live state; `resolve_cleanup_phase` (lines 866–867) sets them.
- `TurnResult` (lines 13–14) copies them for the `play_turn` return value.
- `LLMGameAPI.get_observation()` exposes them (lines 42–43).

## 6. Turn flow placement

Front-line is NOT called from `resolve_turn()` — it is driven externally by a user drawing a polyline (or an LLM action calling `resolve_frontline_phase`). In the intended WeGo flow:

```
PLANNING: draw front line → resolve_frontline_phase(polyline)
RESOLUTION: resolve_turn → ... → resolve_cleanup_phase
  └─ cleanup: reset anti-ship flags → recompute ownership → census → victory check
END: game_over check →  begin_next_turn or stop
```

Cleanup runs last in resolve_turn (GameState.gd:195). Victory census is the tail of cleanup — no further turn mechanics run after it.

## 7. TIV-port fidelity notes

| Component | HexCombat | TIV oracle | Port status |
|---|---|---|---|
| Polyline → hexes | `find_hexes_for_polyline` (2 km sample, haversine nearest hex) | `front_line_service.find_hexes_for_polyline` (same) | Full port |
| Unit distribution | `distribute_units_along_hexes` — brigade-level even spacing | `distribute_battalions_along_line` — battalion-level, per-hex clipping + support offset | Simplified (brigade-level, no sub-hex positioning) |
| Hex ownership | `recompute_hex_ownership()` — bulk scan, in-memory | `cleanup_hex_service.update_hex_ownership()` — per-hex DB write | In-memory equivalent |
| Anti-ship reset | `resolve_cleanup_phase` — clears fired/expended/destroyed_this_turn flags | `cleanup_calculator.reset_systems` — also restores Quantity_Moved/Quantity_Unavailable → Available | HexCombat skips restore (no moved/unavailable split) |
| Victory conditions | `VictoryConditions.evaluate()` — majority or elimination | No TIV equivalent | HexCombat design (settled 2026-06-28, PLAN.md entry) |
| Victory persistence | `game_over`/`winner` on `GameState`, `TurnResult`, LLM observation | N/A | N/A |

**What I cannot verify:** Whether the 2.0 km `sample_interval` produces identical hex sequences to TIV (the TIV oracle uses 2.0 km but sampling is sensitive to the exact hex grid data). Brigade-level distribution skips TIV's per-hex polygon clipping (`_get_polyline_coords_in_hex`) — the hex sequence approach snaps to hex centers, which may assign a brigade to a hex the polyline barely grazes.

**Deferred:** D5-D front-line DRAW UI is not implemented (Track 5 / graphics). The `resolve_frontline_phase` function exists for headless/LLM callers but has no in-game drawing tool.
