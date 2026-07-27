class_name AntishipCrossingContext
extends Resource

## Typed input bundle for AntishipCrossing.resolve_crossing_damage (plan 0052 follow-up).
## Dice stays explicit at the call site so RNG ownership and draw order remain visible; this
## Resource groups the deterministic crossing inputs that otherwise made the public crossing
## signature and launch-stage helper exceed the parameter budget.

# Firing rows and fleet snapshots for the crossing wave.
var systems_fired: Array = []
var ship_snapshots: Array = []

# Anti-ship catalog/config data loaded by the caller.
var combat_catalog: Dictionary = {}
var crossing_config: Dictionary = {}

# Theater/range-gating inputs. Only target_tos is required for own-to launchers.
var target_tos: Array = []
var active_tos: Array = []
var to_adjacency: Dictionary = {}

# Optional cross-turn escort SAM state; empty keeps the count-based no-magazine behavior.
var escort_sam: Dictionary = {}
