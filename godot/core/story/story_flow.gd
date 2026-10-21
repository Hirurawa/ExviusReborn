class_name StoryFlow
extends RefCounted

## The story around the screens (CUTSCENE-PLAN.md section 10): which scenes play when the
## player enters a dungeon or a town or clears a mission, playing them on the cutscene
## screen over the current screen, keeping the switches they set, and going where they
## lead.
##
##   dungeon_entry_scenes(dungeon_id)  map_event rows of the dungeon, trigger 1
##   after_clear_scenes(mission_id)    map_event rows with trigger 2, the mission's and
##                                     its dungeon's (played after the results screen)
##   play_scenes(scenes)               plays them in order; the next location they named
##   enter_town(town_id)               the town's scenes one at a time (its map_event rows
##                                     and the scenes its event packages start), following
##                                     where they lead, then the town itself
##   go_to(location)                   a mission's battle (type 0) or a town (type 1)
##
## A scene is { story_event_id, name, bin_id, layer, switches, done_switch }. `switches`
## are the player's switches with the story event's own on top (they pick the page that
## plays); `done_switch` (0 for none) is set once it has played. A scene whose bin is
## not in the assets, or that has nothing to start under its switches, is skipped but
## still counts as watched, so the story goes on without its files.
##
## A map_event row or an event package plays while its switchInfo is on (or names no
## switch) and its openSwitch is off (or names none). A scene's switch writes are kept
## in SwitchService, except the scene-local ones (switch scope 2, the 191000xx page
## selectors).

const TYPE_MISSION: int = 0
const TYPE_TOWN: int = 1
## map_event's trigger column (XFh30CkV).
const ON_ENTERING: int = 1
const AFTER_CLEAR: int = 2
## 8 town rows use it (main4-4_ED at Dilmagia ...). ❓ played on entering, after trigger 1.
const TOWN_TRIGGER_3: int = 3
const LOCATION_MISSION: int = 1
const LOCATION_TOWN: int = 2
const LOCATION_DUNGEON: int = 3
## GameDatabase.get_switch_kind scope of a scene-local switch.
const SCOPE_LOCAL: int = 2
## switch_type ids of the main story (メイン_C, _S, _L, the boss flag, _C2).
const MAIN_STORY_TYPES: Array = [100, 101, 102, 103, 104]
## A town visit plays at most this many scenes (a page that never turns itself off
## would otherwise loop).
const MAX_SCENES_PER_VISIT: int = 32

var _screen: CutsceneScreen = null


# === Which scenes play ===

## The scenes map_event plays when the player enters dungeon `dungeon_id`, before its
## mission list.
static func dungeon_entry_scenes(dungeon_id: String) -> Array:
	return _map_event_scenes(LOCATION_DUNGEON, dungeon_id, ON_ENTERING)


## The scenes map_event plays after mission `mission_id` is cleared, once its results
## have shown: the mission's own, then its dungeon's.
static func after_clear_scenes(mission_id: String) -> Array:
	if not mission_id.is_valid_int():
		return []
	var scenes: Array = _map_event_scenes(LOCATION_MISSION, mission_id, AFTER_CLEAR)
	var dungeon_id: String = str(MissionService.get_mission_data(mission_id).get("dungeon_id", ""))
	scenes.append_array(_map_event_scenes(LOCATION_DUNGEON, dungeon_id, AFTER_CLEAR))
	return scenes


## The scene of story event `story_event_id` under the player's switches, played by
## `mission_id` if any. Its bin_id is "" when the database names no bin for it.
static func story_event_scene(story_event_id: String, mission_id: String = "", done_switch: int = 0) -> Dictionary:
	var found: Dictionary = GameDatabase.get_story_event_scene(story_event_id, mission_id)
	var switches: Dictionary = SwitchService.as_event_switches()
	switches.merge(found.get("switches", {}), true)
	return {
		"story_event_id": story_event_id,
		"name": str(found.get("name", story_event_id)),
		"bin_id": str(found.get("bin_id", "")),
		"layer": int(found.get("layer", -1)),
		"switches": switches,
		"done_switch": done_switch,
	}


## True when a row with these gates plays now: `switch_info` on or naming no switch,
## `open_switch` off or naming none. `is_on` reads a switch (SwitchService by default).
static func is_active(switch_info: Variant, open_switch: Variant, is_on: Callable = Callable()) -> bool:
	var reader: Callable = is_on if is_on.is_valid() else SwitchService.is_unlocked
	if not _no_switch(switch_info) and not reader.call(str(switch_info)):
		return false
	if not _no_switch(open_switch) and reader.call(str(open_switch)):
		return false
	return true


