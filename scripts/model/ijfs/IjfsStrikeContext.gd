class_name IjfsStrikeContext
extends Resource

## Everything about ONE strike that is not the target, the pairing, the inventory or the dice: which
## day and pass it belongs to, which doctrine rule chose it, and how much of the delivering package
## actually arrived.
##
## Introduced 2026-08-01 (plan 0060). Before it, `IjfsStrike.resolve_strike` took nine positional
## arguments and the plan's package geometry wanted a tenth — the fraction of a four-airframe package
## that survived ingress. The plan review's ruling was explicit: absorb the loose fields into a typed
## context rather than append. Four call-site arguments collapse into one object, and the parameter
## ceiling for resolve_strike ratchets DOWN from 9 to 6 rather than up.
##
## Deliberately per-STRIKE, not per-day: `survivor_fraction` differs between two strikes on the same
## pass, so a day-scoped bundle could not carry it.

# Day identity and which of the two passes this strike belongs to. `phase` is null only on a final
# skip row, which belongs to the day rather than to either pass.
@export var current_day: int = 0
@export var phase: Variant = null

# Which targeting-doctrine rule selected this pairing, and whether it came from that rule's priority
# list or its fallback. Both null when no doctrine rule matched.
@export var doctrine_rule_name: Variant = null
@export var doctrine_selection: Variant = null

## The share of the delivering package that reached the target: `survivors / package_size` (plan 0060
## R8). It multiplies the final destroy and suppress probabilities, so a package that lost half its
## airframes on ingress delivers half the effect. 1.0 — the default — is a full package, and is also
## what every non-Organic munition uses: a missile salvo has no airframes to lose.
@export var survivor_fraction: float = 1.0


static func for_strike(
	current_day: int, phase: Variant, doctrine_rule_name: Variant, doctrine_selection: Variant
) -> IjfsStrikeContext:
	var context := IjfsStrikeContext.new()
	context.current_day = current_day
	context.phase = phase
	context.doctrine_rule_name = doctrine_rule_name
	context.doctrine_selection = doctrine_selection
	return context
