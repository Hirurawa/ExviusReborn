extends RefCounted
class_name MonsterAIRuntime

## Walks a compiled MonsterAIScript against live battle state to decide what a
## monster does. MonsterAIScript is the parse, MonsterAIState the mutable state; this
## is the evaluator. It takes battle state as a plain Dictionary (see CONTEXT below)
## rather than a BattleManager, so a whole turn can be simulated in a test.
##
## TURN MODEL. A monster's turn re-walks the rule list once per action: the first rule
## whose triggers and conditions all hold and whose probability roll passes fires. The
## turn ends when a firing rule's verb is `turn_end`, when nothing matches, or -- for
## the 1084 scripted monsters that have no turn_end rule at all -- after one action.
##
## A rule may fire at most ONCE PER TURN, which is what actually bounds the walk. This
## is an inference, but a well-supported one: Shadow Dragon (10000012) is three rules
## -- `flg9=OFF -> turn_end` then `flg9=ON -> skill 1` -- and once flg9 latches, rule 3
## matches on every re-walk with nothing left to end the turn. 668 of the 2778 scripted
## monsters have that shape and spin until the safety cap without a per-rule lock. With
## it they act once per turn, which is exactly what the 2478 monsters ending on an
## unconditional `attack` should do. The alternative -- a per-monster action budget that
## turn_end exits early -- would need a number that provably is not in this database
## (nothing in monster_parts carries one). The lock also leaves every verified fight
## unchanged, because the scripted multi-action bosses already self-latch their rules:
## it costs nothing and it terminates. `limited_act` remains the separate, battle-scoped
## cap on total fires.
##
##     var state := MonsterAIState.new(monster_id)
##     for action in MonsterAIRuntime.run_turn(ai_script, state, ctx):
##         ... execute action ...
##
## Reaction rules need finer control than run_turn offers: put the event in
## ctx.pending_reaction and call next_action() directly. The firing rule consumes the
## event (next_action erases the key), so a single incoming hit provokes one reaction.
##
## CONTEXT. Every key is optional; a condition whose input is missing fails closed
## (see CONFIDENCE) rather than guessing.
##     self             Dictionary  the acting monster's battle dict
##     party            Array       player units by slot, index-stable, [] slots ok
##     enemies          Array       the enemy formation by slot, index-stable
##     monsters_by_id   Dictionary  monsterId -> battle dict, for cross-monster rules
##     pending_reaction Dictionary  { type: "before_turn_mg" } / { type: "physics_fire" }
## Unit dicts are read for `current_hp` plus `max_hp` (or `hp`), and optionally
## `is_broken` / `statuses`.
##
## CONFIDENCE. Condition support is deliberately tiered, because roughly 6% of the
## table's condition atoms use mechanics this data cannot pin down:
##   SUPPORTED     verified against real fights. Evaluated exactly.
##   APPROXIMATED  implemented on the most plausible reading, warned about once per
##                 type so the guess is visible in the log. Currently `actbetween`
##                 and `act` -- frequent enough (~3% of atoms) that failing them
##                 closed would flatten a lot of monsters.
##   UNSUPPORTED   fails closed, warned about once per type. The rule simply never
##                 fires, so the script falls through to its own catch-all (2478 of
##                 the 2778 scripted monsters end on an unconditional `attack`).
##                 Counter ids other than 1 land here: the data cannot say what
##                 domain they count -- 937 of 1037 ids tested with cntup_over /
##                 cntup_under are never touched by a cntup_act rule in the same
##                 script, so "the _act suffix advances it" cannot be the whole
##                 story. Timers, monster parts and party-wide conditions likewise.
## The warnings are the roadmap: whatever shows up in a real battle log is the next
## mechanic worth pinning down.

## next_action() result kinds. The first four name an action to execute; TURN_OVER
## means the turn produced nothing further.
const KIND_SKILL: String = "skill"
const KIND_ATTACK: String = "attack"
const KIND_GUARD: String = "guard"
const KIND_WAIT: String = "wait"
const KIND_TURN_OVER: String = "turn_over"

