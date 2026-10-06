class_name FixedDamageHandler
extends DamageHandler

## A set amount of damage (opcode 41). The hit's elements apply, and it builds chains
## without taking the chain bonus, the same working assumptions as percent damage.


func handled_types() -> PackedStringArray:
	return PackedStringArray(["FIXED_DAMAGE"])


func amount_for(_engine: BattleEngine, action: BattleAction, effect: SkillEffect, actor: Combatant, target: Combatant) -> float:
	return effect.param_float("amount") * DamageFormula.element_multiplier(target, hit_elements(action, effect, actor))


func takes_chain_bonus(_effect: SkillEffect) -> bool:
	return false
