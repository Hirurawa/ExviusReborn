class_name EventBin
extends RefCounted

## A parsed *_event.bin: the cutscene data of one event cpk (CUTSCENE-PLAN.md section 2).
##
## Everything is big endian and every length is stored, so nothing is guessed; all 502
## bins in the dump parse to their exact sizes. The file is a header, an asset manifest
## and one block per map layer. A block holds the layer's collision grid and its entity
## records; a record holds one or more pages; a page holds a graphic, the switch
## conditions under which it is live, a label table and a script.
##
##   header       u32 file size, u32 version, u32 start layer, 2 or 3 u32 (unknown),
##                u32 asset count (the third unknown word exists from version 1023)
##   manifest     asset count x (u16 marker, u16 length, ascii file name)
##   u16 block count, then blocks to the end of the file:
##   block        u32 size, u16 layer id, u32 width, u32 height, width x height bytes of
##                collision, u16 record count, the records back to back
##   record       id (u32 200000 + slot; u16 0x0d40 + slot before version 1025), u8 type,
##                u32 x, u32 y, u16 w, u16 h, i16, u16, u16, u16 (map.bin's entity header),
##                u16 priority, (2 bytes from version 1046), u8 page count, the pages
##   page         u8 graphic flag, the graphic block, u8 condition count,
##                count x (u32 switch, u8 value), u8 label count, count x u16 offset,
##                u32 script length, the script

const RID_BASE: int = 200000
const OLD_RID_BASE: int = 0x0d40
## Byte 1 of a graphic-less page's 4-byte block. 4 on every scene a story event selects.
const TRIGGER_AUTORUN: int = 4

const TOWN_DATA_ROOT: String = "res://assets/town_data"


class Layer:
	extends RefCounted
	var id: int = 0
	var width: int = 0
	var height: int = 0
	var collision: PackedByteArray = PackedByteArray()
	var records: Array = []  # of EventBin.Record

	func record_by_slot(slot: int) -> Record:
		for record in records:
			if record.slot == slot:
				return record
		return null


class Record:
	extends RefCounted
	var rid: int = 0
	var slot: int = 0
	## 1 character, 0 object or invisible script holder; 15 to 31 are rare special kinds.
	var type: int = 0
	var x: int = 0
	var y: int = 0
	var width: int = 0
	var height: int = 0
	var priority: int = 0
	var pages: Array = []  # of EventBin.Page

	## The live page under `switches`: the last one whose conditions all hold (the
	## RPG Maker convention; only 20 records in the dump have a second page). null when
	## none holds.
	func active_page(switches: Dictionary) -> Page:
		for i in range(pages.size() - 1, -1, -1):
			var page: Page = pages[i]
			if page.matches(switches):
				return page
		return null


class Page:
	extends RefCounted
	## {} for none, {"character": id}, {"image": id, "src_x": px, "src_y": px} or
	## {"effect": file name}.
	var graphic: Dictionary = {}
	## Byte 1 of the 4-byte block on graphic-less pages, -1 on pages with a graphic
	## (where that block's position is not known yet).
	var trigger: int = -1
	var conditions: Array = []  # [switch id, value] pairs
	var labels: PackedInt32Array = PackedInt32Array()
	var code: PackedByteArray = PackedByteArray()

	## Every condition holds; a switch missing from `switches` counts as 0.
	func matches(switches: Dictionary) -> bool:
		for condition in conditions:
			if int(switches.get(condition[0], 0)) != int(condition[1]):
				return false
		return true


var path: String = ""
var version: int = 0
## The layer a scene starts on when its story event does not name one (header word 2).
var start_layer: int = -1
var header_words: PackedInt32Array = PackedInt32Array()
var assets: Dictionary = {}  # manifest marker -> file name
var layers: Dictionary = {}  # layer id -> EventBin.Layer
## [layer id, bytes] for blocks whose records run past their stated size.
var size_mismatches: Array = []
var error: String = ""

var _bytes: PackedByteArray
var _pos: int = 0


## Reads and parses `file_path`. Check `error` on the result.
static func load_file(file_path: String) -> EventBin:
	var bin := EventBin.new()
	bin.path = file_path
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(file_path)
	if bytes.is_empty():
		bin.error = "cannot read %s" % file_path
		return bin
	bin.parse(bytes)
	return bin


