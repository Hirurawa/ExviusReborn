class_name EventStage
extends Node2D

## What a cutscene draws: the map layer, the actors, the camera, the screen fade and
## flash, and the cinema window (CUTSCENE-PLAN.md sections 4.3 and 8). EventInterpreter
## drives it through the methods below; tick() advances everything one frame.
##
## World coordinates are map pixels (58 px tiles). The camera position is the centre of
## the screen and the view is 640 px wide, as the recording shows.

signal line_shown(text_id: int)

const MAP_COMMON: String = "res://assets/map_common/"
const TOWN_DATA: String = "res://assets/town_data/"
## Where the camera position is drawn, as a share of the screen height: 52.0% in the
## first recording (640 x 1107) and 51.5% in the second (640 x 917), measured by lining
## up the map. The cinema window scales the same way (EventDialogue.TOP_FRACTION).
const CAMERA_FRACTION: float = 0.517
## The flashes peaked between half and full white in the recordings.
const FLASH_ALPHA: float = 0.9

## Off in tests that only need the script's effects: building a map's tileset is slow.
@export var draw_map: bool = true

var bin: EventBin = null
var bin_id: String = ""
var layer_id: int = -1
var actors: Dictionary = {}  # key ("pc1", "e9") -> EventActor
## Text ids in the order they were shown.
var lines_shown: Array[int] = []
var dialogue: EventDialogue
var banner: EventBanner
var camera: Camera2D

var _texts: Dictionary = {}    # text id -> raw line
var _tellers: Dictionary = {}  # teller id -> display name
var _images: Dictionary = {}   # image id -> texture path
var _tile_map: Node = null
var _actor_root: Node2D
var _camera_target: Vector2 = Vector2.ZERO
var _camera_speed: float = 0.0
var _camera_moving: bool = false
var _fade: ColorRect
var _fade_from: float = 0.0
var _fade_to: float = 0.0
var _fade_frames: int = 0
var _fade_age: int = 0
var _flash: ColorRect
var _flash_frames: int = 0
var _flash_age: int = 0
var _flash_half_period: int = 1


func _ready() -> void:
	_tile_map = get_node_or_null("TileMap")
	_actor_root = Node2D.new()
	_actor_root.name = "Actors"
	_actor_root.y_sort_enabled = true
	_actor_root.z_index = 5
	add_child(_actor_root)
	camera = Camera2D.new()
	camera.name = "Camera"
	add_child(camera)
	camera.make_current()
	var screen_height: float = get_viewport().get_visible_rect().size.y
	camera.offset = Vector2(0, screen_height * (0.5 - CAMERA_FRACTION))

	var screen := CanvasLayer.new()
	screen.name = "Screen"
	screen.layer = 10
	add_child(screen)
	# The flash covers the map but not the cinema window; the fade covers both.
	_flash = _screen_rect(screen, "Flash")
	banner = EventBanner.new()
	banner.name = "Banner"
	screen.add_child(banner)
	dialogue = EventDialogue.new()
	dialogue.name = "Dialogue"
	dialogue.name_resolver = _speaker_name
	screen.add_child(dialogue)
	_fade = _screen_rect(screen, "Fade")
	_fade.color = Color.BLACK


## Loads what the bin's scenes need besides the bin: its text and teller files and the
## images its records can show.
func setup(event_bin: EventBin, id: String) -> void:
	bin = event_bin
	bin_id = id
	lines_shown.clear()
	var folder: String = bin.path.get_base_dir()
	_texts = _read_csv(folder.path_join("%s_event_text.txt" % id))
	# Teller ids are local to a town (200020 is "Villager" in Mitra), so the map's own
	# list comes before the common one, and the bin's before both.
	_tellers = _read_csv(MAP_COMMON + "common_teller.txt")
	_tellers.merge(_read_csv(TOWN_DATA + _map_id() + "/map_teller.txt"), true)
	_tellers.merge(_read_csv(folder.path_join("%s_event_teller.txt" % id)), true)
	# Image ids resolve through the bin's manifest, then the map's (record images such
	# as 20027 are mapchips of the map), then map_common/common_image.txt.
	_images.clear()
	var common: Dictionary = _read_csv(MAP_COMMON + "common_image.txt", false)
	for image_id in common:
		_images[image_id] = MAP_COMMON + str(common[image_id]).split(",")[0]
	_images.merge(_read_map_manifest(_map_id()), true)
	for marker in bin.assets:
		_images[marker] = folder.path_join(str(bin.assets[marker]))


