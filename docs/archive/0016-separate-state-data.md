---
title: "0016: Separate State Data from Autoload"
status: "Superseded by 0014"
created: "2026-07-19"
---

# Plan 0016: Separate State Data from Autoload — SUPERSEDED

**Superseded by [plan 0014](0014-gamestate-dependency-ceiling.md) (2026-07-19).**

The `GameStateData` extraction described here (pull `phase`, `turn`, `orders`, `commitments`,
RNG streams and all runtime state out of the `GameState` autoload into a `RefCounted` value type;
have resolvers accept `GameStateData` instead of the autoload) is the *foundation* for doing
0014's dependency-ceiling reduction genuinely rather than by laundering references. Keeping them as
two plans risked a weak implementer wiring them out of order, so 0016 was folded into 0014 as its
**Phase 1**. USER call 2026-07-19: fold, don't sequence.

Do the work under 0014.
