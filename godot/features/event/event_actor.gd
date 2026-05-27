extends Node2D
class_name EventActor

# One on-stage actor in a running event. Wraps an AnimatedSprite2D
# whose SpriteFrames are built at runtime from ANIM_REGIONS (the
# uniform 64x64 grid layout shared by every map_characterN.png sheet --
# extracted verbatim from player.tscn). The source PNG is swapped per
# actor: PC slot N -> map_characterN.png. Provides tween-driven
# move / face / visibility helpers used by event_runner.gd.

const PLACEHOLDER_SIZE := 32
const PLACEHOLDER_PARTY_COLOR := Color(0.3, 0.7, 1.0, 0.9)
const PLACEHOLDER_NPC_COLOR := Color(0.9, 0.6, 0.3, 0.9)
const TILE_SIZE := 58.0
const FRAMES_PER_SECOND := 60.0
const MAP_COMMON_PATH := "res://assets/map_common/"
const ANIM_FPS := 5.0
# Character sprites are rendered at 2x. The in-game placement anchors
# at the TOP-LEFT of the unscaled 64x64 cell rather than at the feet,
# so we disable AnimatedSprite2D.centered and offset the sprite by
# (-32, -32) -- the same spot the top-left of an un-scaled, centered
# sprite would have occupied. Scaling then grows the sprite down-right
# from that anchor, matching how the original engine positions actors.
const SPRITE_SCALE := 2.0
const SPRITE_OFFSET := Vector2(-32, -32)

# Emoticon bubble atlas (`map_common/emotion_icon.png`). 2 cols x 12
# rows of 64x64 cells; the two columns are the two animation frames
# of a single emote, rows index by (bubble_id - 1).
const EMOTION_ATLAS_PATH := MAP_COMMON_PATH + "emotion_icon.png"
const EMOTION_CELL := 64
const EMOTION_FRAME_COUNT := 2
const EMOTION_FPS := 4.0
# Bubble sits just above the (scaled) sprite. With top-left anchor at
# (-32, -32) and scale 2x the sprite spans x: -32..96, y: -32..96, so
# the head's horizontal centre is at x=32 (not x=0).
const BUBBLE_OFFSET := Vector2(32, -48)

# (pose, facing) -> animation name in ANIM_REGIONS. The .bin only
# encodes 4 cardinals so diagonals aren't reachable from event data;
# the diagonal anims still exist in ANIM_REGIONS if we ever need them.
const POSE_FACING_TO_ANIM := {
	"idle": {"down": "idle_down", "up": "idle_up", "left": "idle_left", "right": "idle_right"},
	"walk": {"down": "walk_down", "up": "walk_up", "left": "walk_left", "right": "walk_right"},
	"run":  {"down": "run_down",  "up": "run_up",  "left": "run_left",  "right": "run_right"},
}

