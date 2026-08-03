class_name MissionTimeline
extends RefCounted

## Turns a mission's raw phases (GameDatabase.get_mission_timeline) into an
## ordered list of typed, switch-gated STORY STEPS -- the GDScript port of the
## datamine analysis in processed/story_timeline.py.
##
## Each step is one of:
##   CUTSCENE         -- condInfoStr == 1; targetId is a storyEventId (event cpk)
##   BATTLE_DIALOGUE  -- a battle wave that carries in-combat dialogue (battleScriptId)
##   BATTLE_WAVE      -- a plain combat wave (monsters only)
##
## Gating (mirrors the engine's first-time / replay rule against SwitchService):
##   switchNonInfo set & player HAS it      -> skip  (first-time-only, already seen)
##   switchInfo    set & player LACKS it    -> skip  (replay variant, not active yet)
##   otherwise                              -> keep
##
## Usage:
##   var steps := MissionTimeline.build(mission_id)            # runtime, gated
##   print(MissionTimeline.to_text(mission_id))                # full view, for verifying vs the video

const KIND_CUTSCENE := "CUTSCENE"
const KIND_BATTLE_DIALOGUE := "BATTLE_DIALOGUE"
const KIND_BATTLE_WAVE := "BATTLE_WAVE"

## P_COND trigger names (decoded from dialogue context in the datamine).
const COND_NAMES := {
	1: "on battle start",
	2: "on wave cleared",
	3: "on enemy defeated",
	4: "on HP threshold",
	5: "on state",
	6: "special",
	7: "on hit / reaction",
	8: "on turn / action",
	10: "passive AI hook",
}


## Ordered story steps for a mission. When apply_gating is true the player's
## SwitchService state decides which first-time/replay phases are included.
static func build(mission_id: String, apply_gating: bool = true) -> Array:
	var steps: Array = []
	for p in GameDatabase.get_mission_timeline(mission_id):
		var non_info: Variant = p.get("switchNonInfo")
		var info: Variant = p.get("switchInfo")
		if apply_gating:
			if _gated(non_info) and SwitchService.is_unlocked(non_info):
				continue  # first-time-only content, already seen
			if _gated(info) and not SwitchService.is_unlocked(info):
				continue  # replay variant, not active yet

		var step: Dictionary = {
			"phaseNum": int(p.get("phaseNum", 0)),
			"targetId": str(p.get("targetId", "")),
		}
		var script_id: Variant = p.get("battleScriptId")
		if int(p.get("condInfoStr", 2)) == 1:
			step["kind"] = KIND_CUTSCENE
			step["storyEventId"] = str(p.get("targetId", ""))
		elif _gated(script_id):
			step["kind"] = KIND_BATTLE_DIALOGUE
			step["battleScriptId"] = str(script_id)
			step["dialogue"] = parse_battle_script(str(script_id))
		else:
			step["kind"] = KIND_BATTLE_WAVE

		if _gated(non_info):
			step["firstTimeGate"] = str(non_info)
		if _gated(info):
			step["replayGate"] = str(info)
		steps.append(step)
	return steps


## In-combat dialogue for a battleScriptId, as trigger-segments:
##   [{cond, trigger, condParam, skipFlg, lines: [{speaker, text}]}]
static func parse_battle_script(battle_script_id: String) -> Array:
	var segments: Array = []
	for row in GameDatabase.get_battle_script(battle_script_id):
		var cond: int = int(row.get("cond", 0))
		segments.append({
			"cond": cond,
			"trigger": COND_NAMES.get(cond, "cond %d" % cond),
			"condParam": row.get("condParam"),
			"skipFlg": int(row.get("skipFlg", 0)),
			"lines": _parse_param(row.get("paramEn")),
		})
	return segments


## Parse one EN dialogue param string (|-delimited, quoted; caret already
## collapsed at import) into ordered {speaker, text} lines. Non-dialogue tokens
## (waits, "none", tap-target coords) are skipped.
static func _parse_param(param_en: Variant) -> Array:
	var out: Array = []
	if param_en == null:
		return out
	var s: String = str(param_en)
	if s.strip_edges() == "":
		return out
	var rx := RegEx.new()
	# speakerId , name(quoted or a bare space) , "text"
	rx.compile("^\\s*(-?\\d+),(.*?),\"(.*)\"\\s*$")
	for token in s.split("|"):
		var m: RegExMatch = rx.search(token)
		if m == null:
			continue
		var name: String = m.get_string(2).strip_edges()
		if name.begins_with("\"") and name.ends_with("\"") and name.length() >= 2:
			name = name.substr(1, name.length() - 2)
		name = name.strip_edges()
		var text: String = _clean(m.get_string(3))
		if text == "":
			continue
		out.append({
			"speaker": name if name != "" else "(system)",
			"text": text,
		})
	return out


## Strip FFBE markup so the line is display-ready.
static func _clean(t: String) -> String:
	var s: String = t.replace("<br>", " ").replace("<page>", " ").replace("<keywait>", "")
	var rx := RegEx.new()
	rx.compile("<[^>]+>")  # <wait=N>, <name=..>, <speed=..>, ...
	s = rx.sub(s, "", true)
	return s.strip_edges()


## True when a switch/script field is an active value (not null/""/"0"/"null").
static func _gated(v: Variant) -> bool:
	if v == null:
		return false
	var s: String = str(v).strip_edges()
	return s != "" and s != "0" and s != "null"


## Human-readable dump of the whole (ungated) timeline -- mirrors story_timeline.py.
## Print this in Godot and diff it against the gameplay video.
static func to_text(mission_id: String) -> String:
	var out: String = "MISSION %s\n" % mission_id
	for step in build(mission_id, false):
		var tag: String = ""
		if step.has("battleScriptId"):
			tag = "  (script %s)" % step["battleScriptId"]
		elif step.has("storyEventId"):
			tag = "  (storyEvent %s)" % step["storyEventId"]
		if step.has("firstTimeGate"):
			tag += "  [first-time-only, gate %s]" % step["firstTimeGate"]
		elif step.has("replayGate"):
			tag += "  [replay variant, gate %s]" % step["replayGate"]
		out += "[Phase %d] %s%s\n" % [step["phaseNum"], step["kind"], tag]
		for seg in step.get("dialogue", []):
			if (seg["lines"] as Array).is_empty():
				continue
			var cp: Variant = seg["condParam"]
			var cp_txt: String = ""
			if cp != null and str(cp) != "" and str(cp) != "none":
				cp_txt = "  param=%s" % str(cp)
			out += "    - %s%s:\n" % [seg["trigger"], cp_txt]
			for ln in seg["lines"]:
				out += "        %s: %s\n" % [ln["speaker"], ln["text"]]
	return out
