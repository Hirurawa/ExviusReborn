class_name JumpHandler
extends EffectHandler

## Jumps (DELAYED-SKILLS-PLAN.md, the wiki's jump rules):
##   52 JUMP              the unit lands on its own, `delay_min` turns after the jump
##   134 JUMP_ACTIVATED   the player lands it (BattleCommand.land) from that turn on
## `delay_min` equals `delay_max` in every row. One hit on the actor, on the action's
## first frame, puts it in the air (BattleStatus.AWAY, AwayBehavior): nothing targets it
## and it cannot act. The status carries what the landing needs: the target picked at
## the jump and the landing skill (BattleSkill.delayed_part: physical damage at
## `modifier`, with the jump's opcode, frames and attack type). The skill's other effects
## run at the cast as usual. A dual wielder's left swing jumps no more; both hands strike
## on landing (the wiki). BattleEngine lands it (DELAYS AND JUMPS).

const KEY_JUMP: String = "jump"


func handled_types() -> PackedStringArray:
	return PackedStringArray(["JUMP", "JUMP_ACTIVATED"])


func acts_on_actor(_effect: SkillEffect) -> bool:
	return true


func ignores_cover(_effect: SkillEffect) -> bool:
	return true


func schedule(engine: BattleEngine, action: BattleAction, effect: SkillEffect, targets: Array[Combatant]) -> void:
	if action.swing == DualWield.LEFT or targets.is_empty():
		return
	var landing: BattleSkill = action.skill.delayed_part(effect.index)
	if landing == null:
		return
	var declared: BattleSkill = action.declared_skill if action.declared_skill != null else action.skill
	var hit: ScheduledHit = new_hit(action, effect, targets[0])
	hit.payload = {
		"ready_turn": engine.total_turns + maxi(1, int(effect.param_float("delay_min", 1.0))),
		"params": {
			"skill_kind": declared.kind,
			"skill_id": declared.id,
			"effect_index": effect.index,
			"target_id": action.command.target_id if action.command != null else -1,
			"manual": effect.type == "JUMP_ACTIVATED",
			"action": action.id,
			"landing": landing,
		},
	}
	engine.schedule_hit(hit, 0)


func resolve(engine: BattleEngine, hit: ScheduledHit) -> void:
	var jumper: Combatant = engine.combatant(hit.target_id)
	if jumper == null or not jumper.is_alive():
		return
	var params: Dictionary = (hit.payload["params"] as Dictionary).duplicate()
	var away := BattleStatus.make(BattleStatus.AWAY, KEY_JUMP, int(hit.payload["ready_turn"]), -1, params)
	engine.apply_status(hit, jumper, away)
