class_name CombatantPassives
extends RefCounted

## A combatant's passive battle modifiers, from its StatCalculator profile's `passives`
## (PassiveAggregator's totals). Stat and resistance passives are not here: they are
## already in the profile's stats and resistance tables. Enemies get an empty one, since
## monster passives are not read.
##
## DamageFormula reads it next to the attacker's statuses: passive killers are capped per
## race (BattleRules.passive_killer_cap_pct plus the race's raise) before active killer
## buffs go on top; passive LB and skill damage add to the matching buffs; EVO MAG and
## the evoke damage boost multiply evoke damage, each capped by BattleRules; so does jump
## damage, for landings. ChainTracker
## reads the chain passives; BattleEngine the gauges at turn end, evasion at cast time,
## aggro when an enemy picks a random target and the ability MP cut; CombatantFactory the
## limit burst change; CoverTracker the covers; the skill menus the multicast commands;
## Counters the counters; BattleEngine the skills cast at the battle start, at each turn
## start and after a revive.

## Killer percent keyed like the KILLER statuses ("physical:7", "magic:7"), summed over
## the unit's passives, not capped.
var killers: Dictionary = {}
## Raise of the passive killer cap, by race id.
var killer_cap_raise: Dictionary = {}
var lb_damage_pct: int = 0
## [{ skill_ids: PackedStringArray, opcodes: Array, damage_type: int, pct: int }], matched
## like SKILL_BOOST statuses (DamageFormula._boost_applies). damage_type 1 boosts every
## physical attack, 2 every magic attack, 3 both; with skill ids it also limits them.
var skill_boosts: Array[Dictionary] = []
## How far the unit's passives raise its chain cap, in percent (ChainTracker caps the
## result at BattleRules.chain_cap_ceiling_pct).
var chain_cap_raise: int = 0
## Percent added to the chain multiplier of the unit's own chained hits, up to its cap.
var chain_boost_pct: int = 0
## Added to the LB fill rate statuses (Combatant.lb_fill_rate).
var lb_fill_rate_pct: int = 0
## Percent of max MP restored at the end of each turn.
var mp_regen_pct: int = 0
## Limit gauge gained at the end of each turn, in hundredths of a crystal (200 = 2
## crystals), raised by the LB fill rate.
var lb_per_turn: int = 0
## Chance in percent to evade a whole physical or magic attack, single-target or AoE.
var evade_physical_pct: int = 0
var evade_magic_pct: int = 0
## Change to the weight enemies pick this unit with: +50 is 1.5 against 1.0.
var aggro_pct: int = 0
## Percent off the MP cost of abilities (not magic).
var ability_mp_cut_pct: int = 0
## EVO MAG in percent (op 21, "boost parameters of espers evoked"), not capped: evoke
## damage x (1 + EVO MAG / 100), up to BattleRules.evo_mag_cap_pct.
var evo_mag_pct: int = 0
## Evoke damage boost in percent (op 64 naming no esper), not capped; up to
## BattleRules.evoke_boost_cap_pct.
var evoke_damage_pct: int = 0
## Jump damage% (op 17), summed, not capped: a landing's damage x (1 + jump% / 100), up
## to BattleRules.jump_damage_cap_pct (DamageFormula.jump_multiplier).
var jump_damage_pct: int = 0
## The limit burst that replaces the unit's own, "" for none.
var lb_change_id: String = ""
## The ability that replaces the normal attack, "" for none (BattleBuilder swaps the
## combatant's attack_skill for it).
var attack_replace_id: String = ""
## Multicast commands (active ability ids, Multicast) the unit's passives (52, 53) put in
## its skill list for the whole battle, each once.
var multicast_commands: PackedStringArray = PackedStringArray()
## What those passives let each command pick: { command id: { count: int, skill_ids:
## PackedStringArray } }. Multicast.rule_for takes it over the command's own record.
var multicast_picks: Dictionary = {}
## Single-target covers of any ally (8 physical, 59 magic): [{ physical, magic, chance,
## mit_min, mit_max, condition (CoverTracker.CONDITION_*), hp_below_pct (covers only
## while the unit's own HP is at or below it; 100 always) }].
var covers: Array[Dictionary] = []
## Counters (12 and 41 with the normal attack, 49 and 50 with a skill; Counters): [{
## trigger ("physical" or "magic"), chance, modifier (the counter's damage in percent of
## the normal attack, 0 = the attack's own), max (counters per turn, 0 = no cap),
## skill_kind (BattleSkill.KIND_ATTACK, _MAGIC, _ABILITY or _MONSTER), skill_id ("" for
## the attack), source_skill_id (the passive) }].
var counters: Array[Dictionary] = []
## Percent every counter chance is raised by, relatively (op 20: 100 doubles it).
var counter_chance_pct: int = 0
## Skills the passives cast on their own (103, 35, 56, 66): [{ skill_kind, skill_id,
## battle_start, revive, turn_start (when it is cast), chance (percent, rolled at each
## turn start for turn-start casts), source_skill_id }].
var auto_casts: Array[Dictionary] = []
## Passive effects nothing reads yet: [{ type, opcode, effect, skill_id, source }].
var unconsumed: Array = []