## Where the bin for `bin_id` lives: res://assets/town_data/<folder>/<bin_id>_event.bin.
## 136 bins also sit in another event's folder (PARSER-NOTES.md section 1), and such a
## copy can be an older build (112010102/112010101_event.bin is version 1019, the one in
## 112010101 is 1041), so the bin's own folder wins and the scan is only a fallback.
## "" when there is no such bin.
static func find_path(bin_id: String) -> String:
	var direct: String = "%s/%s/%s_event.bin" % [TOWN_DATA_ROOT, bin_id, bin_id]
	if FileAccess.file_exists(direct):
		return direct
	var dir: DirAccess = DirAccess.open(TOWN_DATA_ROOT)
	if dir == null:
		return ""
	for folder in dir.get_directories():
		var candidate: String = "%s/%s/%s_event.bin" % [TOWN_DATA_ROOT, folder, bin_id]
		if FileAccess.file_exists(candidate):
			return candidate
	return ""


## Bytes of an actor reference in a script: a kind byte, then the id as a u32 (u16
## before version 1025, when record ids were u16 too).
func actor_ref_size() -> int:
	return 5 if version >= 1025 else 3


## Slot of a record id as scripts store it.
func slot_of_rid(rid: int) -> int:
	return rid - (RID_BASE if version >= 1025 else OLD_RID_BASE)


func get_layer(layer_id: int) -> Layer:
	return layers.get(layer_id)


## The pages that start on their own on `layer_id` under `switches`, in record order:
## each record's live page when its trigger is TRIGGER_AUTORUN and it has a script.
func autorun_pages(layer_id: int, switches: Dictionary) -> Array:
	var found: Array = []
	var layer: Layer = layers.get(layer_id)
	if layer == null:
		return found
	for record in layer.records:
		var page: Page = record.active_page(switches)
		if page != null and page.trigger == TRIGGER_AUTORUN and not page.code.is_empty():
			found.append(page)
	return found


func parse(bytes: PackedByteArray) -> void:
	_bytes = bytes
	_pos = 0
	if not _need(8):
		return
	_pos += 4  # file size: 6 bytes short in 183030102, whose blocks still end at the end of the file
	version = _u32()
	var word_count: int = 5 if version >= 1023 else 4
	if not _need(4 * word_count):
		return
	for i in word_count:
		header_words.append(_u32())
	start_layer = header_words[0]
	var asset_count: int = header_words[word_count - 1]
	for i in asset_count:
		if not _need(4):
			return
		var marker: int = _u16()
		var length: int = _u16()
		if not _need(length):
			return
		assets[marker] = _bytes.slice(_pos, _pos + length).get_string_from_ascii()
		_pos += length
	if not _need(2):
		return
	_pos += 2  # block count; the chain is walked to the end of the file instead
	while _pos < _bytes.size() and error == "":
		_parse_block()
	_bytes = PackedByteArray()


func _parse_block() -> void:
	var start: int = _pos
	if not _need(14):
		return
	var size: int = _u32()
	var layer := Layer.new()
	layer.id = _u16()
	layer.width = _u32()
	layer.height = _u32()
	var cells: int = layer.width * layer.height
	if size < 14 or start + size > _bytes.size() or not _need(cells + 2):
		_fail("block at %d does not fit" % start)
		return
	layer.collision = _bytes.slice(_pos, _pos + cells)
	_pos += cells
	var count: int = _u16()
	for i in count:
		var record: Record = _parse_record()
		if record == null:
			return
		layer.records.append(record)
	if _pos != start + size:
		# 183030102's layer 3 holds 6 bytes more than its size (and the file size) say,
		# and the next block starts where its records end. The records are the stronger
		# evidence; anything else going wrong here shows up as a parse error next block.
		if _pos < start + size:
			_fail("layer %d ends at %d, its size says %d" % [layer.id, _pos, start + size])
			return
		size_mismatches.append([layer.id, _pos - (start + size)])
	layers[layer.id] = layer


