class_name SsbpData
extends RefCounted

## A SpriteStudio 5 animation file (.ssbp), read at runtime. The game's are data version
## 1 ("Created by Ss5Converter v1.0.0", May 2015): ev_opening.ssbp is the prologue's
## night sky, map_effect.ssbp the maps' weather, fog, shadows and skies.
##
## The layout follows SpriteStudio's own SS5 player for cocos2d-x (SS5PlayerData.h and
## SS5Player.cpp as of June 2015, the last version that reads data version 1). Little
## endian; every offset counts from the start of the file.
##
##   project     u32 "SSPB", u32 version, u32 flags, offsets to the image folder, the
##               cells and the animation packs, s16 cell count, s16 pack count
##   cell        name, cell map (name, image file), s16 index, s16 x, y, u16 w, h
##   pack        name, parts, animations, s16 part count, s16 animation count
##   part        name, s16 index, parent, type (0 null, 1 normal, 3 instance), bounds,
##               blend (0 mix, 1 multiply, 2 add, 3 subtract), name of an instanced
##               animation ("pack/animation")
##   animation   name, initial state per part, an offset per frame, user data, labels,
##               s16 frame count, fps, label count
##
## A frame is a run of u16 words: for every part, in drawing order, its index, u32 flags
## and only the values those flags name (the rest come from the part's initial state).
## Positions are fixed point, tenths of a pixel. The last frame decoded of each
## animation is kept (a battle background's 1,680 frames, all kept, took 112 MB).

const DATA_ID: int = 0x42505353  # "SSPB"

const FLAG_INVISIBLE: int = 1 << 0
const FLAG_FLIP_H: int = 1 << 1
const FLAG_FLIP_V: int = 1 << 2
const FLAG_CELL_INDEX: int = 1 << 3
const FLAG_POSITION_X: int = 1 << 4
const FLAG_POSITION_Y: int = 1 << 5
const FLAG_POSITION_Z: int = 1 << 6
const FLAG_ANCHOR_X: int = 1 << 7
const FLAG_ANCHOR_Y: int = 1 << 8
const FLAG_ROTATION_X: int = 1 << 9
const FLAG_ROTATION_Y: int = 1 << 10
const FLAG_ROTATION_Z: int = 1 << 11
const FLAG_SCALE_X: int = 1 << 12
const FLAG_SCALE_Y: int = 1 << 13
const FLAG_OPACITY: int = 1 << 14
const FLAG_COLOR_BLEND: int = 1 << 15
const FLAG_VERTEX_TRANSFORM: int = 1 << 16
const FLAG_SIZE_X: int = 1 << 17
const FLAG_SIZE_Y: int = 1 << 18
const FLAG_U_MOVE: int = 1 << 19
const FLAG_V_MOVE: int = 1 << 20
const FLAG_UV_ROTATION: int = 1 << 21
const FLAG_U_SCALE: int = 1 << 22
const FLAG_V_SCALE: int = 1 << 23
const FLAG_BOUNDING_RADIUS: int = 1 << 24
const FLAG_INSTANCE_KEYFRAME: int = 1 << 25
const FLAG_INSTANCE_START: int = 1 << 26
const FLAG_INSTANCE_END: int = 1 << 27
const FLAG_INSTANCE_SPEED: int = 1 << 28
const FLAG_INSTANCE_LOOP: int = 1 << 29
const FLAG_INSTANCE_LOOP_FLAGS: int = 1 << 30

const INSTANCE_INFINITY: int = 1 << 0
const INSTANCE_REVERSE: int = 1 << 1
const INSTANCE_PINGPONG: int = 1 << 2
const INSTANCE_INDEPENDENT: int = 1 << 3

const PART_NULL: int = 0
const PART_NORMAL: int = 1
const PART_INSTANCE: int = 3

const BLEND_MIX: int = 0
const BLEND_MULTIPLY: int = 1
const BLEND_ADD: int = 2
const BLEND_SUBTRACT: int = 3

## Positions are stored in tenths of a pixel.
const DOT: float = 10.0


class Cell:
	extends RefCounted
	var name: String = ""
	var image: String = ""
	var rect: Rect2 = Rect2()


class Part:
	extends RefCounted
	var name: String = ""
	var parent: int = -1
	var type: int = PART_NULL
	var blend: int = BLEND_MIX
	## "pack/animation" for instance parts.
	var instance_of: String = ""


