# Supply / DOS — Status

**D2 Red DOS supply** — supply pool / effectiveness tracking. An exhausted Red pool now degrades Red
ground-combat strength (`red_out_of_supply_effectiveness`, default 0.5) via
`CombatResolver.inject_supply_effectiveness`, threaded by `TurnConductor`.
