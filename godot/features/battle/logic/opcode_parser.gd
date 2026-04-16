class_name OpcodeParser

static func parse_skill_improved(skill_data: Dictionary) -> Dictionary:
	var file = "c:\\Workspaces\\GachaTest\\godot\\features\\battle\\logic\\skill_schema.json"
	var json_as_text = FileAccess.get_file_as_string(file)
	var SKILL_SCHEMA = JSON.parse_string(json_as_text)
	
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
		if idx < attack_damage.size():
			current_attack_damage = attack_damage[idx]
			
		var current_attack_frames: Array = []
		if idx < attack_frames.size():
			current_attack_frames = attack_frames[idx]
		
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
		if SKILL_SCHEMA.has(str(opcode)):
			var schema = SKILL_SCHEMA.get(str(opcode))
			parsed_effect["type"] = schema["type"]

			# Map the payload to the keys (Your exact idea)
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

static func parse_skill(skill_data: Dictionary) -> Dictionary:
	var parsed_action: Dictionary = {
		"element_inflict": skill_data.get("element_inflict", []),
		"effects": []
	}

	var effects_raw: Array = skill_data.get("effects_raw", [])
	var i = 0
	for effect in effects_raw:
		if typeof(effect) != TYPE_ARRAY or effect.size() < 4:
			continue

		var target_area: int = int(effect[0])
		var target_type: int = int(effect[1])
		var opcode_id: int = int(effect[2])
		var parameters: Array = effect[3]
		
		var attack_damage: Array = skill_data.get("attack_damage", [])
		var attack_frames: Array = skill_data.get("attack_frames", [])
		
		if(attack_damage.size() >= i): attack_damage = attack_damage[i]
		if(attack_frames.size() >= i): attack_frames = attack_frames[i]
		
		var parsed_effect: Dictionary = {"target_area": target_area, "target_type": target_type, "attack_damage": attack_damage, "attack_frames": attack_frames}
		
		match opcode_id:
			2: # HEAL
				if typeof(parameters) == TYPE_ARRAY and parameters.size() > 3:
					parsed_effect["type"] = "HEAL"
					parsed_effect["base_heal"] =  float(parameters[2])
					parsed_effect["modifier"] = float(parameters[3]) / 100.0
					parsed_action["effects"].append(parsed_effect)
			3: # STAT_BUFF
				if typeof(parameters) == TYPE_ARRAY and parameters.size() > 4:
					parsed_effect["type"] = "STAT_BUFF"
					parsed_effect["atk_buff"] = int(parameters[0])
					parsed_effect["def_buff"] = int(parameters[1])
					parsed_effect["mag_buff"] = int(parameters[2])
					parsed_effect["spr_buff"] = int(parameters[3])
					parsed_effect["duration"] = int(parameters[4])
					
					# Optional: Remove empty buffs to keep the dictionary clean
					for stat in ["atk_buff", "def_buff", "mag_buff", "spr_buff"]:
						if parsed_effect[stat] == 0:
							parsed_effect.erase(stat)
							
					parsed_action["effects"].append(parsed_effect)
			4: # REVIVE
				if typeof(parameters) == TYPE_ARRAY and parameters.size() > 0:
					parsed_effect["type"] = "REVIVE"
					parsed_effect["hp_percent"] = int(parameters[0])
					parsed_action["effects"].append(parsed_effect)
			5: # CURE_STATUS
				if typeof(parameters) == TYPE_ARRAY:
					parsed_effect["type"] = "CURE_STATUS"
					var cures: Array[String] = []
					
					# Loop through the shopping list of IDs
					for ailment_id in parameters:
						match int(ailment_id):
							1: cures.append("POISON")
							2: cures.append("BLIND")
							3: cures.append("SLEEP")
							4: cures.append("SILENCE")
							5: cures.append("PARALYZE")
							6: cures.append("CONFUSION")
							7: cures.append("DISEASE")
							8: cures.append("PETRIFY")
					
					parsed_effect["cures"] = cures
					parsed_action["effects"].append(parsed_effect)
			6: # INFLICT_STATUS
				if typeof(parameters) == TYPE_ARRAY and parameters.size() >= 8:
					parsed_effect["type"] = "INFLICT_STATUS"
					var inflictions: Dictionary = {}
					
					# Map the exact same 8 ailments as Opcode 5, but storing the % chance
					if int(parameters[0]) > 0: inflictions["POISON"] = int(parameters[0])
					if int(parameters[1]) > 0: inflictions["BLIND"] = int(parameters[1])
					if int(parameters[2]) > 0: inflictions["SLEEP"] = int(parameters[2])
					if int(parameters[3]) > 0: inflictions["SILENCE"] = int(parameters[3])
					if int(parameters[4]) > 0: inflictions["PARALYZE"] = int(parameters[4])
					if int(parameters[5]) > 0: inflictions["CONFUSION"] = int(parameters[5])
					if int(parameters[6]) > 0: inflictions["DISEASE"] = int(parameters[6])
					if int(parameters[7]) > 0: inflictions["PETRIFY"] = int(parameters[7])
					
					parsed_effect["inflictions"] = inflictions
					parsed_action["effects"].append(parsed_effect)
			7: # RESIST_STATUS
				if typeof(parameters) == TYPE_ARRAY and parameters.size() >= 10:
					parsed_effect["type"] = "RESIST_STATUS"
					parsed_effect["duration"] = int(parameters[9])
					
					var resistances: Dictionary = {}
					
					# Map the exact same 8 ailments, storing the % resistance buff
					if int(parameters[0]) > 0: resistances["POISON"] = int(parameters[0])
					if int(parameters[1]) > 0: resistances["BLIND"] = int(parameters[1])
					if int(parameters[2]) > 0: resistances["SLEEP"] = int(parameters[2])
					if int(parameters[3]) > 0: resistances["SILENCE"] = int(parameters[3])
					if int(parameters[4]) > 0: resistances["PARALYZE"] = int(parameters[4])
					if int(parameters[5]) > 0: resistances["CONFUSION"] = int(parameters[5])
					if int(parameters[6]) > 0: resistances["DISEASE"] = int(parameters[6])
					if int(parameters[7]) > 0: resistances["PETRIFY"] = int(parameters[7])
					
					parsed_effect["resistances"] = resistances
					parsed_action["effects"].append(parsed_effect)
			8: # REGEN_HP
				if typeof(parameters) == TYPE_ARRAY and parameters.size() >= 4:
					# Index 1 is usually 1 for HP, let's verify it just in case
					if int(parameters[1]) == 1:
						parsed_effect["type"] = "REGEN_HP"
						parsed_effect["modifier"] = float(parameters[0]) / 100.0
						parsed_effect["base_heal"] = float(parameters[2])
						parsed_effect["duration"] = int(parameters[3])
						parsed_action["effects"].append(parsed_effect)
			9: # PERCENT_DAMAGE (Gravity)
				if typeof(parameters) == TYPE_ARRAY and parameters.size() >= 3:
					parsed_effect["type"] = "PERCENT_DAMAGE"
					parsed_effect["hp_percent_loss"] = float(parameters[0]) / 100.0
					parsed_effect["success_rate"] = int(parameters[2])
					parsed_action["effects"].append(parsed_effect)
			10: # MP_DRAIN
				if typeof(parameters) == TYPE_ARRAY and parameters.size() >= 1:
					parsed_effect["type"] = "MP_DRAIN"
					parsed_effect["modifier"] = float(parameters[0]) / 100.0
					
					# We capture the success/conversion rate just in case we need it later
					if parameters.size() >= 3:
						parsed_effect["success_rate"] = int(parameters[2])
					
					parsed_action["effects"].append(parsed_effect)
			13: # DELAYED_ATTACK
				if typeof(parameters) == TYPE_ARRAY and parameters.size() >= 6:
					parsed_effect["type"] = "DELAYED_ATTACK"
					parsed_effect["delay_turns"] = int(parameters[3])
					parsed_effect["hidden_skill_id"] = str(parameters[4])
					parsed_effect["modifier"] = float(parameters[5]) / 100.0
					parsed_action["effects"].append(parsed_effect)
			15: # MAGIC_DAMAGE
				if typeof(parameters) == TYPE_ARRAY and parameters.size() > 5:
					var modifier: float = float(parameters[5]) / 100.0
					parsed_effect["type"] = "MAGIC_DAMAGE"
					parsed_effect["modifier"] = modifier
					parsed_action["effects"].append(parsed_effect)
			17: # RESTORE_MP
				if typeof(parameters) == TYPE_ARRAY and parameters.size() >= 1:
					parsed_effect["type"] = "RESTORE_MP"
					parsed_effect["base_mp"] = int(parameters[0])
					parsed_action["effects"].append(parsed_effect)
			18: # PHYSICAL_MITIGATION
				if typeof(parameters) == TYPE_ARRAY and parameters.size() >= 2:
					parsed_effect["type"] = "PHYSICAL_MITIGATION"
					parsed_effect["mitigation_percent"] = float(parameters[0]) / 100.0
					parsed_effect["duration"] = int(parameters[1])
					parsed_action["effects"].append(parsed_effect)
			19: # MAGIC_MITIGATION
				if typeof(parameters) == TYPE_ARRAY and parameters.size() >= 2:
					parsed_effect["type"] = "MAGIC_MITIGATION"
					parsed_effect["mitigation_percent"] = float(parameters[0]) / 100.0
					parsed_effect["duration"] = int(parameters[1])
					parsed_action["effects"].append(parsed_effect)
			24: # STAT_DEBUFF
				if typeof(parameters) == TYPE_ARRAY and parameters.size() > 4:
					parsed_effect["type"] = "STAT_DEBUFF"
					
					# We keep the negative integers exactly as they are from the JSON
					parsed_effect["atk_debuff"] = int(parameters[0])
					parsed_effect["def_debuff"] = int(parameters[1])
					parsed_effect["mag_debuff"] = int(parameters[2])
					parsed_effect["spr_debuff"] = int(parameters[3])
					parsed_effect["duration"] = int(parameters[4])
					
					# Optional: Remove empty debuffs to keep the dictionary clean
					for stat in ["atk_debuff", "def_debuff", "mag_debuff", "spr_debuff"]:
						if parsed_effect[stat] == 0:
							parsed_effect.erase(stat)
							
					parsed_action["effects"].append(parsed_effect)
			25: # HP_DRAIN
				if typeof(parameters) == TYPE_ARRAY and parameters.size() >= 2:
					parsed_effect["type"] = "HP_DRAIN"
					parsed_effect["drain_percent"] = float(parameters[0]) / 100.0
					parsed_effect["modifier"] = float(parameters[1]) / 100.0
					
					if parameters.size() >= 3:
						parsed_effect["success_rate"] = int(parameters[2])
					
					parsed_action["effects"].append(parsed_effect)
			27: # AUTO_REVIVE
				if typeof(parameters) == TYPE_ARRAY and parameters.size() >= 2:
					parsed_effect["type"] = "AUTO_REVIVE"
					parsed_effect["hp_percent"] = int(parameters[0])
					parsed_effect["duration"] = int(parameters[1])
					parsed_action["effects"].append(parsed_effect)
			30: # REGEN_MP
				if typeof(parameters) == TYPE_ARRAY and parameters.size() >= 4:
					if int(parameters[1]) == 1:
						parsed_effect["type"] = "REGEN_MP"
						parsed_effect["modifier"] = float(parameters[0]) / 100.0
						parsed_effect["base_mp"] = float(parameters[2])
						parsed_effect["duration"] = int(parameters[3])
						parsed_action["effects"].append(parsed_effect)
			33: # RESIST_ELEMENT
				if typeof(parameters) == TYPE_ARRAY and parameters.size() >= 10:
					parsed_effect["type"] = "RESIST_ELEMENT"
					parsed_effect["duration"] = int(parameters[9])
					
					var resistances: Dictionary = {}
					
					# Map the exact same 8 element, storing the % resistance buff
					if int(parameters[0]) != 0: resistances["FIRE"] = int(parameters[0])
					if int(parameters[1]) != 0: resistances["ICE"] = int(parameters[1])
					if int(parameters[2]) != 0: resistances["LIGHTNING"] = int(parameters[2])
					if int(parameters[3]) != 0: resistances["WATER"] = int(parameters[3])
					if int(parameters[4]) != 0: resistances["WIND"] = int(parameters[4])
					if int(parameters[5]) != 0: resistances["EARTH"] = int(parameters[5])
					if int(parameters[6]) != 0: resistances["LIGHT"] = int(parameters[6])
					if int(parameters[7]) != 0: resistances["DARK"] = int(parameters[7])
					
					parsed_effect["resistances"] = resistances
					parsed_action["effects"].append(parsed_effect)
			35: # KO
				parsed_effect["type"] = "KO"
				parsed_effect["success_rate"] = int(parameters[0])
				parsed_action["effects"].append(parsed_effect)
			41: # FIXED_DAMAGE
				parsed_effect["type"] = "FIXED_DAMAGE"
				parsed_effect["damage"] = int(parameters[0])
				parsed_action["effects"].append(parsed_effect)
			47: # LIBRA
				print()
			54: # EVASION
				print()
			59: # DISPEL
				print()
			63: # LB_FILL_RATE
				parsed_effect["type"] = "LB_FILL_RATE"
				parsed_effect["fill_rate"] = float(parameters[0]) / 100.0
				parsed_effect["duration"] = int(parameters[1])
				parsed_action["effects"].append(parsed_effect)
			64: # PERCENT_RESTORE
				print()
			70: # IGNORE_REFLECT_MAGIC
				print()
			72: # CONSECUTIVE_INCREASE_MAGIC
				print()
			86: # REFLECT
				print()
			88: # INFLICT_STOP
				print()
			89: # RESIST_STOP
				print()
			95: # ADD_ELEMENT_TO_PHYSICAL_ATTACK
				print()
			101: # REDUCE_DAMAGE_TAKEN
				print()
			103: # MAGIC_LIGHT
				print()
			111: # REMOVE_DEBUFF
				print()
			120: # INCREASE_LB_DAMAGE
				print()
			125: # INCREASE_LB_GAUGE
				print()
			127: # SHIELD
				print()
			
			_: # Unhandled Opcodes
				print("OpcodeParser: Unhandled Opcode ", opcode_id, " in skill ", skill_data.get("name", "Unknown"))

	return parsed_action
