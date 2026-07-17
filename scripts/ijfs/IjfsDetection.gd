class_name IjfsDetection
extends RefCounted

const LOG_2 := 0.6931471805599453
const ISR_LOCAL_CLAMP_LOW := 0.0
const ISR_LOCAL_CLAMP_HIGH := 1.5
const MATH_CLAMP_LOW := 0.0
const MATH_CLAMP_HIGH := 1.0


static func evaluate_isr_source(source: Dictionary, day: int, isr_status: Variant = null) -> float:
	var override: Variant = source.get("runtime_capability_override", null)
	if override != null:
		return float(override)
	var initial := float(source.get("initial_capability", 1.0))
	var floor_value := float(source.get("floor", 0.0))
	var degradation: Dictionary = source.get("degradation", {})
	var mode := String(degradation.get("mode", "exp_decay"))
	var d: int = maxi(0, day - 1)
	var cap := initial

	if mode == "exp_decay":
		var hl := float(degradation.get("half_life_days", 1))
		cap = floor_value + (initial - floor_value) * exp(-float(d) * LOG_2 / hl) if hl > 0.0 else floor_value
	elif mode == "linear":
		var dur := float(degradation.get("duration_days", 1))
		cap = maxf(floor_value, initial - (initial - floor_value) * float(d) / dur) if dur > 0.0 else floor_value
	elif mode == "weibull":
		var lam := float(degradation.get("lambda", 1.0))
		var k := float(degradation.get("k", 1.0))
		cap = floor_value + (initial - floor_value) * exp(-pow(float(d) / lam, k)) if lam > 0.0 else floor_value
	elif mode == "logistic":
		var k_param := float(degradation.get("k", 1.0))
		var d_mid := float(degradation.get("d_mid", 0.0))
		cap = floor_value + (initial - floor_value) / (1.0 + exp(k_param * (float(d) - d_mid)))
	elif mode == "gompertz":
		var b := float(degradation.get("b", 1.0))
		var c := float(degradation.get("c", 1.0))
		cap = floor_value + (initial - floor_value) * (1.0 - exp(-b * exp(-c * float(d))))
	elif mode == "from_attrition":
		if isr_status == null:
			cap = initial
		else:
			var src_field := String(degradation.get("source", ""))
			var alive := 0.0
			var initial_count := 0.0
			if src_field.contains("uav"):
				alive = float(_status_value(isr_status, "uav_alive"))
				initial_count = float(_status_value(isr_status, "uav_initial"))
			else:
				alive = float(_status_value(isr_status, "manned_alive"))
				initial_count = float(_status_value(isr_status, "manned_initial"))
			cap = alive / initial_count if initial_count > 0.0 else 0.0
	elif mode == "piecewise":
		var values: Array = degradation.get("values", [])
		var idx := mini(d, values.size() - 1)
		cap = float(values[idx]) if not values.is_empty() else floor_value
	else:
		cap = initial

	return _isr_clamp(cap, 0.0, maxf(initial, 1.0))


static func isr_score_for_target(target_category: String, day: int, isr_sources: Array, isr_status: Variant = null) -> float:
	var total := 0.0
	for source_value in isr_sources:
		var source: Dictionary = source_value
		var categories: Array = source.get("target_categories", ["*"])
		if not categories.has("*") and not categories.has(target_category):
			continue
		var weight := float(source.get("detection_weight", 1.0))
		var cap := evaluate_isr_source(source, day, isr_status)
		total += weight * cap
	return total


static func aircraft_isr_raw_score(force: Variant, air_classes: Dictionary) -> float:
	if force == null or air_classes.is_empty():
		return 0.0
	var classes: Dictionary = air_classes.get("classes", {})
	var reference := float(air_classes.get("reference_isr_sum", 1.0))
	if reference == 0.0:
		reference = 1.0
	var total := 0.0
	for squadron_value in _force_squadrons(force):
		var squadron: IjfsSquadron = squadron_value
		if squadron.role != "isr" or squadron.alive <= 0:
			continue
		var class_entry: Dictionary = classes.get(squadron.aircraft_class, {})
		total += float(squadron.alive) * float(class_entry.get("isr_value", 0.0))
	return _math_clamp(total / reference if reference > 0.0 else 0.0)


static func _non_air_isr_score(target_category: String, day: int, isr_sources: Array) -> float:
	var total := 0.0
	for source_value in isr_sources:
		var source: Dictionary = source_value
		var degradation: Dictionary = source.get("degradation", {})
		if String(degradation.get("mode", "")) == "from_attrition":
			continue
		var categories: Array = source.get("target_categories", ["*"])
		if not categories.has("*") and not categories.has(target_category):
			continue
		total += float(source.get("detection_weight", 1.0)) * evaluate_isr_source(source, day, null)
	return total


static func _base_components(target: IjfsTarget, scenario: Dictionary) -> Dictionary:
	var model: Dictionary = scenario["detection_model"]
	var posture := _posture_for_detection(target)
	var label := target.detectability_active if posture == "active" else target.detectability_hiding
	var satellite_floor_probability: Dictionary = model["satellite_floor_probability"]
	var detectability_label_base_probability: Dictionary = model["detectability_label_base_probability"]
	var mobility_multiplier: Dictionary = model["mobility_multiplier"]
	var posture_multiplier: Dictionary = model["posture_multiplier"]
	var satellite_by_mobility: Dictionary = satellite_floor_probability.get(target.mobility, {})
	var posture_by_mobility: Dictionary = posture_multiplier.get(target.mobility, {})
	var components := {
		"detectability_label": label,
		"satellite_floor": float(satellite_by_mobility.get(posture, 0.0)),
		"base_probability": float(detectability_label_base_probability.get(label, 0.0)),
		"mobility_multiplier": float(mobility_multiplier.get(target.mobility, 1.0)),
		"posture_multiplier": float(posture_by_mobility.get(posture, 1.0)),
		"posture_used": posture,
	}
	_apply_antiship_exposure_modifier(target.metadata, model, components)
	return components