class Anim:
	extends RefCounted
	var name: String = ""
	var fps: int = 30
	var frame_count: int = 0
	var frame_offsets: PackedInt32Array = PackedInt32Array()
	## One state per part (Dictionary, the keys of SsbpData.frame_states).
	var initial: Array = []


class Pack:
	extends RefCounted
	var name: String = ""
	var parts: Array = []  # of SsbpData.Part
	var animations: Dictionary = {}  # name -> SsbpData.Anim


var path: String = ""
var version: int = 0
var cells: Array = []  # of SsbpData.Cell
var packs: Dictionary = {}  # name -> SsbpData.Pack
var error: String = ""

static var _loaded: Dictionary = {}
var _bytes: PackedByteArray
var _frame_cache: Dictionary = {}  # "pack/animation" -> [frame, states]


## Reads `file_path` once and shares it. Check `error` on the result.
static func load_file(file_path: String) -> SsbpData:
	if _loaded.has(file_path):
		return _loaded[file_path]
	var data := SsbpData.new()
	data.path = file_path
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(file_path)
	if bytes.is_empty():
		data.error = "cannot read %s" % file_path
	else:
		data.parse(bytes)
	_loaded[file_path] = data
	return data


func parse(bytes: PackedByteArray) -> void:
	_bytes = bytes
	if bytes.size() < 28 or bytes.decode_u32(0) != DATA_ID:
		error = "%s is not an ssbp file" % path.get_file()
		return
	version = bytes.decode_u32(4)
	if version != 1:
		error = "%s: data version %d, only 1 is known" % [path.get_file(), version]
		return
	var cell_at: int = bytes.decode_s32(16)
	var pack_at: int = bytes.decode_s32(20)
	var cell_count: int = bytes.decode_s16(24)
	var pack_count: int = bytes.decode_s16(26)
	for i in cell_count:
		var at: int = cell_at + 20 * i
		var cell := Cell.new()
		cell.name = _string(bytes.decode_s32(at))
		cell.image = _string(bytes.decode_s32(bytes.decode_s32(at + 4) + 4))
		cell.rect = Rect2(bytes.decode_s16(at + 10), bytes.decode_s16(at + 12), bytes.decode_u16(at + 14), bytes.decode_u16(at + 16))
		cells.append(cell)
	for i in pack_count:
		var at: int = pack_at + 16 * i
		var pack := Pack.new()
		pack.name = _string(bytes.decode_s32(at))
		var parts_at: int = bytes.decode_s32(at + 4)
		var animations_at: int = bytes.decode_s32(at + 8)
		var part_count: int = bytes.decode_s16(at + 12)
		var animation_count: int = bytes.decode_s16(at + 14)
		for j in part_count:
			var part_at: int = parts_at + 20 * j
			var part := Part.new()
			part.name = _string(bytes.decode_s32(part_at))
			part.parent = bytes.decode_s16(part_at + 6)
			part.type = bytes.decode_s16(part_at + 8)
			part.blend = bytes.decode_s16(part_at + 12)
			part.instance_of = _string(bytes.decode_s32(part_at + 16))
			pack.parts.append(part)
		for j in animation_count:
			var animation: Anim = _read_animation(animations_at + 28 * j, part_count)
			pack.animations[animation.name] = animation
		packs[pack.name] = pack


## The pack and animation `reference` names ("cosmos/anime"), or [] when unknown.
func find(reference: String) -> Array:
	var names: PackedStringArray = reference.split("/")
	if names.size() != 2 or not packs.has(names[0]):
		return []
	var pack: Pack = packs[names[0]]
	if not pack.animations.has(names[1]):
		return []
	return [pack, pack.animations[names[1]]]


