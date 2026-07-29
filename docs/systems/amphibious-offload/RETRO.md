# Amphibious Offload — Retrospectives

## 2026-07-15 — plan 0006 C8: research verification + closeout   (implementer: direct)

**What would you do differently (implementer):**
- The C8 research runs caught a total sealift livelock (heavy BNs unlandable in one day; see
  `hexcombat-failure-archaeology` → "Sealift livelock") that C1–C7's 53-suite gate and the
  10-turn smoke could not see. Long-horizon ordered runs should have been part of the C6/C7
  verification, not deferred to a final step — the bug shipped in 3 pushed commits before C8 ran.
- When a per-item cost is drawn from a per-turn budget, check max(cost) > min(budget) at design
  time; the TIV oracle's fractional queue existed precisely because of this case.

**Orchestrator triage:**
- Long-horizon research run at feature-verification time → **act now** (done this session: smoke
  extended to 12 turns + landings-past-turn-10 assertion; carry-over fix + 4 tests committed).
- Budget/cost mismatch design check → **record only** — captured as the archaeology lesson.
