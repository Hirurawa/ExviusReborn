class_name CoverTracker
extends RefCounted

## Cover: who takes an attack aimed at an ally. The rules are the FFBE wiki's cover
## page plus the user's answers (2026-10-01). Static, like ChainTracker; the state lives
## on the combatants (Combatant.cover_*) and on each action (BattleAction.cover_map).
##
## A coverer's sources:
##   COVER statuses (opcodes 96 and 118, CoverHandler): key "aoe" covers every ally,
##   "st" one ally (the one 118 chose, or any ally, possibly with a condition).
##   Passive covers (8 physical, 59 magic; CombatantPassives.covers): ST for any ally,
##   some for female allies only, one only while the coverer's own HP is low.
##
## When an opponent's action is declared, each of its damage effects that cover reacts
## to (EffectHandler.cover_attack_type: a physical, magic or hybrid attack type, and not
## DEF-piercing physical damage) settles cover for its targets, in effect order:
##   1. An AoE cover already triggered this turn on the targets' side takes every target
##      but the coverer, when its type matches the attack.
##   2. Otherwise each eligible combatant on that side with a matching AoE cover, in slot
##      order, rolls once per target other than itself (wiki: 50% against a full party
##      is 1 - 0.5^5); the first success triggers it and it takes every target but
##      itself.
##   3. An ST cover already triggered on a target takes it, when its type matches.
##   4. Otherwise, target by target, each eligible combatant in slot order rolls its best
##      ST cover once: the highest chance among its ST statuses that protect the target
##      or anyone and its passives, matching the attack type, the target's sex and the
##      coverer's HP gate (wiki: only the highest rate of a kind is used). One with a
##      matching AoE cover does not use its ST covers (the user's rule). A target that
##      is itself ST covering cannot be ST covered; an AoE cover can take it (wiki).
## A hybrid attack matches physical and magic covers (wiki). The coverer then takes
## everything the action does to that target, damage and every other effect (the user's
## rule), each instance with its own rolls and against the coverer's own stats.
##
## Eligible: alive, not KO'd earlier this turn (a reraised coverer cannot cover again),
## able to act (unless BattleRules.disabled_units_cover), not covering yet this turn (an
## ST coverer protects one ally per turn, the user's rule), and not covered by anyone:
## no triggered AoE cover on its side and no triggered ST cover on it (wiki: once an AoE
## cover triggers, no more covers trigger that turn).
##
## A triggered cover holds until the next phase starts (reset) or the coverer is KO'd.
## Its mitigation, a whole percent rolled between the cover's min and max when it
## triggers, cuts every hit the coverer takes meanwhile, whatever the type, on top of
## other mitigation (wiki). Only opponents' attacks are covered, so a confused ally's
## swing is not.

## Values of a cover's condition (the data's codes; the unit table's `sex` codes differ).
const CONDITION_ANY: int = 0
const CONDITION_FEMALE: int = 1
const CONDITION_MALE: int = 2

const KEY_AOE: String = "aoe"
const KEY_ST: String = "st"


## Settles action.cover_map for `actor`'s action running `skill` on `chosen`. The engine
## calls it once, when the action is declared and before any effect is scheduled.
static func decide(engine: BattleEngine, action: BattleAction, actor: Combatant, skill: BattleSkill, chosen: Combatant) -> void:
	for effect in skill.effects:
		if not effect.is_known() or not _may_reach_opponents(action, effect, chosen):
			continue
		var handler: EffectHandler = engine.effects.handler_for(effect.type)
		if handler == null:
			continue
		var attack_type: int = handler.cover_attack_type(action, effect)
		if attack_type == BattleSkill.ATTACK_NONE:
			continue
		var targets: Array[Combatant] = []
		for target in engine.effect_targets(action, effect, chosen):
			if target.is_opponent_of(actor) and target.is_alive() and not targets.has(target):
				targets.append(target)
		if not targets.is_empty():
			_settle(engine, action, targets, attack_type)


## `targets` with every covered opponent replaced by its coverer, in place, so a coverer
## appears once for itself and once for each ally it covers.
static func redirect(engine: BattleEngine, action: BattleAction, targets: Array[Combatant]) -> Array[Combatant]:
	if action.cover_map.is_empty():
		return targets
	var out: Array[Combatant] = []
	for target in targets:
		var coverer: Combatant = engine.combatant(int(action.cover_map.get(target.id, -1)))
		out.append(coverer if coverer != null and coverer.is_alive() else target)
	return out


## What survives the mitigation of the cover `target` triggered this turn.
static func mitigation_multiplier(target: Combatant) -> float:
	if target.cover_mode == Combatant.COVER_NONE:
		return 1.0
	return 1.0 - float(target.cover_mitigation) / 100.0


