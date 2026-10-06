class_name BattleEngine
extends RefCounted

## Headless battle simulation: pure logic on a fixed tick, no nodes, no autoloads, one
## seeded RNG. BattleSession (milestone 2) ticks it at 60 Hz and turns its events into
## signals; tests drive it directly.
##
## TIME. `frame` counts ticks since start(). A command takes effect on the current
## frame: an action declared on frame F lands a hit with attack frame f on frame
## F + move offset + f, run by the first tick that reaches it. Entries due on the same
## frame run in the order they were scheduled.
##
## COMMANDS IN, EVENTS OUT. queue_command, set_target and execute are the only way in.
## Everything that happens is appended to `events`; callers read state through the
## queries and never write to it.
##
## ACTION LIFECYCLE. Each step is a hook point:
##   1. declare   resolve skill links (wrappers, opcode 99), check cooldowns, uses and
##                costs, pay them
##   2. target    resolve each effect's targets (cover; units in the air are out of
##                reach)
##   3. compute   effect handlers compute amounts at cast time and schedule hits
##   4. each hit  before-hit (dodge, mitigation, defend), chain, barrier, apply,
##                after-hit (drain, death and auto-revive); every damage hit notes what
##                its target sustained, for counters
##   5. end       after the last hit: the counter rolls (Counters)
##
## TURNS. A turn opens with the reactions queued for it, if any (the opening phase,
## below). The player phase is concurrent: units act whenever they are told to, while
## earlier actions are still landing, which is what builds chains. It ends once every
## living unit that can act has acted and the timeline is empty. Enemies then act one
## action at a time in formation order, each decided when it starts, so it sees
## current HP and deaths. The turn ends with regens, poison and status countdowns. The
## battle ends when one side is down (KO'd or petrified) and the timeline is empty.
##
## WAVES. The formation added before start() is wave 1; queue_wave() adds later ones,
## each built when it begins. When a formation is down and another wave follows, the
## engine clears the wave (the party keeps HP, MP, the gauge, buffs and debuffs, grants,
## its action history and the ailments that persist; cooldowns, uses and the turn number
## reset) and waits in the WAVE_CLEARED phase until begin_next_wave(), so the session can
## play dialogue or a transition first. The battle is won when the last wave is down.
##
## AILMENTS. What each one does is its StatusBehavior (engine/behaviors/), asked at
## the hook points: disabled units skip their turn, a berserk unit attacks a random
## opponent on its own, a confused one attacks a random combatant when it acts, silence
## blocks spells, blind makes attacks miss at cast time, physical hits wake sleepers,
## poison ticks at the end of the turn, zombies are hurt by healing. Enemies roll to
## shake ailments off at the start of their turns.
##
## ESPERS. The party shares one esper gauge (esper_orbs, up to rules.esper_gauge_max).
## A damaging party hit on an enemy may drop an orb into it, and skills can fill it. A
## unit with an esper can evoke it (an EVOKE command) only while the gauge is full,
## which empties it. Abilities that "consume evocation gauge (N)" pay N orbs on top of
## their MP. The gauge carries across waves.
##
## MULTICAST. A multicast command (Dualcast; see Multicast) carries the skills the
## player picked. Picking only asks the engine (multicast_rule, multicast_pick_problem):
## costs are summed over the picks, nothing is paid. Executing casts the first pick at
## once and each later one rules.cast_gap_frames after the previous pick's start, from
## the timeline; each pick is its own action that pays, spends its limits and computes
## its damage when it is cast. A pick due after its caster went down is dropped.
##
## HISTORY. Each combatant's SkillHistory records its actions as they start: the stack
## of stacking abilities (72, 126, 1007: damage that grows with consecutive casts, reset
## by a normal attack or guard before the cast, by another stacking ability and by KO)
## and the skills it used last turn, which decide op 99's branch.
##
## GRANTS. Op 100 grants skills for some turns or uses (SkillGrant, Combatant.grants).
## Their turns go down when the enemy phase begins, a use is spent when the granted
## skill's action starts, KO ends them and waves keep them. BattleCommandMenu lists
## them; the engine itself never checked which skills a unit owns, and still does not.
##
## REACTIONS. Actions the engine starts on its own (Reaction, origin REACTION): counters
## (Counters), the skills passives cast at the battle start (103, 35, 56) and at each
## turn start (66), and those they cast after a revive (35, 56). They cost nothing,
## spend no limit, do not use up the unit's turn and stay out of its history. Counters
## rolled in the enemy phase, then the battle-start casts (on each wave's first turn),
## then the turn-start casts wait in a queue that the turn's opening phase runs one at a
## time, rules.reaction_gap_frames after the previous one's last hit; the player phase
## begins when it is empty. A turn with nothing queued has no opening phase. A cast after
## a revive runs at once, from the timeline, in whatever phase the revive happened.
##
## DELAYS AND JUMPS (DELAYED-SKILLS-PLAN.md). A delayed cast (132) or delayed damage (13)
## waits in a queue (DelayedCast) for the turn it is due, the turn of the cast + its
## delay. That turn's opening phase runs it as a reaction, after the turn-start casts,
## together with the party's jumps that land on their own, in the order they were cast.
## A KO drops the caster's pending ones (a reraise does not bring them back), and so does
## a cleared wave. A jump (52, 134) puts its unit in the air (BattleStatus.AWAY): nothing
## targets it and it cannot act. A 52 jump lands on its own at the start of the turn it is
## due, which uses up the unit's turn (the wiki); a 134 jump is ready from that turn, and
## the player lands it with a LAND command, which the turn waits for. An enemy lands on
## its own turn, as its whole turn. Landings and delayed damage compute their damage when
## they land, at the target picked at the cast while it is on the field, else the first
## opponent on the field. A won wave brings jumpers back down without landing.
##
## ITEMS. The party shares the battle's item stock (item_stock, filled before start()).
## A unit that queues an item holds one for itself: the others see one fewer
## (items_available) and cannot queue or use it. The hold ends when the unit acts, is
## KO'd, queues something else, or the turn or wave ends. The item is spent only when
## its action starts (ITEM_USED), so a confused unit that attacks instead keeps it. The
## stock carries across waves.

enum Phase { SETUP, PLAYER, ENEMY, ENDED, WAVE_CLEARED, OPENING }

const PHASE_NAMES: Dictionary = {
	Phase.SETUP: &"setup",
	Phase.PLAYER: &"player",
	Phase.ENEMY: &"enemy",
	Phase.ENDED: &"ended",
	Phase.WAVE_CLEARED: &"wave_cleared",
	Phase.OPENING: &"opening",
}

const OUTCOME_VICTORY: StringName = &"victory"
const OUTCOME_DEFEAT: StringName = &"defeat"

## Command results. OK is the empty StringName; anything else says why the engine
## refused (and a COMMAND_REJECTED event carries the same reason).
const OK: StringName = &""
const REJECT_BATTLE_NOT_RUNNING: StringName = &"battle_not_running"
const REJECT_NOT_PLAYER_PHASE: StringName = &"not_player_phase"
const REJECT_UNKNOWN_UNIT: StringName = &"unknown_unit"
const REJECT_NOT_PARTY_MEMBER: StringName = &"not_a_party_member"
const REJECT_UNIT_DOWN: StringName = &"unit_down"
const REJECT_ALREADY_ACTED: StringName = &"already_acted"
const REJECT_CANNOT_ACT: StringName = &"cannot_act"
const REJECT_SILENCED: StringName = &"silenced"
const REJECT_UNKNOWN_SKILL: StringName = &"unknown_skill"
const REJECT_NOT_ENOUGH_MP: StringName = &"not_enough_mp"
const REJECT_LIMIT_NOT_FULL: StringName = &"limit_gauge_not_full"
const REJECT_NO_ESPER: StringName = &"no_esper"
const REJECT_ESPER_GAUGE_NOT_FULL: StringName = &"esper_gauge_not_full"
const REJECT_NOT_ENOUGH_ORBS: StringName = &"not_enough_orbs"
const REJECT_SKILL_NOT_READY: StringName = &"skill_not_ready"
const REJECT_NO_USES_LEFT: StringName = &"no_uses_left"
const REJECT_NO_ITEMS_LEFT: StringName = &"no_items_left"
## A unit in the air can only land (BattleCommand.land), and only once its jump is ready.
const REJECT_AWAY: StringName = &"away"
## A LAND command from a unit with no jump ready to land.
const REJECT_NOTHING_TO_LAND: StringName = &"nothing_to_land"
## A multicast pick the command cannot cast (Multicast.allows), or picks on a command
## that is not a multicast.
const REJECT_NOT_MULTICASTABLE: StringName = &"not_multicastable"
## A multicast command without exactly as many picks as it takes.
const REJECT_MULTICAST_INCOMPLETE: StringName = &"multicast_incomplete"
const REJECT_UNKNOWN_TARGET: StringName = &"unknown_target"
const REJECT_UNKNOWN_FIELD: StringName = &"unknown_field"
const REJECT_NO_WAVE_WAITING: StringName = &"no_wave_waiting"

## Fields debug_edit can set.
const DEBUG_FIELDS: Array[StringName] = [&"hp", &"max_hp", &"mp", &"max_mp", &"lb", &"stat", &"element_resist", &"ailment", &"orbs"]
const DEBUG_STATS: PackedStringArray = ["ATK", "DEF", "MAG", "SPR"]

## Effect types that link skills to skills. The engine resolves them when an action is
## declared (wrappers, uses, opcode 99) or starts (random casts) instead of running
## them on hit.
const LINK_TYPES: PackedStringArray = [
	"COOLDOWN_SKILL", "LIMITED_USE_SKILL", "USES_PER_BATTLE", "REPLACEMENT", "RANDOM_CAST",
]
## How deep skill links may nest (a wrapper around opcode 99 around ...).
const MAX_LINK_DEPTH: int = 4

## Guards against a runaway tick (a reaction that keeps scheduling on the same frame).
const MAX_ENTRIES_PER_TICK: int = 4096
## Guards against an enemy script that only ever waits.
const MAX_ENEMY_DECISIONS_PER_TICK: int = 64

## targetSelect stat modes -> [stat, pick the highest]. In the datamine's vocabulary
## `int` is MAG and `mind` is SPR.
const _AI_TARGET_STATS: Dictionary = {
	"atk_max": ["ATK", true], "atk_min": ["ATK", false],
	"def_max": ["DEF", true], "def_min": ["DEF", false],
	"int_max": ["MAG", true], "int_min": ["MAG", false],
	"mind_max": ["SPR", true], "mind_min": ["SPR", false],
}


## What a declared skill leads to: the skill whose effects run, and the limits the
## declared one carries (a cooldown from opcode 130, uses from 157 or 1014).
class SkillLinks:
	extends RefCounted
	var skill: BattleSkill = null
	## -1 when there is no cooldown. `turns` is what the data stores: "one use every N
	## turns" is N - 1.
	var cooldown_turns: int = -1
	var cooldown_initial: int = 0
	## -1 when uses are unlimited.
	var uses: int = -1

	func is_limited() -> bool:
		return cooldown_turns >= 0 or uses >= 0


var rules: BattleRules
var catalog: SkillCatalog
var effects: EffectRegistry
var events := BattleEventLog.new()
var timeline := BattleTimeline.new()
var rng := RandomNumberGenerator.new()
var battle_seed: int = 0

## A Phase value (typed int; see Combatant.side).
var phase: int = Phase.SETUP
## The turn within the current wave (restarts at 1 each wave).
var turn: int = 0
## Turns across every wave, for mission-wide counts (the old engine's turn_count).
var total_turns: int = 0
## 1-based number of the wave being fought.
var wave: int = 1
var frame: int = 0
## OUTCOME_VICTORY or OUTCOME_DEFEAT once the battle has ended.
var outcome: StringName = &""
## The party's esper gauge in orbs, 0 .. rules.esper_gauge_max (see ESPERS above).
var esper_orbs: int = 0
## Item id -> how many the party has left this battle (see ITEMS above). An item that
## is not here cannot be used.
var item_stock: Dictionary = {}

## Party by slot; an empty slot holds null.
var party: Array[Combatant] = []
## The current formation by slot.
var enemies: Array[Combatant] = []

## Formation sources for the waves after the first, in order (see queue_wave).
var _wave_sources: Array[Callable] = []
var _combatants: Dictionary = {}
var _next_combatant_id: int = 1
var _next_action_id: int = 1
var _next_status_order: int = 1

# Enemy phase progress: whose turn it is and when the next action may start.
var _enemy_order: PackedInt32Array = PackedInt32Array()
var _enemy_cursor: int = -1
var _enemy_turn_open: bool = false
var _enemies_done: bool = false
var _next_enemy_action_frame: int = 0

# Reactions waiting for the next opening phase (see REACTIONS), and the frame the next
# one may start on.
var _reactions: Array[Reaction] = []
var _next_reaction_frame: int = 0

# Delayed casts and delayed damage waiting for their turn, in cast order (see DELAYS AND
# JUMPS).
var _delayed: Array[DelayedCast] = []


func _init(skill_catalog: SkillCatalog = null, battle_rules: BattleRules = null, seed_value: int = 0) -> void:
	catalog = skill_catalog if skill_catalog != null else SkillCatalog.new()
	rules = battle_rules if battle_rules != null else BattleRules.new()
	effects = EffectRegistry.create_default()
	battle_seed = seed_value
	rng.seed = seed_value


# === Setup ===

## Puts a unit in party slot `slot_index` (-1 takes the next free index) and returns it
## with its id assigned.
func add_party_member(member: Combatant, slot_index: int = -1) -> Combatant:
	var index: int = slot_index if slot_index >= 0 else party.size()
	while party.size() <= index:
		party.append(null)
	if party[index] != null:
		push_warning("BattleEngine: party slot %d was taken; replacing %s" % [index, party[index].describe()])
	member.side = Combatant.Side.PARTY
	member.slot = index
	_register(member)
	party[index] = member
	return member


## Adds an enemy to the formation and returns it with its id assigned. Its brain gets a
## random stream derived from the battle seed.
func add_enemy(foe: Combatant) -> Combatant:
	foe.side = Combatant.Side.ENEMY
	foe.slot = enemies.size()
	if foe.brain == null:
		foe.brain = EnemyBrain.new()
	_register(foe)
	foe.brain.seed_rng(rng.randi())
	enemies.append(foe)
	return foe


## Adds a wave after the ones already planned. `source` is Callable() ->
## Array[Combatant], called when the wave begins, so a lottery pick happens then.
func queue_wave(source: Callable) -> void:
	_wave_sources.append(source)


## How many waves the battle has: the first formation plus the queued ones.
func wave_count() -> int:
	return 1 + _wave_sources.size()


