class_name SkillHistory
extends RefCounted

## What one combatant has done, for the skills that depend on it. The engine calls
## begin() when an action starts and clear() when the combatant is KO'd.
##
## STACKS (ops 72, 126, 1007, "power up with consecutive use"; the user's rules,
## 2026-10-05, from the wiki). A stacking ability deals base + stack modifier x stacks,
## the stacks not counting the initial cast. Each combatant has one stack:
##   - casting the stacking ability the stack belongs to adds a stack (up to its
##     maximum), unless the combatant's previous action was a normal attack or a guard;
##   - casting another stacking ability starts a fresh stack for that one;
##   - other abilities, magic, limit bursts, evocations and items leave the stack alone,
##     and so do ailments that skip a turn (nothing is recorded);
##   - dying clears it, a reraise included.
## So a guard followed by a dualcast of a non-stacking spell and the stacking spell
## keeps the stack (the stacking spell's previous action is the other spell), as the
## wiki says; the same holds for a non-stacking spell on its own turn in between, which
## the wiki does not cover (the user chose the simplest model).
##
## LAST TURN (op 99). `used` keeps every action's keys for the current turn and the one
## before it, by the engine's total_turns (which does not restart each wave).
##
## A key is the skill's kind and id ("ability:207780", "magic:20350",
## "limitburst:100000414", "monster_skill:120280"), or ATTACK, DEFEND, ITEM, ESPER.

const ATTACK: String = "attack"
const DEFEND: String = "defend"
const ITEM: String = "item"
const ESPER: String = "esper"
## The effect types of stacking damage.
const STACKING_TYPES: PackedStringArray = ["CONSECUTIVE_MAG_DAMAGE", "CONSECUTIVE_PHYS_DAMAGE", "CONSECUTIVE_DAMAGE_V3"]

## The previous action: the key of the skill its command named, and of the skill that
## ran (they differ for wrappers and op 99). "" before the first action.
var previous_declared: String = ""
var previous_executed: String = ""
## The stacking ability the stack belongs to ("" for none) and its stacks (0 on the
## initial cast).
var stack_key: String = ""
var stacks: int = 0
## total_turns -> { key: true }: the declared and executed keys of every action started
## on that turn. Only the current turn and the previous one are kept.
var used: Dictionary = {}


## The key of what `command` runs as `skill` (its declared or its executed skill).
static func key_of(command: BattleCommand, skill: BattleSkill) -> String:
	match command.kind:
		BattleCommand.Kind.ATTACK:
			return ATTACK
		BattleCommand.Kind.DEFEND:
			return DEFEND
		BattleCommand.Kind.ITEM:
			return ITEM
		BattleCommand.Kind.EVOKE:
			return ESPER
	return skill_key(skill.kind, skill.id) if skill != null else ""


static func skill_key(kind: StringName, skill_id: String) -> String:
	return "%s:%s" % [kind, skill_id]


## The stacking effect of `skill`, or null when it does not stack.
static func stacking_effect(skill: BattleSkill) -> SkillEffect:
	if skill == null:
		return null
	for effect in skill.effects:
		if STACKING_TYPES.has(effect.type):
			return effect
	return null


## The most stacks `skill` can hold (the data's max_stacks counts the initial cast:
## Blood Pulsar's 4 is the wiki's 3), or -1 when it does not stack.
static func max_stacks_of(skill: BattleSkill) -> int:
	var effect: SkillEffect = stacking_effect(skill)
	if effect == null:
		return -1
	return maxi(0, int(effect.param_float("max_stacks", 1.0)) - 1)


## The modifier of a stacking effect with `stack_count` stacks, in percent: the wiki's
## base (modifier + modifier_increment) plus modifier_increment_2 per stack. Blood
## Pulsar (250, 100, 100): 350 on the initial cast, 650 with 3 stacks.
static func stacked_modifier(effect: SkillEffect, stack_count: int) -> float:
	return effect.param_float("modifier") + effect.param_float("modifier_increment") \
		+ effect.param_float("modifier_increment_2") * float(maxi(0, stack_count))


## Records an action starting on turn `turn` and returns its stacks: -1 unless
## `max_stacks` (max_stacks_of the skill that runs) says it stacks.
func begin(declared: String, executed: String, max_stacks: int, turn: int) -> int:
	var result: int = -1
	if max_stacks >= 0:
		if stack_key == declared and previous_declared != ATTACK and previous_declared != DEFEND:
			stacks = mini(stacks + 1, max_stacks)
		else:
			stacks = 0
		stack_key = declared
		result = stacks
	previous_declared = declared
	previous_executed = executed if executed != "" else declared
	for old_turn in used.keys():
		if int(old_turn) < turn - 1:
			used.erase(old_turn)
	if not used.has(turn):
		used[turn] = {}
	used[turn][previous_declared] = true
	used[turn][previous_executed] = true
	return result


## Whether an action with `key` (declared or executed) started on turn `turn`.
func used_on(key: String, turn: int) -> bool:
	return (used.get(turn, {}) as Dictionary).has(key)


func clear() -> void:
	previous_declared = ""
	previous_executed = ""
	stack_key = ""
	stacks = 0
	used.clear()


func describe() -> String:
	var stack: String = "%s x%d" % [stack_key, stacks] if stack_key != "" else "none"
	var previous: String = previous_declared if previous_declared != "" else "none"
	if previous_executed != previous_declared:
		previous += " (ran %s)" % previous_executed
	return "stack %s, previous action %s" % [stack, previous]
