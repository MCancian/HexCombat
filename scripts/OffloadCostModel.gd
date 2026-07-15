class_name OffloadCostModel
extends RefCounted

# Offload cost computation — ported from TaiwanInvasionViewer
# src/services/offload/beach_throughput.py get_beach_throughput_cost + contracts/units.py
# multiplier constants, generalized to a data-driven matrix.
# Weight = transport weight in tons; cost = weight × node_kind/bn_class/ship_category multiplier.


static func flat_config() -> Dictionary:
	return {"default_tons": OffloadRates.TONS_PER_BN}


static func bn_cost_tons(bn_type: String, ship_category: String, node_kind: String, config: Dictionary) -> float:
	var weights: Dictionary = config.get("weights", {})
	var weight: float = float(weights.get(bn_type, config.get("default_tons", OffloadRates.TONS_PER_BN)))

	var bn_class_of: Dictionary = config.get("bn_class_of", {})
	var bn_class: String = String(bn_class_of.get(bn_type, config.get("default_bn_class", "standard")))

	var mults: Dictionary = config.get("multipliers", {})
	var mult: float = _resolve_multiplier(mults, node_kind, bn_class, ship_category)

	return weight * mult


static func _resolve_multiplier(mults: Dictionary, node_kind: String, bn_class: String, ship_category: String) -> float:
	var level0 = mults.get(node_kind, mults.get("default", 1.0))
	if level0 is float or level0 is int:
		return float(level0)
	var level1 = (level0 as Dictionary).get(bn_class, (level0 as Dictionary).get("default", 1.0))
	if level1 is float or level1 is int:
		return float(level1)
	var level2 = (level1 as Dictionary).get(ship_category, (level1 as Dictionary).get("default", 1.0))
	return float(level2)
