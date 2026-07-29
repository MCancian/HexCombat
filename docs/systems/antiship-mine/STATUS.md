# Anti-Ship & Mine Warfare — Status

**D3 Anti-ship & mine warfare** — IJFS-fed firing plan → crossing damage (count-based) → **geometric
mine model** (randomized approach path, dangerous-mine count within `danger_radius`, decoy-sponge
transit; knobs in `data/antiship/minefields.json`). Ship losses → BNs lost at sea. Crossing
lethality is calibrated to the USER-accepted 32.9% mean loss on the 81-BN sent-cohort wave
via `data/ijfs/ijfs_scenario.json`'s
`intel_locked_antiship_strike_bonus` (0.20) and `prelanding.intel.exquisite_intel.antiship.initial_count`
(36) — see `docs/archive/0001-crossing-lethality-calibration.md`.
**Off-island fleet strikes (plan 0028):** `off_island_strike.shooters[]` in
`antiship_crossing_config.json` (`type` = combat-catalog launcher — `6` submarine `Harpoon_Sub_II`,
`3` air `Harpoon_Air_II`/`SLAM-ER`; `systems_per_turn`) appends **location-less** firing rows every
turn (`AntishipResolver._append_off_island_strikes`) so the follow-on faces sustained interdiction
independent of on-island IJFS suppression/depletion — the toll the front-loaded on-island salvo
lacks (turn-1 carries ~96% of baseline at-sea losses, follow-on crosses at ~3%). Registry knobs
`off_island_{submarine,air}_strikes`; default 0 ⇒ golden byte-stable. It's a real sustained lever
(margin +9→+3, fleet drownings 26→54 over subs 0→64) but does NOT flip alone (offload *rate* is the
binding constraint, reservoir is bottomless) and is antagonistic with the offload throttle (sinking
ships thins the beach queue). Detail: `docs/plans/0028-sustained-followon-interdiction.md`.
**Launcher losses are permanent (plan 0043, USER call):** an `AntishipSystem` row keeps
two source-specific cumulative loss totals — IJFS kills (assigned from the cumulative writeback) and
launch-attrition kills (accumulated one crossing at a time) — and derives `destroyed` / `quantity`
from them, clamping their sum at the establishment. Launchers destroyed while firing used to come
back on the next crossing, because the firing plan rebuilt `quantity` from `original_quantity` minus
IJFS kills alone. Attempting to fire no longer consumes a launcher; only reported destruction does.
Measured over 12 common seeds (scenario_default, `selfplay_default`, 30-turn cap): Green systems
fired falls in every seed that moves (mean −5.4 per campaign, range −18..0, never rises), Red hull
losses mean −0.83 (−14..+4), BNs drowned mean 0.00 — no rebalance indicated, and no pin moved.
Report: `docs/reports/2026-07-27-antiship-permanent-launch-destruction.md`.
