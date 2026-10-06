class_name Reaction
extends RefCounted

## An action the engine starts on its own for a combatant (BattleAction.Origin.REACTION):
## a counter (Counters), a skill a passive casts at the battle start or at each turn
## start, or one it casts after a revive; a delayed cast or delayed damage that is due
## (DelayedCast), or a jump that lands on its own. Counters, the battle-start and
## turn-start casts, the delayed effects and the party's landings wait in the engine's
## queue for the next opening phase; revive casts wait on the timeline (ScheduledCast);
## an enemy lands on its own turn. The plans and the rules are in REACTIONS-PLAN.md and
## DELAYED-SKILLS-PLAN.md.
##
## A reaction costs nothing, spends no cooldown, use or grant, does not use up the
## unit's turn and is not recorded in its action history. It is dropped when its turn
## comes and its unit is KO'd, petrified, disabled or in the air, or no opponent is left.
## A landing is the exception: it is what brings the unit back, it is the unit's action
## for the turn, and it goes into the history as its jump (op 99's drop-time chains).

const COUNTER: StringName = &"counter"
const BATTLE_START: StringName = &"battle_start"
const TURN_START: StringName = &"turn_start"
const REVIVE: StringName = &"revive"
## A delayed cast (opcode 132) or delayed damage (13) that is due.
const DELAYED: StringName = &"delayed"
## A jump landing on its own (opcode 52; an enemy's 134 too).
const LANDING: StringName = &"landing"

## A kind above.
var kind: StringName = COUNTER
var actor_id: int = -1
## BattleSkill.KIND_ATTACK for the normal attack, otherwise the kind of skill_id.
var skill_kind: StringName = BattleSkill.KIND_ATTACK
var skill_id: String = ""
## A counter's damage in percent of the normal attack; 0 keeps the attack's own.
var modifier: int = 0
## Whom it aims at: the attacker for a counter, -1 for the unit itself (its ally effects
## land on it; an opponent effect takes the first living opponent).
var target_id: int = -1
## The action a counter answers, -1 otherwise.
var trigger_action_id: int = -1
## The passive it comes from, the skill that put the counter status, or the skill that
## made a delayed effect or a jump.
var source_skill_id: String = ""
## The skill to run when it is not looked up by skill_kind and skill_id: delayed damage
## or a landing (BattleSkill.delayed_part), a delayed cast's ability. null otherwise.
var skill: BattleSkill = null
## The action that queued a delayed effect or made a jump, -1 otherwise: the order
## delayed effects and landings due on the same turn run in.
var source_action_id: int = -1


## A cast from one of `fighter`'s CombatantPassives.auto_casts entries.
static func auto_cast(reaction_kind: StringName, fighter: Combatant, cast: Dictionary) -> Reaction:
	var made := Reaction.new()
	made.kind = reaction_kind
	made.actor_id = fighter.id
	made.skill_kind = StringName(cast.get("skill_kind", BattleSkill.KIND_ABILITY))
	made.skill_id = str(cast.get("skill_id", ""))
	made.source_skill_id = str(cast.get("source_skill_id", ""))
	return made


## A counter by `fighter` from a Counters source, answering `attack`.
static func counter(fighter: Combatant, source: Dictionary, attack: BattleAction) -> Reaction:
	var made := Reaction.new()
	made.kind = COUNTER
	made.actor_id = fighter.id
	made.skill_kind = StringName(source.get("skill_kind", BattleSkill.KIND_ATTACK))
	made.skill_id = str(source.get("skill_id", ""))
	made.modifier = int(source.get("modifier", 0))
	made.target_id = attack.actor_id
	made.trigger_action_id = attack.id
	made.source_skill_id = str(source.get("source_skill_id", ""))
	return made


## A delayed effect that is due: its caster casts `entry.skill` at the stored target.
static func delayed(entry: DelayedCast) -> Reaction:
	var made := Reaction.new()
	made.kind = DELAYED
	made.actor_id = entry.actor_id
	made.skill = entry.skill
	made.skill_kind = entry.skill.kind
	made.skill_id = entry.skill.id
	made.target_id = entry.target_id
	made.source_skill_id = entry.source_skill_id
	made.source_action_id = entry.source_action_id
	return made


## The landing of `fighter`'s jump (its BattleStatus.AWAY), at the target picked when it
## jumped.
static func landing(fighter: Combatant, away: BattleStatus) -> Reaction:
	var made := Reaction.new()
	made.kind = LANDING
	made.actor_id = fighter.id
	made.skill = away.params.get("landing", null)
	made.skill_kind = StringName(away.params.get("skill_kind", BattleSkill.KIND_ABILITY))
	made.skill_id = str(away.params.get("skill_id", ""))
	made.target_id = int(away.params.get("target_id", -1))
	made.source_skill_id = made.skill_id
	made.source_action_id = int(away.params.get("action", -1))
	return made


func describe() -> String:
	var what: String = "attack" if skill_kind == BattleSkill.KIND_ATTACK else "%s:%s" % [skill_kind, skill_id]
	return "%s %s by #%d" % [kind, what, actor_id]
