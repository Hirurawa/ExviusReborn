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

func _resolve_esper_rank_max_level(entry: Dictionary) -> int:
	var cp_pattern_value: Variant = entry.get("cp_pattern", [])
	if cp_pattern_value is Array:
		var cp_pattern: Array = cp_pattern_value
		if not cp_pattern.is_empty():
			return maxi(1, cp_pattern.size())
	return 1

func _interpolate_esper_stat_value(value: Variant, level: int, rank_max_level: int) -> int:
	if value is Array:
		var values: Array = value
		if values.is_empty():
			return 0
		if values.size() == 1:
			return int(values[0])

		var min_value: float = float(values[0])
		var max_value: float = float(values[1])
		var clamped_max_level: int = maxi(1, rank_max_level)
		var clamped_level: int = clampi(level, 1, clamped_max_level)
		if clamped_max_level <= 1:
			return int(round(min_value))

		var interpolated: float = min_value + float(clamped_level - 1) * (max_value - min_value) / float(clamped_max_level - 1)
		return int(round(interpolated))

	return int(value)

func _extract_esper_stats_for_level_and_rank(summon_data: Dictionary, rank: int, level: int) -> Dictionary:
	var entries_value: Variant = summon_data.get("entries", [])
	if not (entries_value is Array):
		return {}

	var entries: Array = entries_value
	if entries.is_empty():
		return {}

	var rank_index: int = clampi(rank - 1, 0, entries.size() - 1)
	var selected_entry: Variant = entries[rank_index]
	if not (selected_entry is Dictionary):
		return {}
	var entry_data: Dictionary = selected_entry
	var rank_max_level: int = _resolve_esper_rank_max_level(entry_data)

	var stats_value: Variant = entry_data.get("stats", {})
	if not (stats_value is Dictionary):
		return {}

	var raw_stats: Dictionary = stats_value
	var resolved_stats: Dictionary = {}
	for stat_name in CORE_STATS:
		resolved_stats[stat_name] = _interpolate_esper_stat_value(raw_stats.get(stat_name, 0), level, rank_max_level)
	return resolved_stats

func _resolve_active_party_slot_for_unit(unit_instance: Dictionary) -> int:
	var instance_id: String = str(unit_instance.get("instance_id", "")).strip_edges()
	if instance_id == "":
		return -1

	var active_party: Dictionary = PartyService.get_active_party()
	if active_party.is_empty():
		return -1

	var unit_slots: Variant = active_party.get("units", [])
	if not (unit_slots is Array):
		return -1

	var slots: Array = unit_slots
	for i in range(slots.size()):
		if str(slots[i]) == instance_id:
			return i

	return -1

func _resolve_active_party_esper_id_for_unit(unit_instance: Dictionary) -> String:
	var unit_slot_index: int = _resolve_active_party_slot_for_unit(unit_instance)
	if unit_slot_index < 0:
		return ""

	var active_party: Dictionary = PartyService.get_active_party()
	if active_party.is_empty():
		return ""

	var party_espers: Variant = active_party.get("espers", [])
	if not (party_espers is Array):
		return ""

	var espers: Array = party_espers
	if unit_slot_index >= espers.size():
		return ""

	return str(espers[unit_slot_index]).strip_edges()

func _resolve_rank_skill_data_for_summon(summon_id: String, summon_data: Dictionary, rank: int) -> Dictionary:
	var skill_value: Variant = summon_data.get("skill", {})
	if not (skill_value is Dictionary):
		return {}

	var skill_data: Dictionary = skill_value
	if skill_data.is_empty():
		return {}

	var summon_numeric_id: int = int(summon_id)
	var expected_skill_id: String = "%d%02d" % [100 + summon_numeric_id, rank]
	var direct_match: Variant = skill_data.get(expected_skill_id, {})
	if direct_match is Dictionary:
		var direct_dict: Dictionary = direct_match
		if not direct_dict.is_empty():
			var with_id: Dictionary = direct_dict.duplicate(true)
			with_id["skill_id"] = expected_skill_id
			return with_id

	for key_value in skill_data.keys():
		var key: String = str(key_value)
		if key.ends_with(str(rank)):
			var rank_match: Variant = skill_data.get(key, {})
			if rank_match is Dictionary:
				var rank_dict: Dictionary = rank_match
				if not rank_dict.is_empty():
					var with_fallback_id: Dictionary = rank_dict.duplicate(true)
					with_fallback_id["skill_id"] = key
					return with_fallback_id

	return {}