## Starts turn 1. An empty formation (or party) ends the battle at once instead of
## soft-locking.
func start() -> void:
	if phase != Phase.SETUP:
		push_warning("BattleEngine.start: the battle has already started")
		return
	if not catalog.skill_schema.is_empty():
		for type in effects.unknown_types(catalog.skill_schema):
			push_error("BattleEngine: effect handler registered for \"%s\", which skill_schema.json does not define" % type)
	events.append(BattleEventLog.BATTLE_STARTED, frame, {
		"party": _ids(party_members()),
		"enemies": _ids(enemies),
		"seed": battle_seed,
		"waves": wave_count(),
	})
	_begin_turn()
	_check_battle_end()


# === Time ===

## Advances the battle by one frame (1/60 s).
func tick() -> void:
	if not is_running():
		return
	frame += 1
	_process_timeline()
	_advance_phase()


func advance(frames: int) -> void:
	for _i in range(frames):
		tick()


# === Commands ===

## Stores what a party member will do when executed. A queued item is held for the unit
## (see ITEMS above), so an item none of which is left for it is refused. The event
## carries the replaced command's payload.
func queue_command(unit_id: int, command: BattleCommand) -> StringName:
	var reason: StringName = _party_member_problem(unit_id)
	if reason == OK and command.kind == BattleCommand.Kind.ITEM and items_available(command.skill_id, unit_id) <= 0:
		reason = REJECT_NO_ITEMS_LEFT
	if reason != OK:
		return _reject(unit_id, reason, command)
	var unit: Combatant = combatant(unit_id)
	var replaced: BattleCommand = unit.queued_command
	unit.queued_command = command
	events.append(BattleEventLog.COMMAND_QUEUED, frame, {
		"actor": unit_id,
		"command": command.describe(),
		"kind": command.kind,
		"skill_kind": command.skill_kind,
		"skill_id": command.skill_id,
		"target": command.target_id,
		"payload": command.payload,
		"replaced_payload": replaced.payload if replaced != null else {},
	})
	return OK


## Points a party member's queued command (a basic attack when nothing is queued) at
## `target_id`.
func set_target(unit_id: int, target_id: int) -> StringName:
	var reason: StringName = _party_member_problem(unit_id)
	if reason == OK and combatant(target_id) == null:
		reason = REJECT_UNKNOWN_TARGET
	if reason != OK:
		return _reject(unit_id, reason, null)
	var unit: Combatant = combatant(unit_id)
	if unit.queued_command == null:
		unit.queued_command = BattleCommand.attack()
	unit.queued_command.target_id = target_id
	return OK


## Starts a party member's action on the current frame: `command` if given, otherwise
## its queued command, otherwise a basic attack. Returns OK or the reason it cannot.
func execute(unit_id: int, command: BattleCommand = null) -> StringName:
	var reason: StringName = can_execute(unit_id, command)
	var unit: Combatant = combatant(unit_id)
	if reason != OK:
		return _reject(unit_id, reason, _command_for(unit, command) if unit != null else command)
	var chosen: BattleCommand = _command_for(unit, command)
	unit.acted = true
	if chosen.kind == BattleCommand.Kind.LAND:
		# The jump stays the last command, so Repeat jumps again.
		_start_landing(unit, BattleAction.Origin.COMMAND, null)
		return OK
	unit.last_command = chosen.duplicate_command()
	var controller: BattleStatus = unit.controlling_status()
	if controller != null:
		# Confusion (the only control a commandable unit can be under): whatever was
		# chosen becomes a basic attack on a random target, with no cost or limits.
		_start_forced_attack(unit, controller)
		return OK
	var declared: BattleSkill = _skill_for(unit, chosen)
	var links: SkillLinks = _links_for(unit, declared) if declared != null else null
	if links != null:
		_spend_limits(unit, chosen, links)
	if _multicast_rule_of(unit, chosen, declared) != null:
		# The command itself is not an action: its picks are.
		_cast_pick(ScheduledCast.pick(unit.id, chosen, 0, frame))
		return OK
	_start_action(unit, chosen, declared, links.skill if links != null else null, BattleAction.Origin.COMMAND)
	return OK


## After WAVE_CLEARED: builds the next formation and starts its turn 1. Returns OK or
## REJECT_NO_WAVE_WAITING.
func begin_next_wave() -> StringName:
	if phase != Phase.WAVE_CLEARED:
		return REJECT_NO_WAVE_WAITING
	wave += 1
	enemies.clear()
	var built: Variant = _wave_sources[wave - 2].call()
	if built is Array:
		for foe in built:
			if foe is Combatant:
				add_enemy(foe)
	turn = 0
	events.append(BattleEventLog.WAVE_STARTED, frame, {
		"wave": wave,
		"waves": wave_count(),
		"enemies": _ids(enemies),
	})
	_begin_turn()
	_check_battle_end()
	return OK


## Executes several party members on the same frame, in the order given (auto-battle,
## "all attack"). Returns unit id -> result.
func execute_many(unit_ids: Array) -> Dictionary:
	var results: Dictionary = {}
	for unit_id in unit_ids:
		results[int(unit_id)] = execute(int(unit_id))
	return results


## Why `unit_id` cannot run `command` (or its queued command) right now; OK when it can.
func can_execute(unit_id: int, command: BattleCommand = null) -> StringName:
	if not is_running():
		return REJECT_BATTLE_NOT_RUNNING
	if phase != Phase.PLAYER:
		return REJECT_NOT_PLAYER_PHASE
	var reason: StringName = _party_member_problem(unit_id)
	if reason != OK:
		return reason
	var unit: Combatant = combatant(unit_id)
	if unit.acted:
		return REJECT_ALREADY_ACTED
	var chosen: BattleCommand = _command_for(unit, command)
	if unit.is_away():
		return OK if chosen.kind == BattleCommand.Kind.LAND and landing_ready(unit) else REJECT_AWAY
	if chosen.kind == BattleCommand.Kind.LAND:
		return REJECT_NOTHING_TO_LAND
	if not unit.can_take_commands():
		return REJECT_CANNOT_ACT
	if unit.control() == StatusBehavior.CONTROL_CONFUSED:
		return OK
	if chosen.kind == BattleCommand.Kind.DEFEND:
		return OK
	if chosen.kind == BattleCommand.Kind.EVOKE and unit.esper_skill_id == "":
		return REJECT_NO_ESPER
	var declared: BattleSkill = _skill_for(unit, chosen)
	if declared == null:
		return REJECT_UNKNOWN_SKILL
	if unit.skill_blocked(declared):
		return REJECT_SILENCED
	reason = _skill_limit_problem(unit, chosen, _links_for(unit, declared))
	if reason != OK:
		return reason
	reason = _cost_problem(unit, chosen, declared)
	if reason != OK:
		return reason
	var rule: Multicast.Rule = _multicast_rule_of(unit, chosen, declared)
	if rule == null:
		return OK if chosen.picks.is_empty() else REJECT_NOT_MULTICASTABLE
	if chosen.picks.size() != rule.count:
		return REJECT_MULTICAST_INCOMPLETE
	for i in range(chosen.picks.size()):
		reason = _pick_problem(unit, rule, chosen.picks.slice(0, i), chosen.picks[i])
		if reason != OK:
			return reason
	return OK


# === Queries ===

## The multicast rule of the skill `command` names for `unit_id` (how many picks, what it
## may pick, after what the unit's passives say), or null when it is not a multicast
## command (Multicast).
func multicast_rule(unit_id: int, command: BattleCommand) -> Multicast.Rule:
	var unit: Combatant = combatant(unit_id)
	if unit == null or command == null:
		return null
	return _multicast_rule_of(unit, command, _skill_for(unit, command))


## Why `pick` cannot come after `picks_before` in the multicast `command` of `unit_id`; OK
## when it can. What the menu asks while the player picks: it changes nothing. A skill
## with a cooldown or a use limit is picked once; every pick's costs (MP, LB gauge, esper
## orbs) are added to the earlier picks' and checked against what the unit has now.
func multicast_pick_problem(unit_id: int, command: BattleCommand, picks_before: Array[BattleCommand], pick: BattleCommand) -> StringName:
	var unit: Combatant = combatant(unit_id)
	if unit == null:
		return REJECT_UNKNOWN_UNIT
	var rule: Multicast.Rule = multicast_rule(unit_id, command)
	if rule == null:
		return REJECT_NOT_MULTICASTABLE
	return _pick_problem(unit, rule, picks_before, pick)


func combatant(id: int) -> Combatant:
	return _combatants.get(id, null)


func is_running() -> bool:
	return phase == Phase.PLAYER or phase == Phase.ENEMY or phase == Phase.OPENING


## The reactions waiting for the next opening phase, in the order they will run.
func queued_reactions() -> Array[Reaction]:
	return _reactions.duplicate()


## Adds a reaction to the queue the next opening phase runs (Counters queues counters).
func queue_reaction(reaction: Reaction) -> void:
	_reactions.append(reaction)


## The delayed casts and delayed damage waiting for their turn, in cast order (copies).
func pending_delays() -> Array[DelayedCast]:
	var out: Array[DelayedCast] = []
	for entry in _delayed:
		out.append(entry.copy())
	return out


## Puts a delayed effect in the queue (DelayHandler). A pending one of the same caster with
## the same key goes first (DELAY_DROPPED, reason `replaced`).
func queue_delayed(entry: DelayedCast, action: BattleAction) -> void:
	if entry.key != "":
		for pending in _delayed.duplicate():
			if pending.actor_id == entry.actor_id and pending.key == entry.key:
				_drop_delayed_entry(pending, &"replaced")
	_delayed.append(entry)
	events.append(BattleEventLog.DELAY_QUEUED, frame, {
		"action": action.id if action != null else -1,
		"actor": entry.actor_id,
		"kind": entry.kind,
		"skill_kind": entry.skill.kind,
		"skill_id": entry.skill.id,
		"source_skill_id": entry.source_skill_id,
		"target": entry.target_id,
		"due_turn": entry.due_turn,
		"key": entry.key,
	})


## A unit's jump (opcodes 52, 134) while it is in the air: { skill_kind, skill_id (the
## skill its command named), ready_turn (in total_turns), manual (134: the player lands
## it), ready (due this turn or earlier) }, or {} when it is on the ground.
func jump_of(unit_id: int) -> Dictionary:
	var unit: Combatant = combatant(unit_id)
	var away: BattleStatus = unit.away_status() if unit != null else null
	if away == null:
		return {}
	return {
		"skill_kind": StringName(away.params.get("skill_kind", &"")),
		"skill_id": str(away.params.get("skill_id", "")),
		"ready_turn": away.value,
		"manual": bool(away.params.get("manual", false)),
		"ready": total_turns >= away.value,
	}


## Whether party member `unit` is in the air with a jump the player lands (134) that is
## ready, and has not acted this turn: its default command is LAND.
func landing_ready(unit: Combatant) -> bool:
	if unit == null or not unit.is_party() or not unit.is_alive() or unit.acted:
		return false
	var away: BattleStatus = unit.away_status()
	return away != null and bool(away.params.get("manual", false)) and total_turns >= away.value


## Whether the party's esper gauge is full, so a unit with an esper can evoke it.
func esper_gauge_full() -> bool:
	return esper_orbs >= rules.esper_gauge_max


## How many of `item_id` the party member `unit_id` can still pick: the stock less the
## ones other members hold queued (see ITEMS above). The item menu shows this number and
## hides the item at 0.
func items_available(item_id: String, unit_id: int = -1) -> int:
	var held: int = 0
	for member in living_party():
		if member.id != unit_id and _holds_item(member, item_id):
			held += 1
	return maxi(0, int(item_stock.get(item_id, 0)) - held)


## True when nothing is scheduled: no hit in flight, no action still to end.
func is_idle() -> bool:
	return timeline.is_empty()


func party_members() -> Array[Combatant]:
	var out: Array[Combatant] = []
	for member in party:
		if member != null:
			out.append(member)
	return out


func living_party() -> Array[Combatant]:
	var out: Array[Combatant] = []
	for member in party:
		if member != null and member.is_alive():
			out.append(member)
	return out


func living_enemies() -> Array[Combatant]:
	var out: Array[Combatant] = []
	for foe in enemies:
		if foe.is_alive():
			out.append(foe)
	return out


func living_allies_of(fighter: Combatant) -> Array[Combatant]:
	return living_party() if fighter.is_party() else living_enemies()


func living_opponents_of(fighter: Combatant) -> Array[Combatant]:
	return living_enemies() if fighter.is_party() else living_party()


## The members of `fighters` on the field (Combatant.is_targetable): a unit in the air is
## out of reach.
func targetable(fighters: Array[Combatant]) -> Array[Combatant]:
	var out: Array[Combatant] = []
	for fighter in fighters:
		if fighter.is_targetable():
			out.append(fighter)
	return out


## Living opponents of `fighter` on the field: what its attacks can reach.
func targetable_opponents_of(fighter: Combatant) -> Array[Combatant]:
	return targetable(living_opponents_of(fighter))


## KO'd members of `fighter`'s side, for revives.
func fallen_allies_of(fighter: Combatant) -> Array[Combatant]:
	var out: Array[Combatant] = []
	for ally in (party_members() if fighter.is_party() else enemies):
		if not ally.is_alive():
			out.append(ally)
	return out


## Living party members that take commands and have not acted this turn, and those in
## the air with a jump the player can land now (landing_ready): the turn waits for them
## (the user's rule, 2026-10-06). Disabled and berserk units are left out (a berserk one
## attacks on its own), and so are the other units in the air.
func units_to_act() -> Array[Combatant]:
	var out: Array[Combatant] = []
	for member in living_party():
		if not member.acted and (member.can_take_commands() or landing_ready(member)):
			out.append(member)
	return out


## The limits on a party member's skill: { uses_left (-1 unlimited), ready_turn },
## or {} when the skill has none. The UI can show them next to the skill.
func skill_limits(unit_id: int, command: BattleCommand) -> Dictionary:
	var unit: Combatant = combatant(unit_id)
	if unit == null or command == null or command.kind != BattleCommand.Kind.SKILL:
		return {}
	var out: Dictionary = {}
	var declared: BattleSkill = _skill_for(unit, command)
	var links: SkillLinks = _links_for(unit, declared) if declared != null else null
	if links != null and links.is_limited():
		out = _skill_state(unit, command.skill_id, links).duplicate()
	var grant: SkillGrant = _grant_for(unit, command)
	if grant != null:
		out["grant_turns_left"] = grant.turns_left
		out["grant_uses_left"] = grant.uses_left
	return out


## The skill `command` runs for `unit_id` once its links are followed (a cooldown or
## use-limited wrapper's ability, opcode 99's branch for what the unit did last turn):
## the effects whose targets the player picks. null for DEFEND, an unknown unit or an
## unknown skill.
func executed_skill(unit_id: int, command: BattleCommand) -> BattleSkill:
	var unit: Combatant = combatant(unit_id)
	if unit == null or command == null:
		return null
	var declared: BattleSkill = _skill_for(unit, command)
	return _links_for(unit, declared).skill if declared != null else null


