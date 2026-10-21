class_name SsbpPlayer
extends Node2D

## Plays one animation of a SpriteStudio .ssbp file (SsbpData), drawn the way the SS5
## player draws it: every part is a textured quad placed by its parents' transforms,
## instance parts play another animation in their place, and parts draw in the order
## each frame lists them. The node's position is the animation's origin; SpriteStudio's
## y axis points up and is flipped here.
##
## Quads go to RenderingServer canvas items, one per quad, so additive parts can sit
## between normal ones in the drawing order. The last frame's quads of each file and
## animation are kept and shared by every player showing that frame.

## Where the textures of an .ssbp are looked for when they are not next to it.
const TEXTURE_FOLDER: String = "res://assets/map_effect/"

@export_file("*.ssbp") var ssbp_path: String = "":
	set(value):
		ssbp_path = value
		_reload()
## "pack/animation", for example "opening_bg/anime" or "cosmos/anime".
@export var animation: String = "":
	set(value):
		animation = value
		_reload()
@export var playing: bool = true
@export var speed_scale: float = 1.0

## The frame on screen.
var frame: int = 0
var data: SsbpData = null

var _pack: SsbpData.Pack = null
var _animation: SsbpData.Anim = null
var _time: float = 0.0
var _items: Array[RID] = []
var _item_materials: Dictionary = {}  # item index -> ShaderMaterial (colour blend)
var _shown: int = 0

static var _quad_cache: Dictionary = {}  # "path|animation" -> [frame, quads]
static var _textures: Dictionary = {}
static var _add_material: CanvasItemMaterial
static var _color_blend_shader: Shader


func _ready() -> void:
	_reload()


func _exit_tree() -> void:
	for item in _items:
		RenderingServer.free_rid(item)
	_items.clear()
	_shown = 0


func _process(delta: float) -> void:
	if not playing or _animation == null:
		return
	_time += delta * _animation.fps * speed_scale
	var next: int = int(_time) % maxi(_animation.frame_count, 1)
	if next != frame:
		frame = next
		_draw_frame()


## Switches to animation `reference` ("pack/animation") of the file at `path`.
func open(path: String, reference: String) -> void:
	animation = ""  # so the file change does not look up the old name in the new file
	ssbp_path = path
	animation = reference


## Shows frame `number` (looping past the end).
func set_frame(number: int) -> void:
	if _animation == null:
		return
	frame = posmod(number, maxi(_animation.frame_count, 1))
	_time = frame
	_draw_frame()


func frame_count() -> int:
	return _animation.frame_count if _animation != null else 0


## The quads of frame `number`, in drawing order: {points (PackedVector2Array, Godot's
## y down), uvs, colors, texture (Texture2D), blend, color_blend (bool), opacity}.
func quads(number: int) -> Array:
	if _animation == null:
		return []
	var key: String = "%s|%s" % [ssbp_path, animation]
	var cached: Array = _quad_cache.get(key, [])
	if not cached.is_empty() and cached[0] == number:
		return cached[1]
	var out: Array = []
	_collect(_pack, _animation, number, Transform2D.IDENTITY, 1.0, out)
	_quad_cache[key] = [number, out]
	return out


func _reload() -> void:
	_pack = null
	_animation = null
	if ssbp_path == "" or animation == "":
		return
	data = SsbpData.load_file(ssbp_path)
	if data.error != "":
		push_warning("SsbpPlayer: %s" % data.error)
		return
	var found: Array = data.find(animation)
	if found.is_empty():
		push_warning("SsbpPlayer: no animation %s in %s" % [animation, ssbp_path.get_file()])
		return
	_pack = found[0]
	_animation = found[1]
	frame = 0
	_time = 0.0
	if is_inside_tree():
		_draw_frame()


## Walks one animation's frame: parts' transforms in index order (parents first), then
## the parts in the frame's drawing order. Transforms are in SpriteStudio space (y up).
func _collect(pack: SsbpData.Pack, anim: SsbpData.Anim, number: int, root: Transform2D, alpha: float, out: Array) -> void:
	var states: Array = data.frame_states(pack, anim, number)
	var by_part: Array = []
	by_part.resize(pack.parts.size())
	for state in states:
		by_part[state["part"]] = state
	var world: Array = []
	world.resize(pack.parts.size())
	for index in pack.parts.size():
		var state: Dictionary = by_part[index]
		var part: SsbpData.Part = pack.parts[index]
		var parent: Transform2D = world[part.parent] if part.parent >= 0 else root
		var local := Transform2D(deg_to_rad(state["rotation"]), state["scale"], 0.0, state["position"])
		world[index] = parent * local
	for state in states:
		var flags: int = state["flags"]
		if flags & SsbpData.FLAG_INVISIBLE or int(state["opacity"]) == 0:
			continue
		var part: SsbpData.Part = pack.parts[state["part"]]
		var opacity: float = alpha * int(state["opacity"]) / 255.0
		if part.type == SsbpData.PART_INSTANCE:
			var found: Array = data.find(part.instance_of)
			var child_frame: int = SsbpData.instance_frame(state["instance"], number)
			if not found.is_empty() and child_frame >= 0:
				_collect(found[0], found[1], child_frame, world[state["part"]], opacity, out)
			continue
		if part.type != SsbpData.PART_NORMAL or int(state["cell"]) < 0:
			continue
		var quad: Dictionary = _quad(state, part, world[state["part"]], opacity)
		if not quad.is_empty():
			out.append(quad)