# Animation regions for every map_characterN.png sheet (uniform 64x64
# grid). Extracted verbatim from player.tscn -- if that atlas layout
# ever changes, regenerate this dict from the SpriteFrames sub-resource
# rather than hand-editing.
const ANIM_REGIONS := {
	"idle_down": [Rect2(0, 0, 64, 64)],
	"idle_down_left": [Rect2(0, 256, 64, 64)],
	"idle_down_right": [Rect2(0, 320, 64, 64)],
	"idle_left": [Rect2(0, 128, 64, 64)],
	"idle_right": [Rect2(0, 192, 64, 64)],
	"idle_up": [Rect2(0, 64, 64, 64)],
	"idle_up_left": [Rect2(0, 384, 64, 64)],
	"idle_up_right": [Rect2(0, 448, 64, 64)],
	"run_down": [Rect2(64, 512, 64, 64), Rect2(128, 512, 64, 64), Rect2(192, 512, 64, 64), Rect2(256, 512, 64, 64), Rect2(320, 512, 64, 64), Rect2(384, 512, 64, 64)],
	"run_down_left": [Rect2(64, 768, 64, 64), Rect2(128, 768, 64, 64), Rect2(192, 768, 64, 64), Rect2(256, 768, 64, 64), Rect2(320, 768, 64, 64), Rect2(384, 768, 64, 64)],
	"run_down_right": [Rect2(64, 832, 64, 64), Rect2(128, 832, 64, 64), Rect2(192, 832, 64, 64), Rect2(256, 832, 64, 64), Rect2(320, 832, 64, 64), Rect2(384, 832, 64, 64)],
	"run_left": [Rect2(64, 640, 64, 64), Rect2(128, 640, 64, 64), Rect2(192, 640, 64, 64), Rect2(256, 640, 64, 64), Rect2(320, 640, 64, 64), Rect2(384, 640, 64, 64)],
	"run_right": [Rect2(64, 704, 64, 64), Rect2(128, 704, 64, 64), Rect2(192, 704, 64, 64), Rect2(256, 704, 64, 64), Rect2(320, 704, 64, 64), Rect2(384, 704, 64, 64)],
	"run_up": [Rect2(64, 576, 64, 64), Rect2(128, 576, 64, 64), Rect2(192, 576, 64, 64), Rect2(256, 576, 64, 64), Rect2(320, 576, 64, 64), Rect2(384, 576, 64, 64)],
	"run_up_left": [Rect2(64, 896, 64, 64), Rect2(128, 896, 64, 64), Rect2(192, 896, 64, 64), Rect2(256, 896, 64, 64), Rect2(320, 896, 64, 64), Rect2(384, 896, 64, 64)],
	"run_up_right": [Rect2(64, 960, 64, 64), Rect2(128, 960, 64, 64), Rect2(192, 960, 64, 64), Rect2(256, 960, 64, 64), Rect2(320, 960, 64, 64), Rect2(384, 960, 64, 64)],
	"walk_down": [Rect2(64, 1024, 64, 64), Rect2(128, 1024, 64, 64), Rect2(192, 1024, 64, 64), Rect2(256, 1024, 64, 64), Rect2(320, 1024, 64, 64), Rect2(384, 1024, 64, 64)],
	"walk_down_left": [Rect2(64, 1280, 64, 64), Rect2(128, 1280, 64, 64), Rect2(192, 1280, 64, 64), Rect2(256, 1280, 64, 64), Rect2(320, 1280, 64, 64), Rect2(384, 1280, 64, 64)],
	"walk_down_right": [Rect2(64, 1344, 64, 64), Rect2(128, 1344, 64, 64), Rect2(192, 1344, 64, 64), Rect2(256, 1344, 64, 64), Rect2(320, 1344, 64, 64), Rect2(384, 1344, 64, 64)],
	"walk_left": [Rect2(64, 1152, 64, 64), Rect2(128, 1152, 64, 64), Rect2(192, 1152, 64, 64), Rect2(256, 1152, 64, 64), Rect2(320, 1152, 64, 64), Rect2(384, 1152, 64, 64)],
	"walk_right": [Rect2(64, 1216, 64, 64), Rect2(128, 1216, 64, 64), Rect2(192, 1216, 64, 64), Rect2(256, 1216, 64, 64), Rect2(320, 1216, 64, 64), Rect2(384, 1216, 64, 64)],
	"walk_up": [Rect2(64, 1088, 64, 64), Rect2(128, 1088, 64, 64), Rect2(192, 1088, 64, 64), Rect2(256, 1088, 64, 64), Rect2(320, 1088, 64, 64), Rect2(384, 1088, 64, 64)],
	"walk_up_left": [Rect2(64, 1408, 64, 64), Rect2(128, 1408, 64, 64), Rect2(192, 1408, 64, 64), Rect2(256, 1408, 64, 64), Rect2(320, 1408, 64, 64), Rect2(384, 1408, 64, 64)],
	"walk_up_right": [Rect2(64, 1472, 64, 64), Rect2(128, 1472, 64, 64), Rect2(192, 1472, 64, 64), Rect2(256, 1472, 64, 64), Rect2(320, 1472, 64, 64), Rect2(384, 1472, 64, 64)],
}

var actor_id: int = 0
var is_npc: bool = false                       # variant=1 -> ext_ref=0x030d NPC
var facing: String = "down"
var pose: String = "idle"                      # idle | walk | run
var _placeholder: ColorRect
var _sprite: AnimatedSprite2D
var _bubble_sprite: AnimatedSprite2D
var _active_tween: Tween = null
var _bubble_tween: Tween = null
static var _emotion_tex_cache: Texture2D = null

func _ready() -> void:
	z_index = 5  # above ground / static decor (matches player.gd)
	var built := false
	if not is_npc:
		built = _try_build_sprite()
	if not built:
		_build_placeholder()
	_build_bubble()
	_update_animation()