## Backstop for a script whose chain never reaches a turn_end. The deepest real
## per-turn action sequence in the table is 21 (counter steps run 0..20).
const MAX_ACTIONS_PER_TURN: int = 32

## Counter id 1 is the per-turn action index -- verified by the multi-action bosses,
## whose cntup_act steps enumerate 0,1,2,... in lockstep with their actions. It is
## 76% of all counter usage; other ids are UNSUPPORTED.
const ACTION_COUNTER_ID: int = 1

## Condition types implemented on an unverified reading. See CONFIDENCE.
const APPROXIMATED_TYPES: Array = ["actbetween", "act"]

## type -> true, so each unsupported/approximated type is only warned about once per
## run instead of once per rule evaluation.
static var _warned: Dictionary = {}


## Runs a monster's whole turn and returns the ordered actions to execute. Begins the
## turn, so do not call it mid-turn. Reaction-driven flows should drive next_action()
## directly instead.
static func run_turn(ai_script: MonsterAIScript, state: MonsterAIState, ctx: Dictionary) -> Array[Dictionary]:
	state.begin_turn()
	var actions: Array[Dictionary] = []
	while not state.turn_over:
		var action: Dictionary = next_action(ai_script, state, ctx)
		if str(action.get("kind", "")) == KIND_TURN_OVER:
			break
		actions.append(action)
	return actions


## Picks the monster's next action, applying the firing rule's state changes (flag
## writes, action counter, fire count) as it goes. Mutates `state`, and erases
## ctx.pending_reaction when the firing rule consumed it.
##
## Returns { kind, rule_order, skill_index, skill_id, target_mode, target_param,
## reaction, reason }. `kind` is KIND_TURN_OVER when there is nothing to do, with
## `reason` saying why. A KIND_SKILL result with skill_id "" means the rule named a
## skill index this monster's skill set cannot resolve (~22% of the table's skill
## references) -- treat it as a basic attack.
static func next_action(ai_script: MonsterAIScript, state: MonsterAIState, ctx: Dictionary) -> Dictionary:
	if state.turn_over:
		return _turn_over("turn already over")
	if not ai_script.has_script():
		state.end_turn()
		return _turn_over("monster has no ai script")
	if state.acts_this_turn >= MAX_ACTIONS_PER_TURN:
		_warn_once("cap:" + ai_script.monster_id, "monster %s hit the %d-action cap; its rule chain never reached a turn_end. Usually means a gate condition this runtime cannot evaluate never opened." % [
			ai_script.monster_id, MAX_ACTIONS_PER_TURN,
		])
		state.end_turn()
		return _turn_over("action cap reached")

	for rule in ai_script.rules:
		if state.fired_this_turn_already(int(rule.get("order", 0))):
			continue
		if not _triggers_hold(rule, state, ctx):
			continue
		if not _conditions_hold(rule, state, ctx):
			continue
		if state.roll_percent() >= float(rule.get("probability", 0.0)):
			continue
		return _fire(ai_script, state, ctx, rule)

	state.end_turn()
	return _turn_over("no rule matched")


## Applies a matched rule and builds its action result.
static func _fire(ai_script: MonsterAIScript, state: MonsterAIState, ctx: Dictionary, rule: Dictionary) -> Dictionary:
	var verb: String = str(rule.get("verb", ""))
	var order: int = int(rule.get("order", 0))
	state.record_fire(order)

	# A reaction rule consumes the event that let it fire, so one incoming hit
	# provokes one counter rather than every counter rule in the script.
	var reaction: Dictionary = {}
	if _uses_reaction(rule):
		reaction = ctx.get("pending_reaction", {})
		ctx.erase("pending_reaction")

	if verb == MonsterAIScript.VERB_TURN_END:
		state.end_turn(rule)
		return _turn_over("turn_end rule #%d" % order)

	# Scripts with no turn_end rule act once per turn, so this action is also the one
	# that ends the turn -- and therefore the one whose writes carry over.
	state.acts_this_turn += 1
	if ai_script.ends_turn_explicitly():
		state.apply_writes(rule)
	else:
		state.end_turn(rule)

	var skill_index: int = int(rule.get("skill_index", MonsterAIScript.SKILL_INDEX_NONE))
	return {
		"kind": _kind_for_verb(verb),
		"rule_order": order,
		"skill_index": skill_index,
		"skill_id": _resolve_skill_id(ai_script, state, skill_index),
		"target_mode": str(rule.get("target_mode", "")),
		"target_param": int(rule.get("target_param", 0)),
		"reaction": reaction,
		"reason": "",
	}


