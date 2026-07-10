extends RefCounted
class_name GoldenScript

## Single source of truth for the SHAPE of the scripted golden turn (seed, mover, defender,
## hexes). Every golden validator (validate_headless_turn / validate_cleanup / validate_llm_api /
## validate_play_turn) and the scenario-keyed GdUnit suites read these constants, so a scenario
## laydown change is a one-file re-point instead of the 7-file pin hunt the 2026-07-09
## full-defense re-baseline cost. Expected OUTCOMES (casualty/FEBA fingerprints, contested sets)
## stay pinned locally in each validator — they differ per script variant and must be updated
## deliberately on a re-baseline, never here.
##
## Current shape (full ROC defense laydown, 2026-07-09): beach 1 (hex_44_16) is garrisoned by
## BDE-GDU, so the beach-1 lander is in contact at its landing hex; the scripted mover is the
## beach-2 lander (hex_44_15, ungarrisoned) moving one hex east to join that fight.

const SEED := 20260624
const RED_MOVER_ID := "PLA-72-5-Amphibious"
const GREEN_DEFENDER_ID := "BDE-GDU"
const START_HEX := "hex_44_15"
const TARGET_HEX := "hex_44_16"