static func satellite_detect_target_ids(targets: Array[IjfsTarget], scenario: Dictionary, dice: Dice) -> Dictionary:
	return _run_detection_phase(targets, scenario, dice, "phase1", false)


static func aircraft_detect_target_ids(targets: Array[IjfsTarget], scenario: Dictionary, force: Variant, air_classes: Dictionary, contest_adjustment: float, dice: Dice, isr_day: int) -> Dictionary:
	var aircraft_score := aircraft_isr_raw_score(force, air_classes)
	return _run_detection_phase(targets, scenario, dice, "phase2", true, aircraft_score, contest_adjustment, isr_day)


static func _run_detection_phase(targets: Array[IjfsTarget], scenario: Dictionary, dice: Dice, phase: String, is_aircraft: bool, aircraft_score: float = 0.0, contest_adjustment: float = 0.0, isr_day: int = 1) -> Dictionary:
	var detected_ids: Array[String] = []
	var log: Array = []
	for target in _sorted_targets(targets):
		if target.destroyed:
			continue
		if target.mobility == "static" or target.intel_locked:
			detected_ids.append(target.target_id)
			var method := "intel_locked" if target.intel_locked and target.mobility != "static" else "static_known"
			log.append(_log_detection(target, phase, method, 1.0, null, true))
			continue
		var components := _base_components(target, scenario)
		var p_detect := 0.0
		var roll_method := ""
		if is_aircraft:
			var non_air_score := _non_air_isr_score(target.category, isr_day, scenario["isr_sources"])
			var weighted_isr := maxf(0.0, (non_air_score + aircraft_score) * contest_adjustment)
			p_detect = _math_clamp(
				float(components["satellite_floor"])
				+ float(components["base_probability"]) * float(components["mobility_multiplier"]) * float(components["posture_multiplier"]) * weighted_isr
			)
			components["non_air_isr_score"] = non_air_score
			components["aircraft_isr_raw"] = aircraft_score
			components["contest_adjustment"] = contest_adjustment
			components["weighted_isr_capacity"] = weighted_isr
			components["weighted_isr_health"] = weighted_isr
			roll_method = "aircraft_isr_roll"
		else:
			p_detect = _math_clamp(float(components["satellite_floor"]))
			components["weighted_isr_capacity"] = 0.0
			components["weighted_isr_health"] = 0.0
			roll_method = "satellite_floor_roll"
			
		var roll := dice.randf()
		var detected := roll <= p_detect
		if detected:
			detected_ids.append(target.target_id)
		log.append(_log_detection(target, phase, roll_method, p_detect, roll, detected, components))
	return {"detected_ids": detected_ids, "log": log}


static func apply_detection_ids(targets: Array[IjfsTarget], detected_ids: Array, current_day: int) -> void:
	for target in targets:
		target.detected_this_turn = false
		if target.destroyed:
			target.known_to_red = false
			continue
		var detected := detected_ids.has(target.target_id)
		target.detected_this_turn = detected
		target.known_to_red = detected
		if detected:
			target.last_detected_day = current_day


static func _posture_for_detection(target: IjfsTarget) -> String:
	if target.posture == "active":
		return "active"
	return "hiding"


static func _log_detection(target: IjfsTarget, phase: String, method: String, p_detect: float, roll: Variant, detected: bool, components: Variant = null) -> Dictionary:
	var entry := {
		"phase": phase,
		"target_id": target.target_id,
		"source_target_id": target.source_target_id,
		"category": target.category,
		"subcategory": target.subcategory,
		"mobility": target.mobility,
		"posture": target.posture,
		"metadata": target.metadata,
		"detection_method": method,
		"p_detect": p_detect,
		"roll": roll,
		"detected": detected,
	}
	if components != null:
		entry["components"] = components
	return entry


static func _apply_antiship_exposure_modifier(target_metadata: Dictionary, detection_model: Dictionary, components: Dictionary) -> void:
	if target_metadata.get("active", false):
		var multiplier := float(detection_model.get("antiship_active_attempt_multiplier", 1.0))
		components["active_attempt_multiplier"] = multiplier
		components["base_probability"] = _math_clamp(float(components["base_probability"]) * multiplier)


static func _sorted_targets(targets: Array[IjfsTarget]) -> Array[IjfsTarget]:
	var sorted: Array[IjfsTarget] = targets.duplicate()
	sorted.sort_custom(func(a: IjfsTarget, b: IjfsTarget) -> bool: return a.target_id < b.target_id)
	return sorted


static func _force_squadrons(force: Variant) -> Array:
	if force is Array:
		return force
	if force is Dictionary:
		return force.get("squadrons", [])
	var from_object: Variant = force.get("squadrons")
	if from_object is Array:
		return from_object
	_fail("Unsupported IJFS squadron force shape")
	return []


static func _status_value(isr_status: Variant, key: String) -> Variant:
	if isr_status is Dictionary:
		return isr_status[key]
	return isr_status.get(key)


static func _math_clamp(value: float, low: float = MATH_CLAMP_LOW, high: float = MATH_CLAMP_HIGH) -> float:
	return maxf(low, minf(high, value))


static func _isr_clamp(value: float, lo: float = ISR_LOCAL_CLAMP_LOW, hi: float = ISR_LOCAL_CLAMP_HIGH) -> float:
	return maxf(lo, minf(hi, value))


static func _fail(message: String) -> void:
	push_error(message)
	assert(false, message)
