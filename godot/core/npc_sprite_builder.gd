class_name NpcSpriteBuilder
extends RefCounted

# Builds AnimatedSprite2D nodes from 4x4 NPC spritesheets.
#   row 0 = down, row 1 = up, row 2 = left, row 3 = right
#   each row has 4 frames; all rows loop at ANIM_FPS.

const NPC_DIRS: Array[String] = ["res://assets/npc1", "res://assets/npc2"]
const ROW_NAMES: Array[String] = ["down", "up", "left", "right"]
const ANIM_FPS: float = 5.0

# Cache SpriteFrames per npc id so repeat NPCs on a map reuse the same
# resource (each AnimatedSprite2D still gets its own node).
static var _frames_cache: Dictionary = {}

# Returns an AnimatedSprite2D playing the "down" animation, or null if
# the spritesheet PNG can't be located in npc1/ or npc2/.
static func build(npc_id) -> AnimatedSprite2D:
	var id_str: String = str(int(npc_id)).strip_edges()
	if id_str == "":
		return null

	var frames: SpriteFrames = _get_or_build_frames(id_str)
	if frames == null:
		return null

	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = frames
	sprite.animation = "down"
	sprite.centered = false
	sprite.play()
	return sprite


static func _get_or_build_frames(id_str: String) -> SpriteFrames:
	if _frames_cache.has(id_str):
		return _frames_cache[id_str]

	var tex: Texture2D = _load_npc_texture(id_str)
	if tex == null:
		push_warning("NpcSpriteBuilder: no spritesheet found for npc id %s" % id_str)
		_frames_cache[id_str] = null
		return null

	var sheet_w: int = tex.get_width()
	var sheet_h: int = tex.get_height()
	if sheet_w < 4 or sheet_h < 4:
		push_warning("NpcSpriteBuilder: spritesheet too small for npc %s (%dx%d)" % [id_str, sheet_w, sheet_h])
		_frames_cache[id_str] = null
		return null

	var frame_w: int = sheet_w / 4
	var frame_h: int = sheet_h / 4

	var frames := SpriteFrames.new()
	# SpriteFrames ships with a default "default" animation we don't need.
	frames.remove_animation("default")
	for row in range(4):
		var anim_name: String = ROW_NAMES[row]
		frames.add_animation(anim_name)
		frames.set_animation_loop(anim_name, true)
		frames.set_animation_speed(anim_name, ANIM_FPS)
		for col in range(4):
			var atlas := AtlasTexture.new()
			atlas.atlas = tex
			atlas.region = Rect2(col * frame_w, row * frame_h, frame_w, frame_h)
			frames.add_frame(anim_name, atlas)

	_frames_cache[id_str] = frames
	return frames


static func _load_npc_texture(id_str: String) -> Texture2D:
	for dir_path in NPC_DIRS:
		var path: String = "%s/npc%s.png" % [dir_path, id_str]
		if ResourceLoader.exists(path):
			var res: Resource = load(path)
			if res is Texture2D:
				return res
	return null
