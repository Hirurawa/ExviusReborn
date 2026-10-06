class_name CombatantFactory
extends RefCounted

## Builds Combatants from the dicts the rest of the game uses (an owned unit, a
## monster's parts row) plus a StatCalculator profile computed by the caller, or from a
## plain spec for tests. Nothing here reads an autoload; BattleBuilder gathers the
## inputs.

## Fallback basic-attack timing when a unit or monster carries no attackFrames.
const DEFAULT_ATTACK_FRAMES: String = "42:100"
## Stat block for a monster with no parts row (old engine defaults).
const DEFAULT_ENEMY_HP: int = 1000
const DEFAULT_ENEMY_STAT: int = 10


## A party member from a hydrated owned-unit dict (unit table fields merged with the
## instance record) and its StatCalculator.calculate_final_stats() profile.
static func party_member(unit: Dictionary, profile: Dictionary) -> Combatant:
	var member := Combatant.new()
	member.side = Combatant.Side.PARTY
	member.name = str(unit.get("unitName", unit.get("name", "")))
	member.source_id = str(unit.get("instance_id", ""))
	member.template_id = str(unit.get("unitId", unit.get("unit_id", "")))
	member.level = maxi(1, int(unit.get("level", 1)))
	member.sex = int(unit.get("sex", Combatant.SEX_UNKNOWN))
	member.races = races_from(unit.get("tribe"))
	member.limit_burst_id = str(unit.get("limitBurstId", ""))
	member.limit_burst_level = maxi(1, int(unit.get("limitburst_level", 1)))
	member.attack_skill = BattleSkill.basic_attack(
		_frames_or_default(unit.get("attackFrames")), int(unit.get("attackMoveType", 0))
	)
	member.source = unit
	apply_profile(member, profile)
	# "Change LB effects" passives (op 72) replace the unit's own limit burst.
	if member.passives.lb_change_id != "":
		member.limit_burst_id = member.passives.lb_change_id
	return member


## The dict MonsterStatCalculator works from (StatCalculator.calculate_final_stats
## routes it there on `is_monster`), built from a GameDatabase.get_monster_parts row.
## A monster with no parts row gets the old engine's defaults.
static func monster_stat_input(parts: Dictionary) -> Dictionary:
	var hp: int = int(parts.get("hp", 0))
	return {
		"is_monster": true,
		"base_stats": {
			"HP": hp if hp > 0 else DEFAULT_ENEMY_HP,
			"MP": maxi(0, int(parts.get("mp", 0))),
			"ATK": maxi(1, int(parts.get("atk", DEFAULT_ENEMY_STAT))),
			"DEF": maxi(1, int(parts.get("def", DEFAULT_ENEMY_STAT))),
			"MAG": maxi(1, int(parts.get("mag", DEFAULT_ENEMY_STAT))),
			"SPR": maxi(1, int(parts.get("spr", DEFAULT_ENEMY_STAT))),
		},
		"elemResistValue": _text(parts.get("elemResistValue")),
		"ailmentResistValue": _text(parts.get("ailmentResistValue")),
		"active_effects": [],
	}


## An enemy from an EncounterResolver formation descriptor, its GameDatabase monster
## parts row ({} when it has none), the monster_stat_input() dict and its profile.
## Rewards, loot and screen position go to `meta` for the session layer.
static func enemy(descriptor: Dictionary, parts: Dictionary, stat_input: Dictionary, profile: Dictionary) -> Combatant:
	var foe := Combatant.new()
	foe.side = Combatant.Side.ENEMY
	foe.name = str(descriptor.get("name", parts.get("name", "Unknown Monster")))
	foe.source_id = str(descriptor.get("instance_id", ""))
	foe.template_id = str(descriptor.get("id", ""))
	foe.level = maxi(1, int(parts.get("level", 1)))
	foe.is_boss = bool(descriptor.get("is_boss", false))
	foe.races = races_from(parts.get("tribe"))
	foe.physical_resist = int(parts.get("physicsDmgCut", 0))
	foe.magic_resist = int(parts.get("magicDmgCut", 0))
	foe.attack_skill = BattleSkill.basic_attack(_frames_or_default(parts.get("attackFrames")))
	foe.meta = {
		"exp": maxi(0, int(parts.get("exp", 0))),
		"gil": maxi(0, int(parts.get("gil", 0))),
		"loot": descriptor.get("loot", {}),
		"disp_pos": descriptor.get("disp_pos", Vector2.ZERO),
	}
	foe.source = stat_input
	foe.debuff_resist = debuff_resist_from(parts.get("debuffResists"))
	apply_profile(foe, profile)
	return foe