## Copies of the skills `unit_id` holds through grants (op 100), in grant order. Empty
## for an unknown unit.
func grants_of(unit_id: int) -> Array[SkillGrant]:
	var out: Array[SkillGrant] = []
	var unit: Combatant = combatant(unit_id)
	if unit == null:
		return out
	for grant in unit.grants.values():
		out.append((grant as SkillGrant).copy())
	return out


## Grants `target` the skill `kind` `skill_id` for `turns` and `uses` (SkillGrant.UNLIMITED
## for no limit), replacing a grant of the same skill. Run by GrantHandler as op 100's hit
## lands. Nothing happens to a KO'd target.
func grant(target: Combatant, kind: StringName, skill_id: String, turns: int, uses: int, action: BattleAction) -> void:
	if target == null or not target.is_alive() or skill_id == "":
		return
	var made: SkillGrant = SkillGrant.make(kind, skill_id, turns, uses)
	if action != null:
		made.granted_by = action.actor_id
		made.source_skill_id = action.declared_skill.id if action.declared_skill != null else ""
	var replaced: bool = target.grants.has(made.key())
	target.grants[made.key()] = made
	events.append(BattleEventLog.SKILL_GRANTED, frame, {
		"target": target.id,
		"skill_kind": kind,
		"skill_id": skill_id,
		"turns": turns,
		"uses": uses,
		"source_skill_id": made.source_skill_id,
		"by": made.granted_by,
		"replaced": replaced,
	})


## The combatants `effect` reaches when `actor` uses it on `chosen` (null when nothing
## was picked). A single-target effect on the other side falls back to the first living
## opponent when the pick is gone. A single-target effect on the actor's own side uses
## the pick when it is a living ally, otherwise the actor (a random ally, for enemies).
## Revives reach KO'd allies, and zombies (whom they KO) when picked or area-wide. Units
## in the air are out of reach (the wiki: they "cannot be targeted", and party buffs cast
## after the jump miss them); a self effect still reaches its own actor.
func resolve_targets(actor: Combatant, effect: SkillEffect, chosen: Combatant) -> Array[Combatant]:
	var targets: Array[Combatant] = []
	var area_wide: bool = effect.target_area == SkillEffect.AREA_ALL or effect.target_area == SkillEffect.AREA_RANDOM
	if effect.type == "REVIVE":
		var fallen: Array[Combatant] = fallen_allies_of(actor)
		var zombies: Array[Combatant] = []
		for ally in targetable(living_allies_of(actor)):
			if ally.recovery_inverter() != null:
				zombies.append(ally)
		if area_wide:
			fallen.append_array(zombies)
			return fallen
		if chosen != null and (fallen.has(chosen) or zombies.has(chosen)):
			targets.append(chosen)
		elif not fallen.is_empty():
			targets.append(fallen[0])
	elif effect.target_type == SkillEffect.TARGET_SELF or effect.target_type == SkillEffect.TARGET_NONE:
		targets.append(actor)
	elif effect.target_type == SkillEffect.TARGET_OPPONENT:
		var opponents: Array[Combatant] = targetable_opponents_of(actor)
		if opponents.is_empty() or area_wide:
			return opponents
		var picked: bool = chosen != null and chosen.is_targetable() and chosen.is_opponent_of(actor)
		targets.append(chosen if picked else opponents[0])
	elif effect.target_type == SkillEffect.TARGET_EVERYONE:
		targets.append_array(targetable(living_party()))
		targets.append_array(targetable(living_enemies()))
	else:
		var allies: Array[Combatant] = targetable(living_allies_of(actor))
		if effect.target_type == SkillEffect.TARGET_ALLY_EXCEPT_SELF:
			allies.erase(actor)
		if allies.is_empty() or area_wide:
			return allies
		if chosen != null and allies.has(chosen):
			targets.append(chosen)
		elif actor.is_enemy():
			targets.append(allies[rng.randi_range(0, allies.size() - 1)])
		elif allies.has(actor):
			targets.append(actor)
		else:
			targets.append(allies[0])
	return targets


## The combatants `effect` of `action` reaches before cover: an ailment's single pick
## stands, even on the attacker's own side (confusion); otherwise resolve_targets.
func effect_targets(action: BattleAction, effect: SkillEffect, chosen: Combatant) -> Array[Combatant]:
	if action.origin == BattleAction.Origin.FORCED and effect.target_area == SkillEffect.AREA_SINGLE and chosen != null and chosen.is_targetable():
		var picked: Array[Combatant] = [chosen]
		return picked
	return resolve_targets(combatant(action.actor_id), effect, chosen)


# === Effect handler API ===

## Puts `hit` on the timeline `offset` frames after its action's hit start (after the
## left swing's start for a dual wielder's left-hand hit).
func schedule_hit(hit: ScheduledHit, offset: int) -> void:
	var swing_start: int = hit.action.left_swing_offset if hit.swing == DualWield.LEFT else 0
	hit.frame = hit.action.hit_start_frame + swing_start + maxi(0, offset)
	hit.action.pending_hits += 1
	hit.action.end_frame = maxi(hit.action.end_frame, hit.frame)
	timeline.schedule_hit(hit)


## Lands a damage hit: dodge, mitigation (the target's cover mitigation included),
## defend, chain, barrier, HP, events, drain, death. Cover itself was settled when the
## action was declared (CoverTracker).
func resolve_damage_hit(hit: ScheduledHit) -> void:
	var actor: Combatant = combatant(hit.actor_id)
	var target: Combatant = combatant(hit.target_id)
	if target == null or not target.is_alive():
		_miss(hit, &"target_down")
		return
	# Landed or not, the target sustained the attack (wiki: evading still counts).
	Counters.note_sustained(self, hit)
	if hit.cancelled:
		_miss(hit, hit.cancel_reason)
		return
	# Before-hit hook point: nullify and reflect (later) join the evasion here.
	if _evades(target, hit):
		_miss(hit, &"dodged")
		return
	hit.landed = true

	var amount: float = hit.amount * _mitigation_multiplier(actor, target, hit.attack_type) \
		* CoverTracker.mitigation_multiplier(target)
	if target.defending:
		amount *= rules.defend_damage_multiplier

	if hit.builds_chain:
		var chain_pct: int = ChainTracker.register_hit(target, actor, frame, hit.elements, rules)
		if ChainTracker.builds_chain(actor, rules):
			hit.chain_count = target.chain_count
			hit.chain_spark = target.chain_spark
			hit.chain_shared_elements = target.chain_shared_elements
		if hit.takes_chain_bonus:
			hit.chain_percent = chain_pct
	hit.final_amount = maxi(0, floori(amount * float(hit.chain_percent) / 100.0))
	hit.absorbed = _absorb_with_barrier(target, hit.final_amount)
	var hp_lost: int = target.take_damage(hit.final_amount - hit.absorbed)

	events.append(BattleEventLog.HIT_LANDED, frame, {
		"action": hit.action.id,
		"actor": hit.actor_id,
		"target": target.id,
		"effect": hit.effect.type,
		"opcode": hit.effect.opcode,
		"hit": hit.hit_index,
		"hits": hit.hit_count,
		"swing": hit.swing,
		"damage_kind": hit.damage_kind,
		"attack_type": hit.attack_type,
		"elements": hit.elements,
		"amount": hit.final_amount,
		"absorbed": hit.absorbed,
		"hp_lost": hp_lost,
		"hp": target.hp,
		"max_hp": target.max_hp,
		"chain": hit.chain_count,
		"chain_pct": hit.chain_percent,
		"spark": hit.chain_spark,
		"element_chain": hit.chain_shared_elements,
	})

	# After-hit hook point: fatal-prevent and on-hit passives (later). Counters roll when
	# the attack ends (_end_action).
	if target.is_alive() and (hit.attack_type == BattleSkill.ATTACK_PHYSICAL or hit.attack_type == BattleSkill.ATTACK_HYBRID):
		for status in target.statuses.duplicate():
			if status.behavior().ends_on_physical_damage():
				remove_status(target, status, &"damaged")
	if hit.drain_pct > 0 and actor != null and actor.is_alive():
		restore(hit, actor, floori(float(hit.final_amount) * float(hit.drain_pct) / 100.0), 0, &"drain")
	_roll_limit_crystal(actor, target, hit)
	_roll_esper_orb(actor, target, hit)
	if not target.is_alive():
		hit.killed = true
		Counters.note_knocked_out(hit)
		_on_defeated(target, hit.actor_id, hit.action.id)


## Restores HP and MP to a living target and reports what it actually gained. `hit` is
## null for regens at the end of a turn. A zombie loses the HP instead (STATUS_DAMAGE).
func restore(hit: ScheduledHit, target: Combatant, hp: int, mp: int, reason: StringName = &"") -> void:
	if target == null or not target.is_alive():
		return
	var zombie: BattleStatus = target.recovery_inverter() if hp > 0 else null
	if zombie != null:
		status_damage(target, zombie, hp, hit.action if hit != null else null, hit.actor_id if hit != null else -1)
		hp = 0
		if mp <= 0 or not target.is_alive():
			return
	var gained_hp: int = target.restore_hp(hp) if hp > 0 else 0
	var gained_mp: int = target.restore_mp(mp) if mp > 0 else 0
	events.append(BattleEventLog.RESTORED, frame, {
		"action": hit.action.id if hit != null else -1,
		"actor": hit.actor_id if hit != null else -1,
		"target": target.id,
		"hp": gained_hp,
		"mp": gained_mp,
		"reason": reason,
		"hp_now": target.hp,
		"mp_now": target.mp,
	})


## Brings a KO'd combatant back with `hp_pct` of its max HP (at least 1). Returns false
## when it was not KO'd.
func revive(target: Combatant, hp_pct: float, action: BattleAction, actor_id: int, reason: StringName = &"") -> bool:
	if target == null or target.is_alive():
		return false
	target.hp = clampi(floori(float(target.max_hp) * hp_pct / 100.0), 1, target.max_hp)
	events.append(BattleEventLog.REVIVED, frame, {
		"action": action.id if action != null else -1,
		"actor": actor_id,
		"target": target.id,
		"hp": target.hp,
		"reason": reason,
	})
	# Passives that cast after a revive (35, 56) do it right after whatever revived it.
	for cast in target.passives.auto_casts:
		if bool(cast["revive"]):
			timeline.schedule_cast(ScheduledCast.for_reaction(Reaction.auto_cast(Reaction.REVIVE, target, cast), frame), null)
	return true


## KOs `target` outright (a self-sacrifice).
func kill(target: Combatant, by_id: int, action: BattleAction) -> void:
	if target == null or not target.is_alive():
		return
	target.hp = 0
	_on_defeated(target, by_id, action.id if action != null else -1)


## An HP cost paid by `actor` (HP sacrifice skills). It can KO the actor.
func spend_hp(actor: Combatant, amount: int, action: BattleAction) -> void:
	if actor == null or not actor.is_alive() or amount <= 0:
		return
	var lost: int = actor.take_damage(amount)
	events.append(BattleEventLog.COST_PAID, frame, {
		"action": action.id,
		"actor": actor.id,
		"mp_cost": 0,
		"lb_cost": 0,
		"hp_cost": lost,
		"orb_cost": 0,
		"mp": actor.mp,
		"lb": actor.lb,
		"hp": actor.hp,
		"orbs": esper_orbs,
	})
	if not actor.is_alive():
		_on_defeated(actor, actor.id, action.id)


## Changes a limit gauge by `amount` (hundredths of a crystal; negative drains).
func change_lb(target: Combatant, amount: int, action: BattleAction, reason: StringName) -> void:
	var gained: int = target.add_lb(amount)
	events.append(BattleEventLog.LB_CHANGED, frame, {
		"action": action.id if action != null else -1,
		"target": target.id,
		"amount": gained,
		"lb": target.lb,
		"max_lb": target.max_lb,
		"reason": reason,
	})


## Changes the party's esper gauge by `amount` orbs (negative drains), clamped to
## 0 .. rules.esper_gauge_max. `actor` is who caused it (-1 for none).
func change_esper_orbs(amount: int, action: BattleAction, actor_id: int, reason: StringName) -> void:
	var gained: int = _add_esper_orbs(amount)
	events.append(BattleEventLog.ESPER_GAUGE_CHANGED, frame, {
		"action": action.id if action != null else -1,
		"actor": actor_id,
		"amount": gained,
		"orbs": esper_orbs,
		"max_orbs": rules.esper_gauge_max,
		"reason": reason,
	})


## Applies `status` from `hit` to `target` unless a roll fails: `chance` for ailments,
## the target's resistance for breaks, stop and ailments. Returns whether it landed.
## An ailment's behaviour decides how long it lasts, whatever the effect's turns say.
func apply_status(hit: ScheduledHit, target: Combatant, status: BattleStatus, chance: int = 100) -> bool:
	status.source_id = hit.actor_id
	status.skill_id = hit.action.skill.id if hit.action.skill != null else ""
	var resist: int = clampi(_status_resistance(target, status), 0, 100)
	if chance < 100 or resist > 0:
		var odds: float = float(chance) * float(100 - resist) / 100.0
		if rng.randf() * 100.0 >= odds:
			_status_resisted(hit, target, status, &"resisted")
			return false
	return _add_status(target, status, hit)


## HP lost to a status rather than a hit (poison, a zombie being healed). It ignores
## mitigation, defending and barriers, and it can KO. `action` is null and `actor_id`
## whoever inflicted the status when no action is behind it.
func status_damage(target: Combatant, status: BattleStatus, amount: int, action: BattleAction, actor_id: int) -> void:
	if target == null or not target.is_alive() or amount <= 0:
		return
	var lost: int = target.take_damage(amount)
	events.append(BattleEventLog.STATUS_DAMAGE, frame, {
		"action": action.id if action != null else -1,
		"actor": actor_id,
		"target": target.id,
		"kind": status.kind,
		"key": status.key,
		"amount": amount,
		"hp_lost": lost,
		"hp": target.hp,
		"max_hp": target.max_hp,
	})
	if not target.is_alive():
		_on_defeated(target, actor_id, action.id if action != null else -1)


## Rolled once per target when a damage effect is cast: why every hit of `actor`'s
## attack on that target misses because of an ailment (blind), or &"".
func ailment_miss_reason(actor: Combatant, attack_type: int) -> StringName:
	for status in actor.statuses:
		var reason: StringName = status.behavior().cast_miss(self, attack_type)
		if reason != &"":
			return reason
	return &""


