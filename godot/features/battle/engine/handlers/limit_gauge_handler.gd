class_name LimitGaugeHandler
extends EffectHandler

## Limit gauge effects, in hundredths of a crystal like the gauge itself.
##   125 FILL_LB      a random amount between amount_min and amount_max, rolled per
##                    target at cast time
##   31 LB_TRANSFER   the caster's whole gauge moves to the target when the hit lands


func handled_types() -> PackedStringArray:
	return PackedStringArray(["FILL_LB", "LB_TRANSFER"])


func schedule(engine: BattleEngine, action: BattleAction, effect: SkillEffect, targets: Array[Combatant]) -> void:
	for target in targets:
		var hit: ScheduledHit = new_hit(action, effect, target)
		if effect.type == "FILL_LB":
			var low: int = int(effect.param_float("amount_min"))
			var high: int = maxi(low, int(effect.param_float("amount_max")))
			hit.payload = {"amount": low if high == low else engine.rng.randi_range(low, high)}
		engine.schedule_hit(hit, effect.hit_frames[0])


func resolve(engine: BattleEngine, hit: ScheduledHit) -> void:
	var target: Combatant = engine.combatant(hit.target_id)
	if target == null or not target.is_alive():
		return
	if hit.effect.type == "FILL_LB":
		engine.change_lb(target, int(hit.payload["amount"]), hit.action, &"fill")
		return
	var giver: Combatant = engine.combatant(hit.actor_id)
	if giver == null or giver == target or giver.lb <= 0:
		return
	var amount: int = giver.lb
	engine.change_lb(giver, -amount, hit.action, &"transfer")
	engine.change_lb(target, amount, hit.action, &"transfer")
