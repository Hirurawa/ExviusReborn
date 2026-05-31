class_name DialogueLoader
extends RefCounted

# Loads and resolves NPC dialogue lines from a town's map_text.txt /
# map_teller.txt pair. Results are cached per town id so repeat lookups
# (e.g. clicking the same NPC twice, or different NPCs sharing a town)
# don't re-parse the files.
#
# File formats (CSV split on FIRST comma only -- the text column itself
# contains commas / fullwidth commas):
#   map_text.txt   : <dialogue_line_id>,<markup-text>
#   map_teller.txt : <speaker_id>,<display-name>
#
# Markup tokens recognised in v1:
#   <name=ID> / <name_npc=ID>   substituted with map_teller display name
#   <br>                        line break
#   <page>                      page boundary
#   <keywait>                   treated as a page boundary (mid-line pauses
#                               also act as "press to continue" in v1)
# Any other tag is stripped (and logged once per unique tag in dev builds).

const TOWN_DATA_ROOT := "res://assets/town_data"

# town_id -> { "text": { int -> raw_string }, "name": { int -> string } }
static var _cache: Dictionary = {}
# Set of unknown tag names already warned about, to avoid log spam.
static var _warned_tags: Dictionary = {}


# Ensures the given town's text + teller files are parsed and cached.
# Safe to call repeatedly; no-op after first successful load.
static func load_for_town(town_id: String) -> void:
	if town_id == "" or _cache.has(town_id):
		return
	var base := TOWN_DATA_ROOT + "/" + town_id
	var text_by_id := _parse_csv_first_comma(base + "/map_text.txt")
	var name_by_id := _parse_csv_first_comma(base + "/map_teller.txt")
	_cache[town_id] = {"text": text_by_id, "name": name_by_id}


# Returns the resolved, page-split dialogue for (town_id, line_id), or
# an empty array if the line id isn't present. Each entry is a Dictionary
# of the form { "speaker": String, "body": String } -- "speaker" is empty
# when the page had no <name…> tag.
static func get_dialogue(town_id: String, dialogue_line_id) -> Array:
	load_for_town(town_id)
	if not _cache.has(town_id):
		return []
	var line_id := int(dialogue_line_id)
	var text_by_id: Dictionary = _cache[town_id]["text"]
	if not text_by_id.has(line_id):
		Log.warn("no map_text entry for id %d (town %s)" % [line_id, town_id], "DialogueLoader")
		return []
	var name_by_id: Dictionary = _cache[town_id]["name"]
	return _resolve_pages(String(text_by_id[line_id]), name_by_id)


# --- internals --------------------------------------------------------

static func _parse_csv_first_comma(path: String) -> Dictionary:
	var out: Dictionary = {}
	if not FileAccess.file_exists(path):
		Log.warn("missing file %s" % path, "DialogueLoader")
		return out
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		Log.warn("failed to open %s" % path, "DialogueLoader")
		return out
	while not f.eof_reached():
		var raw := f.get_line()
		if raw.is_empty():
			continue
		var comma := raw.find(",")
		if comma <= 0:
			continue
		var key_str := raw.substr(0, comma).strip_edges()
		if not key_str.is_valid_int():
			continue
		var value := raw.substr(comma + 1, raw.length() - comma - 1)
		out[int(key_str)] = value
	return out


# Splits a raw markup string into pages and resolves <name…> + <br>.
static func _resolve_pages(raw: String, name_by_id: Dictionary) -> Array:
	# Normalise both page-break tokens to a single sentinel before splitting.
	var s := raw.replace("<page>", "\u0001").replace("<keywait>", "\u0001")
	var pages_raw := s.split("\u0001", false)
	var pages: Array = []
	var last_speaker := ""
	for p in pages_raw:
		var page_text: String = String(p)
		if page_text.strip_edges().is_empty():
			continue
		var speaker := ""
		var body := page_text
		# Pull the FIRST <name=ID> or <name_npc=ID> out into the speaker
		# field. Subsequent name tags (rare) are left inline-resolved.
		var first_name := _extract_first_name_tag(body)
		if first_name.id != -1:
			speaker = String(name_by_id.get(first_name.id, "[name:%d]" % first_name.id))
			body = body.substr(0, first_name.start) + body.substr(first_name.end, body.length() - first_name.end)
		# Pages produced by <page>/<keywait> splits don't repeat the
		# <name…> tag; carry the most recent speaker forward so the
		# header stays visible across the whole dialogue.
		if speaker.is_empty():
			speaker = last_speaker
		else:
			last_speaker = speaker
		# Resolve any remaining inline name tags (defensive -- usually none).
		body = _resolve_inline_names(body, name_by_id)
		# <br> -> newline.
		body = body.replace("<br>", "\n")
		# Strip any leftover unknown tags (e.g. <wait>, <color=…>) to avoid
		# leaking raw markup to the UI.
		body = _strip_unknown_tags(body)
		body = body.strip_edges()
		if body.is_empty() and speaker.is_empty():
			continue
		pages.append({"speaker": speaker, "body": body})
	return pages


# Finds the first <name=ID> or <name_npc=ID> in `s` and returns
# { id, start, end } where [start, end) is the span to remove. id is -1
# if no name tag exists.
static func _extract_first_name_tag(s: String) -> Dictionary:
	var re := RegEx.new()
	re.compile("<name(?:_npc)?=(\\d+)>")
	var m := re.search(s)
	if m == null:
		return {"id": -1, "start": 0, "end": 0}
	return {
		"id": int(m.get_string(1)),
		"start": m.get_start(),
		"end": m.get_end(),
	}


static func _resolve_inline_names(s: String, name_by_id: Dictionary) -> String:
	var re := RegEx.new()
	re.compile("<name(?:_npc)?=(\\d+)>")
	# RegEx.sub doesn't support a callback in GDScript, so iterate manually.
	var result := s
	while true:
		var m := re.search(result)
		if m == null:
			break
		var nid := int(m.get_string(1))
		var replacement := String(name_by_id.get(nid, "[name:%d]" % nid))
		result = result.substr(0, m.get_start()) + replacement + result.substr(m.get_end(), result.length() - m.get_end())
	return result


# Strips any <…> tag not already handled. Logs unknown tag names once.
static func _strip_unknown_tags(s: String) -> String:
	var re := RegEx.new()
	re.compile("<([^>]+)>")
	var result := s
	while true:
		var m := re.search(result)
		if m == null:
			break
		var tag_inner := m.get_string(1)
		var tag_name := tag_inner.split("=", true, 1)[0].strip_edges().to_lower()
		if not _warned_tags.has(tag_name):
			_warned_tags[tag_name] = true
			Log.warn("stripping unknown tag <%s>" % tag_inner, "DialogueLoader")
		result = result.substr(0, m.get_start()) + result.substr(m.get_end(), result.length() - m.get_end())
	return result
