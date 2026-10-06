class_name PercentDamageHandler
extends DamageHandler

## Damage as a percentage of the target's current HP (opcode 9: "3/4 HP" is pct 75 and
## removes 75% of current HP), measured at cast time like all other damage. The hit's
## elements apply (weakness raises it, resistance lowers it; with a physical attack type
## the weapons' too). It builds chains but does not take the chain bonus. Both are the
## user's working assumptions until checked.


func handled_types() -> PackedStringArray:
	return PackedStringArray(["PCT_DAMAGE"])


func amount_for(_engine: BattleEngine, action: BattleAction, effect: SkillEffect, actor: Combatant, target: Combatant) -> float:
	var pct: float = effect.param_float("pct")
	return float(target.hp) * pct / 100.0 * DamageFormula.element_multiplier(target, hit_elements(action, effect, actor))


func takes_chain_bonus(_effect: SkillEffect) -> bool:
	return false
