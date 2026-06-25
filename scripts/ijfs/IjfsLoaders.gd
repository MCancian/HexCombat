class_name IjfsLoaders
extends RefCounted

const IjfsTargetResource = preload("res://scripts/model/ijfs/IjfsTarget.gd")
const IjfsMunitionResource = preload("res://scripts/model/ijfs/IjfsMunition.gd")
const IjfsPairingResource = preload("res://scripts/model/ijfs/IjfsPairing.gd")
const IjfsSquadronResource = preload("res://scripts/model/ijfs/IjfsSquadron.gd")

const EXPANSION_GUARD := 10000
const TARGET_CORE_KEYS := {
	"target_id": true, "source_target_id": true, "instance_index": true, "name": true,
	"category": true, "subcategory": true, "quantity": true, "mobility": true,
	"hardness": true, "detectability_active": true, "detectability_hiding": true,
	"posture": true, "posture_default": true, "destroyed": true, "status": true,
	"status_default": true, "detected_this_turn": true, "last_detected_day": true,
	"known_to_red": true, "suppressed": true, "suppressed_this_turn": true,
	"target_modeling_level": true, "confidence": true, "sources": true, "notes": true,
	"metadata": true,
}
const REQUIRED_SCENARIO_TOP := ["detection_model", "taiwan_air_defense_health", "red_aircraft_attrition_and_sead"]
const REQUIRED_SCENARIO_BLOCKS := ["prelanding", "red_firing_capacity", "isr_sources", "target_release"]
const VALID_AIR_CLASSES := ["5th Gen", "4.5th Gen", "4th Gen", "J-16D", "JH-7", "H-6", "Stealth", "MALE Armed", "HALE Armed", "Decoys", "HARM"]
const VALID_KINDS := ["manned", "unmanned"]
const VALID_ROLES := ["isr", "sead", "strike", "unused"]
const CLASS_NUMERIC_FIELDS := ["rcs", "wvr", "isr_value", "sead_eff"]
const ISR_CURVE_MODES := ["exp_decay", "linear", "weibull", "logistic", "gompertz", "from_attrition", "piecewise"]
const STRIKE_MODIFIER_OPERATIONS := ["add", "multiply"]
const STRIKE_MODIFIER_MATCH_KEYS := ["category", "subcategory", "mobility", "hardness", "posture", "intel_locked", "munition_id", "munition_category", "phase", "pairing_id", "source_target_id"]
const SAM_CATEGORIES := ["Moveable SAMs", "Static SAMs", "Mobile SAMs"]


static func load_targets(path: String, current_day: int = -1) -> Array[IjfsTarget]:
	var body: Variant = _unwrap_data(_read_json(path))
	if body is Dictionary and body.has("targets") and body["targets"].size() > 0 and body["targets"][0].has("source_target_id"):
		return _load_runtime_targets(body["targets"])
	if body is Array and body.size() > 0 and body[0].has("source_target_id"):
		return _load_runtime_targets(body)

	var rows: Array = []
	if body is Dictionary:
		rows = body.get("targets", [])
	else:
		_fail("Unrecognized targets format: %s" % path)
	var total := 0
	for row in rows:
		total += int(row.get("quantity", 1))
	if total > EXPANSION_GUARD:
		_fail("Target expansion would create %d instances; guard is %d" % [total, EXPANSION_GUARD])

	var targets: Array[IjfsTarget] = []
	for row_value in rows:
		var row: Dictionary = row_value
		var qty := int(row.get("quantity", 1))
		var source_id := String(row["target_id"])
		for idx in range(1, qty + 1):
			var target_id := source_id if qty == 1 else "%s#%03d" % [source_id, idx]
			targets.append(_runtime_target_from_master(row, target_id, source_id, idx, current_day))
	targets.sort_custom(func(a: IjfsTarget, b: IjfsTarget) -> bool: return a.target_id < b.target_id)
	return targets


