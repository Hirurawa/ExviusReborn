class_name BattleTimeline
extends RefCounted

## What is still to happen, ordered by frame: hits, action ends and casts waiting to start
## (multicast picks after the first, casts after a revive). Entries due on the
## same frame run in the order their actions were declared; entries of actions declared
## on the same frame run in party order (the wiki's spark chain order, which decides
## which hit counts first and whether a unit hits twice in a row); the rest in the order
## they were scheduled. So a battle replays identically from the same seed and commands.


class Entry:
	extends RefCounted
	var frame: int = 0
	## The action's start_frame and cast_order; see _sorts_before.
	var cast_frame: int = 0
	var cast_order: int = 0
	## Scheduling order; breaks the remaining ties.
	var seq: int = 0
	## Exactly one of these is set.
	var hit: ScheduledHit = null
	var action_end: BattleAction = null
	var cast: ScheduledCast = null


## Sorted by (frame, cast_frame, cast_order, seq).
var _entries: Array[Entry] = []
var _next_seq: int = 0


func schedule_hit(hit: ScheduledHit) -> void:
	var entry := Entry.new()
	entry.frame = hit.frame
	entry.hit = hit
	_insert(entry, hit.action)


func schedule_action_end(action: BattleAction, at_frame: int) -> void:
	var entry := Entry.new()
	entry.frame = at_frame
	entry.action_end = action
	_insert(entry, action)


## A cast due on `cast.frame`, ordered as an entry of `after` (the action it follows: the
## previous multicast pick), so it runs after that action's hits on the same frame. With
## no `after` it runs after every entry of an action declared up to its frame.
func schedule_cast(cast: ScheduledCast, after: BattleAction) -> void:
	var entry := Entry.new()
	entry.frame = cast.frame
	entry.cast = cast
	if after == null:
		entry.cast_frame = cast.frame
		entry.cast_order = BattleAction.ENEMY_CAST_ORDER + 1
	_insert(entry, after)


## Removes and returns the earliest entry due at or before `current_frame`, or null
## when nothing is due.
func pop_due(current_frame: int) -> Entry:
	if _entries.is_empty() or _entries[0].frame > current_frame:
		return null
	return _entries.pop_front()


func is_empty() -> bool:
	return _entries.is_empty()


func size() -> int:
	return _entries.size()


## Frame of the next entry, or -1 when the timeline is empty.
func next_frame() -> int:
	return -1 if _entries.is_empty() else _entries[0].frame


## Hits still scheduled for `action`.
func hits_for(action: BattleAction) -> Array[ScheduledHit]:
	var out: Array[ScheduledHit] = []
	for entry in _entries:
		if entry.hit != null and entry.hit.action == action:
			out.append(entry.hit)
	return out


## Every hit still scheduled, in the order they will land. A new array; the hits are
## the live ones, so readers must not change them (the sandbox's frame ruler).
func pending_hits() -> Array[ScheduledHit]:
	var out: Array[ScheduledHit] = []
	for entry in _entries:
		if entry.hit != null:
			out.append(entry.hit)
	return out


func clear() -> void:
	_entries.clear()


func _insert(entry: Entry, action: BattleAction) -> void:
	entry.seq = _next_seq
	_next_seq += 1
	if action != null:
		entry.cast_frame = action.start_frame
		entry.cast_order = action.cast_order
	var index: int = _entries.bsearch_custom(entry, _sorts_before, false)
	_entries.insert(index, entry)


## An action schedules its hits and its end when it is declared, so for actions declared
## on different frames cast_frame gives the scheduling order anyway; cast_order only
## reorders actions declared together. An action's end is scheduled after its hits, so
## it still runs after its last hit.
static func _sorts_before(a: Entry, b: Entry) -> bool:
	if a.frame != b.frame:
		return a.frame < b.frame
	if a.cast_frame != b.cast_frame:
		return a.cast_frame < b.cast_frame
	if a.cast_order != b.cast_order:
		return a.cast_order < b.cast_order
	return a.seq < b.seq