## Rolled once per target when a damage effect is cast: &"evaded" when the target's
## evasion passives dodge the whole attack, single-target or AoE (physical evasion for
## physical attacks, magic evasion for magic ones; they add up, no cap: the user's rules,
## 2026-10-01). Hybrid attacks are not evaded. Paralysis, stop and charm stop evasion.
func evasion_miss_reason(target: Combatant, attack_type: int) -> StringName:
	var chance: int = 0
	if attack_type == BattleSkill.ATTACK_PHYSICAL:
		chance = target.passives.evade_physical_pct
	elif attack_type == BattleSkill.ATTACK_MAGIC:
		chance = target.passives.evade_magic_pct
	if chance <= 0 or not target.can_evade():
		return &""
	return &"evaded" if chance >= 100 or rng.randi_range(0, 99) < chance else &""


func remove_status(target: Combatant, status: BattleStatus, reason: StringName) -> void:
	target.remove_status(status)
	events.append(BattleEventLog.STATUS_REMOVED, frame, {
		"target": target.id,
		"kind": status.kind,
		"key": status.key,
		"value": status.value,
		"reason": reason,
	})


# === Debugging ===

## One readable line for an event, naming combatants.
func format_event(event: Dictionary) -> String:
	var type: StringName = event.get("type", &"")
	var head: String = "f%-5d %s" % [int(event.get("frame", 0)), type]
	match type:
		BattleEventLog.HIT_LANDED:
			var link: String = ""
			if bool(event.get("spark", false)):
				link += " spark"
			if int(event.get("element_chain", 0)) > 0:
				link += " elemental %d" % int(event["element_chain"])
			var hand: String = " (left hand)" if int(event.get("swing", 0)) == DualWield.LEFT else ""
			return "%s %s%s -> %s %d (chain %d x%.2f%s) hp %d/%d" % [
				head, _name(event.get("actor")), hand, _name(event.get("target")), int(event["amount"]),
				int(event["chain"]), float(event["chain_pct"]) / 100.0, link, int(event["hp"]), int(event["max_hp"]),
			]
		BattleEventLog.ACTION_STARTED:
			var forced: String = " (%s)" % event["forced_by"] if str(event.get("forced_by", "")) != "" else ""
			var dual: String = " (dual wield)" if bool(event.get("dual_wield", false)) else ""
			var multi: String = ""
			if int(event.get("multicast_index", -1)) >= 0:
				multi = " (multicast %s, %d of %d)" % [
					event["multicast_skill_id"], int(event["multicast_index"]) + 1, int(event["multicast_count"]),
				]
			var stacked: String = " (%d stacks)" % int(event["stacks"]) if int(event.get("stacks", -1)) >= 0 else ""
			var reacting: String = ""
			match StringName(event.get("reaction", &"")):
				Reaction.COUNTER:
					reacting = " (counter to #%d)" % int(event["trigger_action"])
				Reaction.BATTLE_START:
					reacting = " (battle start)"
				Reaction.TURN_START:
					reacting = " (turn start)"
				Reaction.REVIVE:
					reacting = " (revive)"
				Reaction.DELAYED:
					reacting = " (delayed)"
			if int(event["kind"]) == BattleCommand.Kind.LAND:
				reacting += " (landing)"
			return "%s #%d %s: %s%s%s%s%s%s" % [
				head, int(event["action"]), _name(event.get("actor")),
				event["skill_name"] if str(event["skill_name"]) != "" else BattleCommand.Kind.keys()[int(event["kind"])],
				forced, dual, multi, stacked, reacting,
			]
		BattleEventLog.COUNTER_QUEUED:
			var answer: String = "attack" if StringName(event["skill_kind"]) == BattleSkill.KIND_ATTACK else "%s:%s" % [event["skill_kind"], event["skill_id"]]
			if StringName(event["skill_kind"]) == BattleSkill.KIND_ATTACK and int(event["modifier"]) > 0:
				answer += " x%.2f" % (float(event["modifier"]) / 100.0)
			return "%s %s will counter #%d by %s with %s (%d%%, from %s)" % [
				head, _name(event.get("actor")), int(event["action"]), _name(event.get("attacker")), answer,
				int(event["chance"]), event["source_skill_id"],
			]
		BattleEventLog.DELAY_QUEUED:
			var keyed: String = ", key %s" % event["key"] if str(event.get("key", "")) != "" else ""
			return "%s %s: delayed %s %s:%s on turn %d at %s (from %s%s)" % [
				head, _name(event.get("actor")), event["kind"], event["skill_kind"], event["skill_id"], int(event["due_turn"]),
				_name(event.get("target")), event["source_skill_id"], keyed,
			]
		BattleEventLog.DELAY_DROPPED:
			return "%s %s: delayed %s %s:%s dropped, %s" % [
				head, _name(event.get("actor")), event["kind"], event["skill_kind"], event["skill_id"], event["reason"],
			]
		BattleEventLog.REACTION_DROPPED:
			return "%s %s: %s %s:%s dropped, %s" % [
				head, _name(event.get("actor")), event["reaction"], event["skill_kind"], event["skill_id"], event["reason"],
			]
		BattleEventLog.SKILL_GRANTED:
			var turns: String = "no time limit" if int(event["turns"]) < 0 else "%d turn(s)" % int(event["turns"])
			var uses: String = "unlimited uses" if int(event["uses"]) < 0 else "%d use(s)" % int(event["uses"])
			return "%s %s gets %s:%s (%s, %s) from %s%s" % [
				head, _name(event.get("target")), event["skill_kind"], event["skill_id"], turns, uses,
				_name(event.get("by")), ", replacing the old grant" if bool(event["replaced"]) else "",
			]
		BattleEventLog.SKILL_GRANT_ENDED:
			return "%s %s loses %s:%s (%s)" % [head, _name(event.get("target")), event["skill_kind"], event["skill_id"], event["reason"]]
		BattleEventLog.MULTICAST_CAST_DROPPED:
			return "%s %s: pick %d of %s (%s:%s) dropped, %s" % [
				head, _name(event.get("actor")), int(event["index"]) + 1, event["multicast_skill_id"],
				event["skill_kind"], event["skill_id"], event["reason"],
			]
		BattleEventLog.COMBATANT_DEFEATED:
			return "%s %s (by %s)" % [head, _name(event.get("target")), _name(event.get("by"))]
		BattleEventLog.COMMAND_REJECTED:
			return "%s %s: %s" % [head, _name(event.get("actor")), event["reason"]]
		BattleEventLog.ITEM_USED:
			return "%s %s: item %s, %d left" % [head, _name(event.get("actor")), event["item_id"], int(event["left"])]
		BattleEventLog.EFFECT_UNSUPPORTED:
			return "%s %s: opcode %d %s (%s)" % [
				head, _name(event.get("actor")), int(event["opcode"]), event["effect"], event["reason"],
			]
		BattleEventLog.RESTORED:
			return "%s %s +%d HP +%d MP %s" % [head, _name(event.get("target")), int(event["hp"]), int(event["mp"]), event["reason"]]
		BattleEventLog.STATUS_DAMAGE:
			return "%s %s -%d HP (%s) hp %d/%d" % [
				head, _name(event.get("target")), int(event["amount"]), event["key"], int(event["hp"]), int(event["max_hp"]),
			]
		BattleEventLog.STATUS_ADDED:
			return "%s %s %s %s %+d (%d turns)" % [
				head, _name(event.get("target")), event["kind"], event["key"], int(event["value"]), int(event["turns"]),
			]
		BattleEventLog.STATUS_REMOVED:
			return "%s %s %s %s (%s)" % [head, _name(event.get("target")), event["kind"], event["key"], event["reason"]]
		BattleEventLog.PHASE_CHANGED:
			return "%s %s (turn %d)" % [head, event["phase"], int(event["turn"])]
		BattleEventLog.COVER_ACTIVATED:
			var types: PackedStringArray = []
			if bool(event["physical"]):
				types.append("physical")
			if bool(event["magic"]):
				types.append("magic")
			var whom: String = "all allies" if event["mode"] == &"aoe" else _name(event.get("protects"))
			return "%s %s covers %s (%s, -%d%%)" % [head, _name(event.get("coverer")), whom, "+".join(types), int(event["mitigation"])]
		BattleEventLog.COVERED:
			return "%s #%d %s -> %s taken by %s" % [
				head, int(event["action"]), _name(event.get("actor")), _name(event.get("target")), _name(event.get("coverer")),
			]
		BattleEventLog.COVER_ENDED:
			return "%s %s (%s)" % [head, _name(event.get("coverer")), event["reason"]]
		BattleEventLog.WAVE_CLEARED:
			return "%s wave %d of %d cleared" % [head, int(event["wave"]), int(event["waves"])]
		BattleEventLog.WAVE_STARTED:
			var names: PackedStringArray = []
			for id in event["enemies"]:
				names.append(_name(id))
			return "%s wave %d of %d: %s" % [head, int(event["wave"]), int(event["waves"]), ", ".join(names)]
		BattleEventLog.ESPER_ORB_DROPPED:
			return "%s %s's hit on %s +%d orb, gauge %d/%d" % [
				head, _name(event.get("actor")), _name(event.get("source")), int(event["amount"]),
				int(event["orbs"]), int(event["max_orbs"]),
			]
		BattleEventLog.ESPER_GAUGE_CHANGED:
			return "%s %+d orbs by %s (%s), gauge %d/%d" % [
				head, int(event["amount"]), _name(event.get("actor")), event["reason"], int(event["orbs"]), int(event["max_orbs"]),
			]
		BattleEventLog.DEBUG_EDITED:
			var field: String = str(event["field"]) if str(event["key"]) == "" else "%s %s" % [event["field"], event["key"]]
			return "%s %s %s %d -> %d" % [head, _name(event.get("target")), field, int(event["old"]), int(event["value"])]
	var rest: Dictionary = event.duplicate()
	for key in ["type", "frame", "seq"]:
		rest.erase(key)
	return "%s %s" % [head, rest]


func dump_events() -> String:
	var lines: PackedStringArray = []
	for event in events.all():
		lines.append(format_event(event))
	return "\n".join(lines)


## The effects of `declared`, and of the skill its links lead to, that the engine
## cannot run: opcodes missing from the schema or without a handler. Random-cast picks
## are not followed, and a multicast command's own effect is the command (Multicast).
## The sandbox flags skills with these.
func unsupported_effects(declared: BattleSkill) -> Array[SkillEffect]:
	var out: Array[SkillEffect] = []
	if declared == null or Multicast.rule_for(declared) != null:
		return out
	var skills: Array[BattleSkill] = [declared]
	var linked: BattleSkill = _links_for(null, declared).skill
	if linked != declared:
		skills.append(linked)
	for skill in skills:
		for effect in skill.effects:
			if LINK_TYPES.has(effect.type):
				continue
			if not effect.is_known() or effects.handler_for(effect.type) == null:
				out.append(effect)
	return out


## Debug tool (the sandbox): sets one value of a combatant directly, outside the
## command flow, and logs DEBUG_EDITED. `field` is one of DEBUG_FIELDS: hp, max_hp,
## mp, max_mp, lb (hundredths of a crystal), stat (key ATK / DEF / MAG / SPR: the
## value before buffs and breaks), element_resist (key FIRE .. DARK: before
## statuses) or ailment (key an ailment with a behaviour: a value other than 0 inflicts
## it as a skill would without a roll, lasting that many turns if it is stop, charm or
## berserk; 0 removes it) or orbs (the party's esper gauge, whichever combatant is
## named). Pools are clamped to their maximum. HP set to 0 KOs the
## combatant as a hit would; HP above 0 on a KO'd one brings it back without a REVIVED
## event.
func debug_edit(target_id: int, field: StringName, value: int, key: String = "") -> StringName:
	var target: Combatant = combatant(target_id)
	if target == null:
		return REJECT_UNKNOWN_TARGET
	var old: int = 0
	match field:
		&"hp":
			old = target.hp
			target.hp = clampi(value, 0, target.max_hp)
		&"max_hp":
			old = target.max_hp
			target.max_hp = maxi(1, value)
			target.hp = mini(target.hp, target.max_hp)
		&"mp":
			old = target.mp
			target.mp = clampi(value, 0, target.max_mp)
		&"max_mp":
			old = target.max_mp
			target.max_mp = maxi(0, value)
			target.mp = mini(target.mp, target.max_mp)
		&"lb":
			old = target.lb
			target.lb = clampi(value, 0, target.max_lb)
		&"stat":
			if not DEBUG_STATS.has(key):
				return REJECT_UNKNOWN_FIELD
			old = int(target.base_stats.get(key, 0))
			target.base_stats[key] = maxi(0, value)
		&"element_resist":
			if not DamageFormula.ELEMENT_NAMES.has(key):
				return REJECT_UNKNOWN_FIELD
			old = int(target.element_resist.get(key, 0))
			target.element_resist[key] = value
		&"ailment":
			if not target.is_alive() or not StatusBehaviorRegistry.shared().ailment_keys().has(key):
				return REJECT_UNKNOWN_FIELD
			var present: BattleStatus = target.find_status(BattleStatus.AILMENT, key)
			old = 1 if present != null else 0
			if value == 0 and present != null:
				remove_status(target, present, &"debug")
			elif value != 0:
				_add_status(target, BattleStatus.make(BattleStatus.AILMENT, key, 0, value), null)
		&"orbs":
			old = esper_orbs
			esper_orbs = clampi(value, 0, maxi(0, rules.esper_gauge_max))
		_:
			return REJECT_UNKNOWN_FIELD
	var now: int = esper_orbs if field == &"orbs" else _debug_value(target, field, key)
	events.append(BattleEventLog.DEBUG_EDITED, frame, {
		"target": target.id,
		"field": field,
		"key": key,
		"old": old,
		"value": now,
	})
	if field == &"hp" and old > 0 and now == 0:
		_on_defeated(target, -1, -1)
	return OK


static func _debug_value(target: Combatant, field: StringName, key: String) -> int:
	match field:
		&"hp":
			return target.hp
		&"max_hp":
			return target.max_hp
		&"mp":
			return target.mp
		&"max_mp":
			return target.max_mp
		&"lb":
			return target.lb
		&"stat":
			return int(target.base_stats.get(key, 0))
		&"ailment":
			return 1 if target.has_ailment(key) else 0
	return int(target.element_resist.get(key, 0))


# === Internals: actions ===

