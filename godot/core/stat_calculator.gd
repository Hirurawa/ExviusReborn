extends Node

const CORE_STATS = ["HP", "MP", "ATK", "DEF", "MAG", "SPR"]
const ELEMENTS = ["FIRE", "ICE", "LIGHTNING", "WATER", "WIND", "EARTH", "LIGHT", "DARK"]
const STATUSES = ["POISON", "BLIND", "SLEEP", "SILENCE", "PARALYSIS", "CONFUSION", "DISEASE", "PETRIFY"]

const RESIST_KEY_ALIASES: Dictionary = {
	"PARALYZE": "PARALYSIS",
	"PETRIFICATION": "PETRIFY"
}

const RARITY_MAX_LEVELS: Dictionary = {
	1: 15,
	2: 30,
	3: 40,
	4: 60,
	5: 80,
	6: 100,
	7: 120
}

func _apply_parsed_passives(parsed_effects: Array) -> void:
	for effect in parsed_effects:
		# Convert "STAT_BOOST_PCT" to "_apply_stat_boost_pct"
		var func_name = "_apply_" + effect.type.to_lower()
	
	# Check if we have built the logic for this mechanic yet
		if has_method(func_name):
			# Dynamically call the function and pass the effect data
			call(func_name, effect.effect)
		else:
			push_warning("StatCalculator: No logic built for passive type: " + effect.type)

func _normalize_resist_key(raw_key: String) -> String:
	var normalized = raw_key.strip_edges().to_upper().replace(" ", "_").replace("-", "_")
	return RESIST_KEY_ALIASES.get(normalized, normalized)

