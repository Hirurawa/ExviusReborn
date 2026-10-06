class_name AwayBehavior
extends StatusBehavior

## BattleStatus.AWAY: the bearer has left the field, in the air after a jump (opcodes 52
## and 134; hide will join later). The wiki: it "cannot be targeted or attacked, and will
## not be affected by any party buffs not applied prior to jumping". It cannot act either;
## its landing is the engine's (BattleEngine, DELAYS AND JUMPS). Statuses it had before
## keep counting down and poison still ticks (the user's rule, 2026-10-06). A won wave
## cancels the jump: the unit is back on the ground for the next one (wiki).


func removes_from_field() -> bool:
	return true


func persists_after_battle() -> bool:
	return false