## `declared` is the skill the command named (it pays the cost and carries the name);
## `executed` the one whose effects run. Both are null for DEFEND. `forced_by` names the
## ailment behind a FORCED action.
func _start_action(actor: Combatant, command: BattleCommand, declared: BattleSkill, executed: BattleSkill, origin: int, forced_by: String = "", cast: ScheduledCast = null, reaction: Reaction = null) -> BattleAction:
	var action := BattleAction.new()
	action.id = _next_action_id
	_next_action_id += 1
	action.actor_id = actor.id
	action.command = command
	action.declared_skill = declared
	action.skill = executed
	action.origin = origin
	action.start_frame = frame
	action.cast_order = actor.slot if actor.is_party() else BattleAction.ENEMY_CAST_ORDER
	action.end_frame = frame
	action.hit_start_frame = frame + (rules.move_offset(executed.move_type) if executed != null else 0)
	if cast != null:
		action.multicast_skill_id = cast.command.skill_id
		action.multicast_index = cast.index
		action.multicast_count = cast.command.picks.size()
	action.reaction = reaction
	action.dual_wield = DualWield.applies(self, action, actor)
	# What the combatant chose (or an ailment chose for it) goes into its history before
	# any effect is scheduled, so a stacking ability sees its own stacks. A random cast's
	# pick does not: the action that cast it did. A landing goes in as its jump, however it
	# came: the jump counts as used on the landing turn too, which op 99's drop-time chains
	# need (Spineshatter Dive 1 "then decrease drop time for spineshatter dive 2": the
	# landing takes the next turn, so Dive 2 comes the turn after the landing).
	if command.kind == BattleCommand.Kind.LAND or origin == BattleAction.Origin.COMMAND or origin == BattleAction.Origin.AI \
			or origin == BattleAction.Origin.FORCED:
		action.stacks = actor.history.begin(SkillHistory.key_of(command, declared), SkillHistory.key_of(command, executed),
			SkillHistory.max_stacks_of(executed), total_turns)

	events.append(BattleEventLog.ACTION_STARTED, frame, {
		"action": action.id,
		"actor": actor.id,
		"origin": origin,
		"kind": command.kind,
		"skill_kind": declared.kind if declared != null else &"",
		"skill_id": declared.id if declared != null else "",
		"skill_name": declared.name if declared != null else "",
		"executed_skill_id": executed.id if executed != null else "",
		"target": command.target_id,
		"payload": command.payload,
		"forced_by": forced_by,
		"dual_wield": action.dual_wield,
		"esper_id": actor.esper_id if command.kind == BattleCommand.Kind.EVOKE else 0,
		"multicast_skill_id": action.multicast_skill_id,
		"multicast_index": action.multicast_index,
		"multicast_count": action.multicast_count,
		"stacks": action.stacks,
		"reaction": reaction.kind if reaction != null else &"",
		"trigger_action": reaction.trigger_action_id if reaction != null else -1,
		"source_skill_id": reaction.source_skill_id if reaction != null else "",
	})

	# Enemies do not pay for their skills (the old engine never charged them either).
	if origin == BattleAction.Origin.COMMAND:
		_pay_costs(actor, action)
	if command.kind == BattleCommand.Kind.DEFEND:
		actor.defending = true

	if executed != null:
		var chosen: Combatant = combatant(command.target_id)
		CoverTracker.decide(self, action, actor, executed, chosen)
		for effect in executed.effects:
			_schedule_effect(action, effect, chosen)
		if action.dual_wield:
			# The left hand runs the whole skill again, its frames counted from the cast
			# gap after the right hand's start, under the cover already settled.
			action.swing = DualWield.LEFT
			action.left_swing_offset = rules.cast_gap_frames
			for effect in executed.effects:
				_schedule_effect(action, effect, chosen)

	timeline.schedule_action_end(action, action.end_frame)
	return action


## A basic attack on a random target that `status`'s behaviour picks from (berserk: an
## opponent; confusion: anyone but the bearer). It costs nothing and uses no skill limit.
func _start_forced_attack(fighter: Combatant, status: BattleStatus) -> BattleAction:
	var pool: Array[Combatant] = status.behavior().forced_targets(self, fighter)
	var target_id: int = pool[rng.randi_range(0, pool.size() - 1)].id if not pool.is_empty() else -1
	return _start_action(fighter, BattleCommand.attack(target_id), fighter.attack_skill, fighter.attack_skill,
		BattleAction.Origin.FORCED, status.key)


func _schedule_effect(action: BattleAction, effect: SkillEffect, chosen: Combatant) -> void:
	if effect.type == "RANDOM_CAST":
		_start_random_cast(action, effect)
		return
	if LINK_TYPES.has(effect.type):
		return
	if not effect.is_known():
		_report_unsupported(action, effect, &"opcode_not_in_schema")
		return
	var handler: EffectHandler = effects.handler_for(effect.type)
	if handler == null:
		_report_unsupported(action, effect, &"no_handler")
		return
	# A declared action runs all its effects, even after an earlier one KO'd the caster.
	var actor: Combatant = combatant(action.actor_id)
	if actor == null:
		return
	var targets: Array[Combatant] = []
	if handler.acts_on_actor(effect):
		targets.append(actor)
	else:
		targets = effect_targets(action, effect, chosen)
		if not handler.ignores_cover(effect):
			targets = CoverTracker.redirect(self, action, targets)
	if not targets.is_empty():
		handler.schedule(self, action, effect, targets)


## Opcode 29 casts one of up to five skills, [skill_id, weight %] each, picked with the
## battle RNG. The pick runs as its own action from the same actor on the same frame,
## so its effects use its own elements and attack type.
func _start_random_cast(parent: BattleAction, effect: SkillEffect) -> void:
	var choices: Array = []
	var total: int = 0
	for i in range(1, 6):
		var choice: Variant = effect.params.get("choice_%d" % i)
		if choice is Array and (choice as Array).size() >= 2 and int(choice[1]) > 0:
			choices.append(choice)
			total += int(choice[1])
	if choices.is_empty():
		return
	var roll: int = rng.randi_range(0, total - 1)
	for choice in choices:
		roll -= int(choice[1])
		if roll >= 0:
			continue
		var picked: BattleSkill = _random_cast_skill(str(int(choice[0])))
		if picked == null:
			_report_unsupported(parent, effect, &"random_cast_target_missing")
			return
		var actor: Combatant = combatant(parent.actor_id)
		_start_action(actor, parent.command, picked, _links_for(actor, picked).skill, BattleAction.Origin.CAST)
		return


## A random cast's pick: usually an ability, sometimes a monster skill or magic.
func _random_cast_skill(skill_id: String) -> BattleSkill:
	for kind in [BattleSkill.KIND_ABILITY, BattleSkill.KIND_MONSTER, BattleSkill.KIND_MAGIC]:
		var skill: BattleSkill = catalog.get_skill(kind, skill_id)
		if skill != null:
			return skill
	return null


# === Internals: reactions ===

## Starts a reaction (see REACTIONS), or drops it with REACTION_DROPPED when its unit is
## KO'd or petrified, disabled, in the air, the skill is unknown or no opponent is left.
## A landing brings its unit down instead (_start_landing), and a delayed effect runs
## while its caster is in the air (Death Crimson's op 13 falls with its jump). A counter
## aims at its attacker while that one is alive, a delayed effect at the target its cast
## picked; anything else at the unit itself, so a single-target ally effect lands on it
## and an opponent effect takes the first opponent on the field (resolve_targets). It
## costs nothing and spends no limit.
func _start_reaction(reaction: Reaction) -> BattleAction:
	var actor: Combatant = combatant(reaction.actor_id)
	if reaction.kind == Reaction.LANDING and actor != null and actor.is_alive() and actor.is_away():
		return _start_landing(actor, BattleAction.Origin.REACTION, reaction)
	var reason: StringName = OK
	var declared: BattleSkill = null
	if actor == null or not actor.is_standing():
		reason = &"caster_down"
	elif actor.is_away() and reaction.kind != Reaction.DELAYED:
		reason = &"away"
	elif actor.control() == StatusBehavior.CONTROL_DISABLED:
		reason = &"cannot_act"
	elif living_opponents_of(actor).is_empty():
		reason = &"no_opponents"
	else:
		declared = reaction.skill if reaction.skill != null else _reaction_skill(actor, reaction)
		if declared == null:
			reason = &"unknown_skill"
	if reason != OK:
		_drop_reaction(reaction, reason)
		return null
	var aimed: Combatant = combatant(reaction.target_id)
	var target_id: int = aimed.id if aimed != null and aimed.is_alive() else actor.id
	var command: BattleCommand = BattleCommand.attack(target_id) if reaction.skill_kind == BattleSkill.KIND_ATTACK \
		else BattleCommand.skill(reaction.skill_kind, reaction.skill_id, target_id)
	var executed: BattleSkill = declared if declared.kind == BattleSkill.KIND_ATTACK else _links_for(actor, declared).skill
	return _start_action(actor, command, declared, executed, BattleAction.Origin.REACTION, "", null, reaction)


## The skill a reaction runs: the unit's attack for a counter with the normal attack (at
## the counter's modifier when it has one and the attack is the plain one; an op 100
## replacement runs as it is), otherwise the skill it names.
func _reaction_skill(actor: Combatant, reaction: Reaction) -> BattleSkill:
	if reaction.skill_kind != BattleSkill.KIND_ATTACK:
		return catalog.get_skill(reaction.skill_kind, reaction.skill_id)
	if actor.attack_skill == null or reaction.modifier <= 0 or actor.attack_skill.kind != BattleSkill.KIND_ATTACK:
		return actor.attack_skill
	return actor.attack_skill.with_damage_modifier(reaction.modifier)


func _drop_reaction(reaction: Reaction, reason: StringName) -> void:
	events.append(BattleEventLog.REACTION_DROPPED, frame, {
		"actor": reaction.actor_id,
		"reaction": reaction.kind,
		"skill_kind": reaction.skill_kind,
		"skill_id": reaction.skill_id,
		"source_skill_id": reaction.source_skill_id,
		"reason": reason,
	})


## Drops every queued reaction of `actor_id`, or every one when it is -1.
func _drop_queued_reactions(actor_id: int, reason: StringName) -> void:
	for reaction in _reactions.duplicate():
		if actor_id < 0 or reaction.actor_id == actor_id:
			_reactions.erase(reaction)
			_drop_reaction(reaction, reason)


## Drops the pending delayed effects of `actor_id`, or every one when it is -1.
func _drop_delayed(actor_id: int, reason: StringName) -> void:
	for entry in _delayed.duplicate():
		if actor_id < 0 or entry.actor_id == actor_id:
			_drop_delayed_entry(entry, reason)


func _drop_delayed_entry(entry: DelayedCast, reason: StringName) -> void:
	_delayed.erase(entry)
	events.append(BattleEventLog.DELAY_DROPPED, frame, {
		"actor": entry.actor_id,
		"kind": entry.kind,
		"skill_kind": entry.skill.kind,
		"skill_id": entry.skill.id,
		"source_skill_id": entry.source_skill_id,
		"reason": reason,
	})


## Whether `fighter` is in the air with a jump due to land on its own: a 52 jump from its
## due turn, or any enemy jump (no player lands an enemy's 134).
func _landing_due(fighter: Combatant) -> bool:
	var away: BattleStatus = fighter.away_status() if fighter != null and fighter.is_alive() else null
	if away == null or total_turns < away.value:
		return false
	return fighter.is_enemy() or not bool(away.params.get("manual", false))


## Sorts _queue_opening_casts' [action id, rank, position, reaction] items.
static func _due_before(a: Array, b: Array) -> bool:
	for i in range(3):
		if int(a[i]) != int(b[i]):
			return int(a[i]) < int(b[i])
	return false


## Brings `actor` down from its jump and starts the landing: the unit's action for the
## turn (a party member is marked acted; the wiki: "unavailable for further actions on
## that turn"), at the target picked when it jumped, or the first opponent on the field
## when that one is gone (resolve_targets; the wiki). With no opponent on the field it
## comes back without attacking. `reaction` is the landing on its own (origin REACTION),
## null for the player's LAND command (origin COMMAND). The action's command is LAND and
## names the jump, which the event shows; its skill is the landing (delayed_part).
func _start_landing(actor: Combatant, origin: int, reaction: Reaction) -> BattleAction:
	var away: BattleStatus = actor.away_status()
	var landing: Reaction = reaction if reaction != null else Reaction.landing(actor, away)
	remove_status(actor, away, &"landed")
	if actor.is_party():
		actor.acted = true
	if landing.skill == null or targetable_opponents_of(actor).is_empty():
		if reaction != null:
			_drop_reaction(reaction, &"unknown_skill" if landing.skill == null else &"no_opponents")
		return null
	var declared: BattleSkill = catalog.get_skill(landing.skill_kind, landing.skill_id)
	var command := BattleCommand.land()
	command.skill_kind = landing.skill_kind
	command.skill_id = landing.skill_id
	command.target_id = landing.target_id
	return _start_action(actor, command, declared if declared != null else landing.skill, landing.skill, origin, "", null, reaction)


## The casts a new turn adds after the counters already queued: battle-start casts on
## the first turn of each wave, then turn-start casts whose chance roll succeeds (no
## roll at 100%). Standing combatants in slot order, each one's passives in order. Then
## the delayed effects due this turn and the party's jumps landing on their own, in the
## order they were cast (a delayed effect before a landing of the same action, as op 13
## comes before the jump in the data).
func _queue_opening_casts() -> void:
	var everyone: Array[Combatant] = living_party()
	everyone.append_array(living_enemies())
	if turn == 1:
		for fighter in everyone:
			if fighter.is_standing():
				for cast in fighter.passives.auto_casts:
					if bool(cast["battle_start"]):
						_reactions.append(Reaction.auto_cast(Reaction.BATTLE_START, fighter, cast))
	for fighter in everyone:
		if not fighter.is_standing():
			continue
		for cast in fighter.passives.auto_casts:
			if not bool(cast["turn_start"]):
				continue
			var chance: int = int(cast["chance"])
			if chance >= 100 or (chance > 0 and rng.randi_range(0, 99) < chance):
				_reactions.append(Reaction.auto_cast(Reaction.TURN_START, fighter, cast))
	# [action id, 0 for a delayed effect or 1 for a landing, queue position, reaction]
	var due: Array = []
	for entry in _delayed.duplicate():
		if entry.due_turn <= total_turns:
			_delayed.erase(entry)
			due.append([entry.source_action_id, 0, due.size(), Reaction.delayed(entry)])
	for member in living_party():
		if _landing_due(member):
			var away: BattleStatus = member.away_status()
			due.append([int(away.params.get("action", -1)), 1, due.size(), Reaction.landing(member, away)])
	due.sort_custom(_due_before)
	for item in due:
		_reactions.append(item[3])


## The opening phase: starts the next queued reaction once the timeline is empty and the
## gap after the previous one has passed; the player phase begins when none is left.
func _run_opening() -> void:
	while timeline.is_empty():
		if _reactions.is_empty():
			_set_phase(Phase.PLAYER)
			return
		if frame < _next_reaction_frame:
			return
		var action: BattleAction = _start_reaction(_reactions.pop_front())
		if action != null:
			_next_reaction_frame = action.end_frame + rules.reaction_gap_frames


# === Internals: multicast ===

## The multicast rule of `declared` for `unit` when `command` is a SKILL command naming a
## multicast command, otherwise null. A command one of the unit's passives gives picks
## what the passive says (CombatantPassives.multicast_picks).
func _multicast_rule_of(unit: Combatant, command: BattleCommand, declared: BattleSkill) -> Multicast.Rule:
	if command == null or command.kind != BattleCommand.Kind.SKILL or declared == null:
		return null
	return Multicast.rule_for(declared, unit.passives.multicast_picks.get(declared.id, {}))