## Whether `scene` can play: its bin is in the assets and a page starts on its layer
## under its switches.
static func can_play(scene: Dictionary) -> bool:
	var bin: EventBin = _load_bin(str(scene.get("bin_id", "")))
	if bin == null:
		return false
	var layer: int = int(scene["layer"]) if int(scene["layer"]) >= 0 else bin.start_layer
	return not bin.autorun_pages(layer, scene["switches"]).is_empty()


static func _map_event_scenes(location_type: int, target_id: String, trigger: int) -> Array:
	var scenes: Array = []
	if not target_id.is_valid_int():
		return scenes
	for row in GameDatabase.get_map_events(location_type, int(target_id), trigger):
		if is_active(row.get("switchInfo"), row.get("openSwitch")):
			scenes.append(story_event_scene(str(row.get("storyEventId", "")), "", _switch_id(row.get("openSwitch"))))
	return scenes


# === Playing them ===

## Plays `scenes` in order on the cutscene screen and closes it. Returns the next
## location the scenes named ({} for none); the first scene that names one ends the run.
static func play_scenes(scenes: Array) -> Dictionary:
	var flow := StoryFlow.new()
	var next: Dictionary = {}
	for scene in scenes:
		next = await flow.play(scene)
		if not next.is_empty():
			break
	flow.close()
	return next


## Plays `scene` on the cutscene screen (opened over the current screen the first time),
## keeps the switches it set and marks it watched. Returns the next location it named.
func play(scene: Dictionary) -> Dictionary:
	var next: Dictionary = {}
	if can_play(scene):
		if _screen == null:
			UIManager.push("cutscene_ui")
			_screen = UIManager.get_current_scene() as CutsceneScreen
		if _screen != null:
			var result: Dictionary = await _screen.play(scene)
			commit_switches(scene["switches"], result["switches"])
			next = result["next_location"]
	else:
		push_warning("StoryFlow: %s (story event %s, bin %s) cannot play; counted as watched" % [
			scene.get("name", ""), scene.get("story_event_id", ""), scene.get("bin_id", "")])
	var done: int = int(scene.get("done_switch", 0))
	if done != 0:
		SwitchService.unlock_switches(str(done), "story_scene")
	return next


## Closes the cutscene screen if this flow opened it and it is still on top.
func close() -> void:
	if _screen != null and is_instance_valid(_screen) and UIManager.get_current_scene() == _screen:
		UIManager.pop()
	_screen = null


## Keeps what a scene changed: every switch that ended with another value than it
## started with, except the scene-local ones.
static func commit_switches(before: Dictionary, after: Dictionary) -> void:
	var on: PackedStringArray = []
	var off: PackedStringArray = []
	var writes: Dictionary = switch_writes(before, after, GameDatabase.get_switch_kind)
	for switch_id in writes:
		if int(writes[switch_id]) != 0:
			on.append(str(switch_id))
		else:
			off.append(str(switch_id))
	if not on.is_empty():
		SwitchService.unlock_switches(",".join(on), "story_scene")
	if not off.is_empty():
		SwitchService.lock_switches(",".join(off), "story_scene")


## The switches a scene wrote ({ id: value }): those whose value at the end differs from
## the start (a missing one counts as 0), less the ones `kind` (id -> { scope }) calls
## scene-local.
static func switch_writes(before: Dictionary, after: Dictionary, kind: Callable) -> Dictionary:
	var writes: Dictionary = {}
	for switch_id in after:
		if int(after[switch_id]) == int(before.get(switch_id, 0)):
			continue
		if int(kind.call(int(switch_id)).get("scope", -1)) == SCOPE_LOCAL:
			continue
		writes[int(switch_id)] = int(after[switch_id])
	return writes


# === Going places ===

## Goes where a scene led: a mission's battle (type 0) or a town (type 1).
static func go_to(location: Dictionary) -> void:
	var id: String = str(location.get("id", ""))
	if int(location.get("type", -1)) == TYPE_TOWN:
		await enter_town(id)
		return
	var result: Dictionary = MissionService.request_start_mission(id)
	if bool(result.get("success", false)):
		UIManager.push("combat_ui", {"mission_id": id})
	else:
		push_warning("StoryFlow: cannot start mission %s: %s" % [id, result.get("error", "")])


