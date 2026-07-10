extends Node
## SkillResolver — owns opcode schemas + skill / limit-burst / item resolution.
## Reads template data from StaticData; writes nothing back.

const OPCODE_SKILL_SCHEMA_PATH: String = "res://features/battle/logic/skill_schema.json"
const OPCODE_PASSIVE_SCHEMA_PATH: String = "res://features/battle/logic/passive_schema.json"

var opcode_skill_schema: Dictionary = {}
var opcode_passive_schema: Dictionary = {}
var opcode_schemas_ready: bool = false
var opcode_schema_error: String = ""


# === Schema loading ===

func load_schemas() -> void:
	opcode_schemas_ready = false
	opcode_schema_error = ""
	opcode_skill_schema = _load_schema_file(OPCODE_SKILL_SCHEMA_PATH, "skill")
	opcode_passive_schema = _load_schema_file(OPCODE_PASSIVE_SCHEMA_PATH, "passive")

	if opcode_schema_error != "":
		return

	opcode_schemas_ready = true


func _load_schema_file(schema_path: String, schema_name: String) -> Dictionary:
	if not FileAccess.file_exists(schema_path):
		_record_schema_error("CRITICAL ERROR: Missing %s opcode schema at %s" % [schema_name, schema_path])
		return {}

	var json_as_text: String = FileAccess.get_file_as_string(schema_path)
	if json_as_text.strip_edges() == "":
		_record_schema_error("CRITICAL ERROR: Empty %s opcode schema at %s" % [schema_name, schema_path])
		return {}

	var parsed: Variant = JSON.parse_string(json_as_text)
	if parsed == null:
		_record_schema_error("CRITICAL ERROR: Invalid JSON in %s opcode schema at %s" % [schema_name, schema_path])
		return {}

	if not parsed is Dictionary:
		_record_schema_error("CRITICAL ERROR: %s opcode schema must parse as Dictionary at %s" % [schema_name, schema_path])
		return {}

	return parsed as Dictionary


func _record_schema_error(error_message: String) -> void:
	if opcode_schema_error == "":
		opcode_schema_error = error_message
	push_error(error_message)


func _ensure_schemas_ready(caller_name: String) -> bool:
	if opcode_schemas_ready:
		return true

	var details: String = opcode_schema_error if opcode_schema_error != "" else "CRITICAL ERROR: Opcode schemas not loaded."
	push_error("SkillResolver: %s cannot parse opcodes. %s" % [caller_name, details])
	return false


# === Public parse / resolve API ===

func parse_passive_effects(skill_data: Dictionary) -> Dictionary:
	if not _ensure_schemas_ready("parse_passive_effects"):
		return {"effects": []}
	return OpcodeParser.parse_passive(skill_data, opcode_passive_schema)

func parse_skill_effects(skill_data: Dictionary) -> Dictionary:
	if not _ensure_schemas_ready("parse_skill_effects"):
		return {
			"element_inflict": skill_data.get("element_inflict", []),
			"effects": []
		}
	return OpcodeParser.parse_skill(skill_data, opcode_skill_schema)

func resolve_esper_skill(skill_data: Dictionary) -> Dictionary:
	if skill_data.is_empty():
		return {}

	var parsed_data: Dictionary = SkillResolver.parse_skill_effects(skill_data)
	return {
		"source_type": "esper_skill",
		"source_id": skill_data.get("skill_id"),
		"resolved_action_id": skill_data.get("skill_id"),
		"resolved_action_name": skill_data.get("name", ""),
		"resolved_action_data": skill_data,
		"parsed_data": parsed_data,
		"targeting": _build_targeting_metadata(parsed_data)
	}

func resolve_combat_skill(skill_id: String) -> Dictionary:
	var resolved_skill: Dictionary = _get_active_skill_record(skill_id)
	if resolved_skill.is_empty():
		push_error("SkillResolver: Combat skill not found: %s" % skill_id)
		return {}

	var parsed_data: Dictionary = parse_skill_effects(resolved_skill)
	return {
		"source_type": "skill",
		"source_id": skill_id,
		"resolved_action_id": skill_id,
		"resolved_action_name": resolved_skill.get("name", ""),
		"resolved_action_data": resolved_skill,
		"parsed_data": parsed_data,
		"targeting": _build_targeting_metadata(parsed_data)
	}

