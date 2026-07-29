# Amphibious Offload — Status

**D1 Amphibious offload** — ship reserve → beach landing; lands brigades onto beach hexes.
Every scenario's `red_ship_reserve.beach_hex` must be coastal (< 6 land neighbors) —
`validate_scenario_data.gd` rejects fully-inland landing hexes.

**Sealift lifecycle** (plan 0004) — ships cycle ready→sent→offloading→returning→ready
(`SealiftState` + `SealiftResolver`); follow-on echelons embark onto ready amphibious lift so
crossing sustains across turns instead of draining by ~turn 3. A BN crosses **once** (attrited on
its crossing turn, then safe offloading). Escorts carry a cross-turn SAM magazine and cycle to
reload when low. Follow-on is either an explicit `red_followon_reserve` (curated echelon — no
shipped scenario uses this today) or an opt-in deep pool auto-seeded from the OOB
(`auto_seed_followon_pool`, on for both `scenario_default` and `roc_full_defense`); amphibious lift is classified
by `ShipDef.is_amphibious_lift()` and `pack_bns_into_hulls` aggregates fractional hull capacity.
Facts: `docs/systems/amphibious-offload/amphibious-offload.md` → "Sealift lifecycle".

**Offload capacity gate** (plan 0006) — Red buildup is gated by held/operational offload
infrastructure, not just ship lift: ports/airbridges (`data/infrastructure.json`,
`InfrastructureResolver`) contribute throughput once seized and JLSF-repaired (`deploy_jlsf`
order / `auto_jlsf` policy); day-N offload costs vary by BN type × ship category
(`use_offload_weight_matrix` → `OffloadCostModel`, with cross-turn carry-over for heavy
loads); a per-beach occupancy valve (`BeachDef.depth`) closes a beach until landed brigades
move inland. All default-off; `scenario_default` enables the matrix + auto-JLSF. Empty-orders
self-play hard-plateaus instead of overrunning; seizing a port visibly raises the landing
rate. Facts: `docs/systems/amphibious-offload/amphibious-offload.md` §9.
