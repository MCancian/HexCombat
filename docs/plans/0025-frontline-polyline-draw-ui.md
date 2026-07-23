---
status: Sketch
shipped:
landed_in:
---

# 0025 — Front-line polyline-draw UI (D5-D, live play)

**Goal:** Interactive front-line drawing at battalion granularity — the operator draws a polyline
and battalions distribute along it. (Draft-0023 component 4.) Deferred behind plan 0023; also
tracked in `docs/plans/README.md` "Parked refinements" ("Front-line distribution at battalion
granularity").

**How the work is done:** primary agent writes the code directly (no swarm). This is a substantial
interactive feature — treat as its own multi-session effort with per-step gates.

## Verified current state (2026-07-23)
- Backend exists: `FrontLineService.gd` (polyline → hex redistribution) and the D5 cleanup phase.
- Zero UI: the user cannot interactively distribute battalions or draw polylines on the map.

## Sketch scope
Build the polyline drawing tool on the Godot map, bound to `FrontLineService.gd`'s redistribution
contract. Screenshot a drawn, contested frontline.

## Verification
Visual (Godot-MCP screenshots) + canonical gate green. The drawing UI must feed the existing
service, not reimplement redistribution.
