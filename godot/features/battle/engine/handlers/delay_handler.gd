class_name DelayHandler
extends EffectHandler

## Effects that wait some turns before they act (DelayedCast; DELAYED-SKILLS-PLAN.md):
##   132 DELAYED_CAST          casts the ability `skill_id` names, `turn_delay` turns after
##                             the turn of the cast, if `chance_pct` (100 in every row)
##                             rolls; a new cast with the `key` of a pending one from the
##                             same caster replaces it
##   13 DELAYED_PHYS_DAMAGE    deals its physical damage (`modifier`, a percent: Dynamite
##                             Arrow's 12000 is 120x, the wiki) `turn_delay` turns later,
##                             with the effect's own targets and frames
## The cast itself does nothing on the field: the entry goes into the engine's queue, and
## the opening phase of the turn it is due runs it as a reaction (BattleEngine, DELAYS
## AND JUMPS). Damage is computed then, with the buffs of that moment. A dual wielder's
## left swing queues nothing more. Slots 1 and 4 of 132 are not read.


func handled_types() -> PackedStringArray:
	return PackedStringArray(["DELAYED_CAST", "DELAYED_PHYS_DAMAGE"])


func acts_on_actor(_effect: SkillEffect) -> bool:
	return true


func ignores_cover(_effect: SkillEffect) -> bool:
	return true


func schedule(engine: BattleEngine, action: BattleAction, effect: SkillEffect, _targets: Array[Combatant]) -> void:
	if action.swing == DualWield.LEFT:
		return
	var entry := DelayedCast.new()
	entry.actor_id = action.actor_id
	entry.target_id = action.command.target_id if action.command != null else -1
	entry.source_skill_id = action.declared_skill.id if action.declared_skill != null else ""
	entry.source_action_id = action.id
	entry.due_turn = engine.total_turns + maxi(1, int(effect.param_float("turn_delay", 1.0)))
	if effect.type == "DELAYED_CAST":
		entry.kind = DelayedCast.CAST
		var skill_id: int = int(effect.param_float("skill_id"))
		entry.skill = engine.catalog.get_skill(BattleSkill.KIND_ABILITY, str(skill_id)) if skill_id > 0 else null
		var key: int = int(effect.param_float("key"))
		entry.key = str(key) if key > 0 else ""
		var chance: int = int(effect.param_float("chance_pct", 100.0))
		if chance < 100 and engine.rng.randi_range(0, 99) >= chance:
			return
	else:
		entry.kind = DelayedCast.DAMAGE
		entry.skill = action.skill.delayed_part(effect.index)
	if entry.skill == null:
		engine.events.append(BattleEventLog.EFFECT_UNSUPPORTED, engine.frame, {
			"action": action.id,
			"actor": action.actor_id,
			"effect_index": effect.index,
			"opcode": effect.opcode,
			"effect": effect.type,
			"reason": &"delayed_skill_missing",
		})
		return
	engine.queue_delayed(entry, action)
