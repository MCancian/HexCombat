# PLAAF air insertion (plan 0032)

## 1. Purpose

The amphibious crossing is the PLA's binding chokepoint: attritable, capacity-limited, and — per
[0028](../plans/0028-sustained-followon-interdiction.md) — crowded by its own JLSF logistics. This
mechanic gives Red a **second way onto the island** that does not queue for a hull: fly battalions
directly onto any passable hex, under a per-turn lift cap and under fire from Taiwan's air defences.

Two things make it a lever rather than a cheat code:

1. **The lift is destructible and never regrows.** Every battalion the air defences kill also
   destroys the airframe that carried it, permanently lowering the per-turn cap. A bloody early drop
   costs throughput for the rest of the game.
2. **A dropped brigade is out of supply until a corridor reaches it.** Landing 40 battalions in empty
   rear terrain does not win the census; they fight at out-of-supply effectiveness until Red ground
   connects them to a beachhead.

The plan as sketched assumed the OOB already had airborne units. It did not — 945 PLA battalions,
zero airborne — so the same work adds the formations (see §2).

## 2. The force: PLAAF Airborne Corps

Six brigades appended to `data/pla_ground_forces.json`, 50 battalions, never placed by any scenario.
USER call 2026-07-24 (3 light airborne + 2 mechanized airborne + 1 air assault); brigade numbers
assigned by the implementing agent.

| Brigade | `nato_type` | Battalions | Composition | Theater |
|---|---|---|---|---|
| 127th / 128th / 134th Airborne | `airborne` | 8 each | 4 Airborne Combined Arms + Field Artillery + Air Defense + Support + Service Support | Southern / Western / Eastern |
| 131st / 133rd Airborne | `airborne` | 8 each | 4 Mechanized Airborne Combined Arms + Mechanized Artillery + Air Defense + Support + Service Support | — / Northern |
| 130th Air Assault | `air-assault` | 10 | 3 Air Assault Infantry + 6 Utility Helicopter + Service Support | — |

Composition follows the USER's sources ("four combined arms battalions, an artillery battalion, a
support battalion, an anti-air battalion and a logistics battalion"; air assault "as many as six
transport battalions and as many as three infantry battalions"). **Sourcing honesty:** the 130th
takes the air-assault role because a 2024 Taiwan publication names it one of the corps' air assault
brigades; *which two of the remainder are mechanized is a modelling choice, not a sourced one*, as is
the theater assignment of the 130th and 131st (their sources give none).

