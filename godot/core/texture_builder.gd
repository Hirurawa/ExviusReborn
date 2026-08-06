class_name TextureBuilder
extends RefCounted

# Victory pose animations. They live in their own spritesheet folders next to the
# combat ones, so they load through the same path pattern as "idle"/"atk".
const WIN_BEFORE_ANIM: String = "win_before"
const WIN_ANIM: String = "win"

# Resting poses that stand in for "idle" once a unit is hurt badly enough.
const DYING_ANIM: String = "dying"
const DEAD_ANIM: String = "dead"

# The limit burst sheets are the one case where the folder and the file suffix
# disagree: assets/unit_spritesheets/limit/<id>-limit_atk.rawpng.
const LIMIT_ATK_ANIM: String = "limit_atk"
const LIMIT_ATK_FOLDER: String = "limit"

## `folder` defaults to `anim_name`, which is how every sheet but limit_atk is
## laid out. Pass it explicitly when the two disagree.
static func load_unit_animation_data(unit_id: String, anim_name: String = "atk", folder: String = "") -> Dictionary:
	var dir_name: String = folder if folder != "" else anim_name
	var png_path: String = "res://assets/unit_spritesheets/%s/%s-%s.rawpng" % [dir_name, unit_id, anim_name]
	var json_path: String = "res://assets/unit_spritesheets/%s/%s-%s.json" % [dir_name, unit_id, anim_name]
	return _load_animation_data_internal(png_path, json_path)

## Both halves of a unit's victory pose: the one-shot "win_before" lead-in and the
## looping "win" pose. Either entry is {} when that spritesheet is missing.
static func load_unit_win_animations(unit_id: String) -> Dictionary:
	return {
		WIN_BEFORE_ANIM: load_unit_animation_data(unit_id, WIN_BEFORE_ANIM),
		WIN_ANIM: load_unit_animation_data(unit_id, WIN_ANIM)
	}

## The two low-HP resting poses. Either entry is {} when that spritesheet is
## missing, in which case the caller is expected to fall back to plain idle.
static func load_unit_hp_state_animations(unit_id: String) -> Dictionary:
	return {
		DYING_ANIM: load_unit_animation_data(unit_id, DYING_ANIM),
		DEAD_ANIM: load_unit_animation_data(unit_id, DEAD_ANIM)
	}

static func load_monster_animation_data(monster_id: String, anim_name: String = "atk") -> Dictionary:
	var png_path: String = "res://assets/monster_spritesheets/%s/%s-%s.rawpng" % [anim_name, monster_id, anim_name]
	var json_path: String = "res://assets/monster_spritesheets/%s/%s-%s.json" % [anim_name, monster_id, anim_name]
	return _load_animation_data_internal(png_path, json_path)

static func _load_animation_data_internal(png_path: String, json_path: String) -> Dictionary:
	if not FileAccess.file_exists(png_path) or not FileAccess.file_exists(json_path):
		return {}

	var file: FileAccess = FileAccess.open(json_path, FileAccess.READ)
	if not file:
		return {}

	var json_text: String = file.get_as_text()
	var json_data: Variant = JSON.parse_string(json_text)
	if typeof(json_data) != TYPE_DICTIONARY:
		return {}

	var frame_rect: Dictionary = json_data.get("frameRect", {})
	var image_width: int = json_data.get("imageWidth", 0)
	var frame_width: int = frame_rect.get("width", 0)
	var frame_height: int = frame_rect.get("height", 0)

	if frame_width <= 0 or image_width <= 0:
		return {}

	var file_bytes: PackedByteArray = FileAccess.get_file_as_bytes(png_path)
	var image: Image = Image.new()
	var err: Error = image.load_png_from_buffer(file_bytes)
	if err != OK:
		return {}

	@warning_ignore("integer_division")
	var num_frames: int = image_width / frame_width
	var frames: Array[Texture2D] = []

	for i in range(num_frames):
		var x: int = i * frame_width
		var region: Image = image.get_region(Rect2i(x, 0, frame_width, frame_height))
		frames.append(ImageTexture.create_from_image(region))

	var frame_delays: Array = json_data.get("frameDelays", [])

	return {
		"frames": frames,
		"delays": frame_delays,
		"frame_width": frame_width,
		"frame_height": frame_height,
		"num_frames": num_frames
	}
