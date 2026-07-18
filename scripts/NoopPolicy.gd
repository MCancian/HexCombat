extends RefCounted
class_name NoopPolicy

## The empty-orders policy (plan 0012): issues no actions, so a self-play game is pure engine
## dynamics — every phase still resolves (offload landings can still produce beach combat), but
## no seat ever moves or commits. This is the batch-backend equivalent of the retired
## run_sweep_cells.gd end_turn-only loop; the CRBM maneuver sweep runs its games under it so the
## dialed attrition readings keep their measurement semantics.

func build_actions(_observation: Dictionary) -> Array:
	return []