## Every part's state in frame `frame` of `animation`, in drawing order. A state is a
## Dictionary: part, flags, cell, position (Vector2, y up), anchor (Vector2), rotation
## (degrees, counter-clockwise), scale (Vector2), opacity (0 to 255), size (Vector2),
## and when present vertex ([Vector2] x4: left-top, right-top, left-bottom,
## right-bottom), color_blend ({func, colors: [Color] x4, alpha = blend rate}) and
## instance ({keyframe, start, end, speed, loops, loop_flags}).
func frame_states(pack: Pack, animation: Anim, frame: int) -> Array:
	var key: String = "%s/%s" % [pack.name, animation.name]
	var cached: Array = _frame_cache.get(key, [])
	if not cached.is_empty() and cached[0] == frame:
		return cached[1]
	var states: Array = []
	var at: int = animation.frame_offsets[clampi(frame, 0, animation.frame_count - 1)]
	for n in pack.parts.size():
		var index: int = _bytes.decode_s16(at)
		var flags: int = _bytes.decode_u32(at + 2)
		at += 6
		var initial: Dictionary = animation.initial[index]
		var state: Dictionary = {"part": index, "flags": flags}
		state["cell"] = _read_s16(at, flags, FLAG_CELL_INDEX, initial["cell"])
		at += 2 if flags & FLAG_CELL_INDEX else 0
		var position: Vector2 = initial["position"]
		if flags & FLAG_POSITION_X:
			position.x = _bytes.decode_s16(at) / DOT
			at += 2
		if flags & FLAG_POSITION_Y:
			position.y = _bytes.decode_s16(at) / DOT
			at += 2
		if flags & FLAG_POSITION_Z:
			at += 2
		state["position"] = position
		var anchor: Vector2 = initial["anchor"]
		if flags & FLAG_ANCHOR_X:
			anchor.x = _bytes.decode_float(at)
			at += 4
		if flags & FLAG_ANCHOR_Y:
			anchor.y = _bytes.decode_float(at)
			at += 4
		state["anchor"] = anchor
		if flags & FLAG_ROTATION_X:
			at += 4
		if flags & FLAG_ROTATION_Y:
			at += 4
		state["rotation"] = initial["rotation"]
		if flags & FLAG_ROTATION_Z:
			state["rotation"] = _bytes.decode_float(at)
			at += 4
		var scale: Vector2 = initial["scale"]
		if flags & FLAG_SCALE_X:
			scale.x = _bytes.decode_float(at)
			at += 4
		if flags & FLAG_SCALE_Y:
			scale.y = _bytes.decode_float(at)
			at += 4
		state["scale"] = scale
		state["opacity"] = initial["opacity"]
		if flags & FLAG_OPACITY:
			state["opacity"] = _bytes.decode_u16(at)
			at += 2
		var size: Vector2 = initial["size"]
		if flags & FLAG_SIZE_X:
			size.x = _bytes.decode_float(at)
			at += 4
		if flags & FLAG_SIZE_Y:
			size.y = _bytes.decode_float(at)
			at += 4
		state["size"] = size
		# UV move, rotation and scale and the bounding radius: no file of the game's uses
		# the UV ones, and the radius is for hit tests. Skipped, not applied.
		for flag in [FLAG_U_MOVE, FLAG_V_MOVE, FLAG_UV_ROTATION, FLAG_U_SCALE, FLAG_V_SCALE, FLAG_BOUNDING_RADIUS]:
			if flags & flag:
				at += 4
		if flags & FLAG_VERTEX_TRANSFORM:
			var corner_flags: int = _bytes.decode_u16(at)
			at += 2
			var offsets: Array = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
			for corner in 4:
				if corner_flags & (1 << corner):
					offsets[corner] = Vector2(_bytes.decode_s16(at), _bytes.decode_s16(at + 2))
					at += 4
			state["vertex"] = offsets
		if flags & FLAG_COLOR_BLEND:
			var type_and_flags: int = _bytes.decode_u16(at)
			at += 2
			var corner_flags: int = (type_and_flags >> 8) & 0xff
			var colors: Array = [Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE]
			if corner_flags & 16:
				var color: Color = _read_blend_color(at)
				at += 8
				colors = [color, color, color, color]
			else:
				for corner in 4:
					if corner_flags & (1 << corner):
						colors[corner] = _read_blend_color(at)
						at += 8
			state["color_blend"] = {"func": type_and_flags & 0xff, "colors": colors}
		if pack.parts[index].type == PART_INSTANCE:
			var instance: Dictionary = {"keyframe": 0, "start": 0, "end": 0, "speed": 0.0, "loops": 0, "loop_flags": 0}
			if flags & FLAG_INSTANCE_KEYFRAME:
				instance["keyframe"] = _bytes.decode_s16(at)
				at += 2
			if flags & FLAG_INSTANCE_START:
				instance["start"] = _bytes.decode_s16(at)
				at += 2
			if flags & FLAG_INSTANCE_END:
				instance["end"] = _bytes.decode_s16(at)
				at += 2
			if flags & FLAG_INSTANCE_SPEED:
				instance["speed"] = _bytes.decode_float(at)
				at += 4
			if flags & FLAG_INSTANCE_LOOP:
				instance["loops"] = _bytes.decode_s16(at)
				at += 2
			if flags & FLAG_INSTANCE_LOOP_FLAGS:
				instance["loop_flags"] = _bytes.decode_s16(at)
				at += 2
			state["instance"] = instance
		states.append(state)
	_frame_cache[key] = [frame, states]
	return states


