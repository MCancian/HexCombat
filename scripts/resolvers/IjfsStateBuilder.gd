class_name IjfsStateBuilder
extends RefCounted

## Pure builder for GameState.ijfs_state (refactor_audit item 10, Phase A): assembles the
## persistent IJFS daily state — static targets + per-(TO,type) anti-ship targets + per-battalion
## Green maneuver targets, munitions, pairings, scenario, air classes, squadron force, SAM
## enrichment. No autoload access — the caller passes the anti-ship containers (build order:
## anti-ship systems FIRST) and the live Green brigade list in; the GameState wrapper keeps the
## _ensure_antiship_systems() ordering and the _ijfs_day = 0 reset.

## Data sources (single source of truth — used only by this builder).
const TARGETS_PATH := "res://data/ijfs/targets_master.json"
const MUNITIONS_PATH := "res://data/ijfs/red_munitions.json"
const PAIRINGS_PATH := "res://data/ijfs/munition_target_pairings.json"
const SCENARIO_PATH := "res://data/ijfs/ijfs_scenario.json"
const AIR_CLASSES_PATH := "res://data/ijfs/air_classes.json"
const OOB_PATH := "res://data/ijfs/red_air_oob.json"
const SAM_CAPS_PATH := "res://data/ijfs/sam_capabilities.json"


## antiship_containers: container-level Green arsenal bins (AntishipSystemsBuilder).
## green_brigades: live (non-destroyed) Green Brigade list for maneuver-target generation.
static func build(antiship_containers: Array, green_brigades: Array) -> IjfsDailyState:
	var state := IjfsDailyState.new()
	# D3-D (1-A): anti-ship targets are generated per-(TO,type) from the containers (carrying that
	# pair in metadata) and replace the static "Anti-Ship Systems" rows, so IJFS strikes write back
	# by (TO, type) for the D3 firing-plan join.
	state.targets = IjfsLoaders.load_targets_with_antiship(TARGETS_PATH, antiship_containers, 1)
	# D4-H (2c): Green/ROC maneuver units as IJFS targets, one per battalion instance, carrying
	# {brigade_id}-MU-{n} in metadata so the writeback can attribute casualties back to the OOB.
	state.targets.append_array(IjfsLoaders.build_maneuver_targets(green_brigades, 1))
	state.munitions = IjfsLoaders.load_munitions(MUNITIONS_PATH)
	state.pairings = IjfsLoaders.load_pairings(PAIRINGS_PATH)
	state.scenario = IjfsLoaders.load_scenario(SCENARIO_PATH)
	# Plan 0009: the CRBM-heavy-volley knob lives in the scenario but retargets the pairings, so it is
	# applied here once both are loaded (keeps load_pairings/load_scenario single-responsibility).
	IjfsLoaders.apply_crbm_maneuver_rounds_override(state.pairings, state.scenario)
	state.air_classes = IjfsLoaders.load_air_classes(AIR_CLASSES_PATH)
	state.squadron_force = IjfsLoaders.expand_oob_to_squadrons(IjfsLoaders.load_oob(OOB_PATH))
	IjfsLoaders.enrich_sam_scores(state.targets, IjfsLoaders.load_sam_capabilities(SAM_CAPS_PATH))
	return state