func _get_esper_skill_text(skill_data: Dictionary, text_key: String) -> String:
	var strings_value: Variant = skill_data.get("strings", {})
	if not (strings_value is Dictionary):
		return ""

	var strings: Dictionary = strings_value
	var text_value: Variant = strings.get(text_key, [])
	if not (text_value is Array):
		return ""

	var localized_values: Array = text_value
	if localized_values.is_empty():
		return ""

	return str(localized_values[0])

func get_active_party_esper_rank_skill(unit_instance: Dictionary) -> Dictionary:
	var summon_id: String = _resolve_active_party_esper_id_for_unit(unit_instance)
	if summon_id == "":
		return {}
	if not StaticData.game_data_summons.has(summon_id):
		return {}

	var progression: Dictionary = EsperService.get_esper_progression(summon_id)
	var rank: int = maxi(1, int(progression.get("rank", 1)))
	var summon_data: Dictionary = StaticData.game_data_summons.get(summon_id, {})
	if summon_data.is_empty():
		return {}

	var rank_skill_data: Dictionary = _resolve_rank_skill_data_for_summon(summon_id, summon_data, rank)
	if rank_skill_data.is_empty():
		return {}

	var skill_id: String = str(rank_skill_data.get("skill_id", "")).strip_edges()
	if skill_id == "":
		return {}

	var normalized_skill_data: Dictionary = rank_skill_data.duplicate(true)
	var skill_name: String = _get_esper_skill_text(rank_skill_data, "name")
	var skill_description: String = _get_esper_skill_text(rank_skill_data, "desc")
	if skill_name != "":
		normalized_skill_data["name"] = skill_name
	if skill_description != "":
		normalized_skill_data["description"] = skill_description

	return {
		"summon_id": summon_id,
		"rank": rank,
		"skill_id": skill_id,
		"name": skill_name,
		"description": skill_description,
		"skill_data": normalized_skill_data
	}

func _collect_active_party_esper_unlocked_skills(unit_instance: Dictionary) -> Array:
	var unlocked_skill_ids: Array = []

	var summon_id: String = _resolve_active_party_esper_id_for_unit(unit_instance)
	if summon_id == "":
		return unlocked_skill_ids

	var progression: Dictionary = EsperService.get_esper_progression(summon_id)
	var unlocked_raw: Variant = progression.get("unlocked_skills", [])
	if not (unlocked_raw is Array):
		return unlocked_skill_ids

	for skill_id in unlocked_raw:
		var normalized_skill_id: String = str(skill_id).strip_edges()
		if normalized_skill_id == "":
			continue
		if not normalized_skill_id.is_valid_int():
			continue

		# Esper board progression can contain multiple reward types; only surface
		# skills that are represented in the shared magic/ability datasets.
		if StaticData.game_data_skills_magic.has(normalized_skill_id) or StaticData.game_data_skills_ability.has(normalized_skill_id):
			unlocked_skill_ids.append(int(normalized_skill_id))

	return unlocked_skill_ids

