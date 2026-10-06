class_name BattleStatus
extends RefCounted

## One timed effect on a combatant: a buff, a break, an imperil, a mitigation, an
## ailment, a barrier and so on. Combatant keeps the list; the engine and DamageFormula
## read it at their hook points. Two statuses with the same stack_key() cannot coexist:
## the newer replaces the older (BattleRules.keep_stronger_status can keep the stronger
## one instead). A buff and a break of the same stat have different stack keys and add
## up, like StatCalculator's highest-buff-plus-lowest-debuff rule.

## Kinds, with what `key` and `value` hold.
## key ATK / DEF / MAG / SPR; value percent of the stat's base (negative = break).
const STAT: StringName = &"stat"
## key FIRE .. DARK; value resistance percent (negative = imperil).
const ELEMENT_RESIST: StringName = &"element_resist"
## key POISON .. PETRIFY; value resistance percent (negative = lowered).
const AILMENT_RESIST: StringName = &"ailment_resist"
## key POISON .. PETRIFY: the resistance to that ailment counts as 0 while it lasts,
## whatever equipment and resist buffs give (opcode 140, "resistance ... has been
## blown away"). value unused.
const NO_AILMENT_RESIST: StringName = &"no_ailment_resist"
## key ATK / DEF / MAG / SPR / STOP / CHARM; value chance percent to resist that debuff.
const DEBUFF_RESIST: StringName = &"debuff_resist"
## key "all", "physical" or "magic"; value percent of damage taken removed.
const MITIGATION: StringName = &"mitigation"
## key "physical:<race>" or "magic:<race>"; value percent removed from damage that race deals.
const RACE_MITIGATION: StringName = &"race_mitigation"
## key "physical:<race>" or "magic:<race>"; value percent added to damage against that race.
const KILLER: StringName = &"killer"
## key FIRE .. DARK; value percent added to damage of that element.
const ELEMENT_BOOST: StringName = &"element_boost"
## key the boost's stack group; value percent; params { skill_ids, opcodes }.
const SKILL_BOOST: StringName = &"skill_boost"
## value percent added to limit burst damage.
const LB_BOOST: StringName = &"lb_boost"
## key FIRE .. DARK: physical attacks gain that element.
const IMBUE: StringName = &"imbue"
## value physical hits left to evade.
const DODGE: StringName = &"dodge"
## value barrier HP left.
const SHIELD: StringName = &"shield"
## value HP restored at the end of each turn.
const REGEN: StringName = &"regen"
## value MP restored at the end of each turn.
const MP_REGEN: StringName = &"mp_regen"
## value percent of max HP the combatant returns with when KO'd.
const AUTO_REVIVE: StringName = &"auto_revive"
## value percent added to the limit gauge gained from crystals.
const LB_FILL_RATE: StringName = &"lb_fill_rate"
## value chance percent that an enemy's random single-target pick goes to the bearer
## (opcode 61); Combatant.provoke_chance adds passive aggro, BattleEngine.random_target
## rolls it.
const PROVOKE: StringName = &"provoke"
## key POISON .. PETRIFY, ZOMBIE, STOP, CHARM or BERSERK. What each does is its
## StatusBehavior (engine/behaviors/). value: DISEASE the stat percent it takes,
## BERSERK the ATK percent it adds; 0 otherwise.
const AILMENT: StringName = &"ailment"
## key "aoe" (covers every ally) or "st" (one ally); value chance percent to cover;
## params { mit_min, mit_max, physical, magic, protects (the one ally's combatant id, -1
## for any), condition (CoverTracker.CONDITION_*) }. The bearer is the coverer. One of
## each key at a time, the newest winning (CoverTracker).
const COVER: StringName = &"cover"
## key "self" (opcode 119: counters physical attacks on the bearer) or "ally" (123:
## physical attacks on its other allies); value chance percent to counter with the
## normal attack; params { modifier (the counter's damage in percent of the attack, 0 =
## its own), max (counters per turn, 0 = no cap) } (Counters). One of each key at a time,
## the newest winning.
const COUNTER: StringName = &"counter"
## key "jump" (opcodes 52 and 134): the bearer has left the field (AwayBehavior). Nothing
## targets it and it cannot act until it comes back. value is the turn (the engine's
## total_turns) it can land on; permanent until the engine removes it. params { skill_kind,
## skill_id (the skill the command named, a wrapper for instance), effect_index (the jump
## effect in the executed skill), target_id (picked at the jump), manual (134: the player
## lands it), action (the jump's action id), landing (the BattleSkill the landing runs) }.
const AWAY: StringName = &"away"

## Kinds whose negative values are debuffs.
const SIGNED_KINDS: Array[StringName] = [
	STAT, ELEMENT_RESIST, AILMENT_RESIST, DEBUFF_RESIST, MITIGATION, KILLER,
	ELEMENT_BOOST, SKILL_BOOST, LB_BOOST, LB_FILL_RATE,
]

var kind: StringName = STAT
var key: String = ""
var value: int = 0
## Extra data a kind needs (SKILL_BOOST: skill_ids, opcodes).
var params: Dictionary = {}
## Turns left, counted down at the end of each turn; -1 lasts until removed.
var turns_left: int = 1
## Combatant id of whoever applied it, and the skill it came from.
var source_id: int = -1
var skill_id: String = ""
## When the engine added it, as a count that only grows (BattleEngine._add_status): the
## larger, the more recent. Provoke ties go to the most recent.
var added_order: int = 0

var _behavior: StatusBehavior = null


static func make(status_kind: StringName, status_key: String, status_value: int, turns: int, extra: Dictionary = {}) -> BattleStatus:
	var status := BattleStatus.new()
	status.kind = status_kind
	status.key = status_key
	status.value = status_value
	status.turns_left = turns
	status.params = extra
	return status


## True for breaks, imperils, lowered resistances and ailments: what cleansing removes
## and what resistances roll against.
func is_debuff() -> bool:
	if kind == AILMENT or kind == NO_AILMENT_RESIST:
		return true
	return SIGNED_KINDS.has(kind) and value < 0


## What the status does while it lasts; the no-op StatusBehavior for most kinds.
func behavior() -> StatusBehavior:
	if _behavior == null:
		_behavior = StatusBehaviorRegistry.shared().behavior_for(kind, key)
	return _behavior


func is_permanent() -> bool:
	return turns_left < 0


func stack_key() -> String:
	return "%s:%s:%s" % [kind, key, "-" if is_debuff() else "+"]


func describe() -> String:
	var turns: String = "permanent" if is_permanent() else "%d turn(s)" % turns_left
	return "%s %s %+d (%s)" % [kind, key, value, turns]
