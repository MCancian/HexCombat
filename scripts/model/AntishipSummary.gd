extends Resource
class_name AntishipSummary

## Result of GameState.resolve_antiship_turn — the most recent crossing's anti-ship/mine toll: what
## sailed, what fired, hull losses, and the BNs lost at sea. Carried in GameState.last_antiship_summary
## / TurnResult / the event log / the EventBus.antiship_resolved signal, and surfaced in the LLM
## observation. Replaces the former plain dict (refactor_audit item 9 — typed drift-safety). to_dict()
## is the JSON-serialization boundary; its key order and value types mirror the former dict exactly so
## the golden/observation fixtures stay byte-stable. A null last_antiship_summary means no crossing
## wave resolved this turn (the empty case).

@export var resolved_turn: int = 0
@export var sent_by_type: Dictionary = {}
@export var unliftable_bn: int = 0
@export var systems_fired_count: int = 0
@export var destroyed_by_ship_type: Dictionary = {}
@export var crossing_casualties: Dictionary = {}
@export var bns_lost_at_sea: int = 0
@export var target_beaches: Array = []
@export var target_tos: Array = []
@export var mine_status: Array = []
# Size of the sent cohort (BNs sailing this turn, JLSF pseudo-BNs included) — the denominator of
# the crossing-loss rate. Recorded so sweep extractors read it from the game record instead of
# engine internals (plan 0012).
@export var wave_bns: int = 0


func to_dict() -> Dictionary:
	return {
		"resolved_turn": resolved_turn,
		"sent_by_type": sent_by_type.duplicate(true),
		"unliftable_bn": unliftable_bn,
		"systems_fired_count": systems_fired_count,
		"destroyed_by_ship_type": destroyed_by_ship_type.duplicate(true),
		"crossing_casualties": crossing_casualties.duplicate(true),
		"bns_lost_at_sea": bns_lost_at_sea,
		"target_beaches": target_beaches.duplicate(),
		"target_tos": target_tos.duplicate(),
		"mine_status": mine_status.duplicate(true),
		"wave_bns": wave_bns,
	}