## A KO ends the combatant's cover and keeps it from covering again this turn.
static func on_defeated(engine: BattleEngine, target: Combatant) -> void:
	target.cover_spent = true
	if target.cover_mode != Combatant.COVER_NONE:
		target.clear_cover()
		engine.events.append(BattleEventLog.COVER_ENDED, engine.frame, {"coverer": target.id, "reason": &"ko"})


## A new phase: every triggered cover ends, and KO'd coverers may cover again.
static func reset(engine: BattleEngine) -> void:
	var everyone: Array[Combatant] = engine.party_members()
	everyone.append_array(engine.enemies)
	for fighter in everyone:
		if fighter.cover_mode != Combatant.COVER_NONE:
			fighter.clear_cover()
			engine.events.append(BattleEventLog.COVER_ENDED, engine.frame, {"coverer": fighter.id, "reason": &"turn_over"})
		fighter.cover_spent = false


## Whether an ally on `side` (living combatants) covers `fighter` this turn.
static func is_covered(fighter: Combatant, side: Array[Combatant]) -> bool:
	for other in side:
		if other == fighter or not other.is_alive():
			continue
		if other.cover_mode == Combatant.COVER_AOE:
			return true
		if other.cover_mode == Combatant.COVER_ST and other.cover_protects == fighter.id:
			return true
	return false


## The matching AoE cover status on `coverer`, or null.
static func aoe_cover(coverer: Combatant, attack_type: int) -> BattleStatus:
	for status in coverer.statuses_of(BattleStatus.COVER):
		if status.key == KEY_AOE and status.value > 0 and \
				_matches(bool(status.params.get("physical", false)), bool(status.params.get("magic", false)), attack_type):
			return status
	return null


## The best ST cover `coverer` has for `target` against `attack_type`, as
## { chance, mit_min, mit_max, physical, magic, condition, hp_below_pct }, or {}.
static func best_st_cover(coverer: Combatant, target: Combatant, attack_type: int) -> Dictionary:
	var best: Dictionary = {}
	var candidates: Array = coverer.passives.covers.duplicate()
	for status in coverer.statuses_of(BattleStatus.COVER):
		var protects: int = int(status.params.get("protects", -1))
		if status.key == KEY_ST and (protects < 0 or protects == target.id):
			candidates.append(_cover_of(status))
	for cover in candidates:
		if _usable(cover, coverer, target, attack_type) and int(cover["chance"]) > int(best.get("chance", 0)):
			best = cover
	return best


# --- Settling one effect's targets ---

static func _settle(engine: BattleEngine, action: BattleAction, targets: Array[Combatant], attack_type: int) -> void:
	var open: Array[Combatant] = []
	for target in targets:
		if not action.cover_map.has(target.id):
			open.append(target)
	if open.is_empty():
		return
	var side: Array[Combatant] = engine.living_allies_of(open[0])

	var aoe: Combatant = _triggered_aoe(side, attack_type)
	if aoe == null:
		aoe = _roll_aoe(engine, action, side, open, attack_type)
	if aoe != null:
		for target in open.duplicate():
			if target != aoe:
				_cover(engine, action, target, aoe)
				open.erase(target)

	for target in open:
		var coverer: Combatant = _triggered_st(side, target, attack_type)
		if coverer == null and target.cover_mode != Combatant.COVER_ST:
			coverer = _roll_st(engine, action, side, target, attack_type)
		if coverer != null:
			_cover(engine, action, target, coverer)


static func _triggered_aoe(side: Array[Combatant], attack_type: int) -> Combatant:
	for fighter in side:
		if fighter.cover_mode == Combatant.COVER_AOE and _matches(fighter.cover_physical, fighter.cover_magic, attack_type):
			return fighter
	return null


static func _triggered_st(side: Array[Combatant], target: Combatant, attack_type: int) -> Combatant:
	for fighter in side:
		if fighter != target and fighter.cover_mode == Combatant.COVER_ST and fighter.cover_protects == target.id \
				and _matches(fighter.cover_physical, fighter.cover_magic, attack_type):
			return fighter
	return null


static func _roll_aoe(engine: BattleEngine, action: BattleAction, side: Array[Combatant], open: Array[Combatant], attack_type: int) -> Combatant:
	for coverer in side:
		if not _can_cover(engine, coverer, side):
			continue
		var status: BattleStatus = aoe_cover(coverer, attack_type)
		if status == null:
			continue
		var at_risk: int = open.size() - (1 if open.has(coverer) else 0)
		if at_risk > 0 and _roll(engine, status.value, at_risk):
			_trigger(engine, action, coverer, Combatant.COVER_AOE, -1, _cover_of(status))
			return coverer
	return null