## The int fields copied from the profile's keys of the same name.
const _SCALARS: PackedStringArray = [
	"lb_damage_pct", "chain_cap_raise", "chain_boost_pct", "lb_fill_rate_pct", "mp_regen_pct", "lb_per_turn",
	"evade_physical_pct", "evade_magic_pct", "aggro_pct", "ability_mp_cut_pct", "evo_mag_pct", "evoke_damage_pct",
	"counter_chance_pct", "jump_damage_pct",
]


## From a profile's `passives` dict (plain data); {} gives an empty one.
static func from_profile(passives: Dictionary) -> CombatantPassives:
	var made := CombatantPassives.new()
	var killers: Variant = passives.get("killers", {})
	if killers is Dictionary:
		for key in killers:
			made.killers[str(key)] = int(killers[key])
	var raises: Variant = passives.get("killer_cap_bonus", {})
	if raises is Dictionary:
		for race in raises:
			made.killer_cap_raise[int(race)] = int(raises[race])
	for field in _SCALARS:
		made.set(field, int(passives.get(field, 0)))
	made.lb_change_id = str(passives.get("lb_change_id", ""))
	made.attack_replace_id = str(passives.get("attack_replace_id", ""))
	for command_id in passives.get("multicast_commands", []):
		if not made.multicast_commands.has(str(command_id)):
			made.multicast_commands.append(str(command_id))
	var picks: Variant = passives.get("multicast_picks", {})
	if picks is Dictionary:
		for command_id in picks:
			var entry: Variant = picks[command_id]
			if entry is Dictionary:
				made.multicast_picks[str(command_id)] = {
					"count": int((entry as Dictionary).get("count", 0)),
					"skill_ids": PackedStringArray(Array((entry as Dictionary).get("skill_ids", [])).map(func(id: Variant) -> String: return str(id))),
				}
	for boost in passives.get("skill_boosts", []):
		if boost is Dictionary:
			var skill_ids := PackedStringArray()
			for skill_id in boost.get("skill_ids", []):
				skill_ids.append(str(skill_id))
			made.skill_boosts.append({
				"skill_ids": skill_ids,
				"opcodes": Array(boost.get("opcodes", [])),
				"damage_type": int(boost.get("damage_type", 0)),
				"pct": int(boost.get("pct", 0)),
			})
	for cover in passives.get("covers", []):
		if cover is Dictionary:
			made.covers.append({
				"physical": bool(cover.get("physical", false)),
				"magic": bool(cover.get("magic", false)),
				"chance": int(cover.get("chance", 0)),
				"mit_min": int(cover.get("mit_min", 0)),
				"mit_max": int(cover.get("mit_max", 0)),
				"condition": int(cover.get("condition", 0)),
				"hp_below_pct": int(cover.get("hp_below_pct", 100)),
			})
	for counter in passives.get("counters", []):
		if counter is Dictionary:
			made.counters.append({
				"trigger": str(counter.get("trigger", "physical")),
				"chance": int(counter.get("chance", 0)),
				"modifier": int(counter.get("modifier", 0)),
				"max": int(counter.get("max", 0)),
				"skill_kind": StringName(str(counter.get("skill_kind", BattleSkill.KIND_ATTACK))),
				"skill_id": str(counter.get("skill_id", "")),
				"source_skill_id": str(counter.get("source_skill_id", "")),
			})
	for cast in passives.get("auto_casts", []):
		if cast is Dictionary:
			made.auto_casts.append({
				"skill_kind": StringName(str(cast.get("skill_kind", BattleSkill.KIND_ABILITY))),
				"skill_id": str(cast.get("skill_id", "")),
				"battle_start": bool(cast.get("battle_start", false)),
				"revive": bool(cast.get("revive", false)),
				"turn_start": bool(cast.get("turn_start", false)),
				"chance": int(cast.get("chance", 100)),
				"source_skill_id": str(cast.get("source_skill_id", "")),
			})
	var unread: Variant = passives.get("unconsumed", [])
	if unread is Array:
		made.unconsumed = (unread as Array).duplicate()
	return made


