class_name DamageHandler
extends EffectHandler

## The shared half of every damage effect. schedule() works out an amount per target
## at cast time, splits it across the effect's hits by their percentages and puts them
## on the timeline; each hit lands through BattleEngine.resolve_damage_hit (dodge,
## mitigation, defend, chain, barrier, HP, drain, death), then WeaponInflict rolls the
## attacker's weapon ailments once its last physical or hybrid hit on a target is done.
##
## A subclass says what differs: handled_types() and amount_for(). The other methods
## have defaults it can override: a cast-time miss, a cost paid before the hits, the
## elements the hits carry, the chain flags and drain.

## hit.damage_kind for damage that does not use DamageFormula (percent, fixed).
const NO_FORMULA: int = -1


func schedule(engine: BattleEngine, action: BattleAction, effect: SkillEffect, targets: Array[Combatant]) -> void:
	var actor: Combatant = engine.combatant(action.actor_id)
	if actor == null or targets.is_empty():
		return
	before_hits(engine, action, effect, actor)

	# [target, hit index, roll key] per hit. A random-target effect sends every hit to a
	# fresh random target, and hits on the same target share its rolls; otherwise each
	# entry of `targets` takes every hit with rolls of its own (a coverer appears once
	# for itself and once for each ally it covers).
	var plan: Array = []
	if effect.target_area == SkillEffect.AREA_RANDOM:
		for i in range(effect.hit_count()):
			var picked: Combatant = targets[engine.rng.randi_range(0, targets.size() - 1)]
			plan.append([picked, i, picked.id])
	else:
		for n in range(targets.size()):
			for i in range(effect.hit_count()):
				plan.append([targets[n], i, n])

	# One amount and one miss roll per roll key, however many hits it takes. The skill's
	# own miss chance comes first, then the actor's ailments (blind), then the target's
	# evasion passives.
	var amounts: Dictionary = {}
	var misses: Dictionary = {}
	for entry in plan:
		var target: Combatant = entry[0]
		var key: int = entry[2]
		if not amounts.has(key):
			amounts[key] = amount_for(engine, action, effect, actor, target)
			var miss: StringName = miss_reason_for(engine, action, effect, actor, target)
			if miss == &"":
				miss = engine.ailment_miss_reason(actor, attack_type(action, effect))
			if miss == &"":
				miss = engine.evasion_miss_reason(target, attack_type(action, effect))
			misses[key] = miss

	var elements: PackedInt32Array = hit_elements(action, effect, actor)
	for entry in plan:
		var target: Combatant = entry[0]
		var index: int = entry[1]
		var key: int = entry[2]
		var hit: ScheduledHit = new_hit(action, effect, target, index)
		hit.amount = float(amounts[key]) * float(effect.hit_damage[index]) / 100.0
		hit.damage_kind = damage_kind(action, effect)
		hit.attack_type = attack_type(action, effect)
		hit.elements = elements
		hit.builds_chain = builds_chain(effect)
		hit.takes_chain_bonus = takes_chain_bonus(effect)
		hit.drain_pct = drain_pct(effect)
		WeaponInflict.track(actor, hit)
		var miss: StringName = misses[key]
		if miss != &"":
			hit.cancelled = true
			hit.cancel_reason = miss
		engine.schedule_hit(hit, effect.hit_frames[index])


func resolve(engine: BattleEngine, hit: ScheduledHit) -> void:
	engine.resolve_damage_hit(hit)
	WeaponInflict.after_hit(engine, hit)


## The skill's attack type when it is physical, magic or hybrid and the effect does not
## go past cover; cover follows the attack type, not the damage formula (wiki: a magic
## attack dealing physical damage triggers magic cover, a hybrid one both).
func cover_attack_type(action: BattleAction, effect: SkillEffect) -> int:
	if ignores_cover(effect):
		return BattleSkill.ATTACK_NONE
	var type: int = attack_type(action, effect)
	if type == BattleSkill.ATTACK_PHYSICAL or type == BattleSkill.ATTACK_MAGIC or type == BattleSkill.ATTACK_HYBRID:
		return type
	return BattleSkill.ATTACK_NONE


## The damage `target` takes from the whole effect, before the per-hit split.
func amount_for(_engine: BattleEngine, _action: BattleAction, _effect: SkillEffect, _actor: Combatant, _target: Combatant) -> float:
	return 0.0


## Why every hit on `target` misses, rolled once at cast time; &"" when it lands.
func miss_reason_for(_engine: BattleEngine, _action: BattleAction, _effect: SkillEffect, _actor: Combatant, _target: Combatant) -> StringName:
	return &""


## Runs once per effect before any hit is scheduled (an HP cost, for instance).
func before_hits(_engine: BattleEngine, _action: BattleAction, _effect: SkillEffect, _actor: Combatant) -> void:
	pass


## A DamageFormula.Kind value, or NO_FORMULA.
func damage_kind(_action: BattleAction, _effect: SkillEffect) -> int:
	return NO_FORMULA


## The skill's attack type; a record that does not say gets one from the damage kind.
func attack_type(action: BattleAction, effect: SkillEffect) -> int:
	if action.skill.attack_type != BattleSkill.ATTACK_UNKNOWN:
		return action.skill.attack_type
	match damage_kind(action, effect):
		DamageFormula.Kind.MAGIC, DamageFormula.Kind.SPR_BASED:
			return BattleSkill.ATTACK_MAGIC
		DamageFormula.Kind.HYBRID:
			return BattleSkill.ATTACK_HYBRID
		DamageFormula.Kind.PHYSICAL, DamageFormula.Kind.DEF_BASED:
			return BattleSkill.ATTACK_PHYSICAL
	return BattleSkill.ATTACK_NONE


## The skill's elements. A physical or hybrid attack also carries the attacker's weapon
## elements (both weapons' when dual wielding) and imbues (wiki: an attack takes the
## weapons' elements only if it is physical; the user's rule, 2026-10-02: hybrid too, by
## attack type, so Sunbeam-like magic damage with a physical attack type takes them).
func hit_elements(action: BattleAction, effect: SkillEffect, actor: Combatant) -> PackedInt32Array:
	var elements: PackedInt32Array = action.skill.elements.duplicate()
	if actor == null or not BattleSkill.is_weapon_attack(attack_type(action, effect)):
		return elements
	for element in actor.weapon_elements:
		if not elements.has(element):
			elements.append(element)
	for imbue in actor.statuses_of(BattleStatus.IMBUE):
		var imbued: int = DamageFormula.ELEMENT_NAMES.find(imbue.key) + 1
		if imbued > 0 and not elements.has(imbued):
			elements.append(imbued)
	return elements


func builds_chain(_effect: SkillEffect) -> bool:
	return true


func takes_chain_bonus(_effect: SkillEffect) -> bool:
	return true


func drain_pct(_effect: SkillEffect) -> int:
	return 0
