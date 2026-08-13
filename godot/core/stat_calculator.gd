extends Node

const CORE_STATS = ["HP", "MP", "ATK", "DEF", "MAG", "SPR"]
const ELEMENTS = ["FIRE", "ICE", "LIGHTNING", "WATER", "WIND", "EARTH", "LIGHT", "DARK"]
const STATUSES = ["POISON", "BLIND", "SLEEP", "SILENCE", "PARALYSIS", "CONFUSION", "DISEASE", "PETRIFY"]

const RESIST_KEY_ALIASES: Dictionary = {
	"PARALYZE": "PARALYSIS",
	"PETRIFICATION": "PETRIFY"
}

## Ceiling on the summed percentage bonus a single stat can receive.
const MAX_STAT_PCT_BONUS: int = 400

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

func _apply_parsed_passive_effects(effects: Array, pct_mods: Dictionary, element_resists: Dictionary, status_resists: Dictionary) -> void:
	for e in effects:
		var effect_type: String = str(e.get("type", ""))
		var effect_payload: Dictionary = e.get("effect", {})
		match effect_type:
			"STAT_BOOST_PCT":
				for stat in effect_payload.keys():
					if pct_mods.has(stat):
						pct_mods[stat] += effect_payload[stat]
			"ELEMENT_RESIST":
				for el in effect_payload.keys():
					var el_key: String = str(el).to_upper()
					if element_resists.has(el_key):
						element_resists[el_key] += effect_payload[el]
					else:
						push_warning("Unknown element resist key from passive: %s" % el_key)
			"STATUS_RESIST":
				for st in effect_payload.keys():
					var st_key: String = _normalize_resist_key(str(st))
					if status_resists.has(st_key):
						status_resists[st_key] += effect_payload[st]
					else:
						push_warning("Unknown status resist key from passive: %s" % st_key)

# === Shared with MonsterStatCalculator ===
# Units and monsters agree on three things: the stat/element/status vocabulary, how
# innate resistances are encoded, and how active buffs and debuffs combine. Those live
# here and are called from both, so a Full Break resolves identically on a boss and on
# a party member. Everything else about the two is different -- see
# MonsterStatCalculator for why the bodies are separate.

## The zeroed profile every calculator fills in and returns.
func empty_stat_profile() -> Dictionary:
	var stats: Dictionary = {}
	for stat_name in CORE_STATS:
		stats[stat_name] = 0
	return {
		"stats": stats,
		"element_resist": {},
		"status_resist": {},
		"skills": {"magic": [], "ability": [], "passive": []},
		"passive_effects": [],
	}


## Fresh zeroed accumulators: { pct, element, status }.
func new_modifier_pools() -> Dictionary:
	var pct: Dictionary = {}
	for stat_name in CORE_STATS:
		pct[stat_name] = 0
	var element: Dictionary = {}
	for el in ELEMENTS:
		element[el] = 0
	var status: Dictionary = {}
	for st in STATUSES:
		status[st] = 0
	return {"pct": pct, "element": element, "status": status}


## Seeds an instance's innate elemental / status resistances into the pools. Units and
## monsters both store these as the datamine's comma-separated strings in the same
## element and status order, so this is genuinely shared. A missing, null or non-string
## value contributes nothing.
func seed_innate_resists(instance: Dictionary, element_resists: Dictionary, status_resists: Dictionary) -> void:
	_seed_resist_string(instance.get("elemResistValue"), element_resists, ELEMENTS)
	_seed_resist_string(instance.get("ailmentResistValue"), status_resists, STATUSES)


func _seed_resist_string(raw: Variant, targets: Dictionary, ordered_keys: Array) -> void:
	if raw == null or typeof(raw) != TYPE_STRING or str(raw) == "":
		return
	var values: PackedStringArray = str(raw).split(",")
	# min() guards a datamine array that is longer or shorter than our key list.
	for i in range(min(values.size(), ordered_keys.size())):
		if str(values[i]).is_valid_int():
			targets[ordered_keys[i]] += int(values[i])


