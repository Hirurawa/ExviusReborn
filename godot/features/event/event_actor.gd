class_name EventActor
extends Node2D

## One actor on the cutscene stage: a party member (a script's kind-0 reference, sheet
## map_character<N>.png) or a record of the event bin. `position` is the world position
## the script gives, the top-left of the 58 px tile the actor stands on.
##
## EventStage calls tick() once per frame (60 per second); moves, facing and the emote
## bubble all advance there, so a scene plays the same frame for frame every time. Only
## the walk cycle's frames run on the sprite's own clock.

const MAP_COMMON: String = "res://assets/map_common/"
const SPRITE_SCALE: float = 2.0
## Centre of the scaled sprite cell relative to `position`: the middle of the tile's top
## edge. Measured against the map in both recordings (deck, bridge, forest, shrine,
## forge: 17 to 22 px above the first estimate of y + 21, which had assumed the camera
## point at the screen centre), within about 3 px.
const SPRITE_CENTER: Vector2 = Vector2(29, 0)
## Emote bubble centre relative to `position`, before the command's own y offset: Rain's
## "!" (offset -1) and Lasswell's (offset -10) on the deck.
const BUBBLE_CENTER: Vector2 = Vector2(29, -83)
## The 64 px icon drew 42 px wide in the recording (❓).
const BUBBLE_SCALE: float = 0.75
const BUBBLE_CELL: int = 64
const BUBBLE_FRAME_TICKS: int = 15
const WALK_FPS: float = 10.0  # ❓ not measured yet
const DIRECTIONS: Array[String] = ["down", "up", "left", "right"]
const DOWN: int = 0
const UP: int = 1
const LEFT: int = 2
const RIGHT: int = 3

## Animation regions of every map_character<N>.png (a uniform 64 px grid), taken from
## player.tscn's SpriteFrames.
const ANIM_REGIONS: Dictionary = {
	"idle_down": [Rect2(0, 0, 64, 64)],
	"idle_up": [Rect2(0, 64, 64, 64)],
	"idle_left": [Rect2(0, 128, 64, 64)],
	"idle_right": [Rect2(0, 192, 64, 64)],
	"walk_down": [Rect2(64, 1024, 64, 64), Rect2(128, 1024, 64, 64), Rect2(192, 1024, 64, 64), Rect2(256, 1024, 64, 64), Rect2(320, 1024, 64, 64), Rect2(384, 1024, 64, 64)],
	"walk_up": [Rect2(64, 1088, 64, 64), Rect2(128, 1088, 64, 64), Rect2(192, 1088, 64, 64), Rect2(256, 1088, 64, 64), Rect2(320, 1088, 64, 64), Rect2(384, 1088, 64, 64)],
	"walk_left": [Rect2(64, 1152, 64, 64), Rect2(128, 1152, 64, 64), Rect2(192, 1152, 64, 64), Rect2(256, 1152, 64, 64), Rect2(320, 1152, 64, 64), Rect2(384, 1152, 64, 64)],
	"walk_right": [Rect2(64, 1216, 64, 64), Rect2(128, 1216, 64, 64), Rect2(192, 1216, 64, 64), Rect2(256, 1216, 64, 64), Rect2(320, 1216, 64, 64), Rect2(384, 1216, 64, 64)],
}

static var _sheet_cache: Dictionary = {}
static var _emotion_texture: Texture2D

## "pc<N>" for party members, "e<slot>" for records.
var key: String = ""
var facing: int = DOWN
var moving: bool = false

var _target: Vector2 = Vector2.ZERO
var _speed: float = 0.0
## "sheet" (map_character), "npc" (4x4 npc sheet), "image" (a still) or "" (nothing drawn).
var _kind: String = ""
var _sprite: Node2D = null
var _bubble: Sprite2D = null
var _bubble_row: int = 0
var _bubble_ticks: int = 0
var _bubble_age: int = 0


## A party member: map_character<index>.png.
func use_party_sheet(index: int) -> bool:
	return _use_sheet(MAP_COMMON + "map_character%d.png" % index)


## A record's graphic (EventBin.Page.graphic). A character id is an `npc` row or an npc
## texture id (all 923 in the dump resolve to an npc sheet; 13 is "Gran", the
## Grandshelt soldier, not map_character13.png). `images` maps image ids to texture
## paths (the bin's manifest and map_common/common_image.txt). Returns false when
## nothing could be drawn; the actor still exists and moves, it is just invisible.
func use_graphic(graphic: Dictionary, images: Dictionary, size: Vector2i) -> bool:
	if graphic.has("character"):
		var npc: AnimatedSprite2D = NpcSpriteBuilder.build(int(graphic["character"]))
		if npc == null:
			return false
		npc.stop()
		_attach(npc, "npc")
		return true
	if graphic.has("image"):
		var texture_path: String = str(images.get(int(graphic["image"]), ""))
		if texture_path == "" or not ResourceLoader.exists(texture_path):
			return false
		var still := Sprite2D.new()
		still.texture = load(texture_path)
		still.region_enabled = true
		still.region_rect = Rect2(int(graphic["src_x"]), int(graphic["src_y"]), size.x, size.y)
		_attach(still, "image")
		return true
	return false


