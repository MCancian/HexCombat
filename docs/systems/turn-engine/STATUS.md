# Turn Engine — Status

**Turn state machine & WeGo model** — `GameState` (autoload) drives the WeGo turn model:
plan orders (`add_move_order` / `add_commit_order` returning typed `OrderResult`) →
`resolve_turn(dice)` → `begin_next_turn`. Deterministic via an injectable `Dice` (seeded; no global
RNG — enforced by a validator). RNG is **hierarchical** (`Dice.derive(salt)`): the root turn seed
spawns independent substreams per phase and per contested hex (`ijfs:<turn>:<day>`,
`antiship:<turn>`, `combat:<turn>:<hex_id>`), so a roll-count change in one phase or hex never
scrambles another's dice (`ScriptedDice.derive` returns self, so scripted fixtures are unaffected).

**Architecture & State Separation (Plan 0014 / 0038 / 0044)**:
- Runtime state lives in the plain **`GameStateData`** value object (`scripts/model/`).
- **`GameState` (autoload) is a thin state-holder** — owns one `GameStateData` and delegates to `TurnConductor`, `OrderValidator`, and `GameStateBuilder`.
- Turn orchestration is **`TurnConductor`** (pure `RefCounted`, `static` methods): holds the full ordered call list for `resolve_turn`.
- **Phase Coordinators (`scripts/phases/`)**: `ReinforcementPhases` (sealift, offload, mobilization, air insertion), `FiresPhases` (IJFS, anti-ship + mines), `TurnClosure` (supply, cleanup).
- **resolvers**: per-phase decision logic. The `*Resolver` suffix names the phase endpoint and says nothing about purity — the DIRECTORY does that (plan 0055). Pure ones are in `scripts/calc/` (`FrontlineResolver`, `CleanupResolver`, `OffloadResolver`, `InfrastructureResolver`, `CombatResolver`, plus `SealiftResolver` since 0045 and `AntishipResolver` since 0050); `IjfsResolver` applies at its own draw point and is in `scripts/interleaved/`. The old `scripts/resolvers/` (historical) is gone — it had drifted into holding both categories at once. Supply has no resolver at all: it is `SupplyBill` in `calc/` applied by `SupplyTransitions`.
- **Mutation Authorities (`scripts/transitions/`)**: ten of them, one per registered aggregate. `docs/STATUS.md` indexes which owns what; `tools/mutation_authority_manifest.json` is the record.

**Turn resolution order** (12-step high-level summary of `TurnConductor.gd`'s actual 16 granular execution steps):
1. IJFS air/missile fires (`FiresPhases.resolve_ijfs_turn`)
2. IJFS maneuver casualties (`FiresPhases.apply_ijfs_maneuver_casualties`)
3. Sealift tick & embarkation (`ReinforcementPhases.resolve_sealift_turn`)
4. Anti-ship crossing & mines (`FiresPhases.resolve_antiship_turn`)
5. Amphibious offload (`ReinforcementPhases.resolve_offload_turn`)
6. ROC mobilization (`ReinforcementPhases.resolve_mobilization_turn`)
7. PLAAF air insertion (`ReinforcementPhases.resolve_air_insertion_turn`)
8. Movement & commit (`TurnConductor.apply_move_orders`)
9. Ground combat & FEBA retreats (`TurnConductor.resolve_combat_at` / `TurnConductor.apply_feba_retreats`)
10. Hex ownership updates (`GameData.recompute_hex_ownership`)
11. Supply consumption & effectiveness (`TurnClosure.resolve_supply_turn`)
12. Cleanup & victory census (`TurnClosure.resolve_cleanup_phase`)