Two new unit types in `UnitStats.TYPE_DEFS`, anchored on the pre-existing fallback category defs
rather than invented: `Airborne Combined Arms Battalion` = 1.3 (the "Airborne" category's value) and
`Mechanized Airborne Combined Arms Battalion` = 1.4 — above light airborne, below a fully mechanized
CAB's 1.5, level with where "Air Assault" already sat.

The 7 pre-existing `Air Assault Infantry Battalion`s stay where they are, one apiece inside the
PLANMC Marine brigades. They cross by sea with their parents; a brigade occupies one hex, so they
cannot fly while the rest of the formation sails.

## 3. Files & responsibilities

| File | Role |
|---|---|
| `scripts/model/LiftClass.gd` | Sole home for the OOB `nato_type` → lift-class map. `airborne` → `AIRBORNE`, `air-assault` → `AIR_ASSAULT`, everything else sea-lifted. |
| `scripts/model/AirInsertionState.gd` | Cross-turn state: `pool` (battalions waiting to fly, `{brigade_id, lift_class, bns}`), `caps` / `initial_caps` (the airframe ledger), `first_turn`, `landed`, `history`. `eligible_orders(brigades, pending)` builds the order-legality list without touching a singleton. |
| `scripts/model/AirInsertionSummary.gd` | Per-turn result: `drops`, `rejected`, battalion/cap totals, `attrition_by_class`. `to_dict()` projects drops onto `DROP_REPORT_KEYS` — the per-battalion manifests are application detail, not contract. |
| `scripts/resolvers/AirInsertionStateBuilder.gd` | Pure builder: pool from the OOB, caps and `attrition_config` from the scenario block. Unknown config keys fail loud. |
| `scripts/resolvers/AirInsertionResolver.gd` | Pure resolver: `resolve()` flies the packets, `attrition_rate()` is the loss model, `threat_from_ijfs_summary()` is the one place that knows which IJFS fields the air path reads, `isolated_brigades()` is the supply-corridor flood. |
| `scripts/resolvers/ReinforcementPhases.gd` | `resolve_air_insertion_turn()` (the wrapper: casualties, landings, ownership, EventBus), `hex_can_receive_insertion()`, `isolated_air_landed_brigades()`, `red_lodgement_hexes()`. |
| `scripts/resolvers/OrderValidator.gd` | `add_air_insert_order()` + `eligible_air_insert_brigades()`. |
| `scripts/resolvers/CleanupResolver.gd` | `census()` subtracts battalions not yet ashore — from the ship reserve **and** the air pool. |
| `scripts/resolvers/SealiftStateBuilder.gd` | Excludes air-lifted brigades from the follow-on auto-seed (the corps never queues for a hull). |
| `scripts/AirAssaultPolicy.gd` | Policy id `air_assault`: selfplay_default plus the standing airborne doctrine. |
| `scripts/LLMGameAPI.gd` | `_air_insertion_observation()` + the `air_insert` action. |
| `tools/validate_air_insertion.gd` | End-to-end gate coverage on `red_airborne`. |
| `tests/air_insertion_resolver_test.gd`, `tests/air_insertion_builder_test.gd`, `tests/air_insertion_order_test.gd` | Pure unit coverage: caps, attrition, cap erosion, order legality, supply corridor. |

## 4. Scenario configuration

```json
"red_air_insertion": {
  "enabled": true,
  "airborne_cap_per_turn": 7,
  "air_assault_cap_per_turn": 2,
  "first_turn": 1,
  "max_attrition_at_full_ad": 0.75,
  "manpads_max_attrition": 0.25
}
```

**Absent block ⇒ empty pool ⇒ the phase is a no-op that consumes no dice.** Only
`data/scenarios/red_airborne.json` opts in; `scenario_default` is deliberately untouched so existing
baselines stay comparable. All five values are `scenario:`-prefixed registry knobs
(`air_insertion_*`), so any of them can be swept.

## 5. The attrition model

```
airborne     = max_attrition_at_full_ad × effective_ad_health
air_assault  = the same, PLUS manpads_max_attrition × IjfsManpads.threat_fraction(ready_launchers)
```
clamped to [0, 1], rolled **per battalion** from the derived substream `air_insertion:<turn>`.

Linear in AD health by USER call 2026-07-24, anchored on two numbers they supplied: an intact air
defence system destroys **75%** of an inserting packet, and a typical run (3 days of pre-IJFS
warmup) should cost about **15%**. Those are consistent without a fudge factor because the measured
`taiwan_ad_health_after.effective_ad_health` on turn 1 after the warmup is **0.244** — so a turn-1
drop costs 18.3%, falling to ~11% once the SAM layer is gone.

Rotary-wing lift carries the second term because the MANPADS layer is deliberately **excluded** from
the AD-health metric (passive-IR shoulder launchers are not SEAD-targetable) yet is exactly what
engages helicopters. It runs from ~1975 ready launchers on turn 1 to zero by turn 5, so an early
helo assault costs ~43% and a late one ~11%. The two lift classes therefore have different best
moments — a real timing decision, not a reskin.

The air-defence picture is read from **this turn's** IJFS summary, because the phase runs after the
fires. Suppressing Taiwan's SAMs before dropping visibly pays off.

**Landing zones are unrestricted** (USER design call: land on any hex). Enemy-held and contested
ground are explicitly legal targets; dropping onto the enemy is paid for by the ground combat that
follows in the same turn, not by a bespoke landing-zone penalty.

## 6. Turn placement

```
IJFS → sealift → anti-ship crossing → amphibious offload → ROC mobilization
  → AIR INSERTION → movement & commit → ground combat → front-line → cleanup
```

After IJFS because the drop's attrition is read off the air-defence picture those fires just
produced. Before movement so an opposed drop is contested and fought in the same turn. Alongside the
other two reinforcement phases, so all three arrivals share one seam.

Within the wrapper, **losses are applied before landings**: a battalion shot down never reaches the
hex, and killing it first keeps a brigade that lost its whole packet off the map entirely rather than
flickering onto it.

## 7. Supply isolation

An air-landed brigade is **out of supply** unless a chain of Red-held hexes runs from it back to a
lodgement — a landing beach or a port/airbridge Red can offload through. It counts as supplied when
its own hex is on that chain **or merely touches it**, so a formation at the contested tip of a
corridor still eats.

Recomputed every combat: a corridor punched through this turn supplies the drop, a corridor cut
starves it again. The penalty is `red_out_of_supply_effectiveness` (0.5 by default) regardless of the
theatre DOS pool — the tonnage exists, it just cannot reach a battalion behind enemy lines.

This applies **only** to air-landed brigades. Sea-landed brigades that outrun their beachhead are
unaffected; generalising it would be a larger change to the existing supply model.

## 8. Orders

`air_insert` (Red only) — `{brigade_id, target_hex}`, one per brigade per turn. Validation is thin
where the mechanic is meant to be free (no allowance, no adjacency, enemy hexes legal) and strict
where the model demands it: air-lifted brigades only, the hex must exist and be passable, and once a
brigade is ashore its follow-up battalions must reinforce it **there** — a formation occupies one
hex.

How much flies is *not* decided at order time. The per-class budget is spent at resolution in issue
order; an order that finds it already gone is reported in `summary.rejected` rather than rejected
during planning, because losses between planning and resolution can erode the cap underneath the
player.

Observation block `air_insertion` (both seats): `caps` vs `initial_caps` (the airframe ledger),
`eligible` (with `locked_hex` and battalions waiting), `estimated_attrition` per class at the last
resolved turn's picture, `pending_*`, `landed`, `history`.

## 9. Fidelity notes / deliberate divergences

- **Airframes are abstracted into the cap.** There is no aircraft OOB; lift is a battalions-per-turn
  budget that only ever falls. An alternative — deriving the air-assault cap from surviving Utility
  Helicopter battalions in the aviation brigades — was considered and not built.
- **The PLAA's two air assault brigades are not modelled.** The USER's sources give the PLAA 15
  aviation brigades, two of them air assault; the OOB has 13, none air assault. Only the Airborne
  Corps' own air assault brigade feeds the rotary-wing cap.
- **A partially-arrived brigade consumes DOS only for the battalions ashore** (plan 0037, USER call
  2026-07-25). `active_red_battalion_units` subtracts the off-map pools, so battalions still waiting
  to fly neither fight nor eat. This reverses the note that stood here from plan 0032 ("a partially-
  arrived brigade consumes full DOS"), which described the pre-existing sealift behaviour; sealift
  changed at the same time, so the two paths still agree.
- **No landing-zone attrition term.** The plan's original design call (Green-held/contested hexes
  inflict high attrition) was superseded by the USER's air-defence-keyed model; the cost of an
  opposed drop is now the ground combat itself.
