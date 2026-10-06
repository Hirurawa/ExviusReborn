class_name BattleEventLog
extends RefCounted

## Everything the engine reports, in the order it happened. Each event is a Dictionary
## { type, frame, seq, ... } with combatants and actions named by id. Tests assert on
## the log; BattleSession (milestone 2) drains it after every tick and turns it into
## signals.

const BATTLE_STARTED: StringName = &"battle_started"
## { turn, wave, total_turns }. Emitted when a new turn begins, before its opening and
## player phases. `turn` restarts at 1 each wave; `total_turns` counts across waves.
const TURN_STARTED: StringName = &"turn_started"
## { turn }. Emitted after the enemy phase, once regens have ticked and statuses have
## counted down.
const TURN_ENDED: StringName = &"turn_ended"
## { phase: &"opening" | &"player" | &"enemy" | ..., turn }. The opening phase runs the
## turn's reactions (counters, battle-start and turn-start casts) before the player
## phase; a turn without any has none.
const PHASE_CHANGED: StringName = &"phase_changed"
## { actor, command, kind, skill_kind, skill_id, target, payload, replaced_payload }
const COMMAND_QUEUED: StringName = &"command_queued"
## { actor, reason, command }
const COMMAND_REJECTED: StringName = &"command_rejected"
## { action, actor, origin, kind, skill_kind, skill_id, skill_name, executed_skill_id,
##   target, payload, forced_by, dual_wield, esper_id, multicast_skill_id,
##   multicast_index, multicast_count, stacks, reaction, trigger_action,
##   source_skill_id }. skill_* name what the command chose;
##   executed_skill_id is what runs (a wrapper's ability, a random cast's pick).
##   forced_by is the ailment (BERSERK, CONFUSION) that turned the action into a basic
##   attack, "" otherwise. dual_wield is true when the skill runs twice, right hand then
##   left (DualWield). esper_id is the evoked esper's beastId for an EVOKE command, 0
##   otherwise. multicast_* describe a multicast pick (Multicast): the command's ability
##   id, the pick's index (-1 outside a multicast) and how many picks the command has.
##   stacks is what a stacking ability casts with (SkillHistory; 0 on the initial
##   cast), -1 for any other action. reaction is the Reaction kind of an action the
##   engine started on its own (origin REACTION: counter, battle_start, turn_start,
##   revive, delayed, landing), &"" otherwise; trigger_action the action a counter
##   answers (-1 otherwise) and source_skill_id the passive, counter status or skill it
##   came from. A landing's kind is LAND (BattleCommand.Kind.LAND), whether the player
##   landed it (origin COMMAND) or it landed on its own (origin REACTION); its skill_* name
##   the jump.
const ACTION_STARTED: StringName = &"action_started"
## { action, actor, mp_cost, lb_cost, hp_cost, orb_cost, mp, lb, hp, orbs }. orb_cost and
## orbs are the party's esper gauge (an evocation spends all of it, an ability that
## consumes the gauge its orb cost).
const COST_PAID: StringName = &"cost_paid"
## { action, actor, item_id, left }: an item action started and spent one of the party's
## stock; `left` is what remains (BattleEngine.item_stock).
const ITEM_USED: StringName = &"item_used"
## { action, actor, target, effect, opcode, hit, hits, swing, damage_kind, attack_type,
##   elements, amount, absorbed, hp_lost, hp, max_hp, chain, chain_pct, spark,
##   element_chain }. `amount` is the damage dealt, which can exceed the HP the target
##   had left (`hp_lost`); `absorbed` is the part a barrier took. `swing` is
##   DualWield.LEFT for a dual wielder's second swing, RIGHT otherwise. `spark` is true
##   for a spark chain and `element_chain` counts the elements shared with the previous
##   hit (an elemental chain when above 0); both describe how the hit joined the chain.
const HIT_LANDED: StringName = &"hit_landed"
## { action, actor, target, effect, swing, reason }: target_down, dodged, missed, blinded,
## evaded, away (the target left the field, a jump, after the hit was scheduled).
const HIT_MISSED: StringName = &"hit_missed"
## { target, by, action }
const COMBATANT_DEFEATED: StringName = &"combatant_defeated"
## { action, actor, target, hp, mp, reason, hp_now, mp_now }: HP and MP actually
## restored (reason: "" for a skill, drain, regen).
const RESTORED: StringName = &"restored"
## { action, actor, target, hp, reason }: back from KO (reason: "" or auto_revive).
const REVIVED: StringName = &"revived"
## { action, target, amount, lb, max_lb, reason }: gauge change from a skill.
const LB_CHANGED: StringName = &"lb_changed"
## { source, target, amount, lb, max_lb }: a limit crystal from an enemy hit.
const LB_CRYSTAL_DROPPED: StringName = &"lb_crystal_dropped"
## { source, actor, amount, orbs, max_orbs }: an esper orb from `actor`'s hit on the
## enemy `source`, into the party's esper gauge (amount 0 when the gauge was full).
const ESPER_ORB_DROPPED: StringName = &"esper_orb_dropped"
## { action, actor, amount, orbs, max_orbs, reason }: the party's esper gauge changed
## through a skill (reason fill). Evoking spends it through COST_PAID instead.
const ESPER_GAUGE_CHANGED: StringName = &"esper_gauge_changed"
## { action, actor, target, kind, key, value, turns }
const STATUS_ADDED: StringName = &"status_added"
## { action, actor, target, kind, key, reason }: resisted, or weaker (a stronger status
## of the same kind was kept).
const STATUS_RESISTED: StringName = &"status_resisted"
## { target, kind, key, value, reason }: expired, cured, dispelled, ko, used_up, broken,
## recovered (an enemy's roll at the start of its turn), damaged (a physical hit woke a
## sleeper or cleared confusion), debug.
const STATUS_REMOVED: StringName = &"status_removed"
## { action, actor, target, kind, key, amount, hp_lost, hp, max_hp }: HP lost to a
## status rather than a hit: poison at the end of a turn (action -1, actor = who
## inflicted it) or a zombie being healed (the healing action and its actor).
const STATUS_DAMAGE: StringName = &"status_damage"
## { action, actor, coverer, mode: &"aoe" | &"st", protects, physical, magic,
##   mitigation }: a cover triggered on `actor`'s attack. It holds for the rest of the
##   turn (until COVER_ENDED): an AoE cover takes every matching attack on the
##   coverer's allies, an ST cover those on `protects` (-1 for AoE). `mitigation` is
##   the percent cut from every hit the coverer takes meanwhile.
const COVER_ACTIVATED: StringName = &"cover_activated"
## { action, actor, target, coverer }: what `action` does to `target` goes to
##   `coverer` instead, damage and every other effect. Emitted when the action is
##   declared, before its hits.
const COVERED: StringName = &"covered"
## { coverer, reason }: a triggered cover ends: turn_over (the next phase began) or ko.
const COVER_ENDED: StringName = &"cover_ended"
## { action, actor, effect_index, opcode, effect, reason }
const EFFECT_UNSUPPORTED: StringName = &"effect_unsupported"
## { action, actor }
const ACTION_ENDED: StringName = &"action_ended"
## { target, skill_kind, skill_id, turns, uses, source_skill_id, by, replaced }: an op 100
## effect granted a skill (SkillGrant). turns and uses are -1 for no limit; replaced is
## true when the target already held a grant of that skill, which this one replaces.
const SKILL_GRANTED: StringName = &"skill_granted"
## { target, skill_kind, skill_id, reason }: a grant ended: expired (its turns ran out
## when the enemy phase began), used_up (its last use was cast) or ko.
const SKILL_GRANT_ENDED: StringName = &"skill_grant_ended"
## { actor, skill_id, skill_kind, multicast_skill_id, index, reason }: a multicast pick
## that was due and not cast: caster_down (KO'd or petrified since the command ran),
## caster_away (an earlier pick was a jump) or no_opponents (the formation fell). The
## picks after it are dropped too.
const MULTICAST_CAST_DROPPED: StringName = &"multicast_cast_dropped"
## { actor, attacker, action, skill_kind, skill_id, modifier, source_skill_id, chance }: a
## counter roll succeeded (Counters). `actor` will answer `attacker`'s action `action`
## in the next opening phase; `chance` is the combined chance it rolled against.
const COUNTER_QUEUED: StringName = &"counter_queued"
## { actor, reaction, skill_kind, skill_id, source_skill_id, reason }: a reaction that was
## due and did not run: caster_down (KO'd or petrified), cannot_act (disabled),
## unknown_skill, no_opponents, away (its unit is in the air) or battle_over (the battle
## or the wave ended first). A landing dropped this way still brings its unit down.
const REACTION_DROPPED: StringName = &"reaction_dropped"
## { action, actor, kind, skill_kind, skill_id, source_skill_id, target, due_turn, key }:
## a delayed effect (DelayedCast) went into the queue: kind &"cast" (op 132, skill_* the
## ability it will cast) or &"damage" (op 13, skill_* the skill it comes from), due on
## the engine's total_turns `due_turn`, aimed at `target` (the command's pick, -1 for
## none). key is op 132's key, "" for none.
const DELAY_QUEUED: StringName = &"delay_queued"
## { actor, kind, skill_kind, skill_id, source_skill_id, reason }: a delayed effect left
## the queue without running: caster_down (KO'd), replaced (a new cast with its key),
## wave_cleared or battle_over. One whose caster cannot act when it is due is a
## REACTION_DROPPED instead.
const DELAY_DROPPED: StringName = &"delay_dropped"
## { target, field, key, old, value }: a debug tool changed a combatant directly
## (BattleEngine.debug_edit).
const DEBUG_EDITED: StringName = &"debug_edited"
## { wave, waves, turn }: the formation is down and another wave follows. The party has
## already dropped what does not carry over; the engine waits for begin_next_wave().
const WAVE_CLEARED: StringName = &"wave_cleared"
## { wave, waves, enemies }: the next formation is in; its turn 1 follows.
const WAVE_STARTED: StringName = &"wave_started"
## { outcome: &"victory" | &"defeat", turn, wave, total_turns }
const BATTLE_ENDED: StringName = &"battle_ended"

