extends Node

const CORE_STATS = ["HP", "MP", "ATK", "DEF", "MAG", "SPR"]
const ELEMENTS = ["FIRE", "ICE", "LIGHTNING", "WATER", "WIND", "EARTH", "LIGHT", "DARK"]
const STATUSES = ["POISON", "BLIND", "SLEEP", "SILENCE", "PARALYSIS", "CONFUSION", "DISEASE", "PETRIFY"]

## Ceiling on the summed percentage bonus a single stat can receive.
const MAX_STAT_PCT_BONUS: int = 400
## Ceiling on the summed equipment-stat boosts (doublehand, true doublehand, true dual
## wield, single weapon, unarmed) for one stat: they share one pool (the user's rule,
## 2026-09-30; 150% doublehand + 150% true doublehand = 300%).
const MAX_EQUIPMENT_PCT_BONUS: int = 400

const RARITY_MAX_LEVELS: Dictionary = {
	1: 15,
	2: 30,
	3: 40,
	4: 60,
	5: 80,
	6: 100,
	7: 120
}

func _accumulate_named_resists(source: Variant, targets: Dictionary, ordered_keys: Array) -> void:
	if source == null:
		return

	if typeof(source) == TYPE_DICTIONARY:
		for key in source.keys():
			var normalized_key = ordered_keys[int(key)-1]
			if targets.has(normalized_key):
				var resist_value = source[key]
				targets[normalized_key] += int(resist_value)
			else:
				push_warning("StatCalculator: Unknown resist key in equipment stats -> " + str(key))
	elif typeof(source) == TYPE_ARRAY:
		for i in range(min(source.size(), ordered_keys.size())):
			var target_key = ordered_keys[i]
			var resist_value = source[i]
			if typeof(resist_value) in [TYPE_INT, TYPE_FLOAT]:
				targets[target_key] += int(resist_value)

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
		if effect_type not in ["buff", "debuff", "element_resist"]:
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
		elif element_resists.has(key.to_upper()):
			element_resists[key.to_upper()] += val
		elif status_resists.has(key):
			status_resists[key] += val
		else:
			push_warning("StatCalculator: Unhandled modifier -> " + str(key))


## What the equipment-stat boosts add: per stat, the equipment's own stat (every
## equipped item, PassiveSources.build_loadout's `stats`) x min(pct, 400) / 100, rounded.
static func equipment_stat_bonus(equipment_stats: Dictionary, pct: Dictionary) -> Dictionary:
	var bonus: Dictionary = {}
	for stat_name in CORE_STATS:
		var capped: int = mini(int(pct.get(stat_name, 0)), MAX_EQUIPMENT_PCT_BONUS)
		bonus[stat_name] = int(round(float(equipment_stats.get(stat_name, 0)) * float(capped) / 100.0))
	return bonus


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


## The esper in the unit's slot of the active party, as { summon_id, rank, level,
## unlocked_skills, board_bonus }, or {} when the unit is not in the active party or its
## slot has no esper. An esper the account does not own counts at rank 1, level 1.
func resolve_party_esper(unit_instance: Dictionary) -> Dictionary:
	var summon_id: String = _resolve_active_party_esper_id_for_unit(unit_instance)
	if summon_id == "":
		return {}
	var progression: Dictionary = EsperService.get_esper_progression(summon_id)
	var unlocked: Variant = progression.get("unlocked_skills", [])
	return {
		"summon_id": summon_id,
		"rank": maxi(1, int(progression.get("rank", 1))),
		"level": maxi(1, int(progression.get("level", 1))),
		"unlocked_skills": unlocked if unlocked is Array else [],
		"board_bonus": EsperService.get_esper_board_stat_bonuses(summon_id),
	}


