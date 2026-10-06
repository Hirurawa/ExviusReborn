class_name ConfusionBehavior
extends AilmentBehavior

## Confusion: the bearer attacks a random living combatant other than itself, friend or
## foe. A confused party member still waits to be told to act (the user's choice); any
## command it gets becomes that attack. A confused enemy makes that attack in place of
## its turn. A physical or hybrid damage hit ends it.


func _init() -> void:
	super(PackedStringArray(["CONFUSION"]))


func control() -> int:
	return CONTROL_CONFUSED


func ends_on_physical_damage() -> bool:
	return true


## Anyone on the field but the bearer (a unit in the air is out of reach).
func forced_targets(engine: BattleEngine, bearer: Combatant) -> Array[Combatant]:
	var pool: Array[Combatant] = engine.targetable(engine.living_party())
	pool.append_array(engine.targetable(engine.living_enemies()))
	pool.erase(bearer)
	return pool


func persists_after_battle() -> bool:
	return false
