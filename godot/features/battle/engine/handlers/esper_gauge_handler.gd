class_name EsperGaugeHandler
extends EffectHandler

## The party's esper gauge, in orbs (BattleEngine.esper_orbs).
##   32 ESPER_GAUGE_FILL  a random number of orbs between min and max, rolled at cast
##                        time ("fill evocation gauge to max" is 10,10). The gauge is the
##                        party's, so the effect fills it once whatever its targets
##                        (2 abilities aim it at all allies), when its first hit lands.
##                        Only party skills fill it; no monster skill has the opcode.


func handled_types() -> PackedStringArray:
	return PackedStringArray(["ESPER_GAUGE_FILL"])


func schedule(engine: BattleEngine, action: BattleAction, effect: SkillEffect, targets: Array[Combatant]) -> void:
	var actor: Combatant = engine.combatant(action.actor_id)
	if actor == null or not actor.is_party() or targets.is_empty():
		return
	var low: int = int(effect.param_float("min"))
	var high: int = maxi(low, int(effect.param_float("max")))
	var hit: ScheduledHit = new_hit(action, effect, targets[0])
	hit.payload = {"amount": low if high == low else engine.rng.randi_range(low, high)}
	engine.schedule_hit(hit, effect.hit_frames[0])


func resolve(engine: BattleEngine, hit: ScheduledHit) -> void:
	engine.change_esper_orbs(int(hit.payload["amount"]), hit.action, hit.actor_id, &"fill")
