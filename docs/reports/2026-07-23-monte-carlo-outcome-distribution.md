# Monte Carlo outcome distribution — default laydown, symmetric scripted play

**Date:** 2026-07-23 · **Author:** Agent (Opus 4.8) · **Commit:** `7339378`

Feeds presentation deck slide 6 ("Not One Game — Thousands"). The chart in the deck is the inline
SVG generated from this batch; regenerate it, never hand-edit it (see Reproduction below).

## Research question

Under competent symmetric play on the default full-ROC-defense laydown, is the outcome of the PLA
invasion decided by the scenario or by the seed? I.e. how much does the hierarchical per-phase RNG
move the *winner* versus the *margin*?

## Conditions

| | |
|---|---|
| Scenario | `scenario_default` (full ROC defense: 32 ROC brigades / ~88 defending battalions vs 4 PLA amphibious brigades + deep-pool follow-on) |
| Matchup | `selfplay_default` in **both** seats (deterministic scripted policy — policy identity is part of the result) |
| Seeds | 200 common seeds `20260624..20260823` |
| Turn cap | 30 (games stop early on a decisive census) |

**Outcome axis.** The record's own victory census — PLA vs ROC battalions *present* on Taiwan at
end-of-cleanup — the same definition the golden victory gate uses (`winner` / `game_over`). Two
readings: the categorical **winner** (Red / Green / no-decisive) and the continuous **victory
margin** = `census.red − census.green`.

**Why scripted, not LLM.** The mission slide claims "hundreds of seeds." LLM-vs-LLM at that N is
infeasible (per-turn model calls, non-reproducible). Scripted `selfplay_default` is fast (~7 s/game
headless), real (full engine — IJFS, crossing, offload, ground combat), and byte-reproducible per
seed, so the distribution is honest and re-runnable. A trivial-policy result is a statement about
the policy, not the invasion; `selfplay_default` is the reference "sensible both sides" policy.

## Headline distribution (N = 200)

- **PLA wins 200 / 200.** No seed produced a ROC win or a no-decision.
- **But the margin is stochastic and often razor-thin:** min **+1**, median **+6**, mean **+8.0**,
  max **+28**, σ ≈ 6.6. 82 of 200 games finish within +1..+4 battalions — a near-run PLA victory.
- PLA battalions ashore at game end: 59–92 (mean 73). Games decide in **11–23 turns** (median 17).

**Reading:** on this laydown the RNG sets the *size* of the PLA victory, not its *sign*. The
crossing/mine/combat dice swing tens of battalions but never enough to flip the winner.

## Sensitivity (single-knob sweeps)

Common-seed sweeps, `selfplay_default` both seats, same scenario:

| Knob | Range | Effect on PLA win rate |
|---|---|---|
| `beaches[*].capacity_battalions` | 1 → 4 | flat **100 %** |
| `intel_locked_antiship_strike_bonus` (crossing lethality) | 0.0 → 0.8 | flat **100 %** |

Neither knob flips the winner across a wide range — corroborating the headline: **the laydown is
structurally Red-favored.** The crossing-lethality sweep *does* move the mechanic it targets — mean
crossing loss runs 37 % → 21 % as the bonus rises 0.0 → 0.8 (front-loaded kills leave later waves
less opposed), and the default 0.20 reads **33.2 %**, consistent with the USER-accepted 32.9 %
crossing calibration — but the extra losses are absorbed by follow-on echelons over ~17 turns, so
PLA ashore stays above the ROC count. Raw sweep table:
`assets/mc_crossing_sensitivity.sweep.md`.

## Caveats

- **Policy, not doctrine.** `selfplay_default` is one scripted decision-maker in both seats; the
  100 % result characterises *this* symmetric policy on *this* laydown, not "the invasion." A
  stronger ROC policy, an LLM seat, or a different scenario could move it.
- Victory census counts *present* battalions (a known modelling choice; refactor_audit notes a
  "present vs OOB" cleanup). ROC IJFS/CRBM attrition and PLA crossing losses both feed it.
- 30-turn cap: every game here decided well inside it, so the cap did not censor outcomes.

## Reproduction

```bash
# Headline batch (200 seeds) → per-seed records + manifest under reports/batches/ (git-ignored)
python3 tools/run_batch.py --name mc_outcome_distribution --scenarios default \
    --matchups selfplay_default --n 200 --base-seed 20260624 --turns 30 --parallel 6 --no-report

# Aggregate → committed summary JSON
python3 tools/mc_summarize.py --batch reports/batches/mc_outcome_distribution \
    --out reports/mc/mc_outcome_distribution.summary.json

# Render the deck chart SVG from the summary
python3 tools/mc_chart.py --summary reports/mc/mc_outcome_distribution.summary.json \
    --out reports/mc/mc_outcome_distribution.svg

# Sensitivity sweeps
python3 tools/run_sweep.py --spec tools/sweeps/mc_beach_capacity.json
python3 tools/run_sweep.py --name mc_crossing_sensitivity \
    --knob "data/ijfs/ijfs_scenario.json:intel_locked_antiship_strike_bonus" \
    --values 0.0,0.2,0.4,0.6,0.8 --matchup selfplay_default --scenario scenario_default \
    --n 20 --turns 30 --metrics crossing_loss_pct,red_win_rate
```

