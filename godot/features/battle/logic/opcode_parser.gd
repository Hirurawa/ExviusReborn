class_name OpcodeParser

static func parse_passive(skill_data: Dictionary, passive_schema: Dictionary) -> Dictionary:
	
	var parsed_action: Dictionary = {
		"effects": []
	}
	
	var effects_raw: Array = skill_data.get("effects_raw", [])
	for effect_data in effects_raw:
		var parsed_effect: Dictionary = {
			"type": "",
			"effect": {}
			}
		var opcode = effect_data[2]  # e.g., 3
		var payload = effect_data[3] # e.g., [0, 0, 0, 0, 10, 0, 0]
		
		# Check if our "mask file" knows this opcode
		if passive_schema.has(str(opcode)):
			var schema: Dictionary = passive_schema.get(str(opcode), {})
			parsed_effect["type"] = schema["type"]

			# Map the payload to the keys
			for i in range(min(schema["keys"].size(), payload.size())):
				var key = schema["keys"][i]
				var value = payload[i]
				
				# Drop zeros and unknowns for a perfectly clean output!
				if value != 0 and key != "UNKNOWN" and key != "???" and key != "":
					parsed_effect["effect"][key] = value
					
			parsed_action.get("effects").append(parsed_effect)
		else:
			push_warning("OpcodeParser: Unknown passive opcode: " + str(opcode))
			
	return parsed_action

static func parse_skill_improved(skill_data: Dictionary, skill_schema: Dictionary) -> Dictionary:
	
	var parsed_action: Dictionary = {
		"element_inflict": skill_data.get("element_inflict", []),
		"effects": []
	}
	var effects_raw: Array = skill_data.get("effects_raw", [])
	var attack_damage: Array = skill_data.get("attack_damage", [])
	var attack_frames: Array = skill_data.get("attack_frames", [])
	
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
		
		var parsed_effect: Dictionary = {
			"type": "",
			"target_area": target_area,
			"target_type": target_type,
			"attack_damage": current_attack_damage,
			"attack_frames": current_attack_frames,
			"effect": {}
			}
		idx = idx + 1
	
		var opcode = effect_data[2]  # e.g., 3
		var payload = effect_data[3] # e.g., [0, 0, 0, 0, 10, 0, 0]
		
		# Check if our "mask file" knows this opcode
		if skill_schema.has(str(opcode)):
			var schema: Dictionary = skill_schema.get(str(opcode), {})
			parsed_effect["type"] = schema["type"]

			# Map the payload to the keys
			for i in range(min(schema["keys"].size(), payload.size())):
				var key = schema["keys"][i]
				var value = payload[i]
				
				# Drop zeros and unknowns for a perfectly clean output!
				if value != 0 and key != "UNKNOWN":
					parsed_effect["effect"][key] = value
					
			parsed_action.get("effects").append(parsed_effect)
		else:
			push_warning("OpcodeParser: Unknown skill opcode: " + str(opcode))
			
	return parsed_action