func face(direction: int) -> void:
	facing = clampi(direction, DOWN, RIGHT)
	_update_pose()


## Starts a move to `target` at `speed` px per frame; 0 jumps there at once. The actor
## turns to the move's main axis and walks (❓ the move's trailer bytes may control
## both; see CUTSCENE-PLAN.md section 5).
func move_to(target: Vector2, speed: float) -> void:
	if speed <= 0.0 or target.is_equal_approx(position):
		position = target
		moving = false
		_update_pose()
		return
	var delta: Vector2 = target - position
	if absf(delta.x) >= absf(delta.y):
		facing = RIGHT if delta.x > 0 else LEFT
	else:
		facing = DOWN if delta.y > 0 else UP
	_target = target
	_speed = speed
	moving = true
	_update_pose()


## Shows emote `bubble_id` (1-based row of emotion_icon.png) for `ticks` frames.
func show_bubble(bubble_id: int, ticks: int, offset_y: int) -> void:
	if bubble_id < 1 or bubble_id > 12:
		return
	if _bubble == null:
		_bubble = Sprite2D.new()
		_bubble.texture = _emotion_atlas()
		_bubble.region_enabled = true
		_bubble.scale = Vector2(BUBBLE_SCALE, BUBBLE_SCALE)
		_bubble.z_index = 10
		add_child(_bubble)
	_bubble_row = bubble_id - 1
	_bubble_ticks = maxi(ticks, 1)
	_bubble_age = 0
	_bubble.position = BUBBLE_CENTER + Vector2(0, offset_y)
	_bubble.region_rect = Rect2(0, _bubble_row * BUBBLE_CELL, BUBBLE_CELL, BUBBLE_CELL)
	_bubble.visible = true


## One frame: the move and the bubble.
func tick() -> void:
	if moving:
		var delta: Vector2 = _target - position
		var distance: float = delta.length()
		if distance <= _speed:
			position = _target
			moving = false
			_update_pose()
		else:
			position += delta / distance * _speed
	if _bubble != null and _bubble.visible:
		_bubble_age += 1
		if _bubble_age >= _bubble_ticks:
			_bubble.visible = false
		else:
			var column: int = (_bubble_age / BUBBLE_FRAME_TICKS) % 2
			_bubble.region_rect = Rect2(column * BUBBLE_CELL, _bubble_row * BUBBLE_CELL, BUBBLE_CELL, BUBBLE_CELL)


## Moving or showing a bubble: what `advance` waits for.
func is_busy() -> bool:
	return moving or (_bubble != null and _bubble.visible)


func has_sprite() -> bool:
	return _sprite != null


func _use_sheet(texture_path: String) -> bool:
	if not ResourceLoader.exists(texture_path):
		return false
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = _sheet_frames(texture_path)
	sprite.centered = true
	_attach(sprite, "sheet")
	return true


## Party sheets (64 px cells) are centred on SPRITE_CENTER. NPC sheets and stills
## (58 px cells) hang from their top-left corner at `position`, as the town draws its
## NPCs: a bridge soldier's centre sat 60 px right of and 57 px below its record's
## position in the recording, against 58 and 58 for this rule.
func _attach(sprite: Node2D, kind: String) -> void:
	_sprite = sprite
	_kind = kind
	if kind == "sheet":
		sprite.position = SPRITE_CENTER
	else:
		sprite.set("centered", false)
		sprite.position = Vector2.ZERO
	sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	add_child(sprite)
	_update_pose()


func _update_pose() -> void:
	if _sprite == null:
		return
	var direction: String = DIRECTIONS[facing]
	if _kind == "sheet":
		var sheet: AnimatedSprite2D = _sprite
		var animation := StringName(("walk_" if moving else "idle_") + direction)
		if sheet.animation != animation or not sheet.is_playing():
			sheet.play(animation)
	elif _kind == "npc":
		var npc: AnimatedSprite2D = _sprite
		if npc.sprite_frames.has_animation(direction):
			npc.animation = StringName(direction)
		if moving:
			npc.play()
		else:
			npc.stop()
			npc.frame = 0


static func _sheet_frames(texture_path: String) -> SpriteFrames:
	if _sheet_cache.has(texture_path):
		return _sheet_cache[texture_path]
	var texture: Texture2D = load(texture_path)
	var frames := SpriteFrames.new()
	if frames.has_animation(&"default"):
		frames.remove_animation(&"default")
	for animation in ANIM_REGIONS:
		frames.add_animation(animation)
		frames.set_animation_loop(animation, true)
		frames.set_animation_speed(animation, WALK_FPS)
		for region in ANIM_REGIONS[animation]:
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = region
			frames.add_frame(animation, atlas)
	_sheet_cache[texture_path] = frames
	return frames


static func _emotion_atlas() -> Texture2D:
	if _emotion_texture == null:
		_emotion_texture = load(MAP_COMMON + "emotion_icon.png")
	return _emotion_texture