## Aggregates an instance's active_effects into { key: delta }. Buffs keep the highest
## value per key and debuffs the lowest, then the two are summed -- so a buff and a
## debuff on the same stat partially cancel rather than one simply winning.
func collect_active_modifiers(instance: Dictionary) -> Dictionary:
	var active_buffs: Dictionary = {}
	var active_debuffs: Dictionary = {}

	for effect in instance.get("active_effects", []):
		var effect_type: String = str(effect.get("type", "")).to_lower()
		if effect_type not in ["buff", "debuff"]:
			continue
		var modifiers: Dictionary = effect.get("params", {})
		for key in modifiers.keys():
			var val = modifiers[key]
			if typeof(val) not in [TYPE_INT, TYPE_FLOAT]:
				continue
			if val > 0:
				active_buffs[key] = max(active_buffs.get(key, 0), val)
			elif val < 0:
				active_debuffs[key] = min(active_debuffs.get(key, 0), val)

	var combined: Dictionary = active_buffs.duplicate()
	for key in active_debuffs.keys():
		combined[key] = combined.get(key, 0) + active_debuffs[key]
	return combined


## Routes each aggregated modifier into whichever pool owns that key.
func apply_active_modifiers(mods: Dictionary, pct_mods: Dictionary, element_resists: Dictionary, status_resists: Dictionary) -> void:
	for key in mods.keys():
		var val = mods[key]
		if pct_mods.has(key):
			pct_mods[key] += val
		elif element_resists.has(key):
			element_resists[key] += val
		elif status_resists.has(key):
			status_resists[key] += val
		else:
			push_warning("StatCalculator: Unhandled modifier -> " + str(key))


## base * (1 + pct/100) + flat, with the percentage contribution capped.
func combine_stat(base: float, pct: int, flat: int) -> int:
	var capped_pct: int = mini(pct, MAX_STAT_PCT_BONUS)
	return int(round((base * (1.0 + (float(capped_pct) / 100.0))) + float(flat)))


func _resolve_esper_rank_max_level(entry: Dictionary) -> int:
	var cp_pattern_value: Variant = entry.get("cp_pattern", [])
	if cp_pattern_value is Array:
		var cp_pattern: Array = cp_pattern_value
		if not cp_pattern.is_empty():
			return maxi(1, cp_pattern.size())
	return 1

func _interpolate_esper_stat_value(value: Variant, level: int, rank_max_level: int) -> int:
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

