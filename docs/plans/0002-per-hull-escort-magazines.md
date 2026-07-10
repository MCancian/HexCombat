# 0002 — Per-hull escort magazines (D3-B3)

**Status:** Sketch · **Priority:** Low — tie to a concrete balance need, don't port speculatively

## Goal

Escort interception / terminal defense during the crossing should deplete per-hull magazines
(`hq10`/`hhq9`), replacing the current count-based abstraction.

## Why parked

Needs a ship ammo/readiness subsystem HexCombat doesn't have. The count-based port matches all
source pytests today; the per-missile/per-hull pipeline (launches → allocate → leakers →
missile_damage → second_attack, TIV `services.ship_ammo`) is the upstream throughput model and
only pays off alongside plan 0001's missile-pipeline depth. Map:
`docs/antiship_missile_pipeline_ref.md`; port context: `docs/archive/port_audit.md`.

## Checklist

- [ ] Trigger: a balance question the count-based model can't answer (record it here)
- [ ] Ship ammo/readiness subsystem design (USER design call on scope)
- [ ] Port pipeline; per-source-pytest parity; golden re-baseline