## A combatant from a plain spec, for tests and debug battles. Keys (all optional):
## name, party (bool, default true), level, hp, mp, atk, def, mag, spr,
## raw_stats { "ATK": 50 } (the part buffs scale; defaults to the stats),
## element_resist { "FIRE": 50 }, ailment_resist { "SLEEP": 100 },
## debuff_resist { "STOP": 100 }, physical_resist, magic_resist (innate damage cuts),
## weapon_inflicts { "SLEEP": 30 }, weapon_elements [int], hand_atk [right, left] (the
## ATK each weapon adds to `atk`; two entries dual wield), weapon_variance [min, max]
## (whole percent, default [100, 100]), two_handed (bool), races [int], sex
## (Combatant.SEX_*), attack_frames
## ("4:100-20:0"), move_type, lb, max_lb, limit_burst_id, esper_id (a beastId) and
## esper_skill_id (the beast skill it evokes), source_id, template_id,
## is_boss, brain, passives (a profile's `passives` dict:
## { killers { "physical:7": 50 }, killer_cap_bonus { "7": 10 }, lb_damage_pct,
## skill_boosts [...] }).
static func from_spec(spec: Dictionary) -> Combatant:
	var fighter := Combatant.new()
	fighter.side = Combatant.Side.PARTY if bool(spec.get("party", true)) else Combatant.Side.ENEMY
	fighter.name = str(spec.get("name", "Fighter"))
	fighter.source_id = str(spec.get("source_id", fighter.name))
	fighter.template_id = str(spec.get("template_id", ""))
	fighter.level = int(spec.get("level", 1))
	fighter.is_boss = bool(spec.get("is_boss", false))
	fighter.sex = int(spec.get("sex", Combatant.SEX_UNKNOWN))
	for race in spec.get("races", []):
		fighter.races.append(int(race))
	fighter.base_stats = {
		"HP": int(spec.get("hp", 1000)),
		"MP": int(spec.get("mp", 100)),
		"ATK": int(spec.get("atk", 100)),
		"DEF": int(spec.get("def", 100)),
		"MAG": int(spec.get("mag", 100)),
		"SPR": int(spec.get("spr", 100)),
	}
	fighter.raw_stats = fighter.base_stats.duplicate()
	fighter.raw_stats.merge(spec.get("raw_stats", {}), true)
	fighter.max_hp = int(fighter.base_stats["HP"])
	fighter.hp = fighter.max_hp
	fighter.max_mp = int(fighter.base_stats["MP"])
	fighter.mp = fighter.max_mp
	fighter.element_resist = _keyed_table(DamageFormula.ELEMENT_NAMES, spec.get("element_resist", {}))
	fighter.status_resist = _keyed_table(Combatant.AILMENTS, spec.get("ailment_resist", {}))
	fighter.debuff_resist = _keyed_table(Combatant.DEBUFF_KEYS, spec.get("debuff_resist", {}))
	fighter.physical_resist = int(spec.get("physical_resist", 0))
	fighter.magic_resist = int(spec.get("magic_resist", 0))
	fighter.passives = CombatantPassives.from_profile(spec.get("passives", {}))
	for key in spec.get("weapon_inflicts", {}):
		if int(spec["weapon_inflicts"][key]) > 0:
			fighter.weapon_inflicts[str(key).to_upper()] = int(spec["weapon_inflicts"][key])
	for element in spec.get("weapon_elements", []):
		fighter.weapon_elements.append(int(element))
	for atk in spec.get("hand_atk", []):
		fighter.hand_atk.append(int(atk))
	var variance: Array = spec.get("weapon_variance", [100, 100])
	fighter.weapon_variance_min = int(variance[0])
	fighter.weapon_variance_max = int(variance[1])
	fighter.two_handed = bool(spec.get("two_handed", false))
	fighter.max_lb = int(spec.get("max_lb", 0))
	fighter.lb = int(spec.get("lb", 0))
	fighter.limit_burst_id = str(spec.get("limit_burst_id", ""))
	fighter.esper_id = int(spec.get("esper_id", 0))
	fighter.esper_skill_id = str(spec.get("esper_skill_id", ""))
	fighter.attack_skill = BattleSkill.basic_attack(
		str(spec.get("attack_frames", DEFAULT_ATTACK_FRAMES)), int(spec.get("move_type", 0))
	)
	var brain: Variant = spec.get("brain")
	if brain is EnemyBrain:
		fighter.brain = brain
	elif fighter.is_enemy():
		fighter.brain = EnemyBrain.new()
	return fighter