static func load_munitions(path: String) -> Dictionary:
	var body: Variant = _unwrap_data(_read_json(path))
	var result: Dictionary = {}
	if body is Dictionary and body.has("munitions"):
		for row_value in body["munitions"]:
			var row: Dictionary = row_value
			var munition: IjfsMunition = IjfsMunitionResource.new()
			munition.munition_id = String(row["munition_id"])
			munition.name = String(row.get("name", ""))
			munition.category = String(row.get("category", ""))
			munition.inventory_remaining = int(row.get("inventory_remaining_default", row.get("inventory_default", 0)))
			munition.rounds_per_engagement_default = int(row.get("rounds_per_engagement_default", 0))
			munition.display_label = String(row.get("display_label", ""))
			result[munition.munition_id] = munition
		return result
	if body is Dictionary and body.has("inventory"):
		var inventory = body["inventory"]
		if inventory is Dictionary:
			for mid in inventory.keys():
				var value = inventory[mid]
				var m: IjfsMunition = IjfsMunitionResource.new()
				m.munition_id = String(mid)
				if value is Dictionary:
					m.name = String(value.get("name", ""))
					m.category = String(value.get("category", ""))
					m.inventory_remaining = int(value.get("inventory_remaining", value.get("remaining", 0)))
					m.rounds_per_engagement_default = int(value.get("rounds_per_engagement_default", 0))
					m.display_label = String(value.get("display_label", ""))
				else:
					m.inventory_remaining = int(value)
				result[m.munition_id] = m
			return result
		for row in inventory:
			var m2: IjfsMunition = _munition_from_dict(row)
			result[m2.munition_id] = m2
		return result
	_fail("Unrecognized munitions format: %s" % path)
	return result


static func load_pairings(path: String, known_munition_ids: Array = []) -> Array[IjfsPairing]:
	var body: Variant = _unwrap_data(_read_json(path))
	if not (body is Dictionary):
		_fail("Unrecognized pairings format: %s" % path)
	var profiles: Dictionary = {}
	for profile_value in body.get("target_effect_profiles", []):
		var profile: Dictionary = profile_value
		profiles[profile.get("target_effect_profile_id", "")] = profile
	var raw_pairings: Array = []
	for row in body.get("pairings", []):
		raw_pairings.append(row)
	for profile_value in body.get("target_effect_profiles", []):
		var profile: Dictionary = profile_value
		for nested_value in profile.get("pairings", []):
			var item: Dictionary = (nested_value as Dictionary).duplicate(true)
			if not item.has("target_effect_profile_id"):
				item["target_effect_profile_id"] = profile.get("target_effect_profile_id", "")
			raw_pairings.append(item)

	var rules: Array[IjfsPairing] = []
	for order in range(raw_pairings.size()):
		var row: Dictionary = raw_pairings[order]
		if not known_munition_ids.is_empty() and String(row["munition_id"]) not in known_munition_ids:
			continue
		var profile: Dictionary = profiles.get(row.get("target_effect_profile_id", ""), {})
		var rule: IjfsPairing = IjfsPairingResource.new()
		rule.order = order
		rule.pairing_id = String(row.get("pairing_id", "pairing_%d" % order))
		rule.munition_id = String(row["munition_id"])
		rule.target_effect_profile_id = String(row.get("target_effect_profile_id", ""))
		rule.target_category = String(row.get("target_category", profile.get("category", "")))
		rule.target_subcategory = String(row.get("target_subcategory", profile.get("subcategory", "")))
		rule.target_mobility = String(row.get("target_mobility", profile.get("mobility", "")))
		rule.target_hardness = String(row.get("target_hardness", profile.get("hardness", "")))
		rule.rounds_expended_per_engagement = int(row["rounds_expended_per_engagement"])
		rule.probability_destroyed = float(row.get("probability_destroyed", 0.0))
		rule.probability_suppressed_if_not_destroyed = float(row.get("probability_suppressed_if_not_destroyed", 0.0))
		for sid in profile.get("source_target_ids", []):
			rule.source_target_ids.append(String(sid))
		_validate_pairing(rule)
		rules.append(rule)
	return rules


static func load_scenario(path: String) -> Dictionary:
	var scenario: Dictionary = _read_json(path)
	for key in REQUIRED_SCENARIO_TOP:
		if not scenario.has(key):
			_fail("Scenario missing required section: %s" % key)
	_validate_ijfs_config_blocks(scenario)
	return scenario


static func load_air_classes(path: String) -> Dictionary:
	var data: Dictionary = _read_json(path)
	_validate_air_classes(data)
	return data


static func load_oob(path: String) -> Dictionary:
	var data: Dictionary = _read_json(path)
	_validate_oob(data)
	return data