Committed artifacts: `assets/mc_outcome_distribution.summary.json` (the distribution data),
`assets/mc_outcome_distribution.svg` (chart source), `assets/mc_crossing_sensitivity.sweep.md`
(sweep table). Raw per-seed records are reproducible from the commands above.

---

## Follow-up — what actually flips the outcome, and two tooling bugs (2026-07-23)

**Question (USER):** the 100% PLA win rate can't be scenario luck — which dial flips it, and once
the amphibious wave lands, isn't the follow-on logistics-throughput-constrained?

**Nothing wave-level flips it.** Eleven dials swept/probed at extremes leave the win rate flat at
100%: amphibious return time (3→20), anti-ship strike bonus (0→0.8), exquisite missile count
(36→260), DOS supply start (100→6), combat base loss rate, and the combat advantage ratios. The
cause is **structural**: with `auto_seed_followon_pool = true` the PLA follow-on auto-seeds from the
*entire remaining mainland OOB* (`SealiftStateBuilder.resolve_followon_reserve`) — a bottomless
reservoir — and there is no campaign clock, so any positive delivery rate eventually out-accumulates
the defender. Cutting the pool off (first wave only) is the crude flip: Green holds 25:55, margin
−22..−35 over 12 seeds. But "first wave with no follow-on" is not a plausible operational case.

**The follow-on IS throughput-limited (USER instinct confirmed).** Turn 1 ships ~54 BNs but only
~39% discharge; a standing beach queue peaks at 33–45 BNs, draining 2–5/turn. The PLA also captures
the Taipei port **turn 1 for free** — `taipei` is `hex_44_16`, the primary assault beach — and
`auto_jlsf` repairs it to 11,000 t/day. But denying that repair (`auto_jlsf=false`) barely changes
the result (74:69, 63:62, …): the port isn't the crux. The crux is that baseline **beach** throughput
(4,400 t/day/beach) is already generous enough that logistics never binds.

**The plausible flip lever: beach offload throughput.** Sweeping `beaches[*].offload_rate` gives a
clean monotone crossing — the invasion **culminates** (plateaus below the ROC count, no decisive PLA
win) below **~1,330 t/day**:

| offload_rate (t/day) | 4400 | 3000 | 2200 | 1600 | 1200 | 900 | 600 |
|---|---|---|---|---|---|---|---|
| PLA win rate | 100% | 100% | 100% | 80% | 35% | 5% | 0% |
| mean margin | +6.7 | +2.7 | +2.2 | +1.6 | −3.8 | −9.0 | −22.4 |

Chart: `assets/mc_offload_throughput.svg` (deck slide 7). Data:
`assets/mc_offload_throughput.sensitivity.json`, sweep spec `tools/sweeps/mc_offload_throughput.json`.

**Two knob-registry bugs found and (partly) fixed:**

1. `offload_beach_base_rate` pointed at `data/offload_rates.json:rates.beach_base` — a **phantom**:
   that file is never loaded at runtime (throughput is the `OffloadRates` GDScript constants; the
   JSON is only a validation mirror), so a DataOverrides sweep of it silently no-ops while the record
   dump still reads a matching value. **Fixed:** repointed to the real, working path
   `data/beaches.json:beaches[*].offload_rate` (beaches.json *is* routed through DataOverrides).
2. `offload_operational_port_rate` has the same phantom problem (port rate is
   `OffloadRates.OPERATIONAL_PORT`, a code constant). **Marked `sweepable: false`** (dump-only);
   wiring `InfrastructureResolver` to read a loaded rate is backlogged.
3. **Not yet fixed:** `combat_defender_advantage_ratio` / `combat_attacker_advantage_ratio` are
   registry knobs that are recorded but **inert** — overriding either to an extreme produces a
   byte-identical game (they don't reach `CombatResolver`). Backlog: wire them or drop them.

**Reproduce the flip curve:**

```bash
python3 tools/run_sweep.py --name mc_offload_throughput \
    --knob "data/beaches.json:beaches[*].offload_rate" \
    --values 4400,3000,2200,1600,1200,900,600 --matchup selfplay_default \
    --scenario scenario_default --n 20 --turns 30 --metrics red_win_rate
python3 tools/mc_chart.py --crossing reports/mc/mc_offload_throughput.sensitivity.json \
    --out reports/mc/mc_offload_throughput.svg
```

**Open threads (USER-selected next levers, no artificial clock):** sustained per-turn follow-on
interdiction; a bindable offload/lift throughput (fix the port-rate phantom); dynamic ROC defense
(counterattack / reserve mobilization). Each aims to create a plateau below the ROC count *within*
the horizon rather than capping delivery with a timer.