func _parse_record() -> Record:
	var record := Record.new()
	var wide: bool = version >= 1025
	if not _need(25 if wide else 23):
		return null
	record.rid = _u32() if wide else _u16()
	record.slot = slot_of_rid(record.rid)
	record.type = _u8()
	record.x = _u32()
	record.y = _u32()
	record.width = _u16()
	record.height = _u16()
	_pos += 8  # collision offset, interaction height, sprite height and width
	if not _need(3):
		return null
	record.priority = _u16()
	if version >= 1046:
		if not _need(2):
			return null
		_pos += 2
	if not _need(1):
		return null
	var page_count: int = _u8()
	for i in page_count:
		var page: Page = _parse_page(record.type)
		if page == null:
			return null
		record.pages.append(page)
	return record


func _parse_page(record_type: int) -> Page:
	var page := Page.new()
	if not _need(1):
		return null
	var flag: int = _u8()
	if flag == 0:
		if not _need(4):
			return null
		page.trigger = _bytes[_pos + 1]
		_pos += 4
	elif flag == 1:
		if not _parse_graphic(page, record_type):
			return null
	else:
		_fail("graphic flag %d at %d" % [flag, _pos - 1])
		return null
	if not _need(1):
		return null
	var condition_count: int = _u8()
	if not _need(5 * condition_count + 1):
		return null
	for i in condition_count:
		var switch_id: int = _u32()
		page.conditions.append([switch_id, _u8()])
	var label_count: int = _u8()
	if not _need(2 * label_count + 4):
		return null
	for i in label_count:
		page.labels.append(_u16())
	var length: int = _u32()
	if not _need(length):
		return null
	page.code = _bytes.slice(_pos, _pos + length)
	_pos += length
	return page


## The graphic block grew a byte at version 1037 and another at 1045: 19 to 21 bytes
## for a character, 17 to 19 for an image. An image id of 0 is an effect file instead
## (map_bahamut_awakening.bmb, two records), followed by 18 bytes.
func _parse_graphic(page: Page, record_type: int) -> bool:
	var extra: int = 2 if version >= 1045 else (1 if version >= 1037 else 0)
	if record_type == 1:
		if not _need(19 + extra):
			return false
		page.graphic = {"character": EventBin.u32(_bytes, _pos)}
		_pos += 19 + extra
		return true
	if not _need(2):
		return false
	var image_id: int = EventBin.u16(_bytes, _pos)
	if image_id == 0:
		if not _need(6):
			return false
		var length: int = EventBin.u16(_bytes, _pos + 4)
		if not _need(6 + length + 18):
			return false
		page.graphic = {"effect": _bytes.slice(_pos + 6, _pos + 6 + length).get_string_from_ascii()}
		_pos += 6 + length + 18
		return true
	if not _need(17 + extra):
		return false
	page.graphic = {
		"image": image_id,
		"src_x": EventBin.u16(_bytes, _pos + 2),
		"src_y": EventBin.u16(_bytes, _pos + 4),
	}
	_pos += 17 + extra
	return true


func _need(count: int) -> bool:
	if error != "":
		return false
	if _pos + count > _bytes.size():
		_fail("needs %d bytes at %d, the file has %d" % [count, _pos, _bytes.size()])
		return false
	return true


func _fail(message: String) -> void:
	if error == "":
		error = "%s: %s" % [path.get_file(), message]


func _u8() -> int:
	_pos += 1
	return _bytes[_pos - 1]


func _u16() -> int:
	_pos += 2
	return EventBin.u16(_bytes, _pos - 2)


func _u32() -> int:
	_pos += 4
	return EventBin.u32(_bytes, _pos - 4)


# --- big-endian reads, shared with EventInterpreter ---------------------------

static func u16(bytes: PackedByteArray, at: int) -> int:
	return (bytes[at] << 8) | bytes[at + 1]


static func s16(bytes: PackedByteArray, at: int) -> int:
	var value: int = EventBin.u16(bytes, at)
	return value - 0x10000 if value >= 0x8000 else value


static func u32(bytes: PackedByteArray, at: int) -> int:
	return (bytes[at] << 24) | (bytes[at + 1] << 16) | (bytes[at + 2] << 8) | bytes[at + 3]


static func s32(bytes: PackedByteArray, at: int) -> int:
	var value: int = EventBin.u32(bytes, at)
	return value - 0x100000000 if value >= 0x80000000 else value
