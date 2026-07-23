---
status: Sketch
shipped:
landed_in:
---

# 0024 — Order-entry facilitator flow (live play)

**Goal:** A clean interaction loop for a non-developer facilitator running a live game:
Select Unit → Issue Move/Commit Order → End Turn. (Draft-0023 component 2.) Deferred behind
plan 0023 — this is live-facilitator UI, irrelevant to headless LLM-vs-LLM presentation.

**How the work is done:** primary agent writes the code directly (no swarm); Godot-MCP
screenshots for visual verification.

## Verified current state (2026-07-23)
- `GameController.gd` handles clicks via `_on_hex_clicked()`, toggles tactical vs administrative
  movement via an `OptionButton`, and emits `commit_requested` through `CompositionPanel.gd`.
- `HexMap.gd` draws basic reachable/selected highlights via `highlight_hexes()`.
- The flow works but is developer-shaped, not facilitator-shaped.

## Sketch scope
Refine selection visuals, order-confirmation affordances, and the End-Turn control into a legible
facilitator loop. Screenshot the selection state and the order-confirmation state.

## Verification
Visual (not headless-gateable) — Godot-MCP screenshots. Canonical gate stays green
(`bash tools/run_all_tests.sh`) since interaction wiring must not touch turn logic.
