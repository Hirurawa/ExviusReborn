class_name PoisonBehavior
extends AilmentBehavior

## Poison: BattleRules.poison_max_hp_pct of max HP at the end of every turn, after
## regens. It ignores mitigation, defending and barriers, and it can KO (a kill for
## whoever inflicted it).


func _init() -> void:
	super(PackedStringArray(["POISON"]))


func on_turn_end(engine: BattleEngine, bearer: Combatant, status: BattleStatus) -> void:
	var amount: int = maxi(1, floori(float(bearer.max_hp) * float(engine.rules.poison_max_hp_pct) / 100.0))
	engine.status_damage(bearer, status, amount, null, status.source_id)
