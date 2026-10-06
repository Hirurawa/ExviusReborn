class_name SkillCatalog
extends RefCounted

## Where the engine gets its skills. This base class serves records added with
## add_record, which is how tests build battles from fixture dicts;
## DatabaseSkillCatalog (session layer) overrides fetch_record to read GameDatabase.
## Each skill is built once and cached.
##
## Records use GameDatabase's shapes (see BattleSkill.from_record). A limit burst
## record carries `levels` ([gauge, effects_raw] per level); an item's record is the
## ability it casts.

const SKILL_SCHEMA_PATH: String = "res://features/battle/logic/skill_schema.json"
const PASSIVE_SCHEMA_PATH: String = "res://features/battle/logic/passive_schema.json"

var skill_schema: Dictionary = {}
var passive_schema: Dictionary = {}

var _records: Dictionary = {}
var _skills: Dictionary = {}


func _init(skills_schema: Dictionary = {}, passives_schema: Dictionary = {}) -> void:
	skill_schema = skills_schema
	passive_schema = passives_schema


## A catalog with both opcode schemas read straight from disk, for code that runs
## without the SkillResolver autoload.
static func with_schemas_from_disk() -> SkillCatalog:
	return SkillCatalog.new(load_schema(SKILL_SCHEMA_PATH), load_schema(PASSIVE_SCHEMA_PATH))


static func load_schema(path: String) -> Dictionary:
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text) if text != "" else null
	if not parsed is Dictionary:
		push_error("SkillCatalog: cannot read opcode schema at %s" % path)
		return {}
	return parsed


func add_record(kind: StringName, id: String, data: Dictionary) -> void:
	_records[_key(kind, id)] = data
	_skills.erase(_key(kind, id))


## The skill, or null when the id is unknown.
func get_skill(kind: StringName, id: String) -> BattleSkill:
	var key: String = _key(kind, id)
	if _skills.has(key):
		return _skills[key]
	var data: Dictionary = fetch_record(kind, id)
	if data.is_empty():
		return null
	var skill: BattleSkill = BattleSkill.from_record(kind, id, data, skill_schema)
	_skills[key] = skill
	return skill


## The ability an item casts, as a skill of kind item.
func get_item(item_id: String) -> BattleSkill:
	return get_skill(BattleSkill.KIND_ITEM, item_id)


## The ability that replaces a unit's normal attack (passive op 100), or null when the
## id is unknown. A replacement whose record has no attack frames (28 of the 544, 9 of
## them with a damage effect) hits on `unit_attack`'s frames instead of all on frame 0: it
## replaces the swing, so it keeps the swing's timing (a reading, 2026-10-01). Built
## per unit, not cached, since the frames are the unit's.
func get_attack_replacement(ability_id: String, unit_attack: BattleSkill) -> BattleSkill:
	var data: Dictionary = fetch_record(BattleSkill.KIND_ABILITY, ability_id)
	if data.is_empty():
		return null
	if _has_frames(data) or unit_attack == null or unit_attack.effects.is_empty():
		return get_skill(BattleSkill.KIND_ABILITY, ability_id)
	var swing: SkillEffect = unit_attack.effects[0]
	var filled: Dictionary = data.duplicate()
	filled["attack_frames"] = [Array(swing.hit_frames)]
	filled["attack_damage"] = [Array(swing.hit_damage)]
	return BattleSkill.from_record(BattleSkill.KIND_ABILITY, ability_id, filled, skill_schema)


static func _has_frames(data: Dictionary) -> bool:
	for group in data.get("attack_frames", []):
		if group is Array and not (group as Array).is_empty():
			return true
	return false


## A limit burst at `level` (1-based): that level's effects, and its gauge cost in
## hundredths of a crystal.
func get_limit_burst(limit_burst_id: String, level: int) -> BattleSkill:
	var key: String = _key(BattleSkill.KIND_LIMIT_BURST, "%s@%d" % [limit_burst_id, level])
	if _skills.has(key):
		return _skills[key]
	var data: Dictionary = fetch_record(BattleSkill.KIND_LIMIT_BURST, limit_burst_id)
	if data.is_empty():
		return null
	var lb_cost: int = int(data.get("lb_cost", 0))
	var levels: Array = data.get("levels", [])
	if not levels.is_empty():
		var level_entry: Array = levels[clampi(level, 1, levels.size()) - 1]
		data = data.duplicate()
		data["effects_raw"] = level_entry[1]
		lb_cost = roundi(float(level_entry[0]) * 100.0)
	var skill: BattleSkill = BattleSkill.from_record(BattleSkill.KIND_LIMIT_BURST, limit_burst_id, data, skill_schema)
	skill.lb_cost = lb_cost
	_skills[key] = skill
	return skill


## The raw record for a skill, or {} when unknown. Override to read another source.
func fetch_record(kind: StringName, id: String) -> Dictionary:
	return _records.get(_key(kind, id), {})


static func _key(kind: StringName, id: String) -> String:
	return "%s:%s" % [kind, id]