## The monsterSkillId a rule's payload index names. "" when the rule names no skill
## or the index is unresolvable; SKILL_INDEX_RANDOM picks from the whole set.
static func _resolve_skill_id(ai_script: MonsterAIScript, state: MonsterAIState, skill_index: int) -> String:
	if skill_index == MonsterAIScript.SKILL_INDEX_NONE:
		return ""
	if skill_index == MonsterAIScript.SKILL_INDEX_RANDOM:
		var usable: PackedStringArray = PackedStringArray()
		for slot in ai_script.skill_slots:
			if slot != "":
				usable.append(slot)
		var pick: int = state.roll_index(usable.size())
		return "" if pick < 0 else usable[pick]
	return ai_script.skill_id_at(skill_index)


static func _kind_for_verb(verb: String) -> String:
	match verb:
		MonsterAIScript.VERB_SKILL:
			return KIND_SKILL
		MonsterAIScript.VERB_ATTACK:
			return KIND_ATTACK
		MonsterAIScript.VERB_GUARD:
			return KIND_GUARD
	# `wait` burns an action doing nothing; so does the one row with an empty verb.
	return KIND_WAIT


# === Conditions ===

## True when every one of the rule's AND-ed condition atoms holds against the acting
## monster.
static func _conditions_hold(rule: Dictionary, state: MonsterAIState, ctx: Dictionary) -> bool:
	var subject: Dictionary = ctx.get("self", {})
	for condition in rule.get("conditions", []):
		if not _condition_holds(condition, subject, rule, state, ctx):
			return false
	return true


## True when every one of the rule's scoped trigger slots holds. Reaction types test
## ctx.pending_reaction; everything else is a state test against the trigger's
## subject, which the scope selects.
static func _triggers_hold(rule: Dictionary, state: MonsterAIState, ctx: Dictionary) -> bool:
	for trigger in rule.get("triggers", []):
		var type: String = str(trigger.get("type", ""))
		if MonsterAIScript.is_reaction_type(type):
			if not _reaction_pending(type, ctx):
				return false
			continue

		var subject: Variant = _resolve_subject(trigger, ctx)
		if subject == null:
			_warn_once(type, "trigger scope %d is unsupported" % int(trigger.get("scope", 0)))
			return false
		var condition: Dictionary = {
			"type": type,
			"params": str(trigger.get("param", "")).split(","),
		}
		if not _condition_holds(condition, subject, rule, state, ctx):
			return false
	return true


## True when the pending event matches this reaction type. Matching is on the type
## string alone: the trigger's param is 1 for every before_turn_* slot but 0 for every
## element hit, so it is not a boolean to test against -- reading it as one would
## innvert the element counters and break the bosses built on them.
static func _reaction_pending(type: String, ctx: Dictionary) -> bool:
	var pending: Dictionary = ctx.get("pending_reaction", {})
	return not pending.is_empty() and str(pending.get("type", "")) == type


