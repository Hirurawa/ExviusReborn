class_name CleanseHandler
extends EffectHandler

## Effects that remove statuses when their hit lands (one hit per target, on the
## effect's first frame).
##   5 STATUS_CURE          the ailments it lists (packed ids, 1 poison .. 8 petrify)
##   148 STATUS_CURE_EXT    the ailments it flags (8 flags, poison .. petrify) and
##                          zombie
##   111 REMOVE_STAT_DEBUFF breaks of the flagged stats, and stop or charm
##   141 REMOVE_BUFFS       buff types 1-4 (ATK, DEF, MAG, SPR boosts) and 9-16
##                          (fire .. dark resistance boosts); 17-36 are unmapped
##   59 DISPEL              slot 0 = 2 removes debuffs only ("remove some negative
##                          status effects"), 1 buffs only, none or 0 both. Ailments
##                          stay. This reading of slot 0 is unconfirmed.

const STATS: PackedStringArray = ["ATK", "DEF", "MAG", "SPR"]


func handled_types() -> PackedStringArray:
	return PackedStringArray(["STATUS_CURE", "STATUS_CURE_EXT", "REMOVE_STAT_DEBUFF", "REMOVE_BUFFS", "DISPEL"])


func schedule(engine: BattleEngine, action: BattleAction, effect: SkillEffect, targets: Array[Combatant]) -> void:
	for target in targets:
		engine.schedule_hit(new_hit(action, effect, target), effect.hit_frames[0])


func resolve(engine: BattleEngine, hit: ScheduledHit) -> void:
	var target: Combatant = engine.combatant(hit.target_id)
	if target == null or not target.is_alive():
		return
	var reason: StringName = &"dispelled" if hit.effect.type in ["REMOVE_BUFFS", "DISPEL"] else &"cured"
	for status in removed_by(hit.effect, target):
		engine.remove_status(target, status, reason)


## The statuses on `target` that `effect` removes.
func removed_by(effect: SkillEffect, target: Combatant) -> Array[BattleStatus]:
	var out: Array[BattleStatus] = []
	for status in target.statuses:
		if _removes(effect, status):
			out.append(status)
	return out


func _removes(effect: SkillEffect, status: BattleStatus) -> bool:
	match effect.type:
		"STATUS_CURE":
			if status.kind != BattleStatus.AILMENT:
				return false
			for raw in effect.raw_params:
				var index: int = int(raw) - 1 if typeof(raw) in [TYPE_INT, TYPE_FLOAT] else -1
				if index >= 0 and index < Combatant.AILMENTS.size() and Combatant.AILMENTS[index] == status.key:
					return true
			return false
		"STATUS_CURE_EXT":
			if status.kind != BattleStatus.AILMENT:
				return false
			if status.key == "ZOMBIE":
				return effect.param_float("zombie") != 0.0
			var flags: Array = _int_list(effect.params.get("ailments", []))
			var index: int = Combatant.AILMENTS.find(status.key)
			return index >= 0 and index < flags.size() and int(flags[index]) != 0
		"REMOVE_STAT_DEBUFF":
			if status.kind == BattleStatus.STAT and status.is_debuff():
				return effect.param_float(status.key) != 0.0
			if status.kind == BattleStatus.AILMENT and status.key in ["STOP", "CHARM"]:
				return effect.param_float(status.key) != 0.0
			return false
		"REMOVE_BUFFS":
			if status.is_debuff():
				return false
			var types: Array = _int_list(effect.params.get("buff_types", []))
			if status.kind == BattleStatus.STAT:
				return types.has(STATS.find(status.key) + 1)
			if status.kind == BattleStatus.ELEMENT_RESIST:
				return types.has(DamageFormula.ELEMENT_NAMES.find(status.key) + 9)
			return false
		"DISPEL":
			if status.kind == BattleStatus.AILMENT and status.key not in ["STOP", "CHARM"]:
				return false
			var mode: int = int(effect.raw_params[0]) if not effect.raw_params.is_empty() and typeof(effect.raw_params[0]) in [TYPE_INT, TYPE_FLOAT] else 0
			if mode == 2:
				return status.is_debuff()
			if mode == 1:
				return not status.is_debuff()
			return true
	return false


static func _int_list(value: Variant) -> Array:
	var out: Array = []
	for item in (value if value is Array else [value]):
		if typeof(item) in [TYPE_INT, TYPE_FLOAT]:
			out.append(int(item))
	return out
