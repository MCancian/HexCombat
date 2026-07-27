class_name ForceLocation
extends Resource

## Closed vocabulary for where a brigade's battalions are during force transitions (plan 0044).
## Storage still uses the legacy arrays/dictionaries; transition requests use this enum so call sites
## cannot invent new hand-typed locations or accidentally treat JLSF cargo as force.

enum Kind {
	MAINLAND,
	AT_SEA,
	OFFLOADING,
	AWAITING_AIR_INSERTION,
	ASHORE,
	MOBILIZING,
	DEAD,
}


static func label(kind: Kind) -> String:
	match kind:
		Kind.MAINLAND:
			return "mainland"
		Kind.AT_SEA:
			return "at_sea"
		Kind.OFFLOADING:
			return "offloading"
		Kind.AWAITING_AIR_INSERTION:
			return "awaiting_air_insertion"
		Kind.ASHORE:
			return "ashore"
		Kind.MOBILIZING:
			return "mobilizing"
		Kind.DEAD:
			return "dead"
	return "unknown"