## True when any part of the rule is a reaction, i.e. firing it consumes the pending
## event. Reaction types appear in the plain condition atoms as well as the trigger
## slots (365 rows put an element hit or a before_turn_* directly in an atom), and
## they mean the same thing in both places.
static func _uses_reaction(rule: Dictionary) -> bool:
	for trigger in rule.get("triggers", []):
		if MonsterAIScript.is_reaction_type(str(trigger.get("type", ""))):
			return true
	for condition in rule.get("conditions", []):
		if MonsterAIScript.is_reaction_type(str(condition.get("type", ""))):
			return true
	return false


## The battle dict a trigger's scope + subject names, or null when the scope is one
## this runtime does not support yet.
static func _resolve_subject(trigger: Dictionary, ctx: Dictionary) -> Variant:
	var scope: int = int(trigger.get("scope", 0))
	var subject: String = str(trigger.get("subject", ""))

	if scope == MonsterAIScript.TRIGGER_SCOPE_SELF or scope == MonsterAIScript.TRIGGER_SCOPE_INCOMING_ACTION:
		return ctx.get("self", {})
	if scope == MonsterAIScript.TRIGGER_SCOPE_PARTY_SLOT:
		return _slot(ctx.get("party", []), subject)
	if scope == MonsterAIScript.TRIGGER_SCOPE_ENEMY_SLOT:
		return _slot(ctx.get("enemies", []), subject)
	if scope == MonsterAIScript.TRIGGER_SCOPE_MONSTER_ID:
		# A monster absent from the map is UNKNOWN, not dead. Returning {} here would
		# read as dead and make every `alive:0` cross-monster trigger spuriously true.
		var by_id: Dictionary = ctx.get("monsters_by_id", {})
		return by_id[subject] if by_id.has(subject) else null
	# TRIGGER_SCOPE_PARTY needs party-wide aggregates and TRIGGER_SCOPE_MONSTER_PART
	# needs per-part modelling; neither exists yet.
	return null


## The 1-based slot `subject` of an index-stable team array. {} for an empty or
## out-of-range slot, which reads as "dead" -- the right answer for `alive:0`.
static func _slot(team: Array, subject: String) -> Dictionary:
	if not subject.is_valid_int():
		return {}
	var index: int = int(subject) - 1
	if index < 0 or index >= team.size():
		return {}
	return team[index]


