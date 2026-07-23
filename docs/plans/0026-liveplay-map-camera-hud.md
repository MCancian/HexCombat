---
status: Sketch
shipped:
landed_in:
---

# 0026 — Live-play Godot map: camera, HUD, replay screenshotter

**Goal:** The live-operator / projector needs on the Godot scene (as opposed to the headless HTML
viewer covered by plan 0023): camera fit/zoom/pan and a visual phase/turn HUD; plus, if
Godot-quality stills of headless replay turns are ever wanted over the viewer's SVG, a
replay-state screenshotter. (Interactive slice of draft-0023 component 1.) Deferred behind plan
0023.

**How the work is done:** primary agent writes the code directly (no swarm); Godot-MCP screenshots
for verification.

## Verified current state (2026-07-23)
- `HexMap.gd` renders hexes with solid terrain colors; ownership as per-region perimeter borders
  (`_build_ownership_borders()`); brigade markers as stacked badges (`_build_brigade_marker()`).
- No camera pan/zoom script is attached to `Main.tscn`'s `Camera2D`.
- No visual phase HUD — only a basic `TurnStatusLabel` in `GameController.gd`.
- `tools/capture_screenshot.gd` captures the live `Main.tscn` only, not an arbitrary replay turn.

## Sketch scope
1. Attach camera fit/zoom/pan controls to `Main.tscn`'s `Camera2D`.
2. A visual phase/turn HUD on the live scene.
3. (Optional) A script that loads a replay turn's state into the Godot renderer and captures a PNG,
   for Godot-quality presentation stills — only if the HTML viewer's SVG proves insufficient.

## Verification
Visual (Godot-MCP screenshots) + canonical gate green. Cosmetic/view-layer only; no turn logic.