## Summed passive killer percent against a race, before the cap. `side` is "physical"
## or "magic".
func killer_pct(side: String, race: int) -> int:
	return int(killers.get("%s:%d" % [side, race], 0))


## How far the unit's passives raise the killer cap for a race.
func killer_cap_bonus(race: int) -> int:
	return int(killer_cap_raise.get(race, 0))


func is_empty() -> bool:
	for field in _SCALARS:
		if int(get(field)) != 0:
			return false
	return killers.is_empty() and killer_cap_raise.is_empty() and skill_boosts.is_empty() \
		and lb_change_id == "" and attack_replace_id == "" and covers.is_empty() and multicast_commands.is_empty() \
		and counters.is_empty() and auto_casts.is_empty() and unconsumed.is_empty()


## One line per modifier, for the sandbox inspector.
func describe() -> PackedStringArray:
	var lines := PackedStringArray()
	if not killers.is_empty():
		var parts: PackedStringArray = []
		for key in killers:
			parts.append("%s %d" % [key, killers[key]])
		lines.append("Killers: " + "  ".join(parts))
	if not killer_cap_raise.is_empty():
		lines.append("Killer cap raised: %s" % killer_cap_raise)
	if lb_damage_pct != 0:
		lines.append("LB damage +%d%%" % lb_damage_pct)
	for boost in skill_boosts:
		var target: String = "skills %s" % ", ".join(boost["skill_ids"]) if not (boost["skill_ids"] as PackedStringArray).is_empty() else "all"
		if int(boost["damage_type"]) != 0:
			target += " %s" % {1: "physical", 2: "magic", 3: "physical and magic"}.get(int(boost["damage_type"]), "type %d" % int(boost["damage_type"]))
		if not (boost["opcodes"] as Array).is_empty():
			target += ", opcodes %s" % boost["opcodes"]
		lines.append("Skill damage +%d%% (%s)" % [int(boost["pct"]), target])
	if chain_cap_raise != 0:
		lines.append("Chain cap +%d%%" % chain_cap_raise)
	if chain_boost_pct != 0:
		lines.append("Chain modifier +%d%% on own chained hits" % chain_boost_pct)
	if lb_fill_rate_pct != 0:
		lines.append("LB fill rate +%d%%" % lb_fill_rate_pct)
	if mp_regen_pct != 0:
		lines.append("MP +%d%% of max each turn" % mp_regen_pct)
	if lb_per_turn != 0:
		lines.append("LB +%.2f crystals each turn" % (float(lb_per_turn) / 100.0))
	if evade_physical_pct != 0 or evade_magic_pct != 0:
		lines.append("Evasion: physical %d%%, magic %d%%" % [evade_physical_pct, evade_magic_pct])
	if aggro_pct != 0:
		lines.append("Targeted %+d%%" % aggro_pct)
	if ability_mp_cut_pct != 0:
		lines.append("Ability MP cost -%d%%" % ability_mp_cut_pct)
	if evo_mag_pct != 0:
		lines.append("EVO MAG +%d%%" % evo_mag_pct)
	if evoke_damage_pct != 0:
		lines.append("Evoke damage +%d%%" % evoke_damage_pct)
	if jump_damage_pct != 0:
		lines.append("Jump damage +%d%%" % jump_damage_pct)
	if lb_change_id != "":
		lines.append("Limit burst changed to %s" % lb_change_id)
	if attack_replace_id != "":
		lines.append("Normal attack replaced by ability %s" % attack_replace_id)
	if not multicast_commands.is_empty():
		var parts: PackedStringArray = []
		for command_id in multicast_commands:
			var picks: Dictionary = multicast_picks.get(command_id, {})
			var listed: int = (picks.get("skill_ids", PackedStringArray()) as PackedStringArray).size()
			parts.append("%s (x%d%s)" % [command_id, int(picks.get("count", 0)), ", %d listed" % listed if listed > 0 else ""])
		lines.append("Multicast commands: %s" % ", ".join(parts))
	for cover in covers:
		var kind: String = "physical" if bool(cover["physical"]) else "magic"
		var whom: String = {1: "a female ally", 2: "a male ally"}.get(int(cover["condition"]), "an ally")
		var mitigation: String = "%d%%" % int(cover["mit_min"]) if int(cover["mit_min"]) == int(cover["mit_max"]) \
			else "%d-%d%%" % [int(cover["mit_min"]), int(cover["mit_max"])]
		var gate: String = " at %d%% HP or less" % int(cover["hp_below_pct"]) if int(cover["hp_below_pct"]) < 100 else ""
		lines.append("Cover %s: %d%% to take %s's hits, -%s%s" % [kind, int(cover["chance"]), whom, mitigation, gate])
	for counter in counters:
		lines.append("Counter %s attacks %d%%: %s%s" % [counter["trigger"], int(counter["chance"]), counter_text(counter),
			", %d per turn" % int(counter["max"]) if int(counter["max"]) > 0 else ""])
	if counter_chance_pct != 0:
		lines.append("Counter chance +%d%%" % counter_chance_pct)
	for cast in auto_casts:
		var when: PackedStringArray = []
		if bool(cast["battle_start"]):
			when.append("battle start")
		if bool(cast["revive"]):
			when.append("revive")
		if bool(cast["turn_start"]):
			when.append("turn start" if int(cast["chance"]) >= 100 else "turn start %d%%" % int(cast["chance"]))
		lines.append("Casts %s:%s at %s" % [cast["skill_kind"], cast["skill_id"], " and ".join(when)])
	if not unconsumed.is_empty():
		var counts: Dictionary = {}
		for effect in unconsumed:
			var effect_type: String = str(effect.get("type", ""))
			counts[effect_type] = int(counts.get(effect_type, 0)) + 1
		var parts: PackedStringArray = []
		for effect_type in counts:
			parts.append("%s x%d" % [effect_type, counts[effect_type]] if int(counts[effect_type]) > 1 else effect_type)
		lines.append("Not used yet: " + ", ".join(parts))
	return lines


## What a counter answers with, for the logs: "attack x2.00" or "ability:503010".
static func counter_text(counter: Dictionary) -> String:
	if StringName(counter.get("skill_kind", BattleSkill.KIND_ATTACK)) == BattleSkill.KIND_ATTACK:
		var modifier: int = int(counter.get("modifier", 0))
		return "attack x%.2f" % (float(modifier) / 100.0) if modifier > 0 else "attack"
	return "%s:%s" % [counter["skill_kind"], counter["skill_id"]]