## Evaluates one condition atom against `subject`. See the CONFIDENCE note for what
## the tiers mean; anything unsupported returns false so the rule cannot fire.
static func _condition_holds(condition: Dictionary, subject: Dictionary, rule: Dictionary, state: MonsterAIState, ctx: Dictionary) -> bool:
	var type: String = str(condition.get("type", ""))
	var params: PackedStringArray = condition.get("params", PackedStringArray())
	var p0: int = _param(params, 0)
	var p1: int = _param(params, 1)

	# An incoming-event type means the same in an atom slot as in a trigger slot.
	if MonsterAIScript.is_reaction_type(type):
		return _reaction_pending(type, ctx)

	match type:
		"non":
			return true
		"flg_on":
			return state.flag(p0) != 0
		"flg_off":
			return state.flag(p0) == 0
		"flg2_on":
			return state.flag2(p0) != 0
		"flg2_off":
			return state.flag2(p0) == 0
		"limited_act":
			return state.fire_count(int(rule.get("order", 0))) < p0
		"alive":
			return _is_alive(subject) == (p0 != 0)

	# HP thresholds are strict comparisons: Intangir's 50% rule must not fire at
	# exactly full HP, and its pair of thresholds only reads correctly this way.
	if type == "hp_pr_under" or type == "hp_pr_over":
		# An absent subject (empty formation slot) simply has no HP to compare, which
		# is a legitimate false rather than a gap in the battle state.
		if subject.is_empty():
			return false
		var percent: float = _hp_percent(subject)
		if percent < 0.0:
			_warn_once(type, "subject carries no current_hp/max_hp -- cannot evaluate")
			return false
		return percent < float(p0) if type == "hp_pr_under" else percent > float(p0)

	# Counter 1 is the per-turn action index. Other ids count something this data
	# cannot identify.
	if type.begins_with("flg_cntup") or type.begins_with("flg2_cntup"):
		if p0 != ACTION_COUNTER_ID:
			_warn_once("%s:%d" % [type, p0], "only counter %d (the per-turn action index) is understood" % ACTION_COUNTER_ID)
			return false
		if type.ends_with("_act"):
			return state.acts_this_turn == p1
		if type.ends_with("_over"):
			return state.acts_this_turn >= p1
		if type.ends_with("_under"):
			return state.acts_this_turn < p1
		_warn_once(type, "unknown counter comparison")
		return false

	if type == "breaking":
		if not subject.has("is_broken"):
			_warn_once(type, "battle state does not track break yet")
			return false
		return bool(subject.get("is_broken", false)) == (p0 != 0)

	if type == "abnormal_state" or type == "normal_state":
		if not subject.has("statuses"):
			_warn_once(type, "battle state does not track statuses yet")
			return false
		var afflicted: bool = not Array(subject.get("statuses", [])).is_empty()
		return afflicted if type == "abnormal_state" else not afflicted

	if type == "outside_field":
		if not subject.has("is_off_field"):
			_warn_once(type, "battle state does not track off-field units yet")
			return false
		return bool(subject.get("is_off_field", false)) == (p0 != 0)

	# APPROXIMATED. "every N acts" and "on act N" -- plausible readings, not verified.
	if type == "actbetween" or type == "act":
		# An approximation must never be what ENDS a turn. A false positive there
		# silences the monster for the whole battle: Veritas of the Flame (305014001)
		# leads with `act:1 -> turn_end`, so reading act:1 as "the first action" makes
		# it end its turn before ever acting. A false negative merely delays the turn
		# end, and the action cap still backstops that. The trade is cheap -- only 10
		# monsters gate a turn_end this way, against 4289 action rules that use them.
		if str(rule.get("verb", "")) == MonsterAIScript.VERB_TURN_END:
			_warn_once(type + " on turn_end", "an approximated condition is not trusted to end a turn; rule skipped")
			return false
		if type == "actbetween":
			_warn_once(type, "approximated as 'action index divides evenly by %d'" % p0)
			return p0 > 0 and state.acts_this_turn % p0 == 0
		_warn_once(type, "approximated as 'action index (1-based) equals %d'" % p0)
		return state.acts_this_turn + 1 == p0

	_warn_once(type, "condition type not implemented")
	return false


## Subject HP as 0-100, or -1 when it carries no HP to read.
static func _hp_percent(subject: Dictionary) -> float:
	if not subject.has("current_hp"):
		return -1.0
	var max_hp: int = int(subject.get("max_hp", subject.get("hp", 0)))
	if max_hp <= 0:
		return -1.0
	return clampf(float(int(subject.get("current_hp", 0))) / float(max_hp) * 100.0, 0.0, 100.0)


## An empty slot counts as dead, so `alive:0` holds for a formation gap.
static func _is_alive(subject: Dictionary) -> bool:
	return not subject.is_empty() and int(subject.get("current_hp", 0)) > 0


## Condition param `index` as an int; 0 when absent or non-numeric.
static func _param(params: PackedStringArray, index: int) -> int:
	if index >= params.size() or not params[index].is_valid_int():
		return 0
	return int(params[index])


static func _turn_over(reason: String) -> Dictionary:
	return {
		"kind": KIND_TURN_OVER,
		"rule_order": -1,
		"skill_index": MonsterAIScript.SKILL_INDEX_NONE,
		"skill_id": "",
		"target_mode": "",
		"target_param": 0,
		"reaction": {},
		"reason": reason,
	}


## Warns about an unhandled or approximated mechanic once per key per run, so a
## battle log names each gap exactly once instead of thousands of times.
static func _warn_once(key: String, message: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning("MonsterAIRuntime: '%s' -- %s" % [key, message])


## Forgets which mechanics have been warned about, so a fresh run reports them again.
static func clear_warnings() -> void:
	_warned.clear()
