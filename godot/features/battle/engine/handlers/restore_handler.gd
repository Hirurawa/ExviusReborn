class_name RestoreHandler
extends EffectHandler

## Instant recovery. Amounts are worked out at cast time and split across the effect's
## hits like damage; restoring never touches a chain.
##   2 HEAL              amount + (0.5 SPR + 0.1 MAG) x modifier / 100, from the caster
##                       (the old engine's formula)
##   16 HP_RESTORE       a flat amount of HP
##   17 MP_RESTORE       a flat amount of MP
##   65 HP_MP_RESTORE    flat HP and MP
##   26 HP_PCT_RESTORE   a random percent between pct_min and pct_max of max HP
##   64 PCT_RESTORE      percents of max HP and max MP
##   11 SAC_SELF_RESTORE percents of max HP and MP; the caster is KO'd when it casts


func handled_types() -> PackedStringArray:
	return PackedStringArray([
		"HEAL", "HP_RESTORE", "MP_RESTORE", "HP_MP_RESTORE", "HP_PCT_RESTORE", "PCT_RESTORE",
		"SAC_SELF_RESTORE",
	])


func schedule(engine: BattleEngine, action: BattleAction, effect: SkillEffect, targets: Array[Combatant]) -> void:
	var actor: Combatant = engine.combatant(action.actor_id)
	if actor == null:
		return
	if effect.type == "SAC_SELF_RESTORE":
		engine.kill(actor, actor.id, action)
	for target in targets:
		var amounts: Vector2i = amounts_for(engine, effect, actor, target)
		for i in range(effect.hit_count()):
			var share: float = float(effect.hit_damage[i]) / 100.0
			var hit: ScheduledHit = new_hit(action, effect, target, i)
			hit.payload = {"hp": floori(float(amounts.x) * share), "mp": floori(float(amounts.y) * share)}
			engine.schedule_hit(hit, effect.hit_frames[i])


func resolve(engine: BattleEngine, hit: ScheduledHit) -> void:
	engine.restore(hit, engine.combatant(hit.target_id), int(hit.payload["hp"]), int(hit.payload["mp"]), &"")


## The (HP, MP) the whole effect restores to `target`.
func amounts_for(engine: BattleEngine, effect: SkillEffect, actor: Combatant, target: Combatant) -> Vector2i:
	match effect.type:
		"HEAL":
			return Vector2i(floori(heal_amount(actor, effect.param_float("amount"), effect.param_float("modifier"))), 0)
		"HP_RESTORE":
			return Vector2i(int(effect.param_float("amount")), 0)
		"MP_RESTORE":
			return Vector2i(0, int(effect.param_float("amount")))
		"HP_MP_RESTORE":
			return Vector2i(int(effect.param_float("HP")), int(effect.param_float("MP")))
		"HP_PCT_RESTORE":
			var low: int = int(effect.param_float("pct_min"))
			var high: int = maxi(low, int(effect.param_float("pct_max")))
			var pct: int = low if high == low else engine.rng.randi_range(low, high)
			return Vector2i(floori(float(target.max_hp) * float(pct) / 100.0), 0)
		"PCT_RESTORE":
			return Vector2i(_pct_of(target.max_hp, effect.param_float("HP")), _pct_of(target.max_mp, effect.param_float("MP")))
		"SAC_SELF_RESTORE":
			return Vector2i(_pct_of(target.max_hp, effect.param_float("HP_pct")), _pct_of(target.max_mp, effect.param_float("MP_pct")))
	return Vector2i.ZERO


## The heal formula (heals and regens): `amount` + (0.5 SPR + 0.1 MAG) x modifier %,
## with the caster's current stats.
static func heal_amount(caster: Combatant, amount: float, modifier_pct: float) -> float:
	var power: float = 0.5 * float(caster.stat("SPR")) + 0.1 * float(caster.stat("MAG"))
	return maxf(0.0, amount + power * modifier_pct / 100.0)


static func _pct_of(maximum: int, pct: float) -> int:
	return floori(float(maximum) * pct / 100.0)