static func _roll_st(engine: BattleEngine, action: BattleAction, side: Array[Combatant], target: Combatant, attack_type: int) -> Combatant:
	for coverer in side:
		if coverer == target or not _can_cover(engine, coverer, side) or aoe_cover(coverer, attack_type) != null:
			continue
		var cover: Dictionary = best_st_cover(coverer, target, attack_type)
		if not cover.is_empty() and _roll(engine, int(cover["chance"]), 1):
			_trigger(engine, action, coverer, Combatant.COVER_ST, target.id, cover)
			return coverer
	return null


static func _can_cover(engine: BattleEngine, coverer: Combatant, side: Array[Combatant]) -> bool:
	if not coverer.is_alive() or coverer.cover_spent or coverer.cover_mode != Combatant.COVER_NONE:
		return false
	# A unit in the air covers nobody, whatever disabled_units_cover says.
	if coverer.is_away():
		return false
	if not coverer.can_act() and not engine.rules.disabled_units_cover:
		return false
	return not is_covered(coverer, side)


## True on any of `tries` rolls under `chance` percent; 100 or more needs no roll.
static func _roll(engine: BattleEngine, chance: int, tries: int) -> bool:
	if chance >= 100:
		return true
	if chance <= 0:
		return false
	for _i in range(tries):
		if engine.rng.randi_range(0, 99) < chance:
			return true
	return false


static func _trigger(engine: BattleEngine, action: BattleAction, coverer: Combatant, mode: int, protects: int, cover: Dictionary) -> void:
	var low: int = clampi(mini(int(cover["mit_min"]), int(cover["mit_max"])), 0, 100)
	var high: int = clampi(maxi(int(cover["mit_min"]), int(cover["mit_max"])), 0, 100)
	coverer.cover_mode = mode
	coverer.cover_protects = protects
	coverer.cover_physical = bool(cover["physical"])
	coverer.cover_magic = bool(cover["magic"])
	coverer.cover_mitigation = engine.rng.randi_range(low, high) if high > low else low
	engine.events.append(BattleEventLog.COVER_ACTIVATED, engine.frame, {
		"action": action.id,
		"actor": action.actor_id,
		"coverer": coverer.id,
		"mode": &"aoe" if mode == Combatant.COVER_AOE else &"st",
		"protects": protects,
		"physical": coverer.cover_physical,
		"magic": coverer.cover_magic,
		"mitigation": coverer.cover_mitigation,
	})


static func _cover(engine: BattleEngine, action: BattleAction, target: Combatant, coverer: Combatant) -> void:
	action.cover_map[target.id] = coverer.id
	engine.events.append(BattleEventLog.COVERED, engine.frame, {
		"action": action.id,
		"actor": action.actor_id,
		"target": target.id,
		"coverer": coverer.id,
	})


# --- Helpers ---

## Whether an effect of `action` can reach the other side: an ailment's single pick
## (confusion, berserk), or an effect aimed at opponents or everyone. Other effects are
## skipped before targeting, which may roll for an enemy's random ally.
static func _may_reach_opponents(action: BattleAction, effect: SkillEffect, chosen: Combatant) -> bool:
	if action.origin == BattleAction.Origin.FORCED and effect.target_area == SkillEffect.AREA_SINGLE and chosen != null and chosen.is_alive():
		return true
	return effect.target_type == SkillEffect.TARGET_OPPONENT or effect.target_type == SkillEffect.TARGET_EVERYONE


## A cover attack-type pair matches: physical covers take physical attacks, magic covers
## magic ones, and either takes a hybrid attack.
static func _matches(physical: bool, magic: bool, attack_type: int) -> bool:
	match attack_type:
		BattleSkill.ATTACK_PHYSICAL:
			return physical
		BattleSkill.ATTACK_MAGIC:
			return magic
		BattleSkill.ATTACK_HYBRID:
			return physical or magic
	return false


static func _usable(cover: Dictionary, coverer: Combatant, target: Combatant, attack_type: int) -> bool:
	if int(cover.get("chance", 0)) <= 0 or not _matches(bool(cover.get("physical", false)), bool(cover.get("magic", false)), attack_type):
		return false
	match int(cover.get("condition", CONDITION_ANY)):
		CONDITION_FEMALE:
			if target.sex != Combatant.SEX_FEMALE:
				return false
		CONDITION_MALE:
			if target.sex != Combatant.SEX_MALE:
				return false
	var gate: int = int(cover.get("hp_below_pct", 100))
	return gate <= 0 or gate >= 100 or coverer.hp * 100 <= coverer.max_hp * gate


## A COVER status in the shape of a passive cover.
static func _cover_of(status: BattleStatus) -> Dictionary:
	return {
		"chance": status.value,
		"mit_min": int(status.params.get("mit_min", 0)),
		"mit_max": int(status.params.get("mit_max", 0)),
		"physical": bool(status.params.get("physical", false)),
		"magic": bool(status.params.get("magic", false)),
		"condition": int(status.params.get("condition", CONDITION_ANY)),
		"hp_below_pct": 100,
	}
