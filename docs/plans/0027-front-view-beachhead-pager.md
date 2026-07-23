---
status: Sketch
shipped:
landed_in:
---

# 0027 — Front-view per-beachhead pager (ocean-spanning fronts)

**Priority:** Low — build only when BOTH conditions hold (see Trigger).

**Context.** Plan 0023 P1 made the viewer's "Front" viewport
(`tools/viewer/game_viewer.html`, `updateZoomViewport`) group the red/contested hexes into
connected components (`connectedComponents` / `largestCluster`, the `<clustering-pure>` block)
and frame only the **largest** cluster, tie-broken by contested-hex count. That fixed the
"one bbox spanning the water between two beachheads → zoom to empty ocean" failure by showing the
single dominant beachhead. A secondary, spatially-separated beachhead is then **not** framed in
the Front view — it remains visible only in the Theater (whole-island) view.

**Idea (deferred).** When a turn genuinely has ≥2 separated beachheads, offer a per-beachhead
**pager** in the Front box: small next/prev (or numbered tabs) that step the viewport through each
cluster's frame, largest first. The clustering is already done in P1 — this is purely a UI affordance
over `connectedComponents`' output (iterate clusters instead of taking only `largestCluster`), plus
a control and a label ("Beachhead 1 of 2").

**Trigger — do NOT build until both are true:**
1. **A talk actually needs per-beachhead close-ups.** Presentation-driven; USER call.
2. **The sim actually produces an ocean-spanning front.** As of 2026-07-23 the P1 precondition scan
   (`reports/llm/*.viewer.json`) found only *small, tight* multi-cluster turns — all clusters inside
   the one northwest landing region, separated by single-hex gaps (~40–70 px in a 700×1000 viewport;
   best case game_20260711 turn 15, ~4× frame tightening). No turn showed two beachheads on opposite
   coasts. A pager for a state the sim never produces is a speculative feature, not a fix — re-run the
   scan (`scan_disjoint.py` approach in the 0023 work) and confirm a real ocean-spanning turn exists
   first. If the sim's amphibious model changes to open multiple coasts, that changes this calculus.

**Scope when built.**
- Front box gains a compact pager control (numbered tabs or ◀ N/M ▶), hidden when there is ≤1 cluster.
- `updateZoomViewport` frames the *selected* cluster; default selection = largest (current behavior).
- Regression test extends `tools/viewer/test_clustering.mjs`: assert cluster ordering is stable so
  pager indices are deterministic across turns.
- Verify: Playwright screenshot each pager page on a real (or, if greenlit, synthetic) two-beachhead
  bundle.

**Explicitly out.** Interactive free pan/zoom is a live-operator need — that is plan 0026, not this.
