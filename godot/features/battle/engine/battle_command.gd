class_name BattleCommand
extends RefCounted

## What a combatant is told to do: the player's queued choice for a unit, or an enemy AI
## decision turned into the same shape. BattleEngine.queue_command and execute take one.

## LAND brings down a unit in the air from a jump the player lands (opcode 134; BattleEngine,
## DELAYS AND JUMPS). Appended last, so the other values keep their numbers.
enum Kind { ATTACK, DEFEND, SKILL, ITEM, LIMIT_BURST, EVOKE, LAND }

## A Kind value (typed int; see Combatant.side).
var kind: int = Kind.ATTACK
## BattleSkill.KIND_* of the skill to run: magic or ability for SKILL, item for ITEM,
## limitburst for LIMIT_BURST, esper for EVOKE, monster_skill for enemy skills. A LAND
## action's command names the jump (filled in by the engine).
var skill_kind: StringName = BattleSkill.KIND_ATTACK
var skill_id: String = ""
## Combatant id of the chosen target; -1 lets the engine pick the default.
var target_id: int = -1
## Opaque data from the caller (the old UI's queued payload), echoed in action events.
var payload: Dictionary = {}
## A multicast command's picks, in casting order: SKILL commands, each cast as its own
## action (Multicast). A pick whose target_id is -1 takes this command's target. Empty
## for every other command.
var picks: Array[BattleCommand] = []


static func attack(target: int = -1) -> BattleCommand:
	var command := BattleCommand.new()
	command.kind = Kind.ATTACK
	command.skill_kind = BattleSkill.KIND_ATTACK
	command.target_id = target
	return command


static func defend() -> BattleCommand:
	var command := BattleCommand.new()
	command.kind = Kind.DEFEND
	command.skill_kind = &""
	return command


## A magic, ability or monster skill.
static func skill(kind_of_skill: StringName, id: String, target: int = -1) -> BattleCommand:
	var command := BattleCommand.new()
	command.kind = Kind.SKILL
	command.skill_kind = kind_of_skill
	command.skill_id = id
	command.target_id = target
	return command


## A multicast command (Multicast) with the skills it casts, in order.
static func multicast(command_id: String, command_picks: Array[BattleCommand], target: int = -1) -> BattleCommand:
	var command := skill(BattleSkill.KIND_ABILITY, command_id, target)
	command.picks = command_picks
	return command


static func item(item_id: String, target: int = -1) -> BattleCommand:
	var command := BattleCommand.new()
	command.kind = Kind.ITEM
	command.skill_kind = BattleSkill.KIND_ITEM
	command.skill_id = item_id
	command.target_id = target
	return command


static func limit_burst(limit_burst_id: String, target: int = -1) -> BattleCommand:
	var command := BattleCommand.new()
	command.kind = Kind.LIMIT_BURST
	command.skill_kind = BattleSkill.KIND_LIMIT_BURST
	command.skill_id = limit_burst_id
	command.target_id = target
	return command


## Evokes the unit's own esper (Combatant.esper_skill_id), which needs the party's esper
## gauge full.
static func evoke(target: int = -1) -> BattleCommand:
	var command := BattleCommand.new()
	command.kind = Kind.EVOKE
	command.skill_kind = BattleSkill.KIND_ESPER
	command.target_id = target
	return command


## Lands the unit's jump (opcode 134) once it is ready: the jump's landing hits the
## target picked at the jump (the wiki), so the command takes none.
static func land() -> BattleCommand:
	var command := BattleCommand.new()
	command.kind = Kind.LAND
	command.skill_kind = &""
	return command


func duplicate_command() -> BattleCommand:
	var copy := BattleCommand.new()
	copy.kind = kind
	copy.skill_kind = skill_kind
	copy.skill_id = skill_id
	copy.target_id = target_id
	copy.payload = payload.duplicate(true)
	for pick in picks:
		copy.picks.append(pick.duplicate_command())
	return copy


func describe() -> String:
	var kind_name: String = str(Kind.keys()[kind])
	if kind == Kind.ATTACK or kind == Kind.DEFEND or (kind == Kind.LAND and skill_id == ""):
		return kind_name
	if picks.is_empty():
		return "%s %s:%s" % [kind_name, skill_kind, skill_id]
	var picked: PackedStringArray = []
	for pick in picks:
		picked.append("%s:%s" % [pick.skill_kind, pick.skill_id])
	return "%s %s:%s [%s]" % [kind_name, skill_kind, skill_id, ", ".join(picked)]
