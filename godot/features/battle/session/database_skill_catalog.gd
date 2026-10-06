class_name DatabaseSkillCatalog
extends SkillCatalog

## SkillCatalog backed by GameDatabase and SkillResolver's opcode schemas. Session-layer
## code: it names autoloads, so the engine only ever sees it as a SkillCatalog.

## Items cast an ability through this opcode (processId 71, first param = ability id).
const ITEM_CAST_OPCODE: int = 71


func _init() -> void:
	if not SkillResolver.opcode_schemas_ready:
		SkillResolver.load_schemas()
	super(SkillResolver.opcode_skill_schema, SkillResolver.opcode_passive_schema)


func fetch_record(kind: StringName, id: String) -> Dictionary:
	if id == "":
		return {}
	match kind:
		BattleSkill.KIND_MAGIC:
			return GameDatabase.get_magic(id)
		BattleSkill.KIND_ABILITY:
			return GameDatabase.get_ability(id)
		BattleSkill.KIND_LIMIT_BURST:
			return GameDatabase.get_limitburst(id)
		BattleSkill.KIND_MONSTER:
			return GameDatabase.get_monster_skill_record(id)
		BattleSkill.KIND_ITEM:
			return _item_ability_record(id)
		BattleSkill.KIND_ESPER:
			# A beast skill id names the esper and its rank (10101: Siren, rank 1).
			return GameDatabase.get_esper_skill_record(id)
	return {}


## The ability an item casts, with the item's own name and id added, or {} when the
## item casts nothing.
func _item_ability_record(item_id: String) -> Dictionary:
	if not item_id.is_valid_int():
		return {}
	var item: Dictionary = GameDatabase.get_item(int(item_id))
	if item.is_empty() or int(item.get("processId", 0)) != ITEM_CAST_OPCODE or item.get("processParam") == null:
		return {}
	var ability_id: String = str(item.get("processParam")).split(",")[0]
	var ability: Dictionary = GameDatabase.get_ability(ability_id)
	if ability.is_empty():
		return {}
	var record: Dictionary = ability.duplicate()
	record["name"] = str(item.get("name", ability.get("name", "")))
	record["item_id"] = item_id
	record["ability_id"] = ability_id
	return record
