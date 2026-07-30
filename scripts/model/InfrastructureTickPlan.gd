class_name InfrastructureTickPlan
extends Resource

## What one infrastructure tick DECIDED: calculated by `InfrastructureResolver.plan_tick`, applied by
## `InfrastructureTransitions.apply_node_plan` (plan 0047). Building one writes no live state.
##
## WHY THE EVENTS ARE AN ORDERED ARRAY AND NOT ONE LABEL PER NODE. A single node can legitimately emit
## BOTH `seized` and `degraded` in one tick: an explicit `deploy_jlsf` order does not require a seized
## node, so a Taiwanese port can already carry an ARRIVED JLSF when Red takes its hex, and the repair
## branch then reads the status the seizure branch decided a few lines earlier. Collapsing events to
## one per node would drop the second half of that chain, which
## tests/transitions/infrastructure_authority_characterization_test.gd pins as production-reachable.
##
## `events` keeps the exact `{"id": …, "event": …}` row shape the pre-0047 mutating `tick` returned
## under its `{"events": […]}` key, so assertions written against that shape still read.

const EVENT_SEIZED := "seized"
const EVENT_DEGRADED := "degraded"
const EVENT_OPERATIONAL := "operational"

## infra_id -> {"node_status": String, "repair_turns_remaining": int}, in the tick's node order.
## ONLY nodes whose state actually changes appear. A node the tick left alone is ABSENT rather than
## staged with its current values, so applying a plan touches exactly what moved.
@export var node_states: Dictionary = {}

## Ordered {"id": String, "event": String} rows, in the order the tick produced them.
@export var events: Array = []


## Record the end state one node should be left in. Called once per changed node by the planner,
## AFTER it has staged that node's whole transition chain in locals.
func stage(id: String, node_status: String, repair_turns_remaining: int) -> void:
	node_states[id] = {
		"node_status": node_status,
		"repair_turns_remaining": repair_turns_remaining,
	}


func record_event(id: String, event: String) -> void:
	events.append({"id": id, "event": event})


func is_empty() -> bool:
	return node_states.is_empty() and events.is_empty()