## The skills an esper's board has unlocked: { magic: [id], ability: [id] }. "ability"
## holds every id of the ability table, active or passive (esper boards carry 122
## passives: killers, killer cap raises, stat boosts).
func _esper_unlocked_skills(esper: Dictionary) -> Dictionary:
	var unlocked_skill_ids: Dictionary = {"magic": [], "ability": []}
	for skill_id in esper.get("unlocked_skills", []):
		var normalized_skill_id: String = str(skill_id).strip_edges()
		if not normalized_skill_id.is_valid_int():
			continue
		if GameDatabase.has_magic(normalized_skill_id):
			unlocked_skill_ids["magic"].append(int(normalized_skill_id))
		if GameDatabase.has_ability(normalized_skill_id) or GameDatabase.has_passive(normalized_skill_id):
			unlocked_skill_ids["ability"].append(int(normalized_skill_id))
	return unlocked_skill_ids


## 1% of the esper's stats (its level curve plus board stat nodes), as flat bonuses,
## then multiplied by 1 + `boost_pct` / 100 per stat (ESPER_STAT passives, from
## PassiveAggregator's esper_stat_pct). Both steps round down.
func _compute_esper_flat_bonus(esper: Dictionary, boost_pct: Dictionary = {}) -> Dictionary:
	var bonus: Dictionary = {}
	for stat_name in CORE_STATS:
		bonus[stat_name] = 0
	if esper.is_empty():
		return bonus

	var summon_data: Dictionary = GameDatabase.get_esper(int(esper["summon_id"]), int(esper["rank"]))
	var esper_stats: Dictionary = _extract_esper_stats_for_level_and_rank(summon_data, int(esper["level"]))
	var board_stat_bonus: Dictionary = esper.get("board_bonus", {})

	for stat_name in CORE_STATS:
		var esper_stat_value: float = float(esper_stats.get(stat_name, 0)) + float(board_stat_bonus.get(stat_name, 0))
		var share: int = int(floor(esper_stat_value * 0.01))
		bonus[stat_name] = int(floor(float(share) * (1.0 + float(boost_pct.get(stat_name, 0)) / 100.0)))

	return bonus

## The final-stat profile for a battle/roster instance: { stats, base_stats,
## element_resist, status_resist, debuff_resist, skills, passive_effects, passives,
## equipment_stats, equipment_bonus, esper_stats, loadout } (see
## calculate_unit_profile). Monster profiles
## carry stats, element_resist, status_resist, skills and passive_effects.
##
## Monsters take a different path. They are not units with pieces missing -- their base
## stats come flat from MONSTER_PARTS instead of a rarity growth curve, and they have no
## equipment, espers or trait skills. Keeping one entry point means every caller
## (BattleBuilder builds both sides through it) works without knowing which it holds;
## keeping separate bodies means neither has to pretend to be the other. See
## MonsterStatCalculator.
func calculate_final_stats(unit_instance: Dictionary) -> Dictionary:
	if bool(unit_instance.get("is_monster", false)):
		return MonsterStatCalculator.calculate_final_stats(unit_instance)
	if not unit_instance.has("equipment"): push_error("CRITICAL ERROR: unit_instance is missing equipment!")
	return calculate_unit_profile(unit_instance, resolve_equipped_items(unit_instance), resolve_party_esper(unit_instance))


## Every passive the unit has, from its traits and awakenings, equipment, materia and the
## party esper's board, as _passive_sources returns them. EquipmentValidator reads its
## dual-wield permits from here, so both see the same passives.
func collect_passive_sources(unit_instance: Dictionary) -> Array[Dictionary]:
	return passive_sources_for(unit_instance, resolve_equipped_items(unit_instance))


## collect_passive_sources with `items` equipped instead of what the unit wears (entries
## as resolve_equipped_items returns them), so EquipmentValidator can ask about an equip
## before it happens.
func passive_sources_for(unit_instance: Dictionary, items: Array) -> Array[Dictionary]:
	var granted: Dictionary = _granted_skills(unit_instance, items, resolve_party_esper(unit_instance))
	return _passive_sources(granted["abilities"], PassiveSources.build_loadout(items))