## Copies stats, pools and resistances from a StatCalculator profile
## ({ stats, base_stats, element_resist, status_resist, debuff_resist, ... }). HP and MP
## start full. Units carry `base_stats` (the level curve before equipment and passives),
## which is what buffs scale; monsters do not, so their raw stats equal their stats.
## Units also carry `debuff_resist` (break, stop and charm resistance from passives);
## a monster's comes from its parts row and is set before this runs. `passives` (the
## battle modifiers) becomes the fighter's CombatantPassives; monsters have none. The
## weapons in the loadout's hands give the weapon inflicts, elements, per-hand ATK and
## weapon variance.
static func apply_profile(fighter: Combatant, profile: Dictionary) -> void:
	fighter.profile = profile
	var stats: Dictionary = profile.get("stats", {})
	var raw: Dictionary = profile.get("base_stats", stats)
	fighter.base_stats = {}
	fighter.raw_stats = {}
	for stat_name in ["HP", "MP", "ATK", "DEF", "MAG", "SPR"]:
		fighter.base_stats[stat_name] = int(stats.get(stat_name, 0))
		fighter.raw_stats[stat_name] = int(raw.get(stat_name, stats.get(stat_name, 0)))
	fighter.max_hp = maxi(1, int(fighter.base_stats["HP"]))
	fighter.hp = fighter.max_hp
	fighter.max_mp = maxi(0, int(fighter.base_stats["MP"]))
	fighter.mp = fighter.max_mp
	fighter.element_resist = _keyed_table(DamageFormula.ELEMENT_NAMES, profile.get("element_resist", {}))
	fighter.status_resist = _keyed_table(Combatant.AILMENTS, profile.get("status_resist", {}))
	if profile.has("debuff_resist"):
		fighter.debuff_resist = _keyed_table(Combatant.DEBUFF_KEYS, profile["debuff_resist"])
	elif fighter.debuff_resist.is_empty():
		fighter.debuff_resist = _keyed_table(Combatant.DEBUFF_KEYS, {})
	fighter.passives = CombatantPassives.from_profile(profile.get("passives", {}))
	var loadout: Variant = profile.get("loadout", {})
	fighter.weapon_inflicts = weapon_inflicts_from(loadout)
	fighter.weapon_elements = weapon_elements_from(loadout)
	fighter.hand_atk = hand_atk_from(loadout)
	var variance: Vector2i = weapon_variance_from(loadout)
	fighter.weapon_variance_min = variance.x
	fighter.weapon_variance_max = variance.y
	fighter.two_handed = two_handed_from(loadout)


## Whether a weapon in a PassiveSources loadout's hands is two-handed (`is_twohanded`,
## equipFeature 1), which takes both hands.
static func two_handed_from(loadout: Variant) -> bool:
	for hand in _weapons(loadout):
		if bool(hand.get("two_handed", false)):
			return true
	return false


## The ailments the weapons in a PassiveSources loadout's hands inflict, { AILMENT key:
## chance }, non-zero only. Two weapons with the same ailment give the higher chance
## (the user's rule, 2026-10-02).
static func weapon_inflicts_from(loadout: Variant) -> Dictionary:
	var inflicts: Dictionary = {}
	for hand in _weapons(loadout):
		var chances: Array = hand.get("inflicts", [])
		for i in range(mini(chances.size(), Combatant.AILMENTS.size())):
			var key: String = Combatant.AILMENTS[i]
			if int(chances[i]) > int(inflicts.get(key, 0)):
				inflicts[key] = int(chances[i])
	return inflicts


