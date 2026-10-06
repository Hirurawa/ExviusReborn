class_name ScheduledCast
extends RefCounted

## A cast waiting on the timeline, which BattleEngine starts when its frame comes: a
## multicast pick after the first (Multicast), or a reaction that runs right away rather
## than in the opening phase (a passive's cast after a revive; Reaction). Delayed casts
## (opcode 132, not built) can wait the same way.

var actor_id: int = -1
## The multicast command the pick belongs to, and the pick's place in its picks.
var command: BattleCommand = null
var index: int = 0
## Set instead of `command` for a reaction.
var reaction: Reaction = null
## Frame the cast is due on.
var frame: int = 0


static func pick(actor: int, multicast_command: BattleCommand, pick_index: int, due_frame: int) -> ScheduledCast:
	var cast := ScheduledCast.new()
	cast.actor_id = actor
	cast.command = multicast_command
	cast.index = pick_index
	cast.frame = due_frame
	return cast


static func for_reaction(queued: Reaction, due_frame: int) -> ScheduledCast:
	var cast := ScheduledCast.new()
	cast.actor_id = queued.actor_id
	cast.reaction = queued
	cast.frame = due_frame
	return cast