func _try_build_sprite() -> bool:
	# PC slot N -> map_characterN.png. Uniform 64x64 grid; all
	# animations defined by ANIM_REGIONS apply identically.
	var path := MAP_COMMON_PATH + "map_character%d.png" % actor_id
	if not ResourceLoader.exists(path):
		push_warning("EventActor: sheet not found at %s" % path)
		return false
	var tex: Texture2D = load(path)
	if tex == null:
		return false
	_sprite = AnimatedSprite2D.new()
	_sprite.centered = false
	_sprite.position = SPRITE_OFFSET
	_sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	_sprite.sprite_frames = _build_sprite_frames(tex)
	add_child(_sprite)
	return true

func _build_sprite_frames(tex: Texture2D) -> SpriteFrames:
	var frames := SpriteFrames.new()
	# Drop the auto-created "default" animation.
	if frames.has_animation(&"default"):
		frames.remove_animation(&"default")
	for anim_name in ANIM_REGIONS.keys():
		var rects: Array = ANIM_REGIONS[anim_name]
		frames.add_animation(anim_name)
		frames.set_animation_loop(anim_name, true)
		frames.set_animation_speed(anim_name, ANIM_FPS)
		for rect in rects:
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = rect
			frames.add_frame(anim_name, at)
	return frames

func _build_placeholder() -> void:
	# NPC with no sheet, or a PC sheet missing on disk -- show a
	# coloured rect so the actor remains visible and debuggable.
	_placeholder = ColorRect.new()
	_placeholder.color = PLACEHOLDER_NPC_COLOR if is_npc else PLACEHOLDER_PARTY_COLOR
	_placeholder.size = Vector2(PLACEHOLDER_SIZE, PLACEHOLDER_SIZE)
	_placeholder.position = Vector2(-PLACEHOLDER_SIZE * 0.5, -PLACEHOLDER_SIZE * 0.5)
	_placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_placeholder)

func _build_bubble() -> void:
	# AnimatedSprite2D over the actor's head; built lazily on first
	# show_bubble() call since most actors never emote.
	_bubble_sprite = AnimatedSprite2D.new()
	_bubble_sprite.position = BUBBLE_OFFSET
	_bubble_sprite.centered = true
	_bubble_sprite.z_index = 10  # above the character sprite
	_bubble_sprite.visible = false
	add_child(_bubble_sprite)

# Pick the (pose, facing) animation and play it. Safe to call any
# number of times; only restarts the AnimatedSprite2D if the resolved
# animation actually changed.
func _update_animation() -> void:
	if _sprite == null:
		return
	var by_dir: Variant = POSE_FACING_TO_ANIM.get(pose, POSE_FACING_TO_ANIM["idle"])
	var anim: String = by_dir.get(facing, "idle_down")
	if _sprite.animation != StringName(anim):
		_sprite.play(anim)

# Move to absolute world coords. ticks==0 (or unspecified for abs spawns)
# means snap instantly; otherwise tween over (ticks / 60) seconds.
func move_absolute(x: int, y: int, ticks: int, run: bool = false) -> Tween:
	return _start_move(Vector2(x, y), ticks, run)

# Move by relative pixel delta over `ticks` frames.
func move_relative(dx: int, dy: int, ticks: int, run: bool = false) -> Tween:
	return _start_move(position + Vector2(dx, dy), ticks, run)

