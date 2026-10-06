class_name SilenceBehavior
extends AilmentBehavior

## Silence: no spells. A party member cannot cast magic; a monster cannot use a skill
## with the magic attack type (monster skills carry no magic flag, and a silenced
## monster falls back to a basic attack). Abilities, items and limit bursts still work.
## The wiki also names songs, which the data does not mark, so they are not blocked.


func _init() -> void:
	super(PackedStringArray(["SILENCE"]))


func blocks_skill(skill: BattleSkill) -> bool:
	if skill.kind == BattleSkill.KIND_MAGIC:
		return true
	return skill.kind == BattleSkill.KIND_MONSTER and skill.attack_type == BattleSkill.ATTACK_MAGIC
