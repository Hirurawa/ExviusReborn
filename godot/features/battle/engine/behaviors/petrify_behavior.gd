class_name PetrifyBehavior
extends DisableBehavior

## Petrify: a petrified enemy is KO'd at once (a kill for whoever petrified it). A
## petrified party member cannot act and counts as down, so a party that is all KO'd or
## petrified loses; enemies can still target and hurt it (the user's choice). It is not
## a KO, so it does not fail "no ally KO'd" objectives.


func _init() -> void:
	super(PackedStringArray(["PETRIFY"]), false, true)


func counts_as_down() -> bool:
	return true


func on_added(engine: BattleEngine, target: Combatant, status: BattleStatus, hit: ScheduledHit) -> void:
	if target.is_enemy():
		engine.kill(target, status.source_id, hit.action if hit != null else null)