func _start_move(target: Vector2, ticks: int, run: bool = false) -> Tween:
	_stop_active_tween()
	if ticks <= 0:
		position = target
		return null
	var delta := target - position
	# Two distinct timing conventions, gated by `run`:
	#   * walk (run=false): `ticks` is FRAMES-PER-TILE, so duration
	#     scales with distance -- constant walking speed across moves.
	#   * run (run=true): `ticks` is TOTAL FRAMES for the move. This
	#     matches what we observed at @0x34c9+ in 112020101 after the
	#     op_0x67 payload=0x00 "set_move_mode = run" marker: a 4-tile
	#     dy=-232 / ticks=50 burst finishes in 50/60 = 0.83s, i.e.
	#     ~5 tiles/sec instead of the ~1 tile/sec the per-tile formula
	#     would have produced.
	# Movement is also axis-sequenced (the actor walks one axis, then
	# the other) -- the engine does not do diagonal pathing in field
	# cutscenes. Tween the horizontal leg first, then the vertical leg.
	var t := create_tween()
	var leg_x_target := position + Vector2(delta.x, 0.0)
	var leg_y_target := target
	var has_x: bool = absf(delta.x) > 0.5
	var has_y: bool = absf(delta.y) > 0.5
	var dist_total: float = absf(delta.x) + absf(delta.y)
	if has_x:
		var dur_x: float
		if run:
			dur_x = (absf(delta.x) / dist_total) * ticks / FRAMES_PER_SECOND
		else:
			dur_x = absf(delta.x) / TILE_SIZE * ticks / FRAMES_PER_SECOND
		dur_x = maxf(dur_x, 1.0 / FRAMES_PER_SECOND)
		t.tween_property(self, "position", leg_x_target, dur_x)
	if has_y:
		var dur_y: float
		if run:
			dur_y = (absf(delta.y) / dist_total) * ticks / FRAMES_PER_SECOND
		else:
			dur_y = absf(delta.y) / TILE_SIZE * ticks / FRAMES_PER_SECOND
		dur_y = maxf(dur_y, 1.0 / FRAMES_PER_SECOND)
		t.tween_property(self, "position", leg_y_target, dur_y)
	if not has_x and not has_y:
		# Degenerate (no-op) move: still create a 1-frame tween so the
		# caller's await on the tween completes immediately.
		t.tween_interval(1.0 / FRAMES_PER_SECOND)
	_active_tween = t
	# Face the direction of the FIRST leg (horizontal if present, else
	# vertical). The engine flips facing again partway through the
	# motion in-game; this is a reasonable approximation.
	if has_x:
		facing = "right" if delta.x > 0 else "left"
	elif has_y:
		facing = "down" if delta.y > 0 else "up"
	pose = "run" if run else "walk"
	_update_animation()
	t.finished.connect(func():
		pose = "idle"
		_update_animation())
	return t

func face(dir: String) -> void:
	facing = dir
	_update_animation()

func set_visible_state(v: bool) -> void:
	visible = v

# Show the op_0x46 emoticon bubble. `bubble_id` is 1-based and indexes
# the row in `map_common/emotion_icon.png` (2x12 grid; both columns
# are the two animation frames of that emote). map_character sheets
# have no "talking" pose so the actor's own anim continues during the
# bubble.
func show_bubble(bubble_id: int, duration_ticks: int) -> void:
	if _bubble_sprite == null:
		return
	var frames := _build_emotion_frames(bubble_id)
	if frames == null:
		return
	_bubble_sprite.sprite_frames = frames
	_bubble_sprite.visible = true
	# loop=false on the animation -> AnimatedSprite2D stops on the last
	# frame after one cycle, then we hide on the duration timer.
	_bubble_sprite.play(&"emote")
	if _bubble_tween != null and _bubble_tween.is_valid():
		_bubble_tween.kill()
	_bubble_tween = create_tween()
	_bubble_tween.tween_interval(maxf(duration_ticks / FRAMES_PER_SECOND, 0.1))
	_bubble_tween.tween_callback(func():
		if _bubble_sprite != null:
			_bubble_sprite.stop()
			_bubble_sprite.visible = false)

func _build_emotion_frames(bubble_id: int) -> SpriteFrames:
	var tex := _get_emotion_texture()
	if tex == null:
		return null
	var row := bubble_id - 1
	if row < 0 or row > 11:
		push_warning("EventActor: bubble_id %d out of range" % bubble_id)
		return null
	var frames := SpriteFrames.new()
	if frames.has_animation(&"default"):
		frames.remove_animation(&"default")
	frames.add_animation(&"emote")
	frames.set_animation_loop(&"emote", false)
	frames.set_animation_speed(&"emote", EMOTION_FPS)
	for col in range(EMOTION_FRAME_COUNT):
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(col * EMOTION_CELL, row * EMOTION_CELL, EMOTION_CELL, EMOTION_CELL)
		frames.add_frame(&"emote", at)
	return frames

func _get_emotion_texture() -> Texture2D:
	if _emotion_tex_cache != null:
		return _emotion_tex_cache
	if not ResourceLoader.exists(EMOTION_ATLAS_PATH):
		push_warning("EventActor: emotion atlas missing at %s" % EMOTION_ATLAS_PATH)
		return null
	_emotion_tex_cache = load(EMOTION_ATLAS_PATH)
	return _emotion_tex_cache

func _stop_active_tween() -> void:
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	_active_tween = null

func is_busy() -> bool:
	return _active_tween != null and _active_tween.is_valid() and _active_tween.is_running()
