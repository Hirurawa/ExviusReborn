class_name DualWield
extends RefCounted

## A party member holding two weapons (Combatant.hand_atk has two entries). The wiki's
## dual wield page and the user's rules (2026-10-02):
##   - Basic attacks and abilities that deal damage with a physical or hybrid attack type
##     swing twice, right hand first. That includes skills dealing magic damage with a
##     physical attack type (Sunbeam, Wild Card, Dagger Boomerang) and forced attacks.
##     The left hand runs the whole skill again, every effect (the user's rule), with its
##     attack frames counted from BattleRules.cast_gap_frames after the right hand's
##     start (the user's rule, 2026-10-05: the multicast cast delay, from the start of
##     the cast), so the swings of a skill longer than the gap overlap.
##   - Each swing uses its own weapon's ATK: the unit's ATK less the other weapon's
##     (Combatant.hand_atk counts each weapon's equipment-stat boosts, true dual wield
##     included, with that weapon). The ATK both weapons add up to is used by nothing.
##   - A limit burst swings once, with the higher-ATK weapon whichever hand holds it.
##     Magic, items and espers never swing twice.
##   - Both swings carry both weapons' elements (DamageHandler.hit_elements) and ailments
##     (WeaponInflict, which rolls once per swing).
##   - Both swings, and a limit burst, use the right-hand weapon's variance (wiki: "only
##     the right hand weapon variance is used for both hits"; Combatant.weapon_variance_min).
## Each swing makes its own rolls (both variances, blind, evasion, the skill's own
## inflicts).
## Both swings are scheduled when the action is declared, against the targets of that
## moment, so a left swing whose single target the right swing KO'd misses (target_down).
##   - A multicast pick swings once, with the right hand (wiki; the data's "activate one
##     time each regardless of equipment conditions").
## Not done: physical counters swing twice (wiki); counters do not exist yet.

## ScheduledHit.swing and BattleAction.swing values.
const RIGHT: int = 0
const LEFT: int = 1


## Whether `actor` swings twice with `action`'s skill.
static func applies(engine: BattleEngine, action: BattleAction, actor: Combatant) -> bool:
	var skill: BattleSkill = action.skill
	if actor == null or not actor.is_dual_wielding() or skill == null or action.multicast_index >= 0:
		return false
	if skill.kind != BattleSkill.KIND_ATTACK and skill.kind != BattleSkill.KIND_ABILITY:
		return false
	for effect in skill.effects:
		var handler: EffectHandler = engine.effects.handler_for(effect.type) if effect.is_known() else null
		if handler is DamageHandler and BattleSkill.is_weapon_attack((handler as DamageHandler).attack_type(action, effect)):
			return true
	return false


## The ATK `actor`'s current swing in `action` leaves out: the other weapon's. A limit
## burst keeps the higher-ATK weapon; anything else that swings once (magic, items,
## espers) counts as the right hand.
static func atk_left_out(actor: Combatant, action: BattleAction) -> int:
	if actor == null or not actor.is_dual_wielding():
		return 0
	if action.skill != null and action.skill.kind == BattleSkill.KIND_LIMIT_BURST:
		return mini(actor.hand_atk[RIGHT], actor.hand_atk[LEFT])
	return actor.hand_atk[RIGHT] if action.swing == LEFT else actor.hand_atk[LEFT]
