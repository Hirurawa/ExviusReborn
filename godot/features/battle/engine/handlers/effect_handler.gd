class_name EffectHandler
extends RefCounted

## Runs one family of skill effects, keyed by opcode schema type. schedule() runs at
## cast time: it works out what the effect does to each target and puts the hits on
## the timeline through BattleEngine.schedule_hit. resolve() runs as each of those
## hits lands. Both halves live in one class, so there is no receipt type to keep in
## step between two places.


## Schema types (skill_schema.json `type`) this handler runs.
func handled_types() -> PackedStringArray:
	return PackedStringArray()


func schedule(_engine: BattleEngine, _action: BattleAction, _effect: SkillEffect, _targets: Array[Combatant]) -> void:
	pass


func resolve(_engine: BattleEngine, _hit: ScheduledHit) -> void:
	pass


## The attack type cover reacts to when this effect reaches the other side, or
## BattleSkill.ATTACK_NONE when cover ignores it. Only damage triggers cover; the rest
## of the action follows where the damage went (CoverTracker).
func cover_attack_type(_action: BattleAction, _effect: SkillEffect) -> int:
	return BattleSkill.ATTACK_NONE


## Whether the effect goes past cover entirely, even when the rest of its action is
## covered (wiki: physical damage that ignores DEF).
func ignores_cover(_effect: SkillEffect) -> bool:
	return false


## Whether the effect works on its own actor, whatever targets its data names (a jump
## leaves the field, a delayed effect waits in the engine's queue): schedule() then gets
## the actor alone, past cover, even when no opponent is on the field.
func acts_on_actor(_effect: SkillEffect) -> bool:
	return false


## A hit of `effect` on `target`, owned by this handler, for the caller to fill in and
## pass to BattleEngine.schedule_hit.
func new_hit(action: BattleAction, effect: SkillEffect, target: Combatant, hit_index: int = 0) -> ScheduledHit:
	var hit := ScheduledHit.new()
	hit.action = action
	hit.effect = effect
	hit.handler = self
	hit.actor_id = action.actor_id
	hit.target_id = target.id
	hit.hit_index = hit_index
	hit.hit_count = effect.hit_count()
	hit.attack_type = action.skill.attack_type
	hit.swing = action.swing
	return hit
