---
title: "0022: Red reactive beach-opening — feasibility first, then a posture knob"
status: "Sketch"
created: "2026-07-20"
---

# Plan 0022: Red opens a new beach when Green strips its defense

## Research question (USER 2026-07-20)

The counter-pressure half of the garrison-draw study ([[0021-garrison-draw-policy]]): if Green pulls
forces out of a theater to reinforce the beachhead, can Red *punish* it by landing at the now-thinly
-defended beach? Sweep Red's opening rule — **never / open if the target beach is unguarded / open
only if ≤2 brigades sit in the target hex or its adjacent hexes** — and see how much it changes the
value of Green's force-draw.

## ⚠️ This needs a mechanic that does not exist yet — feasibility FIRST

Verified 2026-07-20: **Red's assault beaches are fixed at scenario load.** `red_ship_reserve` and
`red_followon_reserve` entries carry a `locked_beach` + `beach_hex` authored in the scenario file;
`ShipReserveBuilder` / `SealiftStateBuilder` turn them into the first-echelon `ship_reserve` and the
follow-on `mainland_pool`, and the whole downstream pipeline keys off those authored beaches
(`AntishipResolver` builds its `beach_set` from `locked_beach`; offload nodes, minefields, and
`offset_bearing` are all per-authored-beach). **Nothing lets Red observe Green's posture and open a
NEW assault beach mid-game.** The only dynamic beach pick in the code is JLSF *logistics* (lowest
beach-id in an already-seized TO), not a fresh assault.

So this plan is **not** a policy tweak — it is a new capability. Do it in two stages; do not design
the posture knob until stage 1 proves a landing can even be injected.

### Stage 1 — feasibility spike (the gate for the rest)

Answer, with a throwaway experiment, whether a landing can be injected at a beach **not** in the
original reserve and resolve cleanly end-to-end:

- Can a `mainland_pool` entry be re-targeted (or a new entry added) to a different `locked_beach` /
  `beach_hex` at runtime, and does `SealiftStateBuilder`/`ShipReserveBuilder` accept it?
- Does the crossing → offload → antiship → mine pipeline handle a beach that had no first-echelon
  landing (do all 9 beaches carry the data a landing needs — minefields, `offset_bearing`, capacity,
  a valid `beach_hex`, TO adjacency)?
- Determinism: does adding a landing perturb RNG substreams for other phases (hierarchical `Dice`
  should isolate it, but confirm)? Golden must stay byte-stable when the feature is off.

If stage 1 says "cheap" → proceed. If it says "the pipeline assumes fixed beaches deeply" → report
back to USER with the cost before building; this may become its own multi-part effort.

### Stage 2 — the decision layer + posture knob (only if stage 1 passes)

- **Who decides:** a Red order type (like `deploy_jlsf`) that opens a landing at a chosen beach,
  issued by a Red policy — OR an automatic rule inside a scripted Red policy. Likely the former
  (keeps the mechanic inspectable and testable independent of any policy).
- **The posture knob** `red_beach_open_rule` ∈ { `never`, `if_unguarded`, `if_le2` }: evaluated
  against Green brigade positions in the target beach hex + its adjacent hexes (from `GameState`).
  Lives in a `data/*.json` file so it sweeps + records like any knob (pairs with 0021's
  `draw_fraction` for the two-sided grid).
- **Which beach:** the undefended beach nearest Red's existing beachhead / in the stripped TO
  (design call).

## Objectives

1. Stage-1 feasibility spike + written verdict (cost + risks) → USER checkpoint.
2. (gated) Landing-injection mechanic + `deploy`-style Red order; golden byte-stable when off.
3. (gated) `red_beach_open_rule` knob + the three posture rules; Red policy that issues the order.
4. (gated) Two-sided sweep with 0021: `draw_fraction` × `red_beach_open_rule` grid, sensitivity +
   narratives.

## Verification

- Stage 1: a spike script lands a brigade at a non-reserve beach and the turn resolves with no
  index violations; golden untouched with the feature off.
- Stages 2–4: new GdUnit coverage for the order + posture rules; golden byte-stable when the rule is
  `never`; the two-sided sweep produces a sensitivity grid.

## Dependencies / notes

- Pairs with [[0021-garrison-draw-policy]] — 0021 is runnable alone (Green vs a fixed-beach Red);
  0022 turns it into the two-sided study. Sequence 0021 first.
- If stage 1 reveals the pipeline hard-codes fixed beaches, this is a genuine design decision for
  USER (how much new mechanic is worth the study) — surface it, don't guess.
