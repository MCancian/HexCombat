class_name ForceCasualtyCause
extends Resource

## Typed causes for roster-shrinking operations. Narrative/event text can map these to prose later;
## the authority only uses them to make the source of a casualty explicit and auditable.

enum Kind {
	GROUND_COMBAT,
	IJFS_MANEUVER,
	CROSSING,
	AIR_INSERTION,
}


static func label(kind: Kind) -> String:
	match kind:
		Kind.GROUND_COMBAT:
			return "ground_combat"
		Kind.IJFS_MANEUVER:
			return "ijfs_maneuver"
		Kind.CROSSING:
			return "crossing"
		Kind.AIR_INSERTION:
			return "air_insertion"
	return "unknown"