func resolve_combat_limitburst(limitburst_id: String) -> Dictionary:
	var resolved_limitburst: Dictionary = GameDatabase.get_limitburst(limitburst_id)
	if resolved_limitburst.is_empty():
		push_error("SkillResolver: Combat limit burst not found: %s" % limitburst_id)
		return {}

	var parsed_data: Dictionary = parse_skill_effects(resolved_limitburst)
	return {
		"source_type": "limitburst",
		"source_id": limitburst_id,
		"resolved_action_id": limitburst_id,
		"resolved_action_name": resolved_limitburst.get("name", ""),
		"resolved_action_data": resolved_limitburst,
		"parsed_data": parsed_data,
		"targeting": _build_targeting_metadata(parsed_data)
	}

func resolve_combat_item(item_id: String) -> Dictionary:
	var item_data: Dictionary = GameDatabase.get_item(int(item_id))
	if item_data.is_empty():
		push_error("SkillResolver: Combat item not found: %s" % item_id)
		return {}

	var resolved_ability_id: String = _find_item_ability_id(item_data.get("effects_raw", []))
	resolved_ability_id = item_data.get("processParam").split(',')[0] if (not item_data.get("processParam") == null and item_data.get("processId") == 71 ) else ""
	if resolved_ability_id == "":
		push_error("SkillResolver: Combat item missing opcode 71 ability reference: %s" % item_id)
		return {}

	var resolved_action_data: Dictionary = GameDatabase.get_ability(resolved_ability_id)
	if resolved_action_data.is_empty():
		push_error("SkillResolver: Combat item ability not found: %s -> %s" % [item_id, resolved_ability_id])
		return {}

	var parsed_data: Dictionary = parse_skill_effects(resolved_action_data)
	return {
		"source_type": "item",
		"source_id": item_id,
		"source_item_data": item_data,
		"resolved_action_id": resolved_ability_id,
		"resolved_action_name": resolved_action_data.get("name", item_data.get("name", "")),
		"resolved_action_data": resolved_action_data,
		"parsed_data": parsed_data,
		"targeting": _build_targeting_metadata(parsed_data),
		"original_item_id": item_id
	}

func get_limitburst_max_gauge(limitburst_id: String) -> int:
	var default_max_gauge: int = 100
	if limitburst_id == "":
		return default_max_gauge

	var limitburst_data: Dictionary = GameDatabase.get_limitburst(limitburst_id)
	if limitburst_data.is_empty():
		push_error("SkillResolver: Limit burst data not found: %s" % limitburst_id)
		return default_max_gauge

	var levels: Variant = limitburst_data.get("levels", [])
	if not (levels is Array) or (levels as Array).is_empty():
		push_error("SkillResolver: Limit burst levels missing or invalid for id: %s" % limitburst_id)
		return default_max_gauge

	var first_level: Variant = (levels as Array)[0]
	if not (first_level is Array) or (first_level as Array).is_empty():
		push_error("SkillResolver: Limit burst first level invalid for id: %s" % limitburst_id)
		return default_max_gauge

	var gauge_value: Variant = (first_level as Array)[0]
	if typeof(gauge_value) not in [TYPE_INT, TYPE_FLOAT]:
		push_error("SkillResolver: Limit burst gauge value invalid for id: %s" % limitburst_id)
		return default_max_gauge

	return max(1, int(gauge_value))


# === Helpers ===

func _get_active_skill_record(skill_id: String) -> Dictionary:
	var skill_data: Dictionary = GameDatabase.get_magic(skill_id)
	if not skill_data.is_empty():
		return skill_data

	return GameDatabase.get_ability(skill_id)


func _find_item_ability_id(effects_raw: Array) -> String:
	for effect in effects_raw:
		if effect.size() < 4:
			continue
		if int(effect[2]) != 71:
			continue

		var payload: Variant = effect[3]
		if typeof(payload) != TYPE_ARRAY or payload.size() == 0:
			continue

		return str(payload[0])

	return ""


func _build_targeting_metadata(parsed_data: Dictionary) -> Dictionary:
	var metadata: Dictionary = {
		"needs_ally_selection": false,
		"targets_living": false,
		"targets_enemies": false,
		"targets_self": false,
		"has_aoe": false
	}

	for effect in parsed_data.get("effects", []):
		var target_area: int = int(effect.get("target_area", 1))
		var target_type: int = int(effect.get("target_type", 1))
		var t_type: int = int(effect.get("t_type", 0))

		if target_area == 2:
			metadata["has_aoe"] = true

		if target_type == 3:
			metadata["targets_self"] = true
		elif target_type == 1:
			metadata["targets_enemies"] = true
		elif target_type  in [2, 6]:
			if t_type == 7:
				metadata["targets_dead"] = true
			else:
				metadata["targets_living"] = true
			if target_area == 1:
				metadata["needs_ally_selection"] = true

	return metadata
