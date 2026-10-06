class_name GrantHandler
extends EffectHandler

## Op 100 UNLOCK_SKILLS, "Enable X, Y for N turns": each target takes one hit, on the
## effect's first frame, that grants it every listed skill (BattleEngine.grant,
## SkillGrant). `skill_types` has one entry per id, 2 ability or 1 magic; `uses` 1 or 2
## are uses, 0 and 999 up unlimited; `turn_count` counts the cast turn, -1 and 9999 up
## have no time limit. A grant lands with its hit, like a buff, so an ally that has not
## acted yet can use it the same turn. Slots 4 and 5 are not read.


func handled_types() -> PackedStringArray:
	return PackedStringArray(["UNLOCK_SKILLS"])


func schedule(engine: BattleEngine, action: BattleAction, effect: SkillEffect, targets: Array[Combatant]) -> void:
	# A dual wielder's left swing would grant the same skills again; it adds nothing.
	if action.swing == DualWield.LEFT:
		return
	for target in targets:
		engine.schedule_hit(new_hit(action, effect, target), effect.hit_frames[0])


func resolve(engine: BattleEngine, hit: ScheduledHit) -> void:
	var target: Combatant = engine.combatant(hit.target_id)
	if target == null or not target.is_alive():
		return
	var effect: SkillEffect = hit.effect
	var turns: int = SkillGrant.turns_from(int(effect.param_float("turn_count", -1.0)))
	var uses: int = SkillGrant.uses_from(int(effect.param_float("uses")))
	var raw_ids: Variant = effect.params.get("skill_ids", [])
	var raw_types: Variant = effect.params.get("skill_types", [])
	var ids: Array = raw_ids if raw_ids is Array else [raw_ids]
	var types: Array = raw_types if raw_types is Array else [raw_types]
	for i in range(ids.size()):
		if typeof(ids[i]) not in [TYPE_INT, TYPE_FLOAT] or int(ids[i]) <= 0:
			continue
		var skill_type: Variant = types[i] if i < types.size() else 2
		engine.grant(target, BattleEngine.skill_kind_of_type(skill_type), str(int(ids[i])), turns, uses, hit.action)