static func expand_oob_to_squadrons(oob) -> Array[IjfsSquadron]:
	var rows: Array = oob.get("red_air_oob", []) if oob is Dictionary else oob
	var squadrons: Array[IjfsSquadron] = []
	for row_value in rows:
		var row: Dictionary = row_value
		var cls := String(row["class"])
		var role := String(row["role"])
		var count := int(row.get("squadrons", 1))
		var aircraft_per_sqn := int(row.get("aircraft_per_sqn", 0))
		var slug := _class_slug(cls)
		for i in range(1, count + 1):
			var sqn: IjfsSquadron = IjfsSquadronResource.new()
			sqn.squadron_id = "%s__%s__%03d" % [slug, role, i]
			sqn.aircraft_class = cls
			sqn.role = role
			sqn.initial = aircraft_per_sqn
			sqn.alive = aircraft_per_sqn
			sqn.rtb_today = 0
			sqn.losses_today = 0
			squadrons.append(sqn)
	return squadrons


static func load_sam_capabilities(path: String) -> Dictionary:
	var data: Dictionary = _read_json(path)
	_validate_sam_capabilities(data)
	return data


static func enrich_sam_scores(targets: Array[IjfsTarget], sam_caps: Dictionary) -> void:
	var by_sub: Dictionary = sam_caps.get("sam_score_by_subcategory", {})
	var by_cat: Dictionary = sam_caps.get("fallback_by_category", {})
	for target in targets:
		if target.category in SAM_CATEGORIES:
			var score = by_sub.get(target.subcategory, null)
			if score == null:
				score = by_cat.get(target.category, 0)
			target.sam_score = int(score)
		else:
			target.sam_score = -1


static func _load_runtime_targets(rows: Array) -> Array[IjfsTarget]:
	var targets: Array[IjfsTarget] = []
	for row in rows:
		var target := _target_from_dict(row)
		target.suppressed = false
		target.suppressed_this_turn = false
		targets.append(target)
	targets.sort_custom(func(a: IjfsTarget, b: IjfsTarget) -> bool: return a.target_id < b.target_id)
	return targets


static func _runtime_target_from_master(row: Dictionary, target_id: String, source_id: String, index: int, current_day: int) -> IjfsTarget:
	var target: IjfsTarget = IjfsTargetResource.new()
	var destroyed := _status_destroyed(row)
	var mobility := String(row.get("mobility", "static"))
	var static_alive := mobility == "static" and not destroyed
	target.target_id = target_id
	target.source_target_id = source_id
	target.instance_index = index
	target.category = String(row.get("category", ""))
	target.subcategory = String(row.get("subcategory", ""))
	target.quantity = 1
	target.mobility = mobility
	target.hardness = String(row.get("hardness", "soft"))
	target.detectability_active = String(row.get("detectability_active", "medium")).to_lower()
	target.detectability_hiding = String(row.get("detectability_hiding", "low")).to_lower()
	target.posture = _default_posture(row)
	target.destroyed = destroyed
	target.detected_this_turn = static_alive
	target.last_detected_day = current_day if static_alive else int(row.get("last_detected_day", -1))
	target.known_to_red = static_alive
	target.suppressed = false
	target.suppressed_this_turn = false
	target.metadata = _target_metadata(row)
	return target


static func _target_from_dict(data: Dictionary) -> IjfsTarget:
	var target: IjfsTarget = IjfsTargetResource.new()
	target.target_id = String(data["target_id"])
	target.source_target_id = String(data.get("source_target_id", target.target_id.split("#", false, 1)[0]))
	target.instance_index = int(data.get("instance_index", 1))
	target.category = String(data.get("category", ""))
	target.subcategory = String(data.get("subcategory", ""))
	target.quantity = int(data.get("quantity", 1))
	target.mobility = String(data.get("mobility", "static"))
	target.hardness = String(data.get("hardness", "soft"))
	target.detectability_active = String(data.get("detectability_active", "medium")).to_lower()
	target.detectability_hiding = String(data.get("detectability_hiding", "low")).to_lower()
	target.posture = String(data.get("posture", data.get("posture_default", "not_applicable")))
	target.destroyed = bool(data.get("destroyed", false))
	target.detected_this_turn = bool(data.get("detected_this_turn", false))
	target.last_detected_day = int(data.get("last_detected_day", -1))
	target.known_to_red = bool(data.get("known_to_red", false))
	target.suppressed = bool(data.get("suppressed", false))
	target.suppressed_this_turn = bool(data.get("suppressed_this_turn", false))
	target.intel_locked = bool(data.get("intel_locked", false))
	target.sam_score = int(data.get("sam_score", -1))
	target.metadata = data.get("metadata", {})
	return target


