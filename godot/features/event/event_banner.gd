class_name EventBanner
extends Control

## The location banner op 0x6e shows: a dark band across the middle of the screen with
## the town's name ("Town of Mitra" as Mitra's arrival opens in the second recording).
## The band fades in, the name follows, both hold, then fade out; the script does not
## wait for it (the camera keeps panning underneath in the recording). EventStage calls
## tick() once per frame.
##
## The name is an image in the original (townname_1101.png), and none of the 20 are in
## the assets, so the name is drawn as text from the town table until they are.

const BAND_HEIGHT: float = 96.0
## Read from the recording: the band takes about 0.5 s to appear, the name starts once
## it is in and takes about 0.75 s, and both go in about 0.65 s. The data's own number
## (60 for Mitra) is taken as the hold.
const BAND_IN_FRAMES: int = 30
const NAME_DELAY: int = 30
const NAME_IN_FRAMES: int = 45
const OUT_FRAMES: int = 40

var _band: TextureRect
var _name: Label
var _hold: int = 0
var _age: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_HCENTER_WIDE)
	offset_top = -BAND_HEIGHT / 2.0
	offset_bottom = BAND_HEIGHT / 2.0
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	gradient.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.8), Color(0, 0, 0, 0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(0, 1)
	_band = TextureRect.new()
	_band.texture = texture
	_band.stretch_mode = TextureRect.STRETCH_SCALE
	_band.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_band)
	for y in [BAND_HEIGHT * 0.2, BAND_HEIGHT * 0.8]:
		var line := ColorRect.new()
		line.color = Color(0.85, 0.85, 0.9, 0.7)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.anchor_right = 1.0
		line.offset_left = 40
		line.offset_right = -40
		line.offset_top = y
		line.offset_bottom = y + 1
		_band.add_child(line)
	_name = Label.new()
	_name.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name.add_theme_font_size_override("font_size", 28)
	_name.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_name.add_theme_constant_override("shadow_offset_x", 2)
	_name.add_theme_constant_override("shadow_offset_y", 2)
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name)
	visible = false


## Shows the banner for image `file_name` (townname_<town id>.png), holding the name
## for `hold_frames` frames.
func show_banner(file_name: String, hold_frames: int) -> void:
	_name.text = EventBanner.location_name(file_name)
	_hold = maxi(hold_frames, 0)
	_age = 0
	visible = true
	_apply()


## The town's name for townname_<id>.png, or the file's own name when the town is
## unknown.
static func location_name(file_name: String) -> String:
	var id: String = file_name.get_basename().trim_prefix("townname_")
	if id.is_valid_int():
		var town: Dictionary = GameDatabase.get_town(id)
		if not town.is_empty():
			return str(town.get("townName", ""))
	return file_name.get_basename()


func tick() -> void:
	if _age < 0:
		return
	_age += 1
	if _age >= NAME_DELAY + NAME_IN_FRAMES + _hold + OUT_FRAMES:
		_age = -1
		visible = false
		return
	_apply()


func showing() -> bool:
	return _age >= 0


func shown_name() -> String:
	return _name.text


func _apply() -> void:
	var fade_out_start: int = NAME_DELAY + NAME_IN_FRAMES + _hold
	var out: float = 1.0 - clampf(float(_age - fade_out_start) / OUT_FRAMES, 0.0, 1.0)
	_band.modulate.a = minf(clampf(float(_age) / BAND_IN_FRAMES, 0.0, 1.0), out)
	_name.modulate.a = minf(clampf(float(_age - NAME_DELAY) / NAME_IN_FRAMES, 0.0, 1.0), out)
