---
status: Ready
shipped: 
landed_in: 
---

# 0023 — Track D Master Orchestration Plan (Adjudication UI)

**Goal:** Execute Track D from the backlog (Adjudication aid graphics/UI) using a fully autonomous agentic swarm. This plan is written specifically for the **Orchestrator Agent**, dictating how to manage the `opencode` and `agy` subagents.

## Orchestration Strategy

1. **Sequential Execution:** The orchestrator must tackle one UI component at a time to prevent Godot scene merge conflicts and ensure a stable base.
2. **Subagent Lifecycle:** For each component, the orchestrator will spawn a **fresh** pair of subagents:
   *   An `opencode` subagent to write the code.
   *   An `agy` subagent to review the visuals.
   *   *Note: Kill the previous subagents before spawning new ones to conserve resources and context window.*
3. **Screenshot Pipeline:** Because headless testing doesn't cover pixels, the `opencode` agent MUST write a small Godot script to run the scene, wait for the render, capture the viewport (`get_viewport().get_texture().get_image().save_png()`), and save it to the workspace.
4. **The Feedback Loop:** 
   *   The orchestrator acts as the broker. When `opencode` produces a screenshot, the orchestrator passes it to the `agy` agent for visual review against the component's requirements.
   *   The orchestrator passes `agy`'s feedback back to `opencode` for iteration.
5. **Approval & Commit:** Once `agy` approves the visuals, the **orchestrator** performs a final verification of the code against the `AGENTS.md` rules, commits the code, and appends the final screenshot to a master visual log artifact (`track_d_visual_log.md`) for the USER to review at the end of the session. The orchestrator then automatically proceeds to the next component.

---

## Component Sequence

Tackle these components strictly in this order:

### 1. Projector-readable Map (Foundation)
*   **Requirements:** Establish the visual language. Add clear markers, distinct ownership colors, a phase/turn HUD, and camera fit/zoom/pan controls. It must be highly legible when projected in a room.
*   **Subagent Task:** Update `HexMap.gd` and the main scene to implement these visuals. Generate a screenshot of a mid-game state (e.g., turn 5 of `scenario_default`).

### 2. Order-entry Flow Polish
*   **Requirements:** Build a clean interaction loop for a non-developer facilitator: Select Unit -> Issue Move/Commit Order -> End Turn.
*   **Subagent Task:** Refine the UI controls and selection visuals. Generate screenshots of the selection state and the order-confirmation state.

### 3. Anti-ship/Mine Crossing Visualization
*   **Requirements:** Make the D3 crossing mechanics (missile defense, mine encounters) legible on the map.
*   **Subagent Task:** Create transient visual effects or permanent logs on the map that show crossing attrition. Generate a screenshot showing an active crossing phase.

### 4. D5-D Front-line Polyline-draw UI
*   **Requirements:** Implement the complex drawing interaction for the front line, showing battalion-granularity distribution.
*   **Subagent Task:** Build the polyline drawing tool. Generate a screenshot of a drawn, contested frontline.

### 5. Viewer Front-zoom (HTML Viewer)
*   **Requirements:** Fix the HTML viewer's bounding box issue. Currently, non-contiguous fronts (two separate beachheads) create a massive bounding box spanning empty ocean. Cluster the focus set and frame the active/largest cluster, or offer per-cluster paging.
*   **Subagent Task:** Modify `tools/viewer/game_viewer.html` (`updateZoomViewport`). Generate a screenshot of the HTML report using Playwright/browser tools.

---

## Checklist for the Orchestrator

- [ ] Initialize `track_d_visual_log.md` (as a persistent artifact) to store approved screenshots.
- [ ] **Component 1 (Projector Map):** Spawn agents -> Iterate -> Verify -> Commit -> Log.
- [ ] **Component 2 (Order Entry):** Spawn agents -> Iterate -> Verify -> Commit -> Log.
- [ ] **Component 3 (Crossing Vis):** Spawn agents -> Iterate -> Verify -> Commit -> Log.
- [ ] **Component 4 (Front-line Draw):** Spawn agents -> Iterate -> Verify -> Commit -> Log.
- [ ] **Component 5 (Viewer Zoom):** Spawn agents -> Iterate -> Verify -> Commit -> Log.
- [ ] Run full verification gate (`bash tools/run_all_tests.sh`) to ensure no logic regressions.
- [ ] Update `docs/plans/BACKLOG.md` to check off Track D.
- [ ] Log the Track D completion in `docs/DECISIONS.md`.
- [ ] Present `track_d_visual_log.md` to the USER.
