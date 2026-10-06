class_name OpcodeParser

static func _has_meaningful_payload_value(value: Variant) -> bool:
	if typeof(value) == TYPE_ARRAY:
		return not value.is_empty()

	# A processParam slot can be a literal token rather than a number -- "none", or a
	# message id like MST_MONSTERSKILL_PARAM_MSG_78. Comparing those to 0 is an error,
	# and "none" is the data's own way of saying the slot is unused.
	if typeof(value) == TYPE_STRING:
		return value != "" and value != "none"

	return value != 0

## The schema entry that describes one effect: the opcode's top-level entry, or the
## variant whose `match` fits the effect's params. Two active opcodes are overloaded
## (53 with two params is HIDE, 102 with six is MULTICAST_SKILL_TYPES; see
## PARSER-NOTES.md §9), so the entry cannot be picked by opcode alone. {} when the
## schema does not map the opcode.
static func resolve_schema_entry(schema: Dictionary, opcode: Variant, payload: Array) -> Dictionary:
	var entry: Dictionary = schema.get(str(opcode), {})
	for variant in entry.get("variants", []):
		var match_rule: Dictionary = variant.get("match", {})
		if match_rule.has("param_count") and int(match_rule["param_count"]) == payload.size():
			return variant
	return entry

## The effect's payload as { key: value } under the entry's key names. Zeros, "none"
## and unnamed slots are dropped, so a missing key means the slot was unused.
static func map_payload(entry: Dictionary, payload: Array) -> Dictionary:
	var mapped: Dictionary = {}
	var keys: Array = entry.get("keys", [])
	for i in range(min(keys.size(), payload.size())):
		var key = keys[i]
		var value = payload[i]
		# Drop zeros and unknowns for a perfectly clean output!
		if _has_meaningful_payload_value(value) and key != "UNKNOWN" and key != "???" and key != "":
			mapped[key] = value
	return mapped

static func parse_passive(skill_data: Dictionary, passive_schema: Dictionary) -> Dictionary:
	var parsed_action: Dictionary = {
		"effects": []
	}

	var effects_raw: Array = skill_data.get("effects_raw", [])
	for effect_data in effects_raw:
		var opcode = effect_data[2]  # e.g., 3
		var payload = effect_data[3] # e.g., [0, 0, 0, 0, 10, 0, 0]

		# Check if our "mask file" knows this opcode
		var schema: Dictionary = resolve_schema_entry(passive_schema, opcode, payload)
		if not schema.is_empty():
			parsed_action.get("effects").append({
				"type": schema["type"],
				"opcode": opcode,
				"effect": map_payload(schema, payload),
			})
		else:
			#push_warning("OpcodeParser: Unknown passive opcode: " + str(opcode))
			pass

	return parsed_action

static func parse_skill(skill_data: Dictionary, skill_schema: Dictionary) -> Dictionary:
	var parsed_action: Dictionary = {
		"element_inflict": skill_data.get("element_inflict", []),
		"effects": []
	}
	var effects_raw: Array = skill_data.get("effects_raw", [])
	var attack_damage: Array = skill_data.get("attack_damage", [])
	var attack_frames: Array = skill_data.get("attack_frames", [])
	var t_type = skill_data.get("targetType")

	var idx = 0
	for effect_data in effects_raw:
		var target_area: int = int(effect_data[0])
		var target_type: int = int(effect_data[1])

		var current_attack_damage: Array = []
		if attack_damage.size() > 0:
			current_attack_damage = attack_damage[idx] if idx < attack_damage.size() else attack_damage[0]

		var current_attack_frames: Array = []
		if attack_frames.size() > 0:
			current_attack_frames = attack_frames[idx] if idx < attack_frames.size() else attack_frames[0]

		var opcode = effect_data[2]  # e.g., 3
		var payload = effect_data[3] # e.g., [0, 0, 0, 0, 10, 0, 0]

		var parsed_effect: Dictionary = {
			"type": "",
			"opcode": opcode,
			"target_area": target_area,
			"target_type": target_type,
			"t_type": t_type,
			"attack_damage": current_attack_damage,
			"attack_frames": current_attack_frames,
			"effect": {}
			}
		idx = idx + 1

		# Check if our "mask file" knows this opcode
		var schema: Dictionary = resolve_schema_entry(skill_schema, opcode, payload)
		if not schema.is_empty():
			parsed_effect["type"] = schema["type"]
			parsed_effect["effect"] = map_payload(schema, payload)
			parsed_action.get("effects").append(parsed_effect)
		else:
			push_warning("OpcodeParser: Unknown skill opcode: " + str(opcode))

	return parsed_action
