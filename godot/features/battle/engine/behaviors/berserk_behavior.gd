class_name BerserkBehavior
extends AilmentBehavior

## Berserk (a lasting effect, opcode 68): the bearer takes no commands and makes a
## basic attack on a random opponent every turn. A party member attacks on its own at
## the start of the player phase (or as soon as berserk lands on one that has not acted
## yet); an enemy makes the attack in place of its turn. The status value is the ATK
## boost the skill gives, in percent of the raw base.


func _init() -> void:
	super(PackedStringArray(["BERSERK"]), true)


func control() -> int:
	return CONTROL_BERSERK


func stat_percent(status: BattleStatus, stat_name: String) -> int:
	return status.value if stat_name == "ATK" else 0


## Opponents on the field (a unit in the air is out of reach).
func forced_targets(engine: BattleEngine, bearer: Combatant) -> Array[Combatant]:
	return engine.targetable_opponents_of(bearer)
