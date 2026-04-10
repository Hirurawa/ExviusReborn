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
	
	var unit_id = unit_instance.get("unit_id", "")
	var unit_data = DataManager.game_data_units.get(unit_id, {})
	var rarity = int(unit_instance.get("current_rarity", 1))
	var level = int(unit_instance.get("level", 1))
	var max_level = RARITY_MAX_LEVELS.get(rarity, 15)
	
	var entries = unit_data.get("entries", {})
	var entry = entries.get(str(unit_id), entries.get(str(rarity), {}))
	
	for key in entries.keys():
		if entries[key].get("rarity") == rarity:
			entry = entries[key]
			break
			
	var base_stats = entry.get("stats", {})
	
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
			var stat_arr = base_stats.get(stat_name, [0, 0])
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
	
	var equipment = unit_instance.get("equipment", {})
	for slot_id in equipment:
		var item_id = equipment[slot_id]
		if item_id != null and item_id != "":
			var item_data = DataManager.game_data_equipment.get(item_id, {})
			var item_stats = item_data.get("stats", {})
			
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