## See multicast_pick_problem.
func _pick_problem(unit: Combatant, rule: Multicast.Rule, picks_before: Array[BattleCommand], pick: BattleCommand) -> StringName:
	if pick == null or pick.kind != BattleCommand.Kind.SKILL:
		return REJECT_NOT_MULTICASTABLE
	var declared: BattleSkill = _skill_for(unit, pick)
	if declared == null:
		return REJECT_UNKNOWN_SKILL
	if not Multicast.allows(rule, declared):
		return REJECT_NOT_MULTICASTABLE
	if unit.skill_blocked(declared):
		return REJECT_SILENCED
	var links: SkillLinks = _links_for(unit, declared)
	# A granted skill with a use count is use-limited too: picked once (U3, the default).
	var grant: SkillGrant = _grant_for(unit, pick)
	if links.is_limited() or (grant != null and grant.uses_left != SkillGrant.UNLIMITED):
		for earlier in picks_before:
			if earlier.skill_kind == pick.skill_kind and earlier.skill_id == pick.skill_id:
				return REJECT_SKILL_NOT_READY if links.cooldown_turns >= 0 else REJECT_NO_USES_LEFT
		var reason: StringName = _skill_limit_problem(unit, pick, links)
		if reason != OK:
			return reason
	var mp: int = mp_cost_of(unit, declared)
	var lb: int = declared.lb_cost
	var orbs: int = declared.orb_cost
	for earlier in picks_before:
		var spent: BattleSkill = _skill_for(unit, earlier)
		if spent != null:
			mp += mp_cost_of(unit, spent)
			lb += spent.lb_cost
			orbs += spent.orb_cost
	if unit.mp < mp:
		return REJECT_NOT_ENOUGH_MP
	if unit.lb < lb:
		return REJECT_LIMIT_NOT_FULL
	if esper_orbs < orbs:
		return REJECT_NOT_ENOUGH_ORBS
	return OK


## Casts pick `cast.index` of a multicast command, then puts the next pick on the timeline
## rules.cast_gap_frames after this one's start. The pick is an ordinary action of the
## command (origin COMMAND): it pays its costs, spends its cooldown or use and computes
## its damage now. A pick without its own target takes the command's. A pick whose caster
## is down, or that has no opponent left to face, is dropped with the ones after it.
func _cast_pick(cast: ScheduledCast) -> void:
	var actor: Combatant = combatant(cast.actor_id)
	if actor == null or not actor.is_standing():
		_drop_picks(cast, &"caster_down")
		return
	# An earlier pick was a jump: the unit has left the field.
	if actor.is_away():
		_drop_picks(cast, &"caster_away")
		return
	if living_opponents_of(actor).is_empty():
		_drop_picks(cast, &"no_opponents")
		return
	var pick: BattleCommand = cast.command.picks[cast.index].duplicate_command()
	if pick.target_id < 0:
		pick.target_id = cast.command.target_id
	var declared: BattleSkill = _skill_for(actor, pick)
	if declared == null:
		_drop_picks(cast, &"unknown_skill")
		return
	var links: SkillLinks = _links_for(actor, declared)
	_spend_limits(actor, pick, links)
	var action: BattleAction = _start_action(actor, pick, declared, links.skill, BattleAction.Origin.COMMAND, "", cast)
	if cast.index + 1 < cast.command.picks.size():
		timeline.schedule_cast(ScheduledCast.pick(actor.id, cast.command, cast.index + 1, frame + rules.cast_gap_frames), action)


func _drop_picks(cast: ScheduledCast, reason: StringName) -> void:
	for i in range(cast.index, cast.command.picks.size()):
		var pick: BattleCommand = cast.command.picks[i]
		events.append(BattleEventLog.MULTICAST_CAST_DROPPED, frame, {
			"actor": cast.actor_id,
			"skill_id": pick.skill_id,
			"skill_kind": pick.skill_kind,
			"multicast_skill_id": cast.command.skill_id,
			"index": i,
			"reason": reason,
		})


func _report_unsupported(action: BattleAction, effect: SkillEffect, reason: StringName) -> void:
	events.append(BattleEventLog.EFFECT_UNSUPPORTED, frame, {
		"action": action.id,
		"actor": action.actor_id,
		"effect_index": effect.index,
		"opcode": effect.opcode,
		"effect": effect.type,
		"reason": reason,
	})


func _pay_costs(actor: Combatant, action: BattleAction) -> void:
	var cost_skill: BattleSkill = action.declared_skill
	var mp_cost: int = 0
	var lb_cost: int = 0
	var orb_cost: int = 0
	if action.command.kind == BattleCommand.Kind.SKILL and cost_skill != null:
		mp_cost = mini(mp_cost_of(actor, cost_skill), actor.mp)
		actor.mp -= mp_cost
		lb_cost = mini(cost_skill.lb_cost, actor.lb)
		actor.lb -= lb_cost
		orb_cost = mini(cost_skill.orb_cost, esper_orbs)
		esper_orbs -= orb_cost
	elif action.command.kind == BattleCommand.Kind.LIMIT_BURST and cost_skill != null:
		lb_cost = mini(_lb_needed(actor, cost_skill), actor.lb)
		actor.lb -= lb_cost
	elif action.command.kind == BattleCommand.Kind.EVOKE:
		orb_cost = esper_orbs
		esper_orbs = 0
	elif action.command.kind == BattleCommand.Kind.ITEM:
		var item_id: String = action.command.skill_id
		item_stock[item_id] = maxi(0, int(item_stock.get(item_id, 0)) - 1)
		events.append(BattleEventLog.ITEM_USED, frame, {
			"action": action.id,
			"actor": actor.id,
			"item_id": item_id,
			"left": int(item_stock[item_id]),
		})
	if mp_cost > 0 or lb_cost > 0 or orb_cost > 0:
		events.append(BattleEventLog.COST_PAID, frame, {
			"action": action.id,
			"actor": actor.id,
			"mp_cost": mp_cost,
			"lb_cost": lb_cost,
			"hp_cost": 0,
			"orb_cost": orb_cost,
			"mp": actor.mp,
			"lb": actor.lb,
			"hp": actor.hp,
			"orbs": esper_orbs,
		})


func _resolve_hit(hit: ScheduledHit) -> void:
	hit.action.pending_hits -= 1
	# A unit that left the field after the hit was scheduled is out of reach; its own
	# effects still reach it (the jump that sent it away).
	var target: Combatant = combatant(hit.target_id)
	if target != null and target.is_away() and hit.target_id != hit.actor_id:
		_miss(hit, &"away")
		return
	hit.handler.resolve(self, hit)


func _miss(hit: ScheduledHit, reason: StringName) -> void:
	events.append(BattleEventLog.HIT_MISSED, frame, {
		"action": hit.action.id,
		"actor": hit.actor_id,
		"target": hit.target_id,
		"effect": hit.effect.type,
		"swing": hit.swing,
		"reason": reason,
	})


func _end_action(action: BattleAction) -> void:
	action.state = BattleAction.State.ENDED
	events.append(BattleEventLog.ACTION_ENDED, frame, {
		"action": action.id,
		"actor": action.actor_id,
	})
	# End hook point: whoever sustained the attack rolls to counter it.
	Counters.on_attack_ended(self, action)


# === Internals: hit resolution ===

## A dodge status evades physical hits, one charge per hit, unless an ailment
## (paralysis, stop, charm) keeps the target from evading.
func _evades(target: Combatant, hit: ScheduledHit) -> bool:
	if hit.attack_type != BattleSkill.ATTACK_PHYSICAL or not target.can_evade():
		return false
	var dodge: BattleStatus = target.find_status(BattleStatus.DODGE)
	if dodge == null or dodge.value <= 0:
		return false
	dodge.value -= 1
	if dodge.value <= 0:
		remove_status(target, dodge, &"used_up")
	return true


## What survives mitigation: general x physical or magic x the target's mitigation
## against the attacker's races (averaged) x the target's innate physical or magic
## resistance. Hybrid attacks take the mean of the physical and magic values.
func _mitigation_multiplier(actor: Combatant, target: Combatant, attack_type: int) -> float:
	var general: int = target.status_value(BattleStatus.MITIGATION, "all")
	var typed: float = 0.0
	var race_pct: float = 0.0
	var innate: float = 0.0
	var sides: PackedStringArray = _mitigation_sides(attack_type)
	for side in sides:
		typed += float(target.status_value(BattleStatus.MITIGATION, side))
		innate += float(target.damage_resistance(side))
		if actor != null and not actor.races.is_empty():
			var side_total: int = 0
			for race in actor.races:
				side_total += target.status_value(BattleStatus.RACE_MITIGATION, "%s:%d" % [side, race])
			race_pct += float(side_total) / float(actor.races.size())
	if not sides.is_empty():
		typed /= float(sides.size())
		race_pct /= float(sides.size())
		innate /= float(sides.size())
	return maxf(0.0, (1.0 - general / 100.0) * (1.0 - typed / 100.0) * (1.0 - race_pct / 100.0)
		* (1.0 - innate / 100.0))


static func _mitigation_sides(attack_type: int) -> PackedStringArray:
	match attack_type:
		BattleSkill.ATTACK_PHYSICAL:
			return PackedStringArray(["physical"])
		BattleSkill.ATTACK_MAGIC:
			return PackedStringArray(["magic"])
		BattleSkill.ATTACK_HYBRID:
			return PackedStringArray(["physical", "magic"])
	return PackedStringArray()


## The part of `amount` a barrier takes; the barrier breaks when it runs out.
func _absorb_with_barrier(target: Combatant, amount: int) -> int:
	var barrier: BattleStatus = target.find_status(BattleStatus.SHIELD)
	if barrier == null or amount <= 0:
		return 0
	var absorbed: int = mini(amount, barrier.value)
	barrier.value -= absorbed
	if barrier.value <= 0:
		remove_status(target, barrier, &"broken")
	return absorbed


## KO: a triggered cover ends, every status goes (FFBE clears buffs and debuffs on KO),
## then an auto-revive, if there was one, brings the combatant back, unable to cover
## again this turn. A zombie does not come back.
func _on_defeated(target: Combatant, by_id: int, action_id: int) -> void:
	events.append(BattleEventLog.COMBATANT_DEFEATED, frame, {
		"target": target.id,
		"by": by_id,
		"action": action_id,
	})
	CoverTracker.on_defeated(self, target)
	var reraise: BattleStatus = target.find_status(BattleStatus.AUTO_REVIVE) if target.recovery_inverter() == null else null
	for status in target.statuses.duplicate():
		remove_status(target, status, &"ko")
	# Dying ends grants and clears the stack (wiki: even with a reraise) and the rest of
	# the history.
	for value in target.grants.values():
		_end_grant(target, value, &"ko")
	target.history.clear()
	target.defending = false
	# A counter dies with its unit, even when a reraise brings the unit back, and so do
	# its delayed effects (the user's rule, 2026-10-06).
	_drop_queued_reactions(target.id, &"caster_down")
	_drop_delayed(target.id, &"caster_down")
	if reraise != null:
		revive(target, float(reraise.value), null, target.id, &"auto_revive")


func _status_resistance(target: Combatant, status: BattleStatus) -> int:
	if status.kind == BattleStatus.STAT and status.value < 0:
		return target.debuff_resistance(status.key)
	if status.kind == BattleStatus.AILMENT:
		if status.key in ["STOP", "CHARM", "BERSERK"]:
			return target.debuff_resistance(status.key)
		return target.ailment_resistance(status.key)
	return 0


## Adds a status that got past its rolls: its behaviour sets the duration and any value
## from the rules, then acts on it landing (a petrified enemy is KO'd). An auto-revive
## put on a zombie KOs it. `hit` is null for a debug edit.
func _add_status(target: Combatant, status: BattleStatus, hit: ScheduledHit) -> bool:
	var behavior: StatusBehavior = status.behavior()
	status.turns_left = behavior.turns_on(self, target, status.turns_left)
	behavior.prepare(self, target, status)
	if not target.add_status(status, rules.keep_stronger_status and status.kind != BattleStatus.COVER):
		_status_resisted(hit, target, status, &"weaker")
		return false
	status.added_order = _next_status_order
	_next_status_order += 1
	events.append(BattleEventLog.STATUS_ADDED, frame, {
		"action": hit.action.id if hit != null else -1,
		"actor": hit.actor_id if hit != null else -1,
		"target": target.id,
		"kind": status.kind,
		"key": status.key,
		"value": status.value,
		"turns": status.turns_left,
	})
	behavior.on_added(self, target, status, hit)
	if status.kind == BattleStatus.AUTO_REVIVE and target.recovery_inverter() != null:
		kill(target, status.source_id, hit.action if hit != null else null)
	return true


func _status_resisted(hit: ScheduledHit, target: Combatant, status: BattleStatus, reason: StringName) -> void:
	events.append(BattleEventLog.STATUS_RESISTED, frame, {
		"action": hit.action.id if hit != null else -1,
		"actor": hit.actor_id if hit != null else -1,
		"target": target.id,
		"kind": status.kind,
		"key": status.key,
		"reason": reason,
	})


## A damaging party hit on an enemy may drop a limit crystal for a random living party
## member (old engine rule). LB fill rate statuses and passives raise what it gives.
func _roll_limit_crystal(actor: Combatant, target: Combatant, hit: ScheduledHit) -> void:
	if actor == null or not actor.is_party() or not target.is_enemy() or hit.final_amount <= 0:
		return
	if rules.lb_crystal_drop_chance <= 0.0 or rng.randf() >= rules.lb_crystal_drop_chance:
		return
	var receivers: Array[Combatant] = living_party()
	if receivers.is_empty():
		return
	var receiver: Combatant = receivers[rng.randi_range(0, receivers.size() - 1)]
	var gained: int = receiver.add_lb(roundi(float(rules.lb_crystal_amount) * (1.0 + float(receiver.lb_fill_rate()) / 100.0)))
	events.append(BattleEventLog.LB_CRYSTAL_DROPPED, frame, {
		"source": target.id,
		"target": receiver.id,
		"amount": gained,
		"lb": receiver.lb,
		"max_lb": receiver.max_lb,
	})


## A damaging party hit on an enemy may drop an esper orb into the party's gauge
## (rules.esper_orb_drop_chance), the same hits that may drop limit crystals.
func _roll_esper_orb(actor: Combatant, target: Combatant, hit: ScheduledHit) -> void:
	if actor == null or not actor.is_party() or not target.is_enemy() or hit.final_amount <= 0:
		return
	if rules.esper_orb_drop_chance <= 0.0 or rng.randf() >= rules.esper_orb_drop_chance:
		return
	var gained: int = _add_esper_orbs(1)
	events.append(BattleEventLog.ESPER_ORB_DROPPED, frame, {
		"source": target.id,
		"actor": actor.id,
		"amount": gained,
		"orbs": esper_orbs,
		"max_orbs": rules.esper_gauge_max,
	})


