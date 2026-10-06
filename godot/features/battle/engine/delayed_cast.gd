class_name DelayedCast
extends RefCounted

## An effect waiting a number of turns (DelayHandler queues it, BattleEngine keeps it in
## cast order): a delayed cast (opcode 132), which casts the ability it names, or delayed
## damage (13), which deals its physical damage. At the start of the turn it is due, the
## opening phase runs it as a Reaction.DELAYED. The plan and the rules are in
## DELAYED-SKILLS-PLAN.md.

const CAST: StringName = &"cast"
const DAMAGE: StringName = &"damage"

## CAST or DAMAGE.
var kind: StringName = CAST
var actor_id: int = -1
## What runs: the ability a 132 names, or the parent skill reduced to its op 13 effect
## (BattleSkill.delayed_part).
var skill: BattleSkill = null
## The target the parent command picked; the effect's single-target parts go there while
## it is on the field (BattleEngine.resolve_targets falls back otherwise).
var target_id: int = -1
## The engine's total_turns it runs on: the turn of the cast + turn_delay.
var due_turn: int = 0
## Opcode 132's key, "" for none (0, a missing slot, and every op 13): a new cast with the
## key of a pending one from the same caster replaces it (the user's rule, 2026-10-06).
var key: String = ""
## The skill the parent's command named, and the parent action.
var source_skill_id: String = ""
var source_action_id: int = -1


func copy() -> DelayedCast:
	var made := DelayedCast.new()
	made.kind = kind
	made.actor_id = actor_id
	made.skill = skill
	made.target_id = target_id
	made.due_turn = due_turn
	made.key = key
	made.source_skill_id = source_skill_id
	made.source_action_id = source_action_id
	return made


func describe() -> String:
	return "%s %s:%s by #%d on turn %d" % [kind, skill.kind if skill != null else &"", skill.id if skill != null else "", actor_id, due_turn]
