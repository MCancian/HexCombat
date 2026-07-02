class_name PolicyCatalog
extends RefCounted

## Policy registry for research runs (harness B2): a policy id names a decision-maker so batch
## records are attributable ("policy identity is part of the result" — hexcombat-research-runs).
## Every policy object implements build_actions(observation: Dictionary) -> Array (the
## SelfPlayPolicy contract). Unknown ids fail loud — a batch must never silently substitute a
## different player. The LLM-player adapter (B6) registers here when it lands.


## Instantiate the policy for an id, or null (with a push_error) for an unknown id.
static func create(policy_id: String) -> Object:
	match policy_id:
		"selfplay_default":
			return SelfPlayPolicy.new()
		_:
			push_error("Unknown policy id: '%s' (known: %s)" % [policy_id, ", ".join(known_ids())])
			return null


static func known_ids() -> Array[String]:
	return ["selfplay_default"]
