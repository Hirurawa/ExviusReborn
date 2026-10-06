class_name ZombieBehavior
extends AilmentBehavior

## Zombie (monster-only, opcode 144): HP recovery of any kind (heals, regen, drain,
## potions) hurts the bearer instead, and revival KOs it: a revive aimed at it, or an
## auto-revive put on it. A zombie KO'd by other means does not auto-revive. MP
## recovery works as usual. There is no zombie resistance in the data, so only the
## skill's chance rolls.


func _init() -> void:
	super(PackedStringArray(["ZOMBIE"]))


func inverts_recovery() -> bool:
	return true


func persists_after_battle() -> bool:
	return false
