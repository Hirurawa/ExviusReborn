class_name ScriptedEnemyBrain
extends EnemyBrain

## An enemy driven by its compiled AI script through MonsterAIRuntime, one action per
## call, so every decision sees the battle as it is when the action starts. The AI
## module reads GameDatabase, so only session code (BattleBuilder) and tests loaded
## after the autoloads should reference this class; the engine sees an EnemyBrain.

var ai_script: MonsterAIScript = null
var ai_state: MonsterAIState = null


func _init(compiled: MonsterAIScript = null, state: MonsterAIState = null) -> void:
	ai_script = compiled
	ai_state = state if state != null else MonsterAIState.new(compiled.monster_id if compiled != null else "")


func seed_rng(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	ai_state.rng = rng


func begin_turn(_ctx: Dictionary) -> void:
	ai_state.begin_turn()


func next_action(ctx: Dictionary) -> Dictionary:
	if ai_script == null:
		return turn_over("no ai script")
	return MonsterAIRuntime.next_action(ai_script, ai_state, ctx)


## MonsterAIRuntime ends the turn itself for scripts without turn_end rules (one action
## per turn); scripts with them only end on their next walk.
func is_turn_over() -> bool:
	return ai_script == null or ai_state.turn_over