## The unit's equipped items, one per filled slot: { slot, kind
## (PassiveSources.KIND_EQUIPMENT or KIND_MATERIA), id (template id), data (the
## GameDatabase record) }.
func resolve_equipped_items(unit_instance: Dictionary) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	var equipment: Variant = unit_instance.get("equipment", {})
	if not (equipment is Dictionary):
		return items
	for slot_id in equipment:
		var item_id: Variant = equipment[slot_id]
		if item_id == null or str(item_id) == "":
			continue
		var template_id: String = InventoryService.get_equipment_template_id(str(item_id))
		var item: Dictionary = resolve_item(str(slot_id), template_id)
		if item.is_empty():
			push_error("CRITICAL ERROR: template_id not found in equipment or materia data: " + template_id)
			continue
		items.append(item)
	return items


## One entry of resolve_equipped_items for the item with `template_id` in `slot_id`; {}
## when neither the equipment nor the materia table has it.
func resolve_item(slot_id: String, template_id: String) -> Dictionary:
	var kind: String = PassiveSources.KIND_EQUIPMENT
	var item_data: Dictionary = GameDatabase.get_equipment(template_id)
	if item_data.is_empty():
		kind = PassiveSources.KIND_MATERIA
		item_data = GameDatabase.get_materia(int(template_id))
	if item_data.is_empty():
		return {}
	return {"slot": slot_id, "kind": kind, "id": int(template_id), "data": item_data}