static func _munition_from_dict(data: Dictionary) -> IjfsMunition:
	var munition: IjfsMunition = IjfsMunitionResource.new()
	munition.munition_id = String(data["munition_id"])
	munition.name = String(data.get("name", ""))
	munition.category = String(data.get("category", ""))
	munition.inventory_remaining = int(data.get("inventory_remaining", data.get("remaining", 0)))
	munition.rounds_per_engagement_default = int(data.get("rounds_per_engagement_default", 0))
	munition.display_label = String(data.get("display_label", ""))
	return munition


static func _read_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("Could not open %s" % path)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed == null:
		_fail("JSON parsing failed for %s" % path)
	return parsed


static func _unwrap_data(payload: Variant) -> Variant:
	if payload is Dictionary and payload.has("data"):
		return payload["data"]
	return payload


static func _status_destroyed(row: Dictionary) -> bool:
	if row.has("destroyed"):
		return bool(row.get("destroyed"))
	var status: Dictionary = row.get("status", row.get("status_default", {}))
	return bool(status.get("destroyed", false))


static func _default_posture(row: Dictionary) -> String:
	if row.get("posture", null) != null:
		return String(row["posture"])
	if row.get("posture_default", null) != null:
		return String(row["posture_default"])
	return "not_applicable" if String(row.get("mobility", "static")) == "static" else "hiding"


static func _target_metadata(row: Dictionary) -> Dictionary:
	var metadata: Dictionary = row.get("metadata", {}).duplicate(true)
	for key in row.keys():
		if not TARGET_CORE_KEYS.has(key):
			metadata[key] = row[key]
	return metadata


static func _class_slug(name: String) -> String:
	var s := name.to_lower()
	var out := ""
	var prev_us := false
	for i in range(s.length()):
		var ch := s.substr(i, 1)
		var code := ch.unicode_at(0)
		var valid := (code >= 97 and code <= 122) or (code >= 48 and code <= 57)
		if valid:
			out += ch
			prev_us = false
		elif not prev_us:
			out += "_"
			prev_us = true
	return out.strip_edges().trim_prefix("_").trim_suffix("_")


static func _validate_pairing(rule: IjfsPairing) -> void:
	if rule.rounds_expended_per_engagement <= 0:
		_fail("PAIRING_INVALID: pairing '%s' rounds_expended_per_engagement must be > 0" % rule.pairing_id)
	if rule.probability_destroyed < 0.0 or rule.probability_destroyed > 1.0:
		_fail("PAIRING_INVALID: pairing '%s' probability_destroyed must be in [0, 1]" % rule.pairing_id)
	if rule.probability_suppressed_if_not_destroyed < 0.0 or rule.probability_suppressed_if_not_destroyed > 1.0:
		_fail("PAIRING_INVALID: pairing '%s' probability_suppressed_if_not_destroyed must be in [0, 1]" % rule.pairing_id)


static func _validate_ijfs_config_blocks(scenario: Dictionary) -> void:
	if not scenario.has("schema_version") or int(scenario["schema_version"]) != 1:
		_fail("CONFIG_SCHEMA_MISMATCH: schema_version unsupported or missing")
	for block in REQUIRED_SCENARIO_BLOCKS:
		if not scenario.has(block):
			_fail("CONFIG_SCHEMA_MISMATCH: missing required block: %s" % block)
	if scenario.has("prelanding"):
		var days = scenario["prelanding"].get("days", null)
		if days != null and (int(days) < 0 or int(days) > 14):
			_fail("PRELANDING_DAYS_OUT_OF_RANGE: prelanding.days=%s" % days)
	for source in scenario.get("isr_sources", []):
		var degradation: Dictionary = source.get("degradation", {})
		var mode := String(degradation.get("mode", ""))
		if mode not in ISR_CURVE_MODES:
			_fail("ISR_SOURCE_INVALID: unknown curve mode '%s'" % mode)
		if mode == "piecewise" and not degradation.has("values"):
			_fail("ISR_SOURCE_INVALID: piecewise source missing values")
		if mode == "exp_decay" and not degradation.has("half_life_days"):
			_fail("ISR_SOURCE_INVALID: exp_decay source missing half_life_days")
		if mode == "linear" and not degradation.has("duration_days"):
			_fail("ISR_SOURCE_INVALID: linear source missing duration_days")
		if mode == "from_attrition" and not degradation.has("source"):
			_fail("ISR_SOURCE_INVALID: from_attrition source missing degradation.source")
	for rule in scenario.get("target_release", []):
		if not (rule as Dictionary).has("release_day"):
			_fail("TARGET_RELEASE_INVALID: rule missing release_day")
	if not scenario.has("strike_probability_modifiers") and not scenario.has("mobile_target_destroy_caps"):
		_fail("CONFIG_SCHEMA_MISMATCH: missing strike_probability_modifiers or mobile_target_destroy_caps")
	for modifier in scenario.get("strike_probability_modifiers", []):
		var op := String(modifier.get("operation", "")).to_lower()
		if op not in STRIKE_MODIFIER_OPERATIONS:
			_fail("STRIKE_MODIFIER_INVALID: operation must be add or multiply")
		var match_dict: Dictionary = modifier.get("match", {})
		for key in match_dict.keys():
			if key not in STRIKE_MODIFIER_MATCH_KEYS:
				_fail("STRIKE_MODIFIER_INVALID: unknown match key %s" % key)