## Every element of the weapons in a loadout's hands, once each, right hand first (wiki:
## dual wield adds both weapons' elements to physical attacks).
static func weapon_elements_from(loadout: Variant) -> PackedInt32Array:
	var elements := PackedInt32Array()
	for hand in _weapons(loadout):
		for element in hand.get("elements", []):
			if int(element) >= 1 and int(element) <= DamageFormula.ELEMENT_NAMES.size() and not elements.has(int(element)):
				elements.append(int(element))
	return elements


## The ATK each weapon in a loadout's hands adds, right hand first: its own ATK plus the
## share of the equipment-stat boosts StatCalculator put on the hand (`equipment_bonus`).
## A dual wielder's swing leaves the other weapon's out (DualWield).
static func hand_atk_from(loadout: Variant) -> PackedInt32Array:
	var atk := PackedInt32Array()
	for hand in _weapons(loadout):
		var stats: Dictionary = hand.get("stats", {})
		var bonus: Dictionary = hand.get("equipment_bonus", {})
		atk.append(int(stats.get("ATK", 0)) + int(bonus.get("ATK", 0)))
	return atk


## The weapon variance of a loadout's first weapon in hand order (the right hand's, or
## the left's when the right holds none) as (min, max) whole percent, from its
## dmgVariance ("110,120"). A dual wielder's swings both use the right hand's (wiki:
## "only the right hand weapon variance is used for both hits"). (100, 100) without a
## weapon or a readable range.
static func weapon_variance_from(loadout: Variant) -> Vector2i:
	var weapons: Array[Dictionary] = _weapons(loadout)
	if weapons.is_empty():
		return Vector2i(100, 100)
	var parts: PackedStringArray = str(weapons[0].get("variance", "")).split(",")
	if parts.size() != 2 or not parts[0].strip_edges().is_valid_int() or not parts[1].strip_edges().is_valid_int():
		return Vector2i(100, 100)
	var low: int = parts[0].strip_edges().to_int()
	var high: int = parts[1].strip_edges().to_int()
	return Vector2i(mini(low, high), maxi(low, high))


## The weapon hands of a PassiveSources loadout, in its hand order (right hand first).
static func _weapons(loadout: Variant) -> Array[Dictionary]:
	var weapons: Array[Dictionary] = []
	if not (loadout is Dictionary):
		return weapons
	for hand in loadout.get("hands", []):
		if hand is Dictionary and str(hand.get("kind", "")) == PassiveSources.HAND_WEAPON:
			weapons.append(hand)
	return weapons


## monster_parts.debuffResists ("0,0,0,0,100,100,100") as { ATK, DEF, MAG, SPR, STOP,
## CHARM, BERSERK }. The order follows opcode 89's keys; big bosses read 0 for the
## four stats (breakable) and 100 for the rest.
static func debuff_resist_from(raw: Variant) -> Dictionary:
	var table: Dictionary = _keyed_table(Combatant.DEBUFF_KEYS, {})
	var values: PackedStringArray = _text(raw).split(",", false)
	for i in range(mini(values.size(), Combatant.DEBUFF_KEYS.size())):
		if values[i].strip_edges().is_valid_int():
			table[Combatant.DEBUFF_KEYS[i]] = int(values[i])
	return table


## Race ids from a tribe column: "5", or "4,8" for the 620 monster parts with several
## races (killers and race mitigation average over them). Empty for SQL NULL or text
## that holds no id.
static func races_from(raw: Variant) -> PackedInt32Array:
	var races := PackedInt32Array()
	for token in _text(raw).split(",", false):
		var race: String = token.strip_edges()
		if race.is_valid_int() and int(race) > 0:
			races.append(int(race))
	return races


## { key: 0 } for every key, overlaid with the values in `source` (keys upper-cased).
static func _keyed_table(keys: PackedStringArray, source: Variant) -> Dictionary:
	var table: Dictionary = {}
	for key in keys:
		table[key] = 0
	if source is Dictionary:
		for key in source.keys():
			var upper: String = str(key).to_upper()
			if table.has(upper):
				table[upper] = int(source[key])
	return table


static func _frames_or_default(raw: Variant) -> String:
	var text: String = _text(raw)
	return text if text != "" else DEFAULT_ATTACK_FRAMES


## A DB column as trimmed text; "" for SQL NULL.
static func _text(raw: Variant) -> String:
	return "" if raw == null else str(raw).strip_edges()
