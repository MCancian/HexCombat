class_name InfrastructureStateBuilder
extends RefCounted

## Pure builder for InfrastructureState. No autoload access — caller passes the
## infra_defs from GameData. Creates one node entry per def in sorted key order.

const InfrastructureStateResource = preload("res://scripts/model/InfrastructureState.gd")


## infra_defs: dict of id (String) -> InfrastructureDef instances.
static func build(infra_defs: Dictionary) -> InfrastructureState:
	var state: InfrastructureState = InfrastructureStateResource.new()
	var ids: Array = infra_defs.keys()
	ids.sort()
	for id in ids:
		state.nodes[id] = {
			"status": InfrastructureState.STATUS_TAIWANESE,
			"repair_turns_remaining": 0,
			"jlsf": InfrastructureState.JLSF_NONE,
		}
	return state
