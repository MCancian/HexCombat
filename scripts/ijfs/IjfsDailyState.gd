class_name IjfsDailyState
extends RefCounted

## In-memory port of ijfs_standalone/state.py IJFSDailyState — the mutable container threaded
## through one IJFS daily cycle. Unlike the Python original it carries no `rng` (the caller passes
## a shared `Dice` into IjfsEngine.run_daily so draw order is preserved) and no file paths. Logs
## and AD-health snapshots are (re)populated per `run_daily`; targets/munitions/squadron_force
## persist across days for continuity (see IjfsEngine.carry_to_next_day).

# --- Inputs (persist across days) ---
var targets: Array[IjfsTarget] = []
var munitions: Dictionary = {}            # munition_id -> IjfsMunition
var pairings: Array[IjfsPairing] = []
var scenario: Dictionary = {}
var squadron_force: Variant = null        # Array[IjfsSquadron] or null
var air_classes: Variant = null           # Dictionary or null
var seed: Variant = null                  # metadata only
var source_files: Array = []

# --- Per-run outputs (reset at the top of each run_daily) ---
var detection_log: Array = []
var strike_log: Array = []
var engagement_log: Array = []
var contest_log: Array = []
var free_shot_log: Array = []
var taiwan_ad_health_before: Dictionary = {}
var taiwan_ad_health_after_missile_phase: Dictionary = {}
var taiwan_ad_health_after_sead: Dictionary = {}
var taiwan_ad_health_after: Dictionary = {}
var exquisite_intel_overrides: Array = []
var warnings: Array = []
