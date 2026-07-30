extends Resource
class_name HexState

## Per-hex runtime ownership + front-line state, keyed by hex_id in GameData.hex_states.
## Replaces the former plain {owner, feba_km} dict (refactor_audit item 3 — typed drift-safety).
## hex_owner is a HexOwner.* string constant; feba_km is the signed FEBA displacement (Red-positive).
##
## Both fields are protected state of the `map` aggregate; the writer list lives in
## tools/mutation_authority_manifest.json and is not copied here.
##
## The field is `hex_owner`, not `owner`, deliberately (plan 0047): a protected field NAME is claimed
## repo-wide by the mutation-authority gate, and `owner` is a built-in `Node` property — so a future
## `some_node.owner = x` anywhere in the tree would fail that gate as an unresolved write to a
## protected name. Plan 0046 paid 22 false failures to learn this with `name`. The SERIALIZED key
## stays "owner": it is live in every game record's final_snapshot.

@export var hex_owner: String = HexOwner.GREEN
@export var feba_km: float = 0.0


func to_dict() -> Dictionary:
	return {
		"owner": hex_owner,
		"feba_km": feba_km,
	}