## One normal part's quad: the cell's rectangle around its anchor, resized about its
## centre when the frame sets a size, corners nudged by vertex offsets, then placed.
func _quad(state: Dictionary, part: SsbpData.Part, world: Transform2D, opacity: float) -> Dictionary:
	if int(state["cell"]) >= data.cells.size():
		return {}
	var cell: SsbpData.Cell = data.cells[state["cell"]]
	var texture: Texture2D = _texture(cell.image)
	if texture == null:
		return {}
	var flags: int = state["flags"]
	var w: float = cell.rect.size.x
	var h: float = cell.rect.size.y
	var anchor: Vector2 = state["anchor"]
	var left: float = -anchor.x * w
	var right: float = (1.0 - anchor.x) * w
	var bottom: float = -(1.0 - anchor.y) * h
	var top: float = anchor.y * h
	if flags & SsbpData.FLAG_SIZE_X:
		var center_x: float = (left + right) / 2.0
		var half_w: float = float(state["size"].x) / 2.0
		left = center_x - half_w
		right = center_x + half_w
	if flags & SsbpData.FLAG_SIZE_Y:
		var center_y: float = (bottom + top) / 2.0
		var half_h: float = float(state["size"].y) / 2.0
		bottom = center_y - half_h
		top = center_y + half_h
	var corners: Array = [Vector2(left, top), Vector2(right, top), Vector2(left, bottom), Vector2(right, bottom)]
	if state.has("vertex"):
		for i in 4:
			corners[i] += state["vertex"][i]
	var size: Vector2 = texture.get_size()
	var u0: float = cell.rect.position.x / size.x
	var u1: float = cell.rect.end.x / size.x
	var v0: float = cell.rect.position.y / size.y
	var v1: float = cell.rect.end.y / size.y
	if flags & SsbpData.FLAG_FLIP_H:
		var swap: float = u0
		u0 = u1
		u1 = swap
	if flags & SsbpData.FLAG_FLIP_V:
		var swap: float = v0
		v0 = v1
		v1 = swap
	# Corner order left-top, right-top, right-bottom, left-bottom for the polygon.
	var order: Array = [0, 1, 3, 2]
	var corner_uvs: Array = [Vector2(u0, v0), Vector2(u1, v0), Vector2(u0, v1), Vector2(u1, v1)]
	var points := PackedVector2Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var color_blend: bool = state.has("color_blend")
	for i in order:
		var p: Vector2 = world * corners[i]
		points.append(Vector2(p.x, -p.y))
		uvs.append(corner_uvs[i])
		if color_blend:
			colors.append(state["color_blend"]["colors"][i])
		else:
			colors.append(Color(1, 1, 1, opacity))
	return {
		"points": points, "uvs": uvs, "colors": colors, "texture": texture,
		"blend": part.blend, "color_blend": color_blend, "opacity": opacity,
	}


func _draw_frame() -> void:
	if not is_inside_tree():
		return
	var frame_quads: Array = quads(frame)
	for i in frame_quads.size():
		var quad: Dictionary = frame_quads[i]
		var item: RID = _item(i)
		RenderingServer.canvas_item_clear(item)
		RenderingServer.canvas_item_add_polygon(item, quad["points"], quad["colors"], quad["uvs"], quad["texture"].get_rid())
		RenderingServer.canvas_item_set_material(item, _material_for(i, quad))
		RenderingServer.canvas_item_set_draw_index(item, i)
		RenderingServer.canvas_item_set_visible(item, true)
	for i in range(frame_quads.size(), _shown):
		RenderingServer.canvas_item_set_visible(_items[i], false)
	_shown = frame_quads.size()


func _item(index: int) -> RID:
	while _items.size() <= index:
		var item: RID = RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(item, get_canvas_item())
		_items.append(item)
	return _items[index]


func _material_for(index: int, quad: Dictionary) -> RID:
	if quad["color_blend"]:
		if not _item_materials.has(index):
			if _color_blend_shader == null:
				_color_blend_shader = _make_color_blend_shader()
			var material := ShaderMaterial.new()
			material.shader = _color_blend_shader
			_item_materials[index] = material
		var shader_material: ShaderMaterial = _item_materials[index]
		shader_material.set_shader_parameter("opacity", quad["opacity"])
		return shader_material.get_rid()
	if quad["blend"] == SsbpData.BLEND_ADD:
		if _add_material == null:
			_add_material = CanvasItemMaterial.new()
			_add_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		return _add_material.get_rid()
	return RID()


## SpriteStudio's mix colour blend: the texture's colour moves toward the vertex colour
## by the rate carried in the vertex alpha; the part's opacity applies on top.
static func _make_color_blend_shader() -> Shader:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
render_mode blend_mix;
uniform float opacity = 1.0;
varying vec4 blend_color;
void vertex() {
	blend_color = COLOR;
}
void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	COLOR = vec4(mix(tex.rgb, blend_color.rgb, blend_color.a), tex.a * opacity);
}
"""
	return shader


## A cell map's image: next to the .ssbp, else in TEXTURE_FOLDER.
func _texture(image: String) -> Texture2D:
	var key: String = ssbp_path.get_base_dir() + "|" + image
	if _textures.has(key):
		return _textures[key]
	var texture: Texture2D = null
	for candidate in [ssbp_path.get_base_dir().path_join(image), TEXTURE_FOLDER + image]:
		if ResourceLoader.exists(candidate):
			texture = load(candidate)
			break
	if texture == null:
		push_warning("SsbpPlayer: no texture %s for %s" % [image, ssbp_path.get_file()])
	_textures[key] = texture
	return texture