## Shows layer `id`: draws it (when the map exists) and puts out the records whose live
## page has a graphic. Clears every actor from the previous layer.
func load_layer(id: int, switches: Dictionary) -> void:
	layer_id = id
	for actor in actors.values():
		actor.queue_free()
	actors.clear()
	_draw_map_layer(id)
	var layer: EventBin.Layer = bin.get_layer(id)
	if layer == null:
		push_warning("EventStage: bin %s has no layer %d" % [bin_id, id])
		return
	for record in layer.records:
		var page: EventBin.Page = record.active_page(switches)
		if page != null and not page.graphic.is_empty():
			record_actor(record.slot, switches)


## The party member with cast index `index` (map_character<index>.png), created on first
## use at the world origin.
func party_actor(index: int) -> EventActor:
	var key: String = "pc%d" % index
	if actors.has(key):
		return actors[key]
	var actor: EventActor = _new_actor(key)
	if not actor.use_party_sheet(index):
		push_warning("EventStage: no map_character%d.png" % index)
	return actor


## The record in `slot` on the current layer, created on first use at its own position
## with its live page's graphic (invisible when it has none).
func record_actor(slot: int, switches: Dictionary = {}) -> EventActor:
	var key: String = "e%d" % slot
	if actors.has(key):
		return actors[key]
	var actor: EventActor = _new_actor(key)
	var layer: EventBin.Layer = bin.get_layer(layer_id) if bin != null else null
	var record: EventBin.Record = layer.record_by_slot(slot) if layer != null else null
	if record != null:
		actor.position = Vector2(record.x, record.y)
		var page: EventBin.Page = record.active_page(switches)
		if page != null and not page.graphic.is_empty():
			if not actor.use_graphic(page.graphic, _images, Vector2i(record.width, record.height)):
				push_warning("EventStage: cannot draw graphic %s of record %d" % [page.graphic, slot])
	return actor


## Moves the camera so that `target` is the centre of the screen, at `speed` px per
## frame; 0 jumps.
func camera_to(target: Vector2, speed: float) -> void:
	if speed <= 0.0:
		camera.position = target
		_camera_moving = false
		return
	_camera_target = target
	_camera_speed = speed
	_camera_moving = not target.is_equal_approx(camera.position)


func camera_position() -> Vector2:
	return camera.position


## Fades the screen out to `color` or back in over `frames` frames.
func fade(fade_out: bool, color: Color, frames: int) -> void:
	_fade.color = Color(color, _fade.color.a)
	_fade_from = _fade.color.a
	_fade_to = 1.0 if fade_out else 0.0
	_fade_frames = maxi(frames, 0)
	_fade_age = 0
	if _fade_frames == 0:
		_set_fade_alpha(_fade_to)


## Starts the screen fully faded out (scenes that open with a fade-in).
func set_black() -> void:
	_fade.color = Color.BLACK
	_fade_frames = 0
	_fade_to = 1.0
	_set_fade_alpha(1.0)


func fade_alpha() -> float:
	return _fade.color.a


## `pulses` flashes of `color` over the map, each on for `half_period` frames and off
## for as many (❓ CUTSCENE-PLAN.md section 8.6).
func flash(color: Color, half_period: int, pulses: int) -> void:
	_flash.color = Color(color, 0.0)
	_flash_half_period = maxi(half_period, 1)
	_flash_frames = _flash_half_period * 2 * maxi(pulses, 1)
	_flash_age = 0
	_flash.visible = true
	_flash.color.a = FLASH_ALPHA


## The location banner of op 0x6e.
func show_banner(file_name: String, hold_frames: int) -> void:
	banner.show_banner(file_name, hold_frames)


func show_text(text_id: int) -> void:
	var raw: String = str(_texts.get(text_id, "[text %d]" % text_id))
	dialogue.show_line(text_id, raw)
	lines_shown.append(text_id)
	line_shown.emit(text_id)


func set_panel_visible(shown: bool) -> void:
	dialogue.visible = shown


func panel_visible() -> bool:
	return dialogue.visible


## A tap from the player; true when the dialogue used it.
func tap() -> bool:
	return dialogue.tap()


