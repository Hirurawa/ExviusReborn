class_name OpcodeParser

static func parse_skill(skill_data: Dictionary) -> Dictionary:
	var parsed_action: Dictionary = {
		"element_inflict": skill_data.get("element_inflict", []),
		"effects": []
	}

	var effects_raw: Array = skill_data.get("effects_raw", [])

	for effect in effects_raw:
		if typeof(effect) != TYPE_ARRAY or effect.size() < 4:
			continue

		var opcode_id: int = int(effect[2])
		var parameters: Array = effect[3]

		match opcode_id:
			15: # MAGIC_DAMAGE
				if typeof(parameters) == TYPE_ARRAY and parameters.size() > 5:
					var modifier: float = float(parameters[5]) / 100.0
					parsed_action["effects"].append({
						"type": "MAGIC_DAMAGE",
						"modifier": modifier
					})
			_: # Unhandled Opcodes
				print("OpcodeParser: Unhandled Opcode ", opcode_id, " in skill ", skill_data.get("name", "Unknown"))

	return parsed_action