func _compute_active_party_esper_flat_bonus(unit_instance: Dictionary) -> Dictionary:
	var bonus: Dictionary = {}
	for stat_name in CORE_STATS:
		bonus[stat_name] = 0

	var summon_id: String = _resolve_active_party_esper_id_for_unit(unit_instance)
	if summon_id == "":
		return bonus
	if not StaticData.game_data_summons.has(summon_id):
		return bonus

	var progression: Dictionary = EsperService.get_esper_progression(summon_id)
	var rank: int = maxi(1, int(progression.get("rank", 1)))
	var level: int = maxi(1, int(progression.get("level", 1)))
	var summon_data: Dictionary = StaticData.game_data_summons.get(summon_id, {})
	var esper_stats: Dictionary = _extract_esper_stats_for_level_and_rank(summon_data, rank, level)
	var board_stat_bonus: Dictionary = EsperService.get_esper_board_stat_bonuses(summon_id)

	for stat_name in CORE_STATS:
		var esper_stat_value: float = float(esper_stats.get(stat_name, 0)) + float(board_stat_bonus.get(stat_name, 0))
		bonus[stat_name] = int(floor(esper_stat_value * 0.01))

	return bonus

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
			var template_id = InventoryService.get_equipment_template_id(item_id)
			var item_data: Dictionary = {}
			if StaticData.game_data_equipment.has(template_id):
				item_data = StaticData.game_data_equipment[template_id]
			elif StaticData.game_data_materia.has(template_id):
				item_data = StaticData.game_data_materia[template_id]
			else:
				push_error("CRITICAL ERROR: template_id not found in equipment or materia data: " + str(template_id))
				continue

			var item_stats: Dictionary = item_data.get("stats", {})

			for stat_name in final_profile["stats"].keys():
				flat_mods[stat_name] += item_stats.get(stat_name, 0)

			_accumulate_named_resists(item_stats.get("element_resist", null), element_resists, ELEMENTS)
			_accumulate_named_resists(item_stats.get("status_resist", null), status_resists, STATUSES)

			var equip_skills = item_data.get("skills", [])
			if equip_skills != null:
				for skill_id in equip_skills:
					raw_skills.append({"id": skill_id, "source": "Equip"})

	var esper_flat_bonus: Dictionary = _compute_active_party_esper_flat_bonus(unit_instance)
	for stat_name in CORE_STATS:
		flat_mods[stat_name] += int(esper_flat_bonus.get(stat_name, 0))

	var esper_unlocked_skills: Array = _collect_active_party_esper_unlocked_skills(unit_instance)
	for skill_id in esper_unlocked_skills:
		raw_skills.append({"id": skill_id, "source": "Esper"})
				
	# Categorize skills
	for raw_skill in raw_skills:
		var skill_id_str = str(raw_skill["id"])
		var skill_entry = {"id": int(raw_skill["id"]), "source": raw_skill["source"]}
		
		if StaticData.game_data_skills_magic.has(skill_id_str):
			final_profile["skills"]["magic"].append(skill_entry)
		elif StaticData.game_data_skills_ability.has(skill_id_str):
			final_profile["skills"]["ability"].append(skill_entry)
		elif StaticData.game_data_skills_passive.has(skill_id_str):
			final_profile["skills"]["passive"].append(skill_entry)
			var skill_data = StaticData.game_data_skills_passive.get(skill_id_str)
			var parsed_passive = SkillResolver.parse_passive_effects(skill_data)
			final_profile["passive_effects"].append_array(parsed_passive.get("effects", []))
			for e in parsed_passive.get("effects", []):
				if(e.get("type") == "STAT_BOOST_PCT"):
					for stat in e.get("effect").keys():
						pct_mods[stat] += e.get("effect")[stat]
				if(e.get("type") == "ELEMENT_RESIST"):
					for el in e.get("effect").keys():
						element_resists[el.to_upper()] += e.get("effect")[el]
				if(e.get("type") == "STATUS_RESIIST"):
					for st in e.get("effect").keys():
						status_resists[st.to_upper()] += e.get("effect")[st]
			
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
		var capped_pct = mini(int(pct_mods.get(stat_name, 0)), 400)

		var final_val = (base * (1.0 + (float(capped_pct) / 100.0))) + total_flat
		final_profile["stats"][stat_name] = int(round(final_val))
		
	final_profile["element_resist"] = element_resists
	final_profile["status_resist"] = status_resists

	return final_profile
