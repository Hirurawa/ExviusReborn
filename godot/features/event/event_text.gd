class_name EventText
extends RefCounted

## One line of a cutscene's <bin>_event_text.txt, split into what the dialogue window
## plays (CUTSCENE-PLAN.md section 8.4).
##
## A raw line looks like
##   <name=100000><br>Is that...<wait=20>a crystal!?<wait=90>
## The first <name=ID> or <name_npc=ID> is the speaker; a <br> right after it (and any
## before it) only separates the name plate from the text. What remains becomes pages
## of tokens:
##   {"text": String}   characters to reveal
##   {"wait": frames}   pause the reveal (at the end of a page: delay the tap cursor)
##   {"speed": n}       reveal speed from here on (bigger is slower)
## <br> is a newline inside a text token; <page> and <keywait> end a page.
## <invalid_touchwait> marks a line that ends on its own after its last wait (❓).

var speaker_id: int = -1
## "name" (the teller files) or "name_npc" (the npc table).
var speaker_kind: String = ""
var pages: Array = []  # of Array of token dictionaries
var auto_close: bool = false

static var _tag_regex: RegEx


static func parse(raw: String) -> EventText:
	var line := EventText.new()
	line._parse(raw)
	return line


## The visible text of a page, waits and speed changes left out.
static func page_text(page: Array) -> String:
	var text: String = ""
	for token in page:
		if token.has("text"):
			text += String(token["text"])
	return text


func _parse(raw: String) -> void:
	if _tag_regex == null:
		_tag_regex = RegEx.new()
		_tag_regex.compile("<([a-z_]+)(?:=([^>]*))?>")
	var page: Array = []
	var at: int = 0
	var before_speaker: bool = true
	var after_speaker: bool = false
	for found in _tag_regex.search_all(raw):
		var plain: String = raw.substr(at, found.get_start() - at)
		at = found.get_end()
		if plain != "":
			_add_text(page, plain)
			before_speaker = false
			after_speaker = false
		var tag: String = found.get_string(1)
		var value: String = found.get_string(2)
		match tag:
			"name", "name_npc":
				if speaker_id < 0 and value.is_valid_int():
					speaker_id = int(value)
					speaker_kind = tag
					after_speaker = true
			"br":
				if before_speaker or after_speaker:
					after_speaker = false
				else:
					_add_text(page, "\n")
			"wait":
				page.append({"wait": int(value)})
			"speed":
				page.append({"speed": int(value)})
			"page", "keywait":
				pages.append(page)
				page = []
			"invalid_touchwait":
				auto_close = true
			_:
				pass  # valid_touchwait and anything unknown: nothing to show
	_add_text(page, raw.substr(at))
	if not page.is_empty() or pages.is_empty():
		pages.append(page)


## Appends `text` to the page, merging with a text token right before it. The data's
## full-width comma stands for ", " (the recording shows "As a knight of Grandshelt,").
func _add_text(page: Array, text: String) -> void:
	if text == "":
		return
	text = text.replace("，", ", ").replace("　", " ")
	if not page.is_empty() and page[-1].has("text"):
		page[-1]["text"] = String(page[-1]["text"]) + text
	else:
		page.append({"text": text})
