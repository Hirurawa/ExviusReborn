class_name BattleStory
extends RefCounted

## A mission's story inside its battle: the dialogue each wave plays when it starts and
## when it is cleared, and the cutscenes slotted between waves (shown as placeholder
## cards until EventRunner plays them). Ported from the old BattleManager's
## wave_dialogue_lines, _dialogue_gate_seen, _play_cutscenes_for_slot,
## _cutscene_placeholder_line and _switch_present. BattleDirector asks it what to show;
## the battle screen shows it.
##
## Session-layer code: by default it reads GameDatabase, MissionTimeline and
## SwitchService. Tests pass their own readers.

## A battle script segment's `cond`: lines shown when the wave starts, or once it is
## cleared.
const COND_START: int = 1
const COND_VICTORY: int = 2

## The mission's waves (EncounterResolver.build_wave_plan). Each entry may carry a
## `battle_script_id` (its dialogue) and a `switch_non_info` (set once the player has
## seen it). Empty for a battle group or the test battle.
var wave_plan: Array = []
## The mission's cutscenes (GameDatabase.get_mission_cutscenes): { story_event_id,
## after_wave (0 = intro, K = after wave K; after the last wave = outro), switch_info,
## switch_non_info, event_id, resource_id }.
var cutscenes: Array = []
## Callable(switch: Variant) -> bool: whether the player has that switch.
var switch_check: Callable
## Callable(battle_script_id: String) -> Array of { cond, lines: [{ speaker, text }] }.
var script_reader: Callable
## Callable(story_event_id: String) -> Dictionary { name, sceneRes }, {} when unknown.
var story_event_reader: Callable


func _init(plan: Array = [], mission_cutscenes: Array = [], switches: Callable = Callable(), scripts: Callable = Callable(), story_events: Callable = Callable()) -> void:
	wave_plan = plan
	cutscenes = mission_cutscenes
	switch_check = switches if switches.is_valid() else SwitchService.is_unlocked
	script_reader = scripts if scripts.is_valid() else MissionTimeline.parse_battle_script
	story_event_reader = story_events if story_events.is_valid() else GameDatabase.get_story_event


## The story for the params the battle scene gets: a mission's wave plan and cutscenes,
## or nothing for a battle group and the test battle (the old engine had none there).
static func for_params(params: Dictionary) -> BattleStory:
	if not params.has("mission_id"):
		return BattleStory.new()
	var mission_id: String = str(params["mission_id"])
	return BattleStory.new(EncounterResolver.build_wave_plan(mission_id), GameDatabase.get_mission_cutscenes(mission_id))


## Ordered [{ speaker, text }] lines for wave `wave_index` (1-based) and trigger `cond`
## (COND_START or COND_VICTORY), or [] when the wave has no script, the trigger has no
## lines, or the player has already seen them (the wave's first-time switch is set).
func wave_dialogue_lines(wave_index: int, cond: int) -> Array:
	if wave_index < 1 or wave_index > wave_plan.size():
		return []
	var wave: Dictionary = wave_plan[wave_index - 1]
	var script_id: String = str(wave.get("battle_script_id", ""))
	if script_id == "" or script_id == "0":
		return []
	if _gate_seen(wave.get("switch_non_info")):
		return []
	var lines: Array = []
	for segment in script_reader.call(script_id):
		if int(segment.get("cond", 0)) == cond:
			for line in segment.get("lines", []):
				lines.append(line)
	return lines


## One placeholder card ({ speaker, text }) for each cutscene slotted at `slot` (0 =
## intro, K = after wave K) that the player should see now: not seen yet, and, for a
## replay-only cutscene, active. The old engine showed each card as its own dialogue.
func cutscene_cards(slot: int) -> Array:
	var cards: Array = []
	for cut in cutscenes:
		if int(cut.get("after_wave", -1)) != slot:
			continue
		if _gate_seen(cut.get("switch_non_info")):
			continue
		var replay_switch: Variant = cut.get("switch_info")
		if switch_present(replay_switch) and not switch_check.call(replay_switch):
			continue
		cards.append(_placeholder_card(cut))
	return cards


## True when a switch field holds an active value (not null, "", "0" or "null").
static func switch_present(value: Variant) -> bool:
	if value == null:
		return false
	var text: String = str(value).strip_edges()
	return text != "" and text != "0" and text != "null"


## True when a first-time gate switch is already set: the player has seen this (the
## switch is set when the mission is cleared).
func _gate_seen(gate: Variant) -> bool:
	return switch_present(gate) and switch_check.call(gate)


## A card naming the cutscene that should play here, with its event cpk (the folder id
## EventRunner takes) and resource id.
func _placeholder_card(cut: Dictionary) -> Dictionary:
	var story_event_id: String = str(cut.get("story_event_id", ""))
	var story_event: Dictionary = story_event_reader.call(story_event_id)
	var scene_ref: String = str(story_event.get("sceneRes", ""))
	var event_id: String = str(cut.get("event_id", ""))
	var resource_id: String = str(cut.get("resource_id", ""))
	var second_line: String = "storyEvent %s" % story_event_id
	if scene_ref != "":
		second_line += "  ·  " + scene_ref
	var third_line: String = "event %s  (resource %s)" % [
		event_id if event_id != "" else "?",
		resource_id if resource_id != "" else "?",
	]
	return {
		"speaker": "🎬 CUTSCENE (placeholder)",
		"text": "%s\n%s\n%s" % [str(story_event.get("name", "?")), second_line, third_line],
	}