## The frame an instance part plays of its animation while its parent plays `frame`:
## the same timing rules as the SS5 player. -1 when it shows nothing yet.
static func instance_frame(instance: Dictionary, frame: int) -> int:
	var time: int = int(frame * float(instance["speed"])) - int(instance["keyframe"])
	if time < 0:
		return -1
	var start: int = instance["start"]
	var end: int = instance["end"]
	var length: int = end - start + 1
	if length <= 0:
		return -1
	var loop_flags: int = instance["loop_flags"]
	var loop: int = time / length
	var loops: int = instance["loops"]
	if loop_flags & INSTANCE_PINGPONG:
		loops *= 2
	if not (loop_flags & INSTANCE_INFINITY) and loop >= loops:
		time = length - 1
		loop = loops - 1
	var local_frame: int = time % length
	var reverse: bool = (loop_flags & INSTANCE_REVERSE) != 0
	if loop_flags & INSTANCE_PINGPONG and loop % 2 == 1:
		reverse = not reverse
	return end - local_frame if reverse else start + local_frame


func _read_animation(at: int, part_count: int) -> Anim:
	var animation := Anim.new()
	animation.name = _string(_bytes.decode_s32(at))
	var initial_at: int = _bytes.decode_s32(at + 4)
	var frames_at: int = _bytes.decode_s32(at + 8)
	animation.frame_count = _bytes.decode_s16(at + 20)
	animation.fps = _bytes.decode_s16(at + 22)
	for f in animation.frame_count:
		animation.frame_offsets.append(_bytes.decode_s32(frames_at + 4 * f))
	# Files from the Nov 2014 converter build (airship_sky, dungeon001 and two test
	# files) have 76-byte initial states: no position Z and no padding after opacity,
	# so opacity sits 2 bytes and the floats 4 bytes earlier. The version number is the
	# same, so the second state's index tells the builds apart.
	var stride: int = 80
	if part_count > 1 and _bytes.decode_s16(initial_at + 80) != 1:
		stride = 76
	var opacity_at: int = 16 if stride == 80 else 14
	var floats_at: int = 20 if stride == 80 else 16
	for k in part_count:
		var p: int = initial_at + stride * k
		var f: int = p + floats_at
		animation.initial.append({
			"cell": _bytes.decode_s16(p + 8),
			"position": Vector2(_bytes.decode_s16(p + 10), _bytes.decode_s16(p + 12)) / DOT,
			"opacity": _bytes.decode_u16(p + opacity_at),
			"anchor": Vector2(_bytes.decode_float(f), _bytes.decode_float(f + 4)),
			"rotation": _bytes.decode_float(f + 16),
			"scale": Vector2(_bytes.decode_float(f + 20), _bytes.decode_float(f + 24)),
			"size": Vector2(_bytes.decode_float(f + 28), _bytes.decode_float(f + 32)),
		})
	return animation


func _read_s16(at: int, flags: int, flag: int, fallback: int) -> int:
	return _bytes.decode_s16(at) if flags & flag else fallback


## A colour-blend entry: the blend rate (float) and an ARGB colour. The rate rides in
## the colour's alpha.
func _read_blend_color(at: int) -> Color:
	var rate: float = _bytes.decode_float(at)
	var raw: int = _bytes.decode_u32(at + 4)
	return Color8((raw >> 16) & 0xff, (raw >> 8) & 0xff, raw & 0xff, clampi(int(rate * 255.0), 0, 255))


func _string(at: int) -> String:
	if at <= 0 or at >= _bytes.size():
		return ""
	var end: int = at
	while end < _bytes.size() and _bytes[end] != 0:
		end += 1
	return _bytes.slice(at, end).get_string_from_ascii()