## Adds to the esper gauge, clamped to 0 .. rules.esper_gauge_max. Returns the change.
func _add_esper_orbs(amount: int) -> int:
	var before: int = esper_orbs
	esper_orbs = clampi(esper_orbs + amount, 0, maxi(0, rules.esper_gauge_max))
	return esper_orbs - before


# === Internals: commands and skills ===

func _party_member_problem(unit_id: int) -> StringName:
	var unit: Combatant = combatant(unit_id)
	if unit == null:
		return REJECT_UNKNOWN_UNIT
	if not unit.is_party():
		return REJECT_NOT_PARTY_MEMBER
	if not unit.is_alive():
		return REJECT_UNIT_DOWN
	return OK


func _reject(unit_id: int, reason: StringName, command: BattleCommand) -> StringName:
	events.append(BattleEventLog.COMMAND_REJECTED, frame, {
		"actor": unit_id,
		"reason": reason,
		"command": command.describe() if command != null else "",
	})
	return reason


## The command `unit` runs: `command` if given; LAND for a jump ready to land (whatever
## was queued); the queued command; a basic attack.
func _command_for(unit: Combatant, command: BattleCommand) -> BattleCommand:
	if command != null:
		return command
	if landing_ready(unit):
		return BattleCommand.land()
	if unit.queued_command != null:
		return unit.queued_command
	return BattleCommand.attack()


## The skill a command names; null for DEFEND and for unknown ids.
func _skill_for(unit: Combatant, command: BattleCommand) -> BattleSkill:
	match command.kind:
		BattleCommand.Kind.DEFEND:
			return null
		BattleCommand.Kind.ATTACK:
			return unit.attack_skill
		BattleCommand.Kind.ITEM:
			return catalog.get_item(command.skill_id)
		BattleCommand.Kind.LIMIT_BURST:
			var limit_burst_id: String = command.skill_id if command.skill_id != "" else unit.limit_burst_id
			return catalog.get_limit_burst(limit_burst_id, unit.limit_burst_level)
		BattleCommand.Kind.EVOKE:
			# Always the unit's own esper, whatever the command names.
			return catalog.get_skill(BattleSkill.KIND_ESPER, unit.esper_skill_id)
	return catalog.get_skill(command.skill_kind, command.skill_id)


## Follows the links in `declared` for `unit`: a cooldown wrapper (130) or use-limited
## wrapper (157) runs the ability it wraps, 1014 limits uses, and opcode 99 runs its
## `true` skill when `unit` used one of its condition skills last turn, its `false` skill
## otherwise (always `false` without a unit). Deterministic; random casts are picked when
## the action starts.
func _links_for(unit: Combatant, declared: BattleSkill) -> SkillLinks:
	var links := SkillLinks.new()
	var current: BattleSkill = declared
	for _depth in range(MAX_LINK_DEPTH):
		var next: BattleSkill = null
		for effect in current.effects:
			match effect.type:
				"COOLDOWN_SKILL":
					var cooldown: Variant = effect.params.get("cooldown", [])
					var pair: Array = cooldown if cooldown is Array else [cooldown, cooldown]
					links.cooldown_turns = maxi(0, int(pair[0])) if pair.size() > 0 else 0
					links.cooldown_initial = int(pair[1]) if pair.size() > 1 else links.cooldown_turns
					next = _linked_ability(effect.params.get("skill_id"))
				"LIMITED_USE_SKILL":
					links.uses = _uses(effect)
					next = _linked_ability(effect.params.get("skill_id"))
				"USES_PER_BATTLE":
					links.uses = _uses(effect)
				"REPLACEMENT":
					var branch: String = "true" if _used_condition_last_turn(unit, effect) else "false"
					next = _linked_skill(effect.params.get(branch + "_type", 2), effect.params.get(branch))
		if next == null or next == current:
			break
		current = next
	links.skill = current
	return links


## "(N uses per battle)"; a zero or missing count leaves the skill unlimited.
static func _uses(effect: SkillEffect) -> int:
	var uses: int = int(effect.param_float("uses"))
	return uses if uses > 0 else -1


func _linked_ability(skill_id: Variant) -> BattleSkill:
	return _linked_skill(2, skill_id)


## The skill an opcode names with a skill type (op 99, 100: 1 magic, anything else an
## ability) and an id; null for a missing or unknown id.
func _linked_skill(skill_type: Variant, skill_id: Variant) -> BattleSkill:
	if typeof(skill_id) not in [TYPE_INT, TYPE_FLOAT] or int(skill_id) <= 0:
		return null
	return catalog.get_skill(skill_kind_of_type(skill_type), str(int(skill_id)))


## BattleSkill kind of an opcode's skill type: 1 magic, anything else an ability.
static func skill_kind_of_type(skill_type: Variant) -> StringName:
	if typeof(skill_type) in [TYPE_INT, TYPE_FLOAT] and int(skill_type) == 1:
		return BattleSkill.KIND_MAGIC
	return BattleSkill.KIND_ABILITY


## Op 99's condition (the user's rule, 2026-10-05): `unit` used one of the effect's
## condition skills, each read with its type (2 ability, 1 magic), on the previous turn.
## What it did earlier this turn does not count.
func _used_condition_last_turn(unit: Combatant, effect: SkillEffect) -> bool:
	if unit == null:
		return false
	var raw_ids: Variant = effect.params.get("condition", [])
	var raw_types: Variant = effect.params.get("condition_types", [])
	var ids: Array = raw_ids if raw_ids is Array else [raw_ids]
	var types: Array = raw_types if raw_types is Array else [raw_types]
	for i in range(ids.size()):
		if typeof(ids[i]) not in [TYPE_INT, TYPE_FLOAT] or int(ids[i]) <= 0:
			continue
		var skill_type: Variant = types[i] if i < types.size() else 2
		var key: String = SkillHistory.skill_key(skill_kind_of_type(skill_type), str(int(ids[i])))
		if unit.history.used_on(key, total_turns - 1):
			return true
	return false


## Per-skill state, created the first time the skill is looked at. A cooldown of
## [turns, initial] is first ready on turn 1 + turns - initial (initial = turns: ready at
## once; 0: after the full wait), and after a use on turn T it is ready again on turn
## T + turns + 1, which is "one use every turns + 1 turns".
func _skill_state(unit: Combatant, skill_id: String, links: SkillLinks) -> Dictionary:
	if not unit.skill_state.has(skill_id):
		var first_ready: int = 1
		if links.cooldown_turns >= 0:
			first_ready = 1 + maxi(0, links.cooldown_turns - links.cooldown_initial)
		unit.skill_state[skill_id] = {"uses_left": links.uses, "ready_turn": first_ready}
	return unit.skill_state[skill_id]


func _skill_limit_problem(unit: Combatant, command: BattleCommand, links: SkillLinks) -> StringName:
	if not links.is_limited() or command.kind != BattleCommand.Kind.SKILL:
		return OK
	var state: Dictionary = _skill_state(unit, command.skill_id, links)
	if int(state["uses_left"]) == 0:
		return REJECT_NO_USES_LEFT
	if turn < int(state["ready_turn"]):
		return REJECT_SKILL_NOT_READY
	return OK


func _consume_skill_use(unit: Combatant, command: BattleCommand, links: SkillLinks) -> void:
	if command.kind != BattleCommand.Kind.SKILL:
		return
	var state: Dictionary = _skill_state(unit, command.skill_id, links)
	if int(state["uses_left"]) > 0:
		state["uses_left"] = int(state["uses_left"]) - 1
	if links.cooldown_turns > 0:
		state["ready_turn"] = turn + links.cooldown_turns + 1


## What a SKILL command spends as its action starts: its cooldown or use (130, 157,
## 1014) and a use of the grant it is cast through (op 100), which ends at its last use.
func _spend_limits(unit: Combatant, command: BattleCommand, links: SkillLinks) -> void:
	if links.is_limited():
		_consume_skill_use(unit, command, links)
	var grant: SkillGrant = _grant_for(unit, command)
	if grant != null and grant.uses_left > 0:
		grant.uses_left -= 1
		if grant.uses_left == 0:
			_end_grant(unit, grant, &"used_up")


## The grant `command` is cast through, or null (not a SKILL command, or not granted).
func _grant_for(unit: Combatant, command: BattleCommand) -> SkillGrant:
	if unit == null or command == null or command.kind != BattleCommand.Kind.SKILL:
		return null
	return unit.grants.get(SkillHistory.skill_key(command.skill_kind, command.skill_id), null)


func _end_grant(unit: Combatant, grant: SkillGrant, reason: StringName) -> void:
	unit.grants.erase(grant.key())
	events.append(BattleEventLog.SKILL_GRANT_ENDED, frame, {
		"target": unit.id,
		"skill_kind": grant.skill_kind,
		"skill_id": grant.skill_id,
		"reason": reason,
	})


## Every grant with a turn count loses a turn as the enemy phase begins, and ends at 0.
## turn_count counts the cast turn: 2 from the unit's own action lasts through its next
## turn; 1 from a counter in the enemy phase, or from a battle-start cast, lasts through
## the next player phase.
func _count_down_grants() -> void:
	var everyone: Array[Combatant] = party_members()
	everyone.append_array(enemies)
	for fighter in everyone:
		for value in fighter.grants.values():
			var grant: SkillGrant = value
			if grant.turns_left == SkillGrant.UNLIMITED:
				continue
			grant.turns_left -= 1
			if grant.turns_left <= 0:
				_end_grant(fighter, grant, &"expired")


func _cost_problem(unit: Combatant, command: BattleCommand, skill: BattleSkill) -> StringName:
	if command.kind == BattleCommand.Kind.LIMIT_BURST:
		var needed: int = _lb_needed(unit, skill)
		return OK if needed > 0 and unit.lb >= needed else REJECT_LIMIT_NOT_FULL
	if command.kind == BattleCommand.Kind.EVOKE:
		return OK if esper_gauge_full() else REJECT_ESPER_GAUGE_NOT_FULL
	if command.kind == BattleCommand.Kind.SKILL and unit.mp < mp_cost_of(unit, skill):
		return REJECT_NOT_ENOUGH_MP
	if command.kind == BattleCommand.Kind.SKILL and unit.lb < skill.lb_cost:
		return REJECT_LIMIT_NOT_FULL
	if command.kind == BattleCommand.Kind.SKILL and esper_orbs < skill.orb_cost:
		return REJECT_NOT_ENOUGH_ORBS
	if command.kind == BattleCommand.Kind.ITEM and items_available(command.skill_id, unit.id) <= 0:
		return REJECT_NO_ITEMS_LEFT
	return OK


## Whether `member` holds one `item_id` for itself: it has the item queued and has not
## acted yet this turn.
static func _holds_item(member: Combatant, item_id: String) -> bool:
	var queued: BattleCommand = member.queued_command
	return not member.acted and queued != null and queued.kind == BattleCommand.Kind.ITEM and queued.skill_id == item_id


## The MP `unit` pays for `skill`: abilities cost less with MP reduction passives (not
## magic: the user's rule, 2026-10-01), at most 100% off, rounded down.
static func mp_cost_of(unit: Combatant, skill: BattleSkill) -> int:
	if skill.kind != BattleSkill.KIND_ABILITY or unit.passives.ability_mp_cut_pct <= 0:
		return skill.mp_cost
	var cut: int = mini(100, unit.passives.ability_mp_cut_pct)
	return floori(float(skill.mp_cost) * float(100 - cut) / 100.0)


## Gauge a limit burst needs: its level's cost, or the unit's full gauge when the cost
## is unknown.
static func _lb_needed(unit: Combatant, skill: BattleSkill) -> int:
	return skill.lb_cost if skill.lb_cost > 0 else unit.max_lb


# === Internals: turn flow ===

func _process_timeline() -> void:
	var processed: int = 0
	var entry: BattleTimeline.Entry = timeline.pop_due(frame)
	while entry != null:
		if entry.hit != null:
			_resolve_hit(entry.hit)
		elif entry.action_end != null:
			_end_action(entry.action_end)
		elif entry.cast != null and entry.cast.reaction != null:
			_start_reaction(entry.cast.reaction)
		elif entry.cast != null:
			_cast_pick(entry.cast)
		processed += 1
		if processed >= MAX_ENTRIES_PER_TICK:
			push_error("BattleEngine: more than %d timeline entries on frame %d; the rest wait for the next tick" % [MAX_ENTRIES_PER_TICK, frame])
			return
		entry = timeline.pop_due(frame)


func _advance_phase() -> void:
	if timeline.is_empty() and _check_battle_end():
		return
	if phase == Phase.OPENING:
		_run_opening()
	if phase == Phase.PLAYER:
		_run_berserk_party()
		if timeline.is_empty() and units_to_act().is_empty():
			_begin_enemy_phase()
	if phase == Phase.ENEMY:
		_run_enemy_phase()


## Berserk party members that have not acted attack on their own: on the first tick of
## the player phase, or as soon as berserk lands on one mid-phase.
func _run_berserk_party() -> void:
	for member in living_party():
		if not member.acted and not member.is_away() and member.control() == StatusBehavior.CONTROL_BERSERK:
			member.acted = true
			_start_forced_attack(member, member.controlling_status())


func _begin_turn() -> void:
	CoverTracker.reset(self)
	turn += 1
	total_turns += 1
	for member in party_members():
		member.acted = false
		member.defending = false
		member.queued_command = null
	events.append(BattleEventLog.TURN_STARTED, frame, {"turn": turn, "wave": wave, "total_turns": total_turns})
	_queue_opening_casts()
	if _reactions.is_empty():
		_set_phase(Phase.PLAYER)
		return
	_next_reaction_frame = frame
	_set_phase(Phase.OPENING)
	_run_opening()


## Regens restore (statuses, and the MP per turn passives' percent of max MP), the LB
## per turn passives fill the gauge (raised by the LB fill rate), then statuses act
## (poison), then every status counts down a turn and the expired ones go. A poison KO
## can end the battle here.
func _end_turn() -> void:
	var everyone: Array[Combatant] = party_members()
	everyone.append_array(enemies)
	for fighter in everyone:
		if not fighter.is_alive():
			continue
		var hp: int = fighter.status_value(BattleStatus.REGEN)
		var mp: int = fighter.status_value(BattleStatus.MP_REGEN) \
			+ floori(float(fighter.max_mp) * float(fighter.passives.mp_regen_pct) / 100.0)
		if hp > 0 or mp > 0:
			restore(null, fighter, hp, mp, &"regen")
		if fighter.is_alive() and fighter.passives.lb_per_turn > 0:
			var amount: int = roundi(float(fighter.passives.lb_per_turn) * (1.0 + float(fighter.lb_fill_rate()) / 100.0))
			change_lb(fighter, amount, null, &"lb_per_turn")
	for fighter in everyone:
		for status in fighter.statuses.duplicate():
			if fighter.is_alive() and fighter.statuses.has(status):
				status.behavior().on_turn_end(self, fighter, status)
	if _check_battle_end():
		return
	for fighter in everyone:
		for status in fighter.statuses.duplicate():
			if status.is_permanent():
				continue
			status.turns_left -= 1
			if status.turns_left <= 0:
				remove_status(fighter, status, &"expired")
	events.append(BattleEventLog.TURN_ENDED, frame, {"turn": turn})
	_begin_turn()


