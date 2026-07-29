# Anti-Ship & Mine Warfare — Retrospectives

## 2026-07-27 — plan 0043: anti-ship mutation authority + permanent launch destruction   (implementer: direct)

**What would you do differently (implementer):**
- **Run a validator the way the GATE runs it, or its verdict means nothing.** I ran
  `validate_cleanup.gd` bare while checking a reconstructed commit, got `casualties=6, feba=0.43`
  against a pin of `3, -2.66`, and spent three experiments hunting a code bug that did not exist —
  the gate exports `HEXCOMBAT_SCENARIO=scenario_golden` and I had not. This trap is recorded in that
  validator's own header and in the memory file, and I walked into it anyway because I was running a
  single validator "just to check quickly". There is no quick check: use the gate's environment.
- **Measure the effect through the real harness, not a hand-rolled loop.** My first measurement
  drove `GameState.resolve_turn` in a `for` loop and concluded the campaign contained ONE crossing.
  It contains 4–8. Without `begin_next_turn` every turn after the first fails with "Cannot resolve
  turn outside PLANNING phase", and the probe cheerfully summed a stale summary 25 times. Two
  independent wrongs pointing at the same wrong answer. `run_selfplay_game.gd` existed the whole time.
- **A cumulative source that reports nothing has said nothing — not zero.** The IJFS writeback only
  carries rows it actually destroyed, so `get(key, 0)` on an absent key silently meant "no launchers
  have ever been lost here". Reading absence as zero would have resurrected the whole arsenal by the
  back door, on the very commit that removed resurrection. A reviewer caught it; nothing in the tree
  would have, because the golden scenario never exercises it.
- **Guards that `assert(false)` cannot be tested, so they get shipped unproven.** Switching the
  authority's refusals to `push_error` + change-nothing made all five of them testable with
  `assert_error(...).is_push_error(...)`, and writing those tests immediately found that the
  launch-attrition backwards guard was passing a floor of `0` — inert by construction.
- **Splitting work into commits AFTER the fact costs a full gate run per commit, and re-creating an
  intermediate state is where you introduce the bug you are trying to prove absent.** The separation
  was worth it (an extraction proven inert, then a behaviour change measured against it), but commit
  as you go: I had the byte-stable tree in hand at the time and threw it away.

**Actions:** none outstanding — the absent-key rule and the no-`assert(false)` rule are recorded in
`hexcombat-architecture-contract`; the scenario-env trap is already in `validate_cleanup.gd`'s header.
