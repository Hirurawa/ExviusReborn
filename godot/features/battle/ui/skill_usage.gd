extends RefCounted
class_name SkillUsage

## Shared vocabulary and pure helpers for "can this unit use this action, and what
## does the action resolve to". Used by both the in-combat ActionMenu (to grey out
## unusable entries) and the battle UI's Reload/Repeat path (to re-validate a saved
## command before re-queueing it). Pure functions over unit/skill dicts.

const SKILL_DISABLE_REASON_NONE: String = ""
const SKILL_DISABLE_REASON_LACK_MP: String = "lack_mp"
const SKILL_DISABLE_REASON_LACK_LIMIT: String = "lack_limit"
const SKILL_DISABLE_REASON_UNIT_UNAVAILABLE: String = "unit_unavailable"

const SKILL_ROLE_STANDARD: String = "standard"
const SKILL_ROLE_LIMITBURST: String = "limitburst"
const SKILL_ROLE_ESPER: String = "esper_skill"
const SKILL_ROLE_MAGIC: String = "magic"
const SKILL_ROLE_ABILITY: String = "ability"
const SOURCE_TYPE_ITEM: String = "item"


## Dispatches an action id to the right SkillResolver entry point for its source
## type. Returns the resolution dict, or {} when the action cannot be resolved.
static func resolve_action(source_type: String, action_id: String, action_data: Dictionary = {}) -> Dictionary:
	match source_type:
		SKILL_ROLE_MAGIC:
			return SkillResolver.resolve_combat_magic(action_id)
		SKILL_ROLE_ABILITY:
			return SkillResolver.resolve_combat_ability(action_id)
		SKILL_ROLE_LIMITBURST:
			return SkillResolver.resolve_combat_limitburst(action_id)
		SKILL_ROLE_ESPER:
			return SkillResolver.resolve_esper_skill(action_data)
		SOURCE_TYPE_ITEM:
			return SkillResolver.resolve_combat_item(action_id)
		_:
			return SkillResolver.resolve_combat_skill(action_id)


static func can_unit_pay_skill_mp(unit_data: Dictionary, skill_data: Dictionary) -> bool:
	if unit_data.is_empty():
		return false

	var current_mp: int = int(unit_data.get("current_mp", 0))
	var cost_value: Variant = skill_data.get("cost", {})
	var mp_cost: int = int(cost_value.get("MP", 0)) if cost_value is Dictionary else int(cost_value) if typeof(cost_value) in [TYPE_INT, TYPE_FLOAT] else 0
	return current_mp >= mp_cost


## SKILL_DISABLE_REASON_NONE when the unit can use the skill right now, otherwise
## the reason code the skill button uses to render its disabled state.
static func skill_disabled_reason(unit_data: Dictionary, source_type: String, skill_data: Dictionary) -> String:
	if unit_data.is_empty() or int(unit_data.get("current_hp", 0)) <= 0:
		return SKILL_DISABLE_REASON_UNIT_UNAVAILABLE
	if source_type == SKILL_ROLE_LIMITBURST:
		var max_limit: int = int(unit_data.get("max_limit", 0))
		if max_limit <= 0 or int(unit_data.get("limit_gauge", 0)) < max_limit:
			return SKILL_DISABLE_REASON_LACK_LIMIT
	elif not can_unit_pay_skill_mp(unit_data, skill_data):
		return SKILL_DISABLE_REASON_LACK_MP
	return SKILL_DISABLE_REASON_NONE