func _extract_esper_stats_for_level_and_rank(summon_data: Dictionary, level: int) -> Dictionary:
	var rank_max_level: int = int(summon_data.get("maxLv"))
	var resolved_stats: Dictionary = {}
	for stat_name in CORE_STATS:
		resolved_stats[stat_name] = _interpolate_esper_stat_value(summon_data.get(stat_name.to_lower()).split(','), level, rank_max_level)
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

	var progression: Dictionary = EsperService.owned_summons.filter(func(x): return x.summon_id == summon_id)[0]#EsperService.get_esper_progression(summon_id)
	var rank: int = maxi(1, int(progression.get("rank", 1)))
	var summon_data: Dictionary = GameDatabase.get_esper(int(summon_id), rank)
	if summon_data.is_empty():
		return {}

	var skill_id: String = str(summon_data.get("beastSkillId"))
	if skill_id == "":
		return {}
	
	var skill_data: Dictionary = GameDatabase.get_esper_skill(int(summon_id), rank)
	
	var skill_name: String = skill_data.get("name")
	var skill_description: String = skill_data.get("description")

	return {
		"summon_id": summon_id,
		"rank": rank,
		"skill_id": skill_id,
		"name": skill_name,
		"explainShort": skill_description,
		"skill_data": skill_data
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
		# `dataset_has()` consults the lightweight keys index instead of forcing
		# a 30+ MB Variant decode of skills_ability for a simple presence check.
		if GameDatabase.has_magic(normalized_skill_id) or GameDatabase.has_ability(normalized_skill_id):
			unlocked_skill_ids.append(int(normalized_skill_id))

	return unlocked_skill_ids

func _compute_active_party_esper_flat_bonus(unit_instance: Dictionary) -> Dictionary:
	var bonus: Dictionary = {}
	for stat_name in CORE_STATS:
		bonus[stat_name] = 0

	var summon_id: String = _resolve_active_party_esper_id_for_unit(unit_instance)
	if summon_id == "":
		return bonus

	var progression: Dictionary = EsperService.get_esper_progression(summon_id)
	var rank: int = maxi(1, int(progression.get("rank", 1)))
	var level: int = maxi(1, int(progression.get("level", 1)))
	var summon_data: Dictionary = GameDatabase.get_esper(int(summon_id), rank)
	var esper_stats: Dictionary = _extract_esper_stats_for_level_and_rank(summon_data, level)
	var board_stat_bonus: Dictionary = EsperService.get_esper_board_stat_bonuses(summon_id)

	for stat_name in CORE_STATS:
		var esper_stat_value: float = float(esper_stats.get(stat_name, 0)) + float(board_stat_bonus.get(stat_name, 0))
		bonus[stat_name] = int(floor(esper_stat_value * 0.01))

	return bonus

## The final-stat profile for a battle/roster instance: { stats, element_resist,
## status_resist, skills, passive_effects }.
##
## Monsters take a different path. They are not units with pieces missing -- their base
## stats come flat from MONSTER_PARTS instead of a rarity growth curve, and they have no
## equipment, espers or trait skills. Keeping one entry point means every caller
## (result_processor, _tick_active_effect_durations, dispel) works for both sides
## without knowing which it holds; keeping separate bodies means neither has to pretend
## to be the other. See MonsterStatCalculator.
func calculate_final_stats(unit_instance: Dictionary) -> Dictionary:
	if bool(unit_instance.get("is_monster", false)):
		return MonsterStatCalculator.calculate_final_stats(unit_instance)

	var final_profile = empty_stat_profile()

	var pools: Dictionary = new_modifier_pools()
	var pct_mods: Dictionary = pools["pct"]
	var element_resists: Dictionary = pools["element"]
	var status_resists: Dictionary = pools["status"]

	if not unit_instance.has("current_rarity"):
		# A monster reaching this line means its dict was built without is_monster (only
		# BattleManager._generate_enemy_from_descriptor sets it), so it is being run
		# through the unit path it has none of the inputs for.
		push_error("CRITICAL ERROR: unit_instance is missing current_rarity!%s" % [
			"  (this looks like a monster -- is_monster is not set on it)" if unit_instance.has("base_stats") else "",
		])
	var rarity = int(unit_instance["current_rarity"])

	if not unit_instance.has("level"): push_error("CRITICAL ERROR: unit_instance is missing level!")
	var level = int(unit_instance["level"])

	if not RARITY_MAX_LEVELS.has(rarity): push_error("CRITICAL ERROR: RARITY_MAX_LEVELS is missing rarity: " + str(rarity))
	var max_level = RARITY_MAX_LEVELS[rarity]
	
	seed_innate_resists(unit_instance, element_resists, status_resists)

	var base_calculated = {
		"HP": 0.0,
		"MP": 0.0,
		"ATK": 0.0,
		"DEF": 0.0,
		"MAG": 0.0,
		"SPR": 0.0
	}
	
	for stat_name in final_profile["stats"].keys():
		if not unit_instance.has(stat_name.to_lower()): push_error("CRITICAL ERROR: unit_unstance is missing stat " + stat_name + "!")
		var stat_arr = unit_instance[stat_name.to_lower()].split(',')
		if stat_arr.size() >= 2:
			var min_stat = int(stat_arr[0])
			var max_stat = int(stat_arr[1])
			var current_stat = min_stat
			if max_level > 1:
				current_stat = min_stat + (level - 1) * float(max_stat - min_stat) / (max_level - 1)
			base_calculated[stat_name] = round(current_stat)

	var raw_skills = []
	
	# Harvest innate skills
	var innate_skills = GameDatabase.get_unit_skills(unit_instance.get("unitSeries"), unit_instance.get("rare"), unit_instance.get("level"))
	for skill in innate_skills:
		var magic_id = skill.get("magicId")
		var ability_id = skill.get("abilityId")
		var magic_array: Array = magic_id.split(',') if not magic_id == null else []
		var ability_array: Array = ability_id.split(',') if not ability_id == null else []
		var combined = magic_array + ability_array
		for id in combined:
			raw_skills.append({"id": id, "source": "Trait"})

	var flat_mods = {
		"HP": 0,
		"MP": 0,
		"ATK": 0,
		"DEF": 0,
		"MAG": 0,
		"SPR": 0
	}
	
	if not unit_instance.has("equipment"): push_error("CRITICAL ERROR: unit_instance is missing equipment!")
	var equipment = unit_instance["equipment"]
	for slot_id in equipment:
		var item_id = equipment[slot_id]
		if item_id != null and item_id != "":
			var template_id = InventoryService.get_equipment_template_id(item_id)
			var item_data: Dictionary = {}
			item_data = GameDatabase.get_equipment(template_id)
			if item_data.is_empty():
				item_data = GameDatabase.get_materia(int(template_id))
			if item_data.is_empty():
				push_error("CRITICAL ERROR: template_id not found in equipment or materia data: " + str(template_id))
				continue

			var item_stats: Dictionary = item_data.get("stats", {})

			for stat_name in final_profile["stats"].keys():
				flat_mods[stat_name] += item_stats.get(stat_name, 0)

			_accumulate_named_resists(item_stats.get("element_resist", null), element_resists, ELEMENTS)
			_accumulate_named_resists(item_stats.get("status_resist", null), status_resists, STATUSES)

			var ability_id = str(item_data.get("abilityId"))
			var ability_array: Array
			if ability_id != null:
				if ability_id.contains(','):
					ability_array = ability_id.split(',')
				else:
					ability_array = [ability_id]
			for skill_id in ability_array:
				raw_skills.append({"id": skill_id, "source": "Equip"})

			var magic_id = str(item_data.get("magicId"))
			var magic_array: Array
			if magic_id != null:
				if magic_id.contains(','):
					magic_array = magic_id.split(',')
				else:
					magic_array = [magic_id]
			for skill_id in magic_array:
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

		var category: String = GameDatabase.classify_skill_id(skill_id_str)
		if category == "magic":
			final_profile["skills"]["magic"].append(skill_entry)
		elif category == "ability":
			final_profile["skills"]["ability"].append(skill_entry)
		elif category == "passive":
			final_profile["skills"]["passive"].append(skill_entry)
			# Passive parsing genuinely needs the record body, so this is the
			# one site that intentionally pulls skills_passive into memory.
			var skill_data = GameDatabase.get_passive(skill_id_str)
			var parsed_passive = SkillResolver.parse_passive_effects(skill_data)
			final_profile["passive_effects"].append_array(parsed_passive.get("effects", []))
			_apply_parsed_passive_effects(parsed_passive.get("effects", []), pct_mods, element_resists, status_resists)
			
	# TODO: Parse effects_raw for pct_mods here

	apply_active_modifiers(
		collect_active_modifiers(unit_instance), pct_mods, element_resists, status_resists
	)

	for stat_name in final_profile["stats"].keys():
		final_profile["stats"][stat_name] = combine_stat(
			float(base_calculated.get(stat_name, 0.0)),
			int(pct_mods.get(stat_name, 0)),
			int(flat_mods.get(stat_name, 0))
		)


	final_profile["element_resist"] = element_resists
	final_profile["status_resist"] = status_resists

	return final_profile