## One frame of every running movement and effect.
func tick() -> void:
	for actor in actors.values():
		actor.tick()
	if _camera_moving:
		var delta: Vector2 = _camera_target - camera.position
		var distance: float = delta.length()
		if distance <= _camera_speed:
			camera.position = _camera_target
			_camera_moving = false
		else:
			camera.position += delta / distance * _camera_speed
	if _fade_frames > 0 and _fade_age < _fade_frames:
		_fade_age += 1
		_set_fade_alpha(lerpf(_fade_from, _fade_to, float(_fade_age) / float(_fade_frames)))
	if _flash.visible:
		_flash_age += 1
		if _flash_age >= _flash_frames:
			_flash.visible = false
		else:
			var lit: bool = (_flash_age / _flash_half_period) % 2 == 0
			_flash.color.a = FLASH_ALPHA if lit else 0.0
	banner.tick()
	dialogue.tick()


## Anything still moving or waiting on the player: what `advance` waits for.
func is_busy() -> bool:
	if _camera_moving or _flash.visible or dialogue.is_busy():
		return true
	if _fade_frames > 0 and _fade_age < _fade_frames:
		return true
	for actor in actors.values():
		if actor.is_busy():
			return true
	return false


func _new_actor(key: String) -> EventActor:
	var actor := EventActor.new()
	actor.key = key
	actor.name = key
	_actor_root.add_child(actor)
	actors[key] = actor
	return actor


## Event bins sit on the map whose folder shares their first seven digits
## (111010105 -> 111010100).
func _map_id() -> String:
	return bin_id.substr(0, 7) + "00" if bin_id.length() >= 7 else ""


## A map.bin's texture manifest: atlas id -> path. The 32-byte header ends with the
## entry count; entries are u16 atlas id, u16 length, file name.
static func _read_map_manifest(map_id: String) -> Dictionary:
	var out: Dictionary = {}
	var map_path: String = TOWN_DATA + map_id + "/map.bin"
	if map_id == "" or not FileAccess.file_exists(map_path):
		return out
	var file := FileAccess.open(map_path, FileAccess.READ)
	file.big_endian = true
	file.seek(28)
	var count: int = file.get_32()
	for i in count:
		var atlas_id: int = file.get_16()
		var file_name: String = file.get_buffer(file.get_16()).get_string_from_ascii()
		out[atlas_id] = TOWN_DATA + map_id + "/" + file_name
	return out


func _draw_map_layer(id: int) -> void:
	if not draw_map or _tile_map == null:
		return
	var map_id: String = _map_id()
	if map_id == "" or not FileAccess.file_exists(TOWN_DATA + map_id + "/map.bin"):
		push_warning("EventStage: no map %s for bin %s" % [map_id, bin_id])
		return
	if str(_tile_map.get("town_id")) != map_id:
		_tile_map.call("load_town", map_id)
	if not bool(_tile_map.call("show_layer", id)):
		push_warning("EventStage: map %s has no layer %d" % [map_id, id])


func _set_fade_alpha(alpha: float) -> void:
	_fade.color.a = alpha
	_fade.visible = alpha > 0.0


func _speaker_name(id: int, kind: String) -> String:
	if kind == "name" and _tellers.has(id):
		return str(_tellers[id])
	var npc_name: String = GameDatabase.get_npc_name(id)
	if npc_name != "":
		return npc_name
	return str(_tellers.get(id, ""))


func _screen_rect(parent: Node, node_name: String) -> ColorRect:
	var rect := ColorRect.new()
	rect.name = node_name
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.color = Color(1, 1, 1, 0)
	rect.visible = false
	parent.add_child(rect)
	return rect


## `<int id>,<rest of the line>` files: text, teller and image lists. The text and
## teller files are UTF-8; common_image.txt carries Shift-JIS descriptions after its
## ASCII id and file name, so it is read as bytes (`utf8` false) instead of making
## Godot report an invalid UTF-8 byte.
static func _read_csv(file_path: String, utf8: bool = true) -> Dictionary:
	var out: Dictionary = {}
	if not FileAccess.file_exists(file_path):
		return out
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(file_path)
	var text: String = bytes.get_string_from_utf8() if utf8 else bytes.get_string_from_ascii()
	for line in text.split("\n"):
		var comma: int = line.find(",")
		if comma <= 0:
			continue
		var key: String = line.substr(0, comma).strip_edges()
		if key.is_valid_int():
			out[int(key)] = line.substr(comma + 1).strip_edges(false, true)
	return out
