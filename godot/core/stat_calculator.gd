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
	var final_stats = {
		"HP": 0,
		"MP": 0,
		"ATK": 0,
		"DEF": 0,
		"MAG": 0,
		"SPR": 0
	}
	
	assert(unit_instance.has("unit_id"), "CRITICAL ERROR: unit_instance is missing unit_id!")
	if not unit_instance.has("unit_id"): push_error("CRITICAL ERROR: unit_instance is missing unit_id!")
	var unit_id = str(unit_instance["unit_id"])
	
	assert(DataManager.game_data_units.has(unit_id), "CRITICAL ERROR: game_data_units is missing unit_id: " + str(unit_id))
	if not DataManager.game_data_units.has(unit_id): push_error("CRITICAL ERROR: game_data_units is missing unit_id: " + str(unit_id))
	var unit_data = DataManager.game_data_units[unit_id]

	assert(unit_instance.has("current_rarity"), "CRITICAL ERROR: unit_instance is missing current_rarity!")
	if not unit_instance.has("current_rarity"): push_error("CRITICAL ERROR: unit_instance is missing current_rarity!")
	var rarity = int(unit_instance["current_rarity"])

	assert(unit_instance.has("level"), "CRITICAL ERROR: unit_instance is missing level!")
	if not unit_instance.has("level"): push_error("CRITICAL ERROR: unit_instance is missing level!")
	var level = int(unit_instance["level"])

	assert(RARITY_MAX_LEVELS.has(rarity), "CRITICAL ERROR: RARITY_MAX_LEVELS is missing rarity: " + str(rarity))
	if not RARITY_MAX_LEVELS.has(rarity): push_error("CRITICAL ERROR: RARITY_MAX_LEVELS is missing rarity: " + str(rarity))
	var max_level = RARITY_MAX_LEVELS[rarity]

	assert(unit_data.has("entries"), "CRITICAL ERROR: unit_data is missing entries!")
	if not unit_data.has("entries"): push_error("CRITICAL ERROR: unit_data is missing entries!")
	var entries = unit_data["entries"]

	var entry = {}
	if entries.has(str(unit_id)):
		entry = entries[str(unit_id)]
	elif entries.has(str(rarity)):
		entry = entries[str(rarity)]
	
	for key in entries.keys():
		assert(entries[key].has("rarity"), "CRITICAL ERROR: entry in entries is missing rarity!")
		if not entries[key].has("rarity"): push_error("CRITICAL ERROR: entry in entries is missing rarity!")
		if entries[key]["rarity"] == rarity:
			entry = entries[key]
			break
			
	assert(entry.has("stats"), "CRITICAL ERROR: entry is missing stats!")
	if not entry.has("stats"): push_error("CRITICAL ERROR: entry is missing stats!")
	var base_stats = entry["stats"]
	
	var base_calculated = {
		"HP": 0.0,
		"MP": 0.0,
		"ATK": 0.0,
		"DEF": 0.0,
		"MAG": 0.0,
		"SPR": 0.0
	}
	
	if not base_stats.is_empty():
		for stat_name in final_stats.keys():
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

	var pct_mods = {
		"HP": 0,
		"MP": 0,
		"ATK": 0,
		"DEF": 0,
		"MAG": 0,
		"SPR": 0
	}
	
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
			
			for stat_name in final_stats.keys():
				flat_mods[stat_name] += item_stats.get(stat_name, 0)
				pct_mods[stat_name] += item_stats.get(stat_name + "_pct", 0)

	for stat_name in final_stats.keys():
		var base = base_calculated[stat_name]
		var total_pct = pct_mods[stat_name]
		var total_flat = flat_mods[stat_name]
		
		var final_val = base + (base * float(total_pct) / 100.0) + total_flat
		final_stats[stat_name] = int(round(final_val))
		
	return final_stats