func _set_phase(next: int) -> void:
	phase = next
	events.append(BattleEventLog.PHASE_CHANGED, frame, {"phase": PHASE_NAMES[next], "turn": turn})


## Ends the battle, or the wave, when a side is down: every member KO'd or petrified.
## Called only while the timeline is empty, so the last hit has landed. A mutual wipe
## counts as a defeat. Returns true when the battle is not running any more.
func _check_battle_end() -> bool:
	if phase == Phase.ENDED or phase == Phase.WAVE_CLEARED:
		return true
	var party_up: bool = party_members().any(func(member: Combatant) -> bool: return member.is_standing())
	var enemies_up: bool = enemies.any(func(foe: Combatant) -> bool: return foe.is_standing())
	if party_up and enemies_up:
		return false
	_drop_queued_reactions(-1, &"battle_over")
	if party_up and wave < wave_count():
		_drop_delayed(-1, &"wave_cleared")
		_clear_wave()
		return true
	_drop_delayed(-1, &"battle_over")
	outcome = OUTCOME_VICTORY if party_up else OUTCOME_DEFEAT
	phase = Phase.ENDED
	events.append(BattleEventLog.BATTLE_ENDED, frame, {
		"outcome": outcome, "turn": turn, "wave": wave, "total_turns": total_turns,
	})
	return true


## The formation is down and another wave follows. Party members keep HP, MP, the
## gauge, buffs and debuffs with their turns left, grants with their turns and uses
## left, their action history (stack included), and the ailments that persist after
## a battle (StatusBehavior.persists_after_battle); the other ailments go (reason
## battle_end), a jump too (the unit is back on the ground without landing, the wiki),
## and so do chains, defending, queued commands, cooldowns and uses per battle, which
## reset each wave. KO'd members stay KO'd. begin_next_wave() goes on.
func _clear_wave() -> void:
	events.append(BattleEventLog.WAVE_CLEARED, frame, {"wave": wave, "waves": wave_count(), "turn": turn})
	for member in party_members():
		member.acted = false
		member.defending = false
		member.queued_command = null
		member.skill_state.clear()
		member.reset_chain()
		for status in member.statuses.duplicate():
			if not status.behavior().persists_after_battle():
				remove_status(member, status, &"battle_end")
	_set_phase(Phase.WAVE_CLEARED)


# === Internals: enemy phase ===

func _begin_enemy_phase() -> void:
	CoverTracker.reset(self)
	Counters.reset_caps(self)
	_count_down_grants()
	_set_phase(Phase.ENEMY)
	_enemy_order = PackedInt32Array()
	for foe in enemies:
		if foe.is_alive():
			_enemy_order.append(foe.id)
	_enemy_cursor = -1
	_enemy_turn_open = false
	_enemies_done = false
	_next_enemy_action_frame = frame


func _run_enemy_phase() -> void:
	if not _enemies_done and frame >= _next_enemy_action_frame:
		_run_enemy_decisions()
	if _enemies_done and timeline.is_empty():
		_end_turn()


## Asks enemies for decisions until one declares an action that takes time on the
## timeline, or every enemy has finished its turn.
func _run_enemy_decisions() -> void:
	for _i in range(MAX_ENEMY_DECISIONS_PER_TICK):
		if living_party().is_empty():
			return
		if not _enemy_turn_open and not _open_next_enemy_turn():
			_enemies_done = true
			return
		var foe: Combatant = combatant(_enemy_order[_enemy_cursor])
		var action: BattleAction = null
		if _landing_due(foe):
			# Landing is the enemy's whole turn (the user's rule, 2026-10-06).
			_enemy_turn_open = false
			action = _start_landing(foe, BattleAction.Origin.REACTION, Reaction.landing(foe, foe.away_status()))
			if action == null:
				continue
		elif not foe.can_act():
			_enemy_turn_open = false
			continue
		elif foe.controlling_status() != null:
			# Berserk or confused: one basic attack on a random target replaces the turn.
			action = _start_forced_attack(foe, foe.controlling_status())
			_enemy_turn_open = false
		else:
			var decision: Dictionary = foe.brain.next_action(_ai_context(foe))
			if str(decision.get("kind", "")) == EnemyBrain.KIND_TURN_OVER:
				_enemy_turn_open = false
				continue
			action = _declare_enemy_action(foe, decision)
			if foe.brain.is_turn_over():
				_enemy_turn_open = false
		# Waiting and guarding show nothing, so the next decision comes at once. Anything
		# else holds the next enemy action until this one has landed and been read.
		if action != null and action.skill != null:
			_next_enemy_action_frame = frame + maxi(
				action.span() + rules.enemy_action_gap_frames, rules.enemy_action_min_span_frames
			)
			if not _enemy_turn_open and not _enemy_left_after_cursor():
				_enemies_done = true
			return
	push_warning("BattleEngine: an enemy made %d decisions on frame %d without acting; ending its turn" % [MAX_ENEMY_DECISIONS_PER_TICK, frame])
	_enemy_turn_open = false


## Opens the next enemy's turn, skipping the dead. Each living enemy first rolls to
## shake off its ailments; one still disabled after that skips its turn. The AI is not
## asked while an ailment picks the enemy's action.
func _open_next_enemy_turn() -> bool:
	while _enemy_cursor + 1 < _enemy_order.size():
		_enemy_cursor += 1
		var foe: Combatant = combatant(_enemy_order[_enemy_cursor])
		if foe == null or not foe.is_alive():
			continue
		_roll_ailment_recovery(foe)
		if foe.can_act() or _landing_due(foe):
			# A guard lasts until the enemy's own next turn.
			foe.defending = false
			if foe.control() == StatusBehavior.CONTROL_NORMAL and not foe.is_away():
				foe.brain.begin_turn(_ai_context(foe))
			_enemy_turn_open = true
			return true
	return false


## At the start of an enemy's turn, each ailment it can shake off goes with
## BattleRules.enemy_ailment_recovery_pct (stop, charm and berserk run out instead).
func _roll_ailment_recovery(foe: Combatant) -> void:
	if rules.enemy_ailment_recovery_pct <= 0:
		return
	for status in foe.statuses.duplicate():
		if status.behavior().recovers_by_roll() and rng.randi_range(0, 99) < rules.enemy_ailment_recovery_pct:
			remove_status(foe, status, &"recovered")


## Whether an enemy later in the order may still act this phase: it can act now, or a
## recovery roll at the start of its turn may free it.
func _enemy_left_after_cursor() -> bool:
	for i in range(_enemy_cursor + 1, _enemy_order.size()):
		var foe: Combatant = combatant(_enemy_order[i])
		if foe == null or not foe.is_alive():
			continue
		if foe.can_act() or _landing_due(foe):
			return true
		if rules.enemy_ailment_recovery_pct > 0 and foe.statuses.any(func(status: BattleStatus) -> bool: return status.behavior().recovers_by_roll()):
			return true
	return false


func _declare_enemy_action(foe: Combatant, decision: Dictionary) -> BattleAction:
	var kind: String = str(decision.get("kind", ""))
	if kind == EnemyBrain.KIND_WAIT:
		return null
	if kind == EnemyBrain.KIND_GUARD:
		return _start_action(foe, BattleCommand.defend(), null, null, BattleAction.Origin.AI)

	var target: Combatant = _pick_ai_target(str(decision.get("target_mode", "random")), int(decision.get("target_param", 0)))
	var target_id: int = target.id if target != null else -1
	var command: BattleCommand = BattleCommand.attack(target_id)
	var skill: BattleSkill = foe.attack_skill
	if kind == EnemyBrain.KIND_SKILL:
		var skill_id: String = str(decision.get("skill_id", ""))
		var monster_skill: BattleSkill = catalog.get_skill(BattleSkill.KIND_MONSTER, skill_id) if skill_id != "" else null
		# A rule naming no usable skill (an index outside the skill set, or a skill whose
		# opcodes no schema entry covers) becomes a basic attack, as in the old engine. So
		# does a skill an ailment blocks (silence: magic attack type).
		if monster_skill != null and _has_known_effect(monster_skill) and not foe.skill_blocked(monster_skill):
			command = BattleCommand.skill(BattleSkill.KIND_MONSTER, skill_id, target_id)
			skill = monster_skill
	command.payload = {"rule_order": int(decision.get("rule_order", -1))}
	return _start_action(foe, command, skill, _links_for(foe, skill).skill, BattleAction.Origin.AI)


static func _has_known_effect(skill: BattleSkill) -> bool:
	for effect in skill.effects:
		if effect.is_known():
			return true
	return false


## The party member an AI targetSelect mode picks, among those on the field (a unit in
## the air is out of reach; none left gives null). 48089 of the table's 49944 rules say
## "random" (provoke, then aggro passives: see random_target); the rest aim at a stat
## extreme or a party slot. Modes not modelled fall back to random.
func _pick_ai_target(mode: String, param: int) -> Combatant:
	var pool: Array[Combatant] = targetable(living_party())
	if pool.is_empty():
		return null
	if mode == "disp_order":
		for member in pool:
			if member.slot == param:
				return member
	elif mode == "hp_max" or mode == "hp_min":
		return _extreme(pool, "hp", mode == "hp_max")
	elif mode == "mp_max" or mode == "mp_min":
		return _extreme(pool, "mp", mode == "mp_max")
	elif _AI_TARGET_STATS.has(mode):
		return _extreme(pool, str(_AI_TARGET_STATS[mode][0]), bool(_AI_TARGET_STATS[mode][1]))
	return random_target(pool)


## An enemy's random single-target pick from `pool`. Provokers (opcode 61) roll first,
## each with its Combatant.provoke_chance, highest chance first and the most recent
## provoke first on a tie: the first roll that lands picks its unit. When none lands, or
## nobody provokes, weighted_target picks (the user's rules, 2026-10-06). Without
## provokers it rolls nothing extra, so seeded battles are unchanged.
func random_target(pool: Array[Combatant]) -> Combatant:
	var provokers: Array[Combatant] = []
	for member in pool:
		if member.provoke_chance() > 0:
			provokers.append(member)
	provokers.sort_custom(_provokes_before)
	for member in provokers:
		var chance: int = member.provoke_chance()
		if chance >= 100 or rng.randi_range(0, 99) < chance:
			return member
	return weighted_target(pool)


static func _provokes_before(a: Combatant, b: Combatant) -> bool:
	var a_chance: int = a.provoke_chance()
	var b_chance: int = b.provoke_chance()
	if a_chance != b_chance:
		return a_chance > b_chance
	return a.find_status(BattleStatus.PROVOKE).added_order > b.find_status(BattleStatus.PROVOKE).added_order


## A random member of `pool`, weighted by aggro passives: each weighs 100 + its
## aggro_pct (at least 0), so +50% is 1.5 against 1.0 (the user's rule, 2026-10-01) and
## -100% is never picked while someone else can be. Uniform when nobody has aggro
## passives, with the same single roll as before.
func weighted_target(pool: Array[Combatant]) -> Combatant:
	var weights: Array[int] = []
	var total: int = 0
	var uniform: bool = true
	for member in pool:
		var weight: int = maxi(0, 100 + member.passives.aggro_pct)
		weights.append(weight)
		total += weight
		uniform = uniform and weight == 100
	if uniform or total <= 0:
		return pool[rng.randi_range(0, pool.size() - 1)]
	var roll: int = rng.randi_range(0, total - 1)
	for i in range(pool.size()):
		roll -= weights[i]
		if roll < 0:
			return pool[i]
	return pool[pool.size() - 1]


## The first pool member with the highest (or lowest) value of `metric`: "hp", "mp" or
## a stat name.
static func _extreme(pool: Array[Combatant], metric: String, want_max: bool) -> Combatant:
	var best: Combatant = pool[0]
	var best_value: int = _metric(best, metric)
	for fighter in pool:
		var value: int = _metric(fighter, metric)
		if (value > best_value) if want_max else (value < best_value):
			best = fighter
			best_value = value
	return best


static func _metric(fighter: Combatant, metric: String) -> int:
	if metric == "hp":
		return fighter.hp
	if metric == "mp":
		return fighter.mp
	return fighter.stat(metric)


## The battle as MonsterAIRuntime reads it (see its CONTEXT notes). Party views are
## slot-stable, with {} for an empty slot, so the AI's 1-based party slots line up.
func _ai_context(subject: Combatant) -> Dictionary:
	var party_views: Array = []
	for member in party:
		party_views.append(ai_view(member) if member != null else {})
	var enemy_views: Array = []
	var by_source: Dictionary = {}
	var own_view: Dictionary = {}
	for foe in enemies:
		var view: Dictionary = ai_view(foe)
		enemy_views.append(view)
		by_source[foe.source_id] = view
		if foe == subject:
			own_view = view
	if own_view.is_empty():
		own_view = ai_view(subject)
	return {
		"self": own_view,
		"party": party_views,
		"enemies": enemy_views,
		"monsters_by_id": by_source,
	}


## A combatant as the AI sees it. `statuses` lists its ailments (for the
## abnormal_state / normal_state conditions), `is_off_field` whether it is in the air (for
## outside_field).
static func ai_view(fighter: Combatant) -> Dictionary:
	var ailments: Array = []
	for status in fighter.statuses_of(BattleStatus.AILMENT):
		ailments.append(status.key)
	return {
		"id": fighter.id,
		"instance_id": fighter.source_id,
		"index": fighter.slot,
		"current_hp": fighter.hp,
		"max_hp": fighter.max_hp,
		"hp": fighter.max_hp,
		"current_mp": fighter.mp,
		"max_mp": fighter.max_mp,
		"statuses": ailments,
		"is_off_field": fighter.is_away(),
	}


# === Internals: misc ===

func _register(fighter: Combatant) -> void:
	fighter.id = _next_combatant_id
	_next_combatant_id += 1
	_combatants[fighter.id] = fighter


## "Name#id". Current HP is left out: the event may be from earlier in the battle.
func _name(id: Variant) -> String:
	var fighter: Combatant = combatant(int(id)) if typeof(id) in [TYPE_INT, TYPE_FLOAT] else null
	return "%s#%d" % [fighter.name, fighter.id] if fighter != null else str(id)


static func _ids(fighters: Array) -> Array[int]:
	var out: Array[int] = []
	for fighter in fighters:
		if fighter != null:
			out.append((fighter as Combatant).id)
	return out