## Enters town `town_id` the way the story wants. Its scenes play one at a time, each
## under the switches the one before left, since a scene may start the next (Mitra's
## arrival warps to the forge, which sets the switch the next page waits for). A scene
## may lead to another town, whose scenes play in turn, or to a mission. Once nothing is
## left to play, the town opens.
static func enter_town(town_id: String) -> void:
	var flow := StoryFlow.new()
	var town: String = town_id
	var played: Dictionary = {}
	var next: Dictionary = {}
	while played.size() < MAX_SCENES_PER_VISIT:
		var scene: Dictionary = next_town_scene(town, played)
		if scene.is_empty():
			break
		next = await flow.play(scene)
		if next.is_empty():
			continue
		if int(next.get("type", -1)) != TYPE_TOWN:
			break
		town = str(next["id"])
		played.clear()
		next = {}
	flow.close()
	if not next.is_empty():
		await go_to(next)
		return
	finish_town_story(town)
	UIManager.push("town_map_ui", {"town_id": town})


## The next scene town `town_id` plays, {} when none: its map_event rows (trigger 1,
## then 3), then the page an event package starts on its start layer. `played` holds
## what this visit has played already ("story:<id>" or "<bin>|<layer>|<code hash>") and
## gains the scene returned. A main-story package missing from the assets counts as
## done (its openSwitch is set) so the story goes on.
static func next_town_scene(town_id: String, played: Dictionary) -> Dictionary:
	if not town_id.is_valid_int():
		return {}
	for trigger in [ON_ENTERING, TOWN_TRIGGER_3]:
		for scene in _map_event_scenes(LOCATION_TOWN, town_id, trigger):
			var key: String = "story:%s" % scene["story_event_id"]
			if not played.has(key):
				played[key] = true
				return scene
	for package in GameDatabase.get_town_event_packages(int(town_id)):
		if package["bin_id"] == "" or not is_active(package["switch_info"], package["open_switch"]):
			continue
		var bin: EventBin = _load_bin(package["bin_id"])
		if bin == null:
			if package["open_switch"] != 0 and _is_main_story(package["open_switch"]):
				push_warning("StoryFlow: town %s's event package %s is not in the assets; counted as done" % [town_id, package["bin_id"]])
				SwitchService.unlock_switches(str(package["open_switch"]), "story_scene")
			continue
		var switches: Dictionary = SwitchService.as_event_switches()
		var pages: Array = bin.autorun_pages(bin.start_layer, switches)
		if pages.is_empty():
			continue
		var key: String = "%s|%d|%d" % [package["bin_id"], bin.start_layer, hash((pages[0] as EventBin.Page).code)]
		if played.has(key):
			continue
		played[key] = true
		return {
			"story_event_id": "",
			"name": "town %s, event package %s" % [town_id, package["bin_id"]],
			"bin_id": package["bin_id"],
			"layer": bin.start_layer,
			"switches": switches,
			"done_switch": 0,
		}
	return {}


## A town's chapter of the story (story_sub, and the town's own openSwitch) when none
## of its event packages are in the assets: counted as done on entering, as before the
## scenes were played, so the story goes on.
static func finish_town_story(town_id: String) -> void:
	if not town_id.is_valid_int():
		return
	for package in GameDatabase.get_town_event_packages(int(town_id)):
		if package["bin_id"] != "" and is_active(package["switch_info"], package["open_switch"]) and EventBin.find_path(package["bin_id"]) != "":
			return
	var done: PackedStringArray = []
	for chapter in GameDatabase.get_story_sub(town_id):
		if is_active(chapter.get("switchInfo"), chapter.get("openSwitch")) and not _no_switch(chapter.get("openSwitch")):
			done.append(str(chapter.get("openSwitch")))
	if done.is_empty():
		return
	var town_switch: Variant = GameDatabase.get_town(town_id).get("openSwitch")
	if not _no_switch(town_switch):
		done.append(str(town_switch))
	SwitchService.unlock_switches(",".join(done), "town_story")


# === Helpers ===

static func _load_bin(bin_id: String) -> EventBin:
	if bin_id == "":
		return null
	var path: String = EventBin.find_path(bin_id)
	if path == "":
		return null
	var bin: EventBin = EventBin.load_file(path)
	return bin if bin.error == "" else null


static func _is_main_story(switch_id: int) -> bool:
	return int(GameDatabase.get_switch_kind(switch_id).get("type", -1)) in MAIN_STORY_TYPES


static func _no_switch(value: Variant) -> bool:
	if value == null:
		return true
	var text: String = str(value).strip_edges()
	return text == "" or text == "0" or text == "null"


static func _switch_id(value: Variant) -> int:
	return int(str(value)) if not _no_switch(value) and str(value).is_valid_int() else 0
