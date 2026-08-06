extends RefCounted
class_name MonsterStatCalculator

## Final-stat profile for a battle monster. Reached through
## StatCalculator.calculate_final_stats(), which dispatches here on `is_monster`, so
## every existing consumer of `final_stats` works for both sides without knowing which
## kind of combatant it is holding.
##
## WHY THIS IS SEPARATE. Monsters and units both need "base stats, plus active
## buffs/debuffs, plus resistances", but almost nothing underneath that matches:
##
##   base stats    A unit interpolates a "min,max" growth curve across its level against
##                 RARITY_MAX_LEVELS[current_rarity]. A monster has one flat value per
##                 stat on its MONSTER_PARTS row -- no curve, no rarity, and its `level`
##                 is descriptive rather than an input to any formula.
##   contributors  A unit layers on equipment, esper bonuses, innate trait skills and
##                 parsed passive opcodes. A monster has none of those.
##   monster-only  MONSTER_PARTS carries physicsDmgCut / magicDmgCut, debuffResists and
##                 spResist, which no unit has. (Not consumed yet -- see below.)
##
## Running a monster through the unit path would mean fabricating current_rarity, a
## RARITY_MAX_LEVELS entry, an empty equipment dict, unitSeries/rare that resolve to no
## skills, and "N,N" stat strings -- five fictions to satisfy code that then does
## nothing with them, and each one a trap for the next reader. So the bodies are split.
## What genuinely IS shared -- the stat vocabulary, innate-resist decoding, and how
## buffs and debuffs combine -- lives on StatCalculator and is called from here, so a
## Full Break resolves identically on a boss and on a party member.
##
## INPUTS, all placed on the enemy dict by BattleManager._generate_enemy_from_descriptor:
##   base_stats          { HP, MP, ATK, DEF, MAG, SPR } flat, from MONSTER_PARTS
##   elemResistValue     the raw comma-separated MONSTER_PARTS string
##   ailmentResistValue  likewise
##   active_effects      buffs/debuffs applied during the battle
##
## NOT MODELLED YET, and each needs work outside this file to be useful:
##   * monster passives (monster_passive_skill_set -> monster_passive_skill) would fill
##     `skills` / `passive_effects`; nothing consumes those for enemies today.
##   * physicsDmgCut / magicDmgCut and debuffResists need action_processor support.

## Builds the profile. Shape matches StatCalculator.calculate_final_stats exactly.
static func calculate_final_stats(monster: Dictionary) -> Dictionary:
	var profile: Dictionary = StatCalculator.empty_stat_profile()

	var pools: Dictionary = StatCalculator.new_modifier_pools()
	var pct_mods: Dictionary = pools["pct"]
	var element_resists: Dictionary = pools["element"]
	var status_resists: Dictionary = pools["status"]

	StatCalculator.seed_innate_resists(monster, element_resists, status_resists)
	StatCalculator.apply_active_modifiers(
		StatCalculator.collect_active_modifiers(monster), pct_mods, element_resists, status_resists
	)

	for stat_name in profile["stats"].keys():
		profile["stats"][stat_name] = StatCalculator.combine_stat(
			float(_base_stat(monster, stat_name)), int(pct_mods.get(stat_name, 0)), 0
		)

	profile["element_resist"] = element_resists
	profile["status_resist"] = status_resists
	return profile


## One flat base stat. Falls back to the monster's existing final_stats so that a
## recalculation triggered mid-battle can never zero out a monster that was spawned
## without a base_stats block -- it would otherwise drop to 0 ATK/DEF the first time
## anything debuffed it.
static func _base_stat(monster: Dictionary, stat_name: String) -> int:
	var base_stats: Dictionary = monster.get("base_stats", {})
	if base_stats.has(stat_name):
		return int(base_stats[stat_name])

	var existing: Dictionary = monster.get("final_stats", {}).get("stats", {})
	if existing.has(stat_name):
		_warn_missing_base_stats(monster)
		return int(existing[stat_name])

	_warn_missing_base_stats(monster)
	return 0


static var _warned_monsters: Dictionary = {}


## Warns once per monster, since a stat recalculation can run several times a turn.
static func _warn_missing_base_stats(monster: Dictionary) -> void:
	var key: String = str(monster.get("instance_id", monster.get("id", "?")))
	if _warned_monsters.has(key):
		return
	_warned_monsters[key] = true
	push_warning("MonsterStatCalculator: monster %s has no base_stats block; falling back to its existing final_stats. It was probably built outside _generate_enemy_from_descriptor." % key)
