extends Node

const RARITY_MAX_LEVELS: Dictionary = {
	1: 15,
	2: 30,
	3: 40,
	4: 60,
	5: 80,
	6: 100,
	7: 120
}

func calculate_final_stats(unit_instance: Dictionary) -> Dictionary:
	var final_profile = {
		"stats": {
			"HP": 0,
			"MP": 0,
			"ATK": 0,
			"DEF": 0,
			"MAG": 0,
			"SPR": 0
		},
		"element_resist": {},
		"status_resist": {},
		"active_skills": [],
		"passive_skills": []
	}
	
	assert(unit_instance.has("current_rarity"), "CRITICAL ERROR: unit_instance is missing current_rarity!")
	if not unit_instance.has("current_rarity"): push_error("CRITICAL ERROR: unit_instance is missing current_rarity!")
	var rarity = int(unit_instance["current_rarity"])

	assert(unit_instance.has("level"), "CRITICAL ERROR: unit_instance is missing level!")
	if not unit_instance.has("level"): push_error("CRITICAL ERROR: unit_instance is missing level!")
	var level = int(unit_instance["level"])

	assert(RARITY_MAX_LEVELS.has(rarity), "CRITICAL ERROR: RARITY_MAX_LEVELS is missing rarity: " + str(rarity))
	if not RARITY_MAX_LEVELS.has(rarity): push_error("CRITICAL ERROR: RARITY_MAX_LEVELS is missing rarity: " + str(rarity))
	var max_level = RARITY_MAX_LEVELS[rarity]
			
	var base_stats = unit_instance.get("stats", {})
	
	# Seed innate resistances
	var _elem_res = base_stats.get("element_resist")
	final_profile["element_resist"] = _elem_res.duplicate() if typeof(_elem_res) == TYPE_DICTIONARY else {}
	var _stat_res = base_stats.get("status_resist")
	final_profile["status_resist"] = _stat_res.duplicate() if typeof(_stat_res) == TYPE_DICTIONARY else {}

	var base_calculated = {
		"HP": 0.0,
		"MP": 0.0,
		"ATK": 0.0,
		"DEF": 0.0,
		"MAG": 0.0,
		"SPR": 0.0
	}
	
	if not base_stats.is_empty():
		for stat_name in final_profile["stats"].keys():
			assert(base_stats.has(stat_name), "CRITICAL ERROR: base_stats is missing " + stat_name + "!")
			if not base_stats.has(stat_name): push_error("CRITICAL ERROR: base_stats is missing " + stat_name + "!")
			var stat_arr = base_stats[stat_name]
			if stat_arr.size() >= 2:
				var min_stat = stat_arr[0]
				var max_stat = stat_arr[1]
				var current_stat = min_stat
				if max_level > 1:
					current_stat = min_stat + (level - 1) * float(max_stat - min_stat) / (max_level - 1)
				base_calculated[stat_name] = round(current_stat)

	var raw_skills = []
	
	# Harvest innate skills
	var innate_skills = unit_instance.get("skills", [])
	for skill in innate_skills:
		if skill.get("level", 999) <= level and skill.get("rarity", 999) <= rarity:
			raw_skills.append({"id": skill.get("id"), "source": "Trait"})

	var flat_mods = {
		"HP": 0,
		"MP": 0,
		"ATK": 0,
		"DEF": 0,
		"MAG": 0,
		"SPR": 0
	}
	
	assert(unit_instance.has("equipment"), "CRITICAL ERROR: unit_instance is missing equipment!")
	if not unit_instance.has("equipment"): push_error("CRITICAL ERROR: unit_instance is missing equipment!")
	var equipment = unit_instance["equipment"]
	for slot_id in equipment:
		var item_id = equipment[slot_id]
		if item_id != null and item_id != "":
			var template_id = DataManager.get_equipment_template_id(item_id)
			assert(DataManager.game_data_equipment.has(template_id), "CRITICAL ERROR: game_data_equipment is missing template_id: " + str(template_id))
			if not DataManager.game_data_equipment.has(template_id): push_error("CRITICAL ERROR: game_data_equipment is missing template_id: " + str(template_id))
			var item_data = DataManager.game_data_equipment[template_id]

			assert(item_data.has("stats"), "CRITICAL ERROR: item_data is missing stats!")
			if not item_data.has("stats"): push_error("CRITICAL ERROR: item_data is missing stats!")
			var item_stats = item_data["stats"]
			
			for stat_name in final_profile["stats"].keys():
				flat_mods[stat_name] += item_stats.get(stat_name, 0)

			var equip_skills = item_data.get("skills", [])
			for skill_id in equip_skills:
				raw_skills.append({"id": skill_id, "source": "Equip"})

	# Categorize skills
	for raw_skill in raw_skills:
		var skill_id_str = str(raw_skill["id"])
		var skill_entry = {"id": int(raw_skill["id"]), "source": raw_skill["source"]}

		if DataManager.game_data_skills_magic.has(skill_id_str):
			final_profile["active_skills"].append(skill_entry)
		elif DataManager.game_data_skills_ability.has(skill_id_str):
			final_profile["active_skills"].append(skill_entry)
		elif DataManager.game_data_skills_passive.has(skill_id_str):
			final_profile["passive_skills"].append(skill_entry)

	# TODO: Parse effects_raw for pct_mods here

	for stat_name in final_profile["stats"].keys():
		var base = base_calculated[stat_name]
		var total_flat = flat_mods[stat_name]
		
		var final_val = base + total_flat
		final_profile["stats"][stat_name] = int(round(final_val))
		
	return final_profile
