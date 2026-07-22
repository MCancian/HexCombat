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
		"inland_clear":
			return InlandClearPolicy.new()
		"garrison_draw":
			return GarrisonDrawPolicy.new()
		"noop":
			return NoopPolicy.new()
		"llm_local":
			return LLMPolicy.new()
		_:
			push_error("Unknown policy id: '%s' (known: %s)" % [policy_id, ", ".join(known_ids())])
			return null


## Instantiate a policy for one WeGo seat. Seat-aware policies receive their perspective and
## replay-log path at this boundary; deterministic policies need no seat-specific configuration.
static func create_for_seat(policy_id: String, seat: String, log_path: String = "") -> Object:
	if policy_id == "llm_local":
		return LLMPolicy.for_seat(seat, log_path)
	return create(policy_id)


static func known_ids() -> Array[String]:
	return ["selfplay_default", "inland_clear", "noop", "llm_local", "garrison_draw"]
