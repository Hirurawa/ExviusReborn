class_name BattleCommandMenu
extends RefCounted

## What the battle screen's skill and item menus offer a party member, why an option is
## greyed out, whom a skill lets the player pick, and what Reload and Repeat restore.
## It reads the engine; the screen draws the options (Skill.tscn's
## setup_from_skill_data takes `skill.record`) and sends the commands through the
## session. Replaces the old battle_ui.gd's _open_skill_menu list,
## _skill_disabled_reason, _can_unit_pay_skill_mp, _resolve_action, the validity rule
## of _enter_ally_selection_state, _unit_has_saved_skill and _saved_target_is_valid.
## SandboxBattleFactory.command_options builds a similar list for the sandbox.

## disabled_reason values. The first four match the Skill button's overlays
## (features/shared/skill.gd): none, "lack MP", "lack limit", "lack summon" (the esper
## gauge is not full or holds too few orbs). Any other refusal (silenced, not ready, no
## uses left, already acted, not the player's phase...) is REASON_UNAVAILABLE: greyed,
## with no overlay.
const REASON_NONE: String = ""
const REASON_LACK_MP: String = "lack_mp"
const REASON_LACK_LIMIT: String = "lack_limit"
const REASON_LACK_SUMMON: String = "lack_summon"
const REASON_UNAVAILABLE: String = "unavailable"

## role_style values, the Skill button's backgrounds.
const ROLE_STANDARD: String = "standard"
const ROLE_LIMITBURST: String = "limitburst"
const ROLE_ESPER: String = "esper_skill"


