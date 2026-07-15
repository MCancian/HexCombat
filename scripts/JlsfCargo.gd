class_name JlsfCargo
extends RefCounted

## Builds the pseudo mainland_pool entry for a JLSF deployment (plan 0006). The entry
## must satisfy the sealift/crossing plumbing contracts: a REAL locked_beach id
## (AntishipResolver derives crossing target beaches from it and push_errors on unknown
## ids), beach_hex = the target node's hex (where the detachment comes ashore), and
## unique BN ids (cohort binding + crossing attrition draw operate on BN id strings).

const BRIGADE_ID_PREFIX := "JLSF:"
const BN_TYPE := "JLSF Detachment"


## True when the reserve/pool entry is a JLSF pseudo-entry, not a troop brigade.
static func is_jlsf_entry(entry: Dictionary) -> bool:
	return String(entry.get("cargo", "")) == "jlsf"


## brigade id for a port: "JLSF:<port_id>"
static func brigade_id_for(port_id: String) -> String:
	return BRIGADE_ID_PREFIX + port_id


## Build the pseudo pool entry.
##   node_def: InfrastructureDef of the target port/airbridge.
##   beaches: GameData.beaches (beach_id int -> BeachDef).
##   beach_to_to: beach_id int -> to_number int.
##   bn_count: lift cost in BN-equivalents (scenario knob jlsf_lift_bn_equiv, default 4).
## locked_beach = the LOWEST beach id in the node's TO (same-TO staging); when the TO
## has no beach, the lowest beach id overall (any real beach keeps the crossing
## targeting legal).
static func build_pool_entry(node_def: InfrastructureDef, beaches: Dictionary, beach_to_to: Dictionary, bn_count: int) -> Dictionary:
	var sorted_ids: Array = beaches.keys()
	sorted_ids.sort()

	var locked_beach: int = 0
	for id_value in sorted_ids:
		var bid: int = int(id_value)
		if int(beach_to_to.get(bid, -1)) == node_def.to_number:
			locked_beach = bid
			break
	if locked_beach == 0 and not sorted_ids.is_empty():
		locked_beach = int(sorted_ids[0])
	if locked_beach == 0:
		push_error("JlsfCargo: no beaches loaded")

	var bns: Array = []
	for i in range(1, bn_count + 1):
		bns.append({
			"id": "JLSF:%s:%d" % [node_def.id, i],
			"type": BN_TYPE,
		})

	return {
		"brigade_id": brigade_id_for(node_def.id),
		"cargo": "jlsf",
		"port_id": node_def.id,
		"locked_beach": locked_beach,
		"beach_hex": node_def.hex_id,
		"offset_bearing": 0.0,
		"bns": bns,
	}
