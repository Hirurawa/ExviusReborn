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

		var parsed_effect: Dictionary = {}
		
		match opcode_id:
			2: # HEAL
				if typeof(parameters) == TYPE_ARRAY and parameters.size() > 3:
					parsed_action["effects"].append({
						"type": "HEAL",
						"base_heal": float(parameters[2]),
						"modifier": float(parameters[3]) / 100.0
					})
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
					parsed_action["effects"].append({
						"type": "MAGIC_DAMAGE",
						"modifier": modifier
					})
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
			
			_: # Unhandled Opcodes
				print("OpcodeParser: Unhandled Opcode ", opcode_id, " in skill ", skill_data.get("name", "Unknown"))

	return parsed_action
