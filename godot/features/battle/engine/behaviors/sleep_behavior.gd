class_name SleepBehavior
extends DisableBehavior

## Sleep: the bearer does nothing until a physical or hybrid damage hit wakes it (basic
## attacks included; magic and fixed damage do not). On a party member it also wears
## off after BattleRules.party_sleep_turns; enemies roll to wake like any ailment.


func _init() -> void:
	super(PackedStringArray(["SLEEP"]), false, true)


func ends_on_physical_damage() -> bool:
	return true


func turns_on(engine: BattleEngine, target: Combatant, _data_turns: int) -> int:
	return engine.rules.party_sleep_turns if target.is_party() else -1


func persists_after_battle() -> bool:
	return false