## The skill menu of party member `unit`, in the old menu's order: its limit burst, its
## esper, then its magic and abilities (the StatCalculator profile's skills: innate,
## equipment and esper ones), then the multicast commands its passives give (52, 53),
## then the skills it holds through grants (op 100, engine.grants_of; source "Granted").
## Each option is { command, skill, name, source, awaken_level, role_style,
## disabled_reason, limits, targeting, multicast_count }: `limits` is
## engine.skill_limits ({} when the skill has none), `targeting` is targeting() of what
## the command runs, `multicast_count` how many skills a multicast command picks (0 for
## any other option; see multicast_options). A skill the catalog cannot build is left
## out, as before.
static func options(engine: BattleEngine, unit: Combatant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if unit.limit_burst_id != "":
		var limit_burst: BattleSkill = engine.catalog.get_limit_burst(unit.limit_burst_id, unit.limit_burst_level)
		if limit_burst != null:
			out.append(_option(engine, unit, BattleCommand.limit_burst(unit.limit_burst_id), limit_burst, "", 0, ROLE_LIMITBURST))
	if unit.esper_skill_id != "":
		var esper: BattleSkill = engine.catalog.get_skill(BattleSkill.KIND_ESPER, unit.esper_skill_id)
		if esper != null:
			out.append(_option(engine, unit, BattleCommand.evoke(), esper, "Esper", 0, ROLE_ESPER))
	for entry in _skill_entries(engine, unit):
		out.append(_option(engine, unit, entry["command"], entry["skill"], entry["source"], entry["awaken_level"], ROLE_STANDARD))
	return out


## What a multicast draft offers: options(), with each option's disabled_reason saying
## whether it can be the next pick of `command` after `picks`
## (engine.multicast_pick_problem): what the command cannot cast, the limit burst, the
## esper, other commands and a limited skill already picked are REASON_UNAVAILABLE; a pick
## the unit cannot pay for on top of the earlier ones shows its lack overlay. Each option
## also carries `picked`, how many times the draft already holds it.
static func multicast_options(engine: BattleEngine, unit: Combatant, command: BattleCommand, picks: Array[BattleCommand]) -> Array[Dictionary]:
	var out: Array[Dictionary] = options(engine, unit)
	for option in out:
		var candidate: BattleCommand = option["command"]
		option["disabled_reason"] = disabled_reason(engine.multicast_pick_problem(unit.id, command, picks, candidate))
		var picked: int = 0
		for pick in picks:
			if pick.kind == candidate.kind and pick.skill_kind == candidate.skill_kind and pick.skill_id == candidate.skill_id:
				picked += 1
		option["picked"] = picked
	return out


## The item menu of party member `unit`: each item of the party's stock (in the combat
## item bar's order) that `unit` can still pick, { command, skill, name, item_id, count,
## disabled_reason, targeting }. `count` is engine.items_available: the stock less the
## items other members hold queued; an item at 0 is left out.
static func item_options(engine: BattleEngine, unit: Combatant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item_id in engine.item_stock:
		var count: int = engine.items_available(str(item_id), unit.id)
		var skill: BattleSkill = engine.catalog.get_item(str(item_id))
		if count <= 0 or skill == null:
			continue
		var command: BattleCommand = BattleCommand.item(str(item_id))
		out.append({
			"command": command,
			"skill": skill,
			"name": skill.name,
			"item_id": str(item_id),
			"count": count,
			"disabled_reason": disabled_reason(engine.can_execute(unit.id, command)),
			"targeting": targeting(engine.executed_skill(unit.id, command)),
		})
	return out


## The Skill button's reason for a can_execute result (see the REASON_ constants).
static func disabled_reason(result: StringName) -> String:
	match result:
		BattleEngine.OK:
			return REASON_NONE
		BattleEngine.REJECT_NOT_ENOUGH_MP:
			return REASON_LACK_MP
		BattleEngine.REJECT_LIMIT_NOT_FULL:
			return REASON_LACK_LIMIT
		BattleEngine.REJECT_ESPER_GAUGE_NOT_FULL, BattleEngine.REJECT_NOT_ENOUGH_ORBS:
			return REASON_LACK_SUMMON
	return REASON_UNAVAILABLE


## Whom `skill` (what a command runs: engine.executed_skill) lets the player pick, the
## rule SkillResolver._build_targeting_metadata used:
##   needs_ally_pick    an effect aims at one member of the caster's side (target 2, 5
##                      or 6, single target): the screen asks for an ally first
##   targets_fallen     the pick must be KO'd (the record's targetType 7, or a revive)
##   targets_opponent   an effect aims at the other side: the screen's chosen enemy
##   others_only        every ally pick is "an ally except the caster" (target 5)
static func targeting(skill: BattleSkill) -> Dictionary:
	var result: Dictionary = {
		"needs_ally_pick": false,
		"targets_fallen": false,
		"targets_opponent": false,
		"others_only": false,
	}
	if skill == null:
		return result
	var ally_picks: int = 0
	var other_picks: int = 0
	for effect in skill.effects:
		if BattleEngine.LINK_TYPES.has(effect.type):
			continue
		match effect.target_type:
			SkillEffect.TARGET_OPPONENT:
				result["targets_opponent"] = true
			SkillEffect.TARGET_ALLY, SkillEffect.TARGET_ALLY_EXCEPT_SELF, SkillEffect.TARGET_ALLY_ALT:
				if effect.target_area == SkillEffect.AREA_SINGLE:
					ally_picks += 1
					if effect.target_type == SkillEffect.TARGET_ALLY_EXCEPT_SELF:
						other_picks += 1
	result["needs_ally_pick"] = ally_picks > 0
	result["others_only"] = ally_picks > 0 and other_picks == ally_picks
	result["targets_fallen"] = str(skill.record.get("targetType", "")).to_int() == 7 \
		or skill.has_effect_type(["REVIVE"])
	return result


## Whether party member `ally` is a valid pick for a skill with `skill_targeting`
## (targeting()): KO'd for a revive, living and on the field otherwise (not in the air),
## and not `caster` when the skill only reaches the others.
static func valid_ally(skill_targeting: Dictionary, ally: Combatant, caster: Combatant = null) -> bool:
	if ally == null or not ally.is_party():
		return false
	if bool(skill_targeting.get("others_only", false)) and caster != null and ally.id == caster.id:
		return false
	if bool(skill_targeting.get("targets_fallen", false)):
		return not ally.is_alive()
	return ally.is_targetable()


## What Reload and Repeat queue for `unit`: LAND for a unit in the air with a jump it can
## land now; otherwise a copy of the last command it executed, when the engine would run
## it now (can_execute: phase, MP, gauge, orbs, cooldowns, uses, items left, silence, and
## every pick of a multicast), the unit still has each skill it names (a granted skill
## only while the grant lasts), and its ally picks are still valid, or, for a command that
## aims at opponents, an enemy is still standing. null otherwise. The screen sets the
## enemy target when it executes, as for any command.
static func restore_command(engine: BattleEngine, unit: Combatant) -> BattleCommand:
	if unit != null and engine.landing_ready(unit):
		return BattleCommand.land()
	if unit == null or unit.last_command == null:
		return null
	var command: BattleCommand = unit.last_command.duplicate_command()
	if engine.can_execute(unit.id, command) != BattleEngine.OK or not _has_skills(engine, unit, command):
		return null
	if command.kind == BattleCommand.Kind.DEFEND:
		return command
	var parts: Array[BattleCommand] = command.picks.duplicate()
	if parts.is_empty():
		parts.append(command)
	for part in parts:
		var skill_targeting: Dictionary = targeting(engine.executed_skill(unit.id, part))
		if bool(skill_targeting["needs_ally_pick"]) and not valid_ally(skill_targeting, engine.combatant(part.target_id), unit):
			return null
	if aims_at_opponents(engine, unit, command) and engine.living_enemies().is_empty():
		return null
	return command


## Whether `command` takes the screen's chosen enemy: a skill that aims at the other side
## and lets the player pick no ally, or a multicast with such a pick left without its own
## target. A basic attack (no command) does.
static func aims_at_opponents(engine: BattleEngine, unit: Combatant, command: BattleCommand) -> bool:
	if command == null:
		return true
	if command.picks.is_empty():
		var skill_targeting: Dictionary = targeting(engine.executed_skill(unit.id, command))
		return bool(skill_targeting["targets_opponent"]) and not bool(skill_targeting["needs_ally_pick"])
	for pick in command.picks:
		if pick.target_id < 0 and aims_at_opponents(engine, unit, pick):
			return true
	return false


## The unit's magic and abilities as { command, skill, source, awaken_level }: the
## profile's skills, then the multicast commands its passives give that the profile does
## not list (source "Trait": passive 53 is innate on all but one item), then its granted
## skills that neither lists (source "Granted").
static func _skill_entries(engine: BattleEngine, unit: Combatant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var listed: Dictionary = {}
	var skills: Dictionary = unit.profile.get("skills", {})
	for kind in [BattleSkill.KIND_MAGIC, BattleSkill.KIND_ABILITY]:
		for entry in skills.get(str(kind), []):
			if not entry is Dictionary:
				continue
			var skill_id: String = str(int(entry.get("id", 0)))
			var skill: BattleSkill = engine.catalog.get_skill(kind, skill_id)
			if skill == null:
				continue
			listed["%s:%s" % [kind, skill_id]] = true
			out.append({"command": BattleCommand.skill(kind, skill_id), "skill": skill,
				"source": str(entry.get("source", "")), "awaken_level": int(entry.get("awaken_level", 0))})
	for command_id in unit.passives.multicast_commands:
		var skill: BattleSkill = engine.catalog.get_skill(BattleSkill.KIND_ABILITY, command_id)
		if skill == null or listed.has("%s:%s" % [BattleSkill.KIND_ABILITY, command_id]):
			continue
		listed["%s:%s" % [BattleSkill.KIND_ABILITY, command_id]] = true
		out.append({"command": BattleCommand.skill(BattleSkill.KIND_ABILITY, command_id), "skill": skill, "source": "Trait", "awaken_level": 0})
	for grant in engine.grants_of(unit.id):
		var skill: BattleSkill = engine.catalog.get_skill(grant.skill_kind, grant.skill_id)
		if skill == null or listed.has(grant.key()):
			continue
		listed[grant.key()] = true
		out.append({"command": BattleCommand.skill(grant.skill_kind, grant.skill_id), "skill": skill, "source": "Granted", "awaken_level": 0})
	return out


## Whether every SKILL command in `command` (itself, or each pick of a multicast) names a
## skill in the unit's menu. Other kinds are not checked.
static func _has_skills(engine: BattleEngine, unit: Combatant, command: BattleCommand) -> bool:
	if command.kind != BattleCommand.Kind.SKILL:
		return true
	var offered: Dictionary = {}
	for entry in _skill_entries(engine, unit):
		var entry_command: BattleCommand = entry["command"]
		offered["%s:%s" % [entry_command.skill_kind, entry_command.skill_id]] = true
	var parts: Array[BattleCommand] = [command]
	parts.append_array(command.picks)
	for part in parts:
		if not offered.has("%s:%s" % [part.skill_kind, part.skill_id]):
			return false
	return true


## The disabled_reason of a multicast command in the normal list: what can_execute says
## about the command itself (its picks are not chosen yet), and unavailable when no skill
## of the unit can be its first pick.
static func _command_reason(engine: BattleEngine, unit: Combatant, command: BattleCommand) -> StringName:
	var result: StringName = engine.can_execute(unit.id, command)
	if result != BattleEngine.REJECT_MULTICAST_INCOMPLETE:
		return result
	var no_picks: Array[BattleCommand] = []
	for entry in _skill_entries(engine, unit):
		if engine.multicast_pick_problem(unit.id, command, no_picks, entry["command"]) == BattleEngine.OK:
			return BattleEngine.OK
	return BattleEngine.REJECT_NOT_MULTICASTABLE


static func _option(engine: BattleEngine, unit: Combatant, command: BattleCommand, skill: BattleSkill, source: String, awaken_level: int, role_style: String) -> Dictionary:
	var rule: Multicast.Rule = engine.multicast_rule(unit.id, command)
	var result: StringName = _command_reason(engine, unit, command) if rule != null else engine.can_execute(unit.id, command)
	return {
		"command": command,
		"skill": skill,
		"name": skill.name,
		"source": source,
		"awaken_level": awaken_level,
		"role_style": role_style,
		"disabled_reason": disabled_reason(result),
		"limits": engine.skill_limits(unit.id, command),
		"targeting": targeting(engine.executed_skill(unit.id, command)),
		"multicast_count": rule.count if rule != null else 0,
	}
