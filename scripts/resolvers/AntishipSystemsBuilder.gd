class_name AntishipSystemsBuilder
extends RefCounted

## Pure builder for the persistent Green anti-ship arsenal (refactor_audit item 10, Phase A).
## Produces both views of the same arsenal from the grouping spec: per-(to_number, type_id)
## firing rows ("systems") and container-level platform-group bins ("containers", the IJFS
## target source). No autoload/engine access; GameState's thin wrapper owns the lazy-build
## guard and assigns the two arrays.

## Data sources (single source of truth for these two paths; the other antiship data paths
## are consumed by resolve_antiship_turn and stay on GameState).
const TYPES_PATH := "res://data/antiship/antiship_systems_consolidated.json"
const GROUPING_PATH := "res://data/antiship/antiship_grouping_spec.json"


## Returns {"systems": Array[AntishipSystem-like rows], "containers": Array}.
static func build() -> Dictionary:
	var types := AntishipLoaders.load_system_types(TYPES_PATH)
	return {
		"systems": AntishipLoaders.load_systems(GROUPING_PATH, types),
		"containers": AntishipLoaders.load_containers(GROUPING_PATH, types),
	}
