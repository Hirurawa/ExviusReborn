class_name IdleEnemyBrain
extends EnemyBrain

## An enemy that passes every turn: the sandbox's "pass" behaviour, for trying skills
## without being hit back.


func begin_turn(_ctx: Dictionary) -> void:
	pass


func next_action(_ctx: Dictionary) -> Dictionary:
	return turn_over("idle")


func is_turn_over() -> bool:
	return true