static func _validate_air_classes(data: Dictionary) -> void:
	if not data.has("model_version"):
		_fail("AIR_CLASSES_INVALID: missing model_version")
	if not data.has("reference_isr_sum") or float(data["reference_isr_sum"]) <= 0.0:
		_fail("AIR_CLASSES_INVALID: reference_isr_sum must be > 0")
	var classes: Dictionary = data.get("classes", {})
	if classes.is_empty():
		_fail("AIR_CLASSES_INVALID: classes must be a non-empty dict")
	for cls_name in classes.keys():
		var entry: Dictionary = classes[cls_name]
		if String(cls_name) not in VALID_AIR_CLASSES:
			_fail("AIR_CLASSES_INVALID: unknown class '%s'" % cls_name)
		if String(entry.get("kind", "")) not in VALID_KINDS:
			_fail("AIR_CLASSES_INVALID: class '%s' invalid kind" % cls_name)
		for field in CLASS_NUMERIC_FIELDS:
			if not entry.has(field):
				_fail("AIR_CLASSES_INVALID: class '%s' missing field '%s'" % [cls_name, field])
		if float(entry["isr_value"]) < 0.0 or float(entry["isr_value"]) > 1.0:
			_fail("AIR_CLASSES_INVALID: class '%s' isr_value must be in [0, 1]" % cls_name)
		if float(entry["wvr"]) < 0.0 or float(entry["sead_eff"]) < 0.0:
			_fail("AIR_CLASSES_INVALID: class '%s' negative wvr/sead_eff" % cls_name)


static func _validate_sam_capabilities(data: Dictionary) -> void:
	if not data.has("model_version"):
		_fail("SAM_CAPABILITIES_INVALID: missing model_version")
	for cat in data.get("fallback_by_category", {}).keys():
		if float(data["fallback_by_category"][cat]) < 0.0:
			_fail("SAM_CAPABILITIES_INVALID: fallback score for '%s' must be >= 0" % cat)
	for sub in data.get("sam_score_by_subcategory", {}).keys():
		if float(data["sam_score_by_subcategory"][sub]) < 0.0:
			_fail("SAM_CAPABILITIES_INVALID: score for '%s' must be >= 0" % sub)


static func _validate_oob(data: Dictionary) -> void:
	if not data.has("model_version"):
		_fail("OOB_INVALID: missing model_version")
	if not (data.get("red_air_oob") is Array):
		_fail("OOB_INVALID: red_air_oob must be a list")
	for i in range(data["red_air_oob"].size()):
		var row: Dictionary = data["red_air_oob"][i]
		if String(row.get("class", "")) not in VALID_AIR_CLASSES:
			_fail("OOB_INVALID: row %d invalid class" % i)
		if String(row.get("role", "")) not in VALID_ROLES:
			_fail("OOB_INVALID: row %d invalid role" % i)
		if int(row.get("squadrons", 0)) <= 0:
			_fail("OOB_INVALID: row %d squadrons must be int > 0" % i)
		if int(row.get("aircraft_per_sqn", -1)) < 0:
			_fail("OOB_INVALID: row %d aircraft_per_sqn must be int >= 0" % i)


static func _fail(message: String) -> void:
	push_error(message)
	assert(false, message)