func _accumulate_named_resists(source: Variant, targets: Dictionary, ordered_keys: Array) -> void:
	if source == null:
		return

	if typeof(source) == TYPE_DICTIONARY:
		for key in source.keys():
			var normalized_key = _normalize_resist_key(str(key))
			if targets.has(normalized_key):
				var resist_value = source[key]
				if typeof(resist_value) in [TYPE_INT, TYPE_FLOAT]:
					targets[normalized_key] += int(resist_value)
			else:
				push_warning("StatCalculator: Unknown resist key in equipment stats -> " + str(key))
	elif typeof(source) == TYPE_ARRAY:
		for i in range(min(source.size(), ordered_keys.size())):
			var target_key = ordered_keys[i]
			var resist_value = source[i]
			if typeof(resist_value) in [TYPE_INT, TYPE_FLOAT]:
				targets[target_key] += int(resist_value)

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
		"skills": {
			"magic": [],
			"ability": [],
			"passive": []
		},
		"passive_effects": []
	}
	
	var pct_mods = {}
	for stat in CORE_STATS:
		pct_mods[stat] = 0

	var element_resists = {}
	for el in ELEMENTS:
		element_resists[el] = 0

	var status_resists = {}
	for st in STATUSES:
		status_resists[st] = 0

	assert(unit_instance.has("current_rarity"), "CRITICAL ERROR: unit_instance is missing current_rarity!")
	if not unit_instance.has("current_rarity"): push_error("CRITICAL ERROR: unit_instance is missing current_rarity!")
	var rarity = int(unit_instance["current_rarity"])

	assert(unit_instance.has("level"), "CRITICAL ERROR: unit_instance is missing level!")
	if not unit_instance.has("level"): push_error("CRITICAL ERROR: unit_instance is missing level!")
	var level = int(unit_instance["level"])

	assert(RARITY_MAX_LEVELS.has(rarity), "CRITICAL ERROR: RARITY_MAX_LEVELS is missing rarity: " + str(rarity))
	if not RARITY_MAX_LEVELS.has(rarity): push_error("CRITICAL ERROR: RARITY_MAX_LEVELS is missing rarity: " + str(rarity))
	var max_level = RARITY_MAX_LEVELS[rarity]
	
	# Seed innate resistances into pools
	var innate_elements = unit_instance.get("element_resist", [])
	if typeof(innate_elements) == TYPE_ARRAY:
		# Use min() to prevent out-of-bounds crashes if the datamine array is too long/short
		for i in range(min(innate_elements.size(), ELEMENTS.size())):
			var element_name = ELEMENTS[i]
			element_resists[element_name] += innate_elements[i]

	var innate_statuses = unit_instance.get("status_resist", [])
	if typeof(innate_statuses) == TYPE_ARRAY:
		for i in range(min(innate_statuses.size(), STATUSES.size())):
			var status_name = STATUSES[i]
			status_resists[status_name] += innate_statuses[i]
	
	var base_calculated = {
		"HP": 0.0,
		"MP": 0.0,
		"ATK": 0.0,
		"DEF": 0.0,
		"MAG": 0.0,
		"SPR": 0.0
	}
	
	var base_stats = unit_instance.get("stats", {})
	
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
		if typeof(skill.get("rarity", 999)) != TYPE_STRING:
			var req_rarity = skill.get("rarity", 999)
			if rarity > int(req_rarity) or (rarity == req_rarity and level >= skill.get("level", 999)):
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

			_accumulate_named_resists(item_stats.get("element_resist", null), element_resists, ELEMENTS)
			_accumulate_named_resists(item_stats.get("status_resist", null), status_resists, STATUSES)
				
			var equip_skills = item_data.get("skills", [])
			if equip_skills != null:
				for skill_id in equip_skills:
					raw_skills.append({"id": skill_id, "source": "Equip"})
				
	# Categorize skills
	for raw_skill in raw_skills:
		var skill_id_str = str(raw_skill["id"])
		var skill_entry = {"id": int(raw_skill["id"]), "source": raw_skill["source"]}
		
		if DataManager.game_data_skills_magic.has(skill_id_str):
			final_profile["skills"]["magic"].append(skill_entry)
		elif DataManager.game_data_skills_ability.has(skill_id_str):
			final_profile["skills"]["ability"].append(skill_entry)
		elif DataManager.game_data_skills_passive.has(skill_id_str):
			final_profile["skills"]["passive"].append(skill_entry)
			var skill_data = DataManager.game_data_skills_passive.get(skill_id_str)
			var parsed_passive = DataManager.parse_passive_effects(skill_data)
			final_profile["passive_effects"].append_array(parsed_passive.get("effects", []))
			for e in parsed_passive.get("effects", []):
				if(e.get("type") == "STAT_BOOST_PCT"):
					for stat in e.get("effect").keys():
						pct_mods[stat] = e.get("effect")[stat]
			
	# TODO: Parse effects_raw for pct_mods here

	var active_buffs = {}
	var active_debuffs = {}

	for effect in unit_instance.get("active_effects", []):
		var effect_type: String = str(effect.get("type", "")).to_lower()
		if effect_type not in ["buff", "debuff"]:
			continue
		var modifiers: Dictionary = effect.get("params", {})
		for key in modifiers.keys():
			var val = modifiers[key]

			# If it's a positive buff, keep the highest value
			if val > 0:
				active_buffs[key] = max(active_buffs.get(key, 0), val)
			# If it's a negative debuff, keep the lowest (most negative) value
			elif val < 0:
				active_debuffs[key] = min(active_debuffs.get(key, 0), val)

	var all_active_mods = active_buffs.duplicate()
	for key in active_debuffs.keys():
		all_active_mods[key] = all_active_mods.get(key, 0) + active_debuffs[key]

	for key in all_active_mods.keys():
		var val = all_active_mods[key]
		if pct_mods.has(key):
			pct_mods[key] += val
		elif element_resists.has(key):
			element_resists[key] += val
		elif status_resists.has(key):
			status_resists[key] += val
		else:
			push_warning("StatCalculator: Unhandled modifier -> " + key)

	for stat_name in final_profile["stats"].keys():
		var base = base_calculated.get(stat_name, 0.0)
		var total_flat = flat_mods.get(stat_name, 0)
		
		var final_val = (base * (1.0 + (float(pct_mods.get(stat_name, 0)) / 100.0))) + total_flat
		final_profile["stats"][stat_name] = int(round(final_val))
		
	final_profile["element_resist"] = element_resists
	final_profile["status_resist"] = status_resists

	return final_profile
