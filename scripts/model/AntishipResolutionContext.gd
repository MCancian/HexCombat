class_name AntishipResolutionContext
extends Resource

## Typed input bundle for AntishipResolver.resolve (plan 0052). Turn number and Dice stay explicit
## at the call site; this Resource groups the crossing wave, Green establishment, world lookups, and
## carried state that otherwise made the resolver signature exceed the parameter budget.

# Crossing wave: only BNs/hulls sailing this turn, not the whole reserve.
var crossing_reserve: Array = []
var sent_by_type: Dictionary = {}

# Green anti-ship establishment as projected by AntishipTransitions before the resolver reads it.
var antiship_systems: Array = []

# World lookups supplied by GameData through the phase coordinator; the resolver never touches the
# autoload directly.
var ship_defs: Dictionary = {}
var beach_to_to: Dictionary = {}
var active_tos: Array = []
var to_adjacency: Dictionary = {}

# Carried cross-turn state owned by GameStateData / SealiftState.
var lost_at_sea_accumulator: float = 0.0
var escort_sam: Dictionary = {}
