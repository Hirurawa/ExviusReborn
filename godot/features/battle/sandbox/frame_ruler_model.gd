class_name FrameRulerModel
extends RefCounted

## What the sandbox's frame ruler shows: a window of frames around the current one, a
## row per target, a mark per hit (landed ones from the event log, pending ones from
## the timeline) and the chain window each damage hit opens. Built from engine state
## and events only, so tests can check it headless.

const PAST_FRAMES: int = 60
const FUTURE_FRAMES: int = 120


class Mark:
	extends RefCounted
	var frame: int = 0
	var actor_id: int = -1
	var target_id: int = -1
	## Still on the timeline (false: already landed or missed).
	var pending: bool = true
	var missed: bool = false
	## A damage hit: it counts toward the target's chain.
	var damage: bool = true
	var effect_type: String = ""
	## Pending: the cast-time share before hit-time terms. Landed: the damage dealt.
	var amount: int = 0
	## Landed damage hits: the chain count and multiplier (percent) they got.
	var chain: int = 0
	var chain_pct: int = 100
	var takes_chain_bonus: bool = true
	## Why it missed (landed) or will miss (pending, a miss rolled at cast time).
	var reason: String = ""


class Row:
	extends RefCounted
	var target_id: int = -1
	var label: String = ""
	var marks: Array[Mark] = []


var now: int = 0
var first_frame: int = 0
var last_frame: int = 0
var chain_window: int = 20
var rows: Array[Row] = []
## Actor ids in the order they first appear, for colours and the legend.
var actors: Array[int] = []


## `landed` holds HIT_LANDED and HIT_MISSED events; those older than PAST_FRAMES are
## left out. Every enemy gets a row; a party member only when a mark falls on it.
static func build(engine: BattleEngine, landed: Array[Dictionary]) -> FrameRulerModel:
	var model := FrameRulerModel.new()
	model.now = engine.frame
	model.first_frame = engine.frame - PAST_FRAMES
	model.last_frame = engine.frame + FUTURE_FRAMES
	model.chain_window = engine.rules.chain_window_frames

	var by_target: Dictionary = {}
	for event in landed:
		var frame: int = int(event.get("frame", 0))
		if frame < model.first_frame or frame > model.now:
			continue
		var mark := Mark.new()
		mark.frame = frame
		mark.actor_id = int(event.get("actor", -1))
		mark.target_id = int(event.get("target", -1))
		mark.pending = false
		mark.effect_type = str(event.get("effect", ""))
		if event.get("type") == BattleEventLog.HIT_MISSED:
			mark.missed = true
			mark.reason = str(event.get("reason", ""))
		else:
			mark.amount = int(event.get("amount", 0))
			mark.chain = int(event.get("chain", 0))
			mark.chain_pct = int(event.get("chain_pct", 100))
		_add(model, by_target, mark)

	for hit in engine.timeline.pending_hits():
		if hit.frame > model.last_frame:
			break
		var mark := Mark.new()
		mark.frame = hit.frame
		mark.actor_id = hit.actor_id
		mark.target_id = hit.target_id
		mark.effect_type = hit.effect.type if hit.effect != null else ""
		mark.amount = roundi(hit.amount)
		mark.damage = hit.handler is DamageHandler and hit.builds_chain
		mark.takes_chain_bonus = hit.takes_chain_bonus
		if hit.cancelled:
			mark.missed = true
			mark.reason = str(hit.cancel_reason)
		_add(model, by_target, mark)

	var order: Array[Combatant] = engine.enemies.duplicate()
	order.append_array(engine.party_members())
	for fighter in order:
		if fighter.is_enemy() or by_target.has(fighter.id):
			var row := Row.new()
			row.target_id = fighter.id
			row.label = "%s#%d" % [fighter.name, fighter.id]
			row.marks = by_target.get(fighter.id, row.marks)
			model.rows.append(row)
	return model


## The x position (0..1) of `frame` within the window.
func position_of(frame: int) -> float:
	return float(frame - first_frame) / float(maxi(1, last_frame - first_frame))


## One line about a mark, for the ruler's tooltip.
func describe(mark: Mark, engine: BattleEngine) -> String:
	var who: String = "%s -> %s" % [_name(engine, mark.actor_id), _name(engine, mark.target_id)]
	var when: String = "f%d (%+d)" % [mark.frame, mark.frame - now]
	if mark.missed:
		return "%s %s %s: %s %s" % [when, who, mark.effect_type, "will miss" if mark.pending else "missed", mark.reason]
	if mark.pending:
		var chain_note: String = ""
		if mark.damage:
			chain_note = ", builds the chain" + ("" if mark.takes_chain_bonus else " without the bonus")
		return "%s %s %s, %d at cast time%s" % [when, who, mark.effect_type, mark.amount, chain_note]
	return "%s %s %s %d (chain %d, x%.2f)" % [when, who, mark.effect_type, mark.amount, mark.chain, float(mark.chain_pct) / 100.0]


static func _add(model: FrameRulerModel, by_target: Dictionary, mark: Mark) -> void:
	if not by_target.has(mark.target_id):
		var marks: Array[Mark] = []
		by_target[mark.target_id] = marks
	(by_target[mark.target_id] as Array).append(mark)
	if not model.actors.has(mark.actor_id):
		model.actors.append(mark.actor_id)


static func _name(engine: BattleEngine, id: int) -> String:
	var fighter: Combatant = engine.combatant(id)
	return "%s#%d" % [fighter.name, fighter.id] if fighter != null else str(id)