## When false, drain() discards what it returns, which keeps a long battle's memory flat.
var keep_history: bool = true

var _events: Array[Dictionary] = []
var _drain_cursor: int = 0
var _next_seq: int = 0


func append(type: StringName, frame: int, data: Dictionary = {}) -> Dictionary:
	var event: Dictionary = data.duplicate()
	event["type"] = type
	event["frame"] = frame
	event["seq"] = _next_seq
	_next_seq += 1
	_events.append(event)
	return event


## Events appended since the previous drain.
func drain() -> Array[Dictionary]:
	var fresh: Array[Dictionary] = _events.slice(_drain_cursor)
	if keep_history:
		_drain_cursor = _events.size()
	else:
		_events.clear()
		_drain_cursor = 0
	return fresh


func all() -> Array[Dictionary]:
	return _events.duplicate()


func of_type(type: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for event in _events:
		if event["type"] == type:
			out.append(event)
	return out


func count_of_type(type: StringName) -> int:
	return of_type(type).size()


## The most recent event of `type`, or {} when there is none.
func last_of_type(type: StringName) -> Dictionary:
	for i in range(_events.size() - 1, -1, -1):
		if _events[i]["type"] == type:
			return _events[i]
	return {}


func size() -> int:
	return _events.size()


func clear() -> void:
	_events.clear()
	_drain_cursor = 0
