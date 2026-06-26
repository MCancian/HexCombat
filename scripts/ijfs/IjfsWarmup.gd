class_name IjfsWarmup
extends RefCounted

## Port of ijfs_standalone/warmup_profiles.py. Prelanding warmup attrition-profile helpers.
## Profiles scale daily firing capacity only; per-strike kill probabilities stay owned by the
## munition-target pairings and strike resolution.

const ATTRITION_PROFILES := {"even": true, "front_loaded": true, "back_loaded": true}


static func profile_multiplier(profile: String, x_day: int, total_days: int) -> float:
	if total_days <= 1 or profile == "even":
		return 1.0
	var weight: int
	if profile == "front_loaded":
		weight = total_days - x_day + 1
	elif profile == "back_loaded":
		weight = x_day
	else:
		weight = 1
	return (2.0 * float(weight)) / float(total_days + 1)


static func scale_firing_capacity(config: Dictionary, multiplier: float) -> Dictionary:
	if config.is_empty() or multiplier == 1.0:
		return config
	var scaled: Dictionary = {}
	for munition_id in config.keys():
		var entry: Dictionary = config[munition_id]
		var row: Dictionary = entry.duplicate(true)
		row["sorties_per_unit_per_day"] = float(row.get("sorties_per_unit_per_day", 0)) * multiplier
		scaled[munition_id] = row
	return scaled