## The profile for a unit from inputs already gathered: `items` as resolve_equipped_items
## returns them and `esper` as resolve_party_esper does ({} for none). Reads GameDatabase
## and SkillResolver but no account state, so tests can pass any equipment and esper.
##
## A passive whose equip condition fails for the loadout is listed in skills.passive
## with `active` false, and its effects are neither applied nor put in passive_effects.
## The active ones go through PassiveAggregator: its stat, resistance and debuff
## totals are applied here, its equipment-stat boosts add equipment_bonus (the
## equipment's stats x the capped percent) to the flat part, its esper boost scales
## esper_stats, and its battle
## modifiers (killers, killer cap raises, LB and skill damage) go to `passives` with the
## effects it has no handler for (passives.unconsumed). equipment_stats, esper_stats and
## base_stats are each only their own part of the total (the stat detail screen's
## columns).
func calculate_unit_profile(unit_instance: Dictionary, items: Array, esper: Dictionary) -> Dictionary:
	var final_profile = empty_stat_profile()

	var pools: Dictionary = new_modifier_pools()
	var pct_mods: Dictionary = pools["pct"]
	var element_resists: Dictionary = pools["element"]
	var status_resists: Dictionary = pools["status"]

	if not unit_instance.has("current_rarity"):
		# A monster reaching this line means its dict was built without is_monster (only
		# CombatantFactory.monster_stat_input sets it), so it is being run
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
			base_calculated[stat_name] = int(round(current_stat))

	final_profile["base_stats"] = base_calculated

	var loadout: Dictionary = PassiveSources.build_loadout(items)
	final_profile["loadout"] = loadout

	var flat_mods = {
		"HP": 0,
		"MP": 0,
		"ATK": 0,
		"DEF": 0,
		"MAG": 0,
		"SPR": 0
	}

	for item in items:
		var item_stats: Dictionary = item["data"].get("stats", {})
		for stat_name in CORE_STATS:
			flat_mods[stat_name] += int(item_stats.get(stat_name, 0))
		_accumulate_named_resists(item_stats.get("element_resist", null), element_resists, ELEMENTS)
		_accumulate_named_resists(item_stats.get("status_resist", null), status_resists, STATUSES)

	# The stat detail screen's "Equip" column: the equipment's own stats and nothing else.
	final_profile["equipment_stats"] = (loadout["stats"] as Dictionary).duplicate()

	var granted: Dictionary = _granted_skills(unit_instance, items, esper)
	final_profile["skills"]["magic"].append_array(granted["magic"])
	for entry in granted["abilities"]:
		var category: String = GameDatabase.classify_skill_id(str(entry.get("id")))
		if category == "magic":
			final_profile["skills"]["magic"].append(entry)
		elif category == "ability":
			final_profile["skills"]["ability"].append(entry)

	var active_passives: Array = []
	for source in _passive_sources(granted["abilities"], loadout):
		var entry: Dictionary = source["entry"]
		entry["active"] = source["active"]
		final_profile["skills"]["passive"].append(entry)
		if not bool(source["active"]):
			continue
		var effects: Array = SkillResolver.parse_passive_effects(source["record"]).get("effects", [])
		final_profile["passive_effects"].append_array(effects)
		active_passives.append({"skill_id": str(entry.get("id")), "source": str(entry.get("source", "")), "effects": effects})

	var totals: Dictionary = PassiveAggregator.aggregate(active_passives, loadout, esper)
	var equipment_bonus: Dictionary = equipment_stat_bonus(loadout["stats"], totals[PassiveAggregator.POOL_EQUIPMENT_PCT])
	final_profile["equipment_bonus"] = equipment_bonus
	# Each hand's share, for the battle: a dual wielder's swing leaves the other weapon's
	# ATK out, boost included (DualWield).
	for hand in loadout["hands"]:
		hand["equipment_bonus"] = equipment_stat_bonus(hand["stats"], totals[PassiveAggregator.POOL_EQUIPMENT_PCT])
	for stat_name in CORE_STATS:
		pct_mods[stat_name] += int(totals[PassiveAggregator.POOL_STAT_PCT][stat_name])
		flat_mods[stat_name] += int(totals[PassiveAggregator.POOL_STAT_FLAT][stat_name])
		flat_mods[stat_name] += int(equipment_bonus[stat_name])
	for element in ELEMENTS:
		element_resists[element] += int(totals[PassiveAggregator.POOL_ELEMENT][element])
	for status in STATUSES:
		status_resists[status] += int(totals[PassiveAggregator.POOL_STATUS][status])
	final_profile["debuff_resist"] = totals[PassiveAggregator.POOL_DEBUFF]
	# The battle modifiers, for CombatantPassives.from_profile.
	var battle_passives: Dictionary = {}
	for key in PassiveAggregator.BATTLE_KEYS:
		battle_passives[key] = totals[key]
	final_profile["passives"] = battle_passives

	var esper_flat_bonus: Dictionary = _compute_esper_flat_bonus(esper, totals[PassiveAggregator.POOL_ESPER_PCT])
	for stat_name in CORE_STATS:
		flat_mods[stat_name] += int(esper_flat_bonus.get(stat_name, 0))
	final_profile["esper_stats"] = esper_flat_bonus

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


## The skills the unit is granted, before they are sorted: { magic: [entry], abilities:
## [entry] }. An entry is { id, source ("Trait", "Equip" or "Esper") }, plus `slot` for
## equipment and materia and get_awakened_skills' awakening fields for traits.
## `abilities` holds ability-table ids, active and passive alike.
func _granted_skills(unit_instance: Dictionary, items: Array, esper: Dictionary) -> Dictionary:
	var magic: Array = []
	var abilities: Array = []
	var traits: Dictionary = get_awakened_skills(
		int(unit_instance.get("unitSeries", 0)), int(unit_instance.get("current_rarity", 1)),
		int(unit_instance.get("level", 1)), unit_instance.get("awakened_abilities", [])
	)
	for entry in traits["magic"]:
		entry.merge({"source": "Trait"})
		magic.append(entry)
	for entry in traits["ability"]:
		entry.merge({"source": "Trait"})
		abilities.append(entry)

	for item in items:
		var item_data: Dictionary = item["data"]
		for skill_id in _split_ids(item_data.get("abilityId")):
			abilities.append({"id": skill_id, "source": "Equip", "slot": item["slot"]})
		for skill_id in _split_ids(item_data.get("magicId")):
			magic.append({"id": skill_id, "source": "Equip", "slot": item["slot"]})

	var esper_skills: Dictionary = _esper_unlocked_skills(esper)
	for skill_id in esper_skills["magic"]:
		magic.append({"id": skill_id, "source": "Esper"})
	for skill_id in esper_skills["ability"]:
		abilities.append({"id": skill_id, "source": "Esper"})

	# Skill ids a debug tool adds for one battle (the battle sandbox's extra skills,
	# `extra_skills` on the unit dict): actives join the skill lists and passives count
	# like the unit's own.
	for skill_id in unit_instance.get("extra_skills", []):
		abilities.append({"id": str(skill_id), "source": "Extra"})
	return {"magic": magic, "abilities": abilities}


