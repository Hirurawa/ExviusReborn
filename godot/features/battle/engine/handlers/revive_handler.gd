class_name ReviveHandler
extends EffectHandler

## REVIVE (4): a KO'd ally comes back with HP_pct of its own max HP when the hit lands
## (the old engine used the first target's max HP for everyone). Only KO'd allies are
## targeted, and zombies, whom a revive KOs; see BattleEngine.resolve_targets. An ally
## revived by something else before the hit lands is left alone.


func handled_types() -> PackedStringArray:
	return PackedStringArray(["REVIVE"])


func schedule(engine: BattleEngine, action: BattleAction, effect: SkillEffect, targets: Array[Combatant]) -> void:
	for target in targets:
		var hit: ScheduledHit = new_hit(action, effect, target)
		hit.payload = {"hp_pct": effect.param_float("HP_pct")}
		engine.schedule_hit(hit, effect.hit_frames[0])


func resolve(engine: BattleEngine, hit: ScheduledHit) -> void:
	var target: Combatant = engine.combatant(hit.target_id)
	if target == null:
		return
	if not target.is_alive():
		engine.revive(target, float(hit.payload["hp_pct"]), hit.action, hit.actor_id, &"")
	elif target.recovery_inverter() != null:
		engine.kill(target, hit.actor_id, hit.action)
