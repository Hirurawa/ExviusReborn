class_name BlindBehavior
extends AilmentBehavior

## Blind: the bearer's physical and hybrid attacks miss a target with
## BattleRules.blind_miss_pct, rolled once per target when the attack is cast, so a
## multi-hit skill misses all its hits on that target or none. Only damage misses; the
## skill's other effects (a break, an ailment) still land.


func _init() -> void:
	super(PackedStringArray(["BLIND"]))


func cast_miss(engine: BattleEngine, attack_type: int) -> StringName:
	if attack_type != BattleSkill.ATTACK_PHYSICAL and attack_type != BattleSkill.ATTACK_HYBRID:
		return &""
	return &"blinded" if engine.rng.randi_range(0, 99) < engine.rules.blind_miss_pct else &""