## The passives among `entries` (from _granted_skills), each as { entry, record
## (GameDatabase.get_passive), active }. `active` is false when the passive's equip
## condition fails for the loadout. The same passive from two sources is listed twice
## and counts twice (the user's rule, 2026-09-30).
func _passive_sources(entries: Array, loadout: Dictionary) -> Array[Dictionary]:
	var sources: Array[Dictionary] = []
	for entry in entries:
		var skill_id: String = str(entry.get("id"))
		if GameDatabase.classify_skill_id(skill_id) != "passive":
			continue
		var record: Dictionary = GameDatabase.get_passive(skill_id)
		sources.append({
			"entry": entry,
			"record": record,
			"active": PassiveSources.condition_holds(record.get("equip_condition", []), loadout),
		})
	return sources


## "101600,101700" as its ids; none for SQL NULL or "".
static func _split_ids(value: Variant) -> PackedStringArray:
	var ids := PackedStringArray()
	if value == null:
		return ids
	for token in str(value).split(",", false):
		var skill_id: String = token.strip_edges()
		if skill_id != "":
			ids.append(skill_id)
	return ids


func get_awakened_skills(unit_series_id: int, rarity: int, level: int, unlocked_recipes: Array) -> Dictionary:
	var final_skills = {"magic": [], "ability": []}
	
	# 1. Create the base mapping dictionary
	var awakened_map = {}
	if unlocked_recipes.size() > 0:
		var recipe_results = GameDatabase.get_awakened_skill_info(unlocked_recipes)
		
		for row in recipe_results:
			awakened_map[str(row["beforeSkillId"])] = str(row["afterSkillId"])

	# 2. Query the base skills
	var base_results = GameDatabase.get_unit_skills(unit_series_id, rarity, level)
	
	var resolve_skill_chain = func(base_skill_id: String) -> Dictionary:
		var current_skill = base_skill_id
		var awaken_steps = 0
		
		while awakened_map.has(current_skill) and awaken_steps < 5:
			current_skill = awakened_map[current_skill]
			awaken_steps += 1
			
		return {
			"id": current_skill, # The final equipped skill ID
			"base_id": base_skill_id, # Might not need. The original unawakened skill ID
			"is_awakened": awaken_steps > 0, # Might not need. Boolean flag (true if awakened at least once)
			"awaken_level": awaken_steps # Useful for displaying UI text like "Skill Name +2"
		}

	# 3. Process and replace using the while-loop logic
	for row in base_results:
		# Process Magic
		if row["magicId"]:
			var magics = row["magicId"].split(",")
			for m in magics:
				var m_clean = m.strip_edges()
				final_skills["magic"].append(resolve_skill_chain.call(m_clean))
				
		# Process Abilities
		if row["abilityId"]:
			var abilities = row["abilityId"].split(",")
			for a in abilities:
				var a_clean = a.strip_edges()
				final_skills["ability"].append(resolve_skill_chain.call(a_clean))
				
	return final_skills
