class_name EnemyBrain
extends RefCounted

## Decides what an enemy does, one action at a time. The engine calls begin_turn when
## the enemy's turn starts, then next_action each time the enemy may act, until it
## answers KIND_TURN_OVER.
##
## This base class is the behaviour of an unscripted monster (14153 of the 16931 in the
## data have no `ai` rows): `attacks_per_turn` basic attacks on a random party member.
## ScriptedEnemyBrain drives a monster from its AI script.
##
## Actions use MonsterAIRuntime.next_action's result shape: { kind, skill_id,
## target_mode, target_param, ... }. The kind strings below equal
## MonsterAIRuntime.KIND_*; they are repeated here so the engine does not depend on
## the AI module (which reads GameDatabase).

const KIND_SKILL: String = "skill"
const KIND_ATTACK: String = "attack"
const KIND_GUARD: String = "guard"
const KIND_WAIT: String = "wait"
const KIND_TURN_OVER: String = "turn_over"

var attacks_per_turn: int = 1
var _attacks_left: int = 0


## Gives the brain its own random stream, derived from the battle's seed.
func seed_rng(_seed_value: int) -> void:
	pass


## `ctx` is the AI view the engine builds: { self, party, enemies, monsters_by_id }
## (see MonsterAIRuntime for the keys a scripted brain reads).
func begin_turn(_ctx: Dictionary) -> void:
	_attacks_left = attacks_per_turn


func next_action(_ctx: Dictionary) -> Dictionary:
	if _attacks_left <= 0:
		return turn_over("attacks used up")
	_attacks_left -= 1
	return action(KIND_ATTACK)


## True once the brain knows its turn is finished without being asked again, so the
## engine can close the enemy phase as soon as the last hit lands. A brain that cannot
## tell answers false and returns KIND_TURN_OVER from its next next_action call.
func is_turn_over() -> bool:
	return _attacks_left <= 0


static func action(kind: String, skill_id: String = "", target_mode: String = "random", target_param: int = 0) -> Dictionary:
	return {
		"kind": kind,
		"skill_id": skill_id,
		"target_mode": target_mode,
		"target_param": target_param,
		"reason": "",
	}


static func turn_over(reason: String) -> Dictionary:
	var result: Dictionary = action(KIND_TURN_OVER, "", "", 0)
	result["reason"] = reason
	return result
