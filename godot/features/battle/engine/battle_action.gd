class_name BattleAction
extends RefCounted

## One declared action: who does what, when it started and how many of its hits are
## still in flight. Reactions (counters, casts passives make on their own; Reaction) are
## actions too, told apart by `origin`.

enum Origin {
	## A player command (execute).
	COMMAND,
	## An enemy AI decision.
	AI,
	## Started by the engine on its own (Reaction): a counter, a battle-start, turn-start
	## or revive cast. Pays no cost.
	REACTION,
	## Cast by another action's effect (a random cast's pick). Pays no cost.
	CAST,
	## Chosen by an ailment: a berserk or confused combatant's basic attack.
	FORCED,
}

enum State { RUNNING, ENDED }

## cast_order of every enemy action: after the party, so enemies keep the order their
## actions were scheduled in.
const ENEMY_CAST_ORDER: int = 100

var id: int = 0
var actor_id: int = -1
var command: BattleCommand = null
## The skill whose effects run; null for DEFEND, the only command that runs no skill.
var skill: BattleSkill = null
## The skill the command named, which pays the cost and carries the name. It differs
## from `skill` for wrappers (cooldown or use-limited abilities), opcode 99 and random
## casts.
var declared_skill: BattleSkill = null
## An Origin value (typed int; see Combatant.side).
var origin: int = Origin.COMMAND
## A State value.
var state: int = State.RUNNING
## Frame the action was declared on.
var start_frame: int = 0
## Where the action's hits go among hits on the same frame from actions declared on
## the same frame: the actor's party slot (wiki, spark chain order: party order from
## one to six; a guest, not modelled yet, would come last), or ENEMY_CAST_ORDER.
var cast_order: int = 0
## Frame its attack frames count from: start_frame plus the move offset.
var hit_start_frame: int = 0
## Frame of its last hit (start_frame when it has none). The action ends here.
var end_frame: int = 0
## Hits scheduled and not yet resolved.
var pending_hits: int = 0
## Who takes what the action does to a covered opponent: { target id: coverer id },
## settled when the action is declared (CoverTracker).
var cover_map: Dictionary = {}
## The actor's weapon inflicts still to roll: { Vector2i(target id, swing): { pending:
## hits not resolved yet, landed: bool } } for each target its physical and hybrid
## damage reaches, per swing (WeaponInflict).
var weapon_inflict_targets: Dictionary = {}
## The actor swings twice: the skill runs again for the left hand (DualWield).
var dual_wield: bool = false
## The hand the effects being scheduled swing with (DualWield.RIGHT or LEFT); new hits
## copy it.
var swing: int = 0
## Frames after hit_start_frame where the left hand's attack frames start counting.
var left_swing_offset: int = 0
## A multicast pick (Multicast): the command's ability id, the pick's place among the
## command's picks (-1 outside a multicast) and how many picks it has.
var multicast_skill_id: String = ""
var multicast_index: int = -1
var multicast_count: int = 0
## The stacks a stacking ability casts with (SkillHistory; 0 on the initial cast), -1
## for any other action.
var stacks: int = -1
## What an action of origin REACTION reacts to (its kind, source and target), or null.
var reaction: Reaction = null
## Who sustained this action's attack, for counters: { target id: Counters.PHYSICAL and /
## or Counters.MAGIC }, noted as its damage hits reach living opponents, landed or not
## (Counters.note_sustained).
var sustained: Dictionary = {}


func is_running() -> bool:
	return state == State.RUNNING


## Frames from declaration to the last hit.
func span() -> int:
	return end_frame - start_frame
