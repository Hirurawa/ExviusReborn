extends Node2D

## A viewer for the game's SpriteStudio animations: open SsbpViewer.tscn and run it
## (F6). Pick a file and an animation at the top; play, pause or scrub the frames.
## Mouse wheel zooms, right or middle drag pans, Fit (or F) frames the animation again.
##
## Files are listed from every folder under res://assets/. Animations put their
## origin (the red cross) in different places: full-screen map backdrops such as
## opening_bg/anime hang down and right from it, battle backgrounds stand on it
## (bottom centre) and small effects such as cosmos/anime are tiles around it. The grey
## box is what a few frames of the animation cover; the camera fits it on selection.

const ROOT: String = "res://assets/"
## Frames looked at for the grey box: effects that start empty still get framed.
const FIT_SAMPLES: int = 8

@export_file("*.ssbp") var ssbp_path: String = ROOT + "map_effect/ev_opening.ssbp"
@export var animation: String = "opening_bg/anime"

var _player: SsbpPlayer
var _camera: Camera2D
var _paths: PackedStringArray = []
var _bounds: Rect2 = Rect2()
var _files: OptionButton
var _animations: OptionButton
var _play: Button
var _slider: HSlider
var _frame_label: Label
var _panel: PanelContainer
var _dragging: bool = false


func _ready() -> void:
	_camera = Camera2D.new()
	add_child(_camera)
	_camera.make_current()
	_player = SsbpPlayer.new()
	add_child(_player)
	_build_ui()
	_paths = list_files()
	for path in _paths:
		_files.add_item(path.trim_prefix(ROOT))
	_select_file(maxi(_paths.find(ssbp_path), 0), animation)


## Every .ssbp one folder below ROOT, sorted by folder then name.
static func list_files() -> PackedStringArray:
	var paths: PackedStringArray = []
	for folder in DirAccess.get_directories_at(ROOT):
		for file in DirAccess.get_files_at(ROOT + folder):
			if file.ends_with(".ssbp"):
				paths.append("%s%s/%s" % [ROOT, folder, file])
	paths.sort()
	return paths


func _process(_delta: float) -> void:
	if _player.frame_count() > 0:
		_slider.set_value_no_signal(_player.frame)
		_frame_label.text = "frame %d / %d" % [_player.frame, _player.frame_count() - 1]


func _draw() -> void:
	if _bounds.has_area():
		draw_rect(_bounds, Color(0.5, 0.5, 0.5, 0.6), false, 2.0 / _camera.zoom.x)
	var arm: float = 20.0 / _camera.zoom.x
	draw_line(Vector2(-arm, 0), Vector2(arm, 0), Color(1, 0.3, 0.3), 2.0 / _camera.zoom.x)
	draw_line(Vector2(0, -arm), Vector2(0, arm), Color(1, 0.3, 0.3), 2.0 / _camera.zoom.x)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_camera.zoom *= 1.1
			queue_redraw()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_camera.zoom /= 1.1
			queue_redraw()
		elif event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		_camera.position -= event.relative / _camera.zoom
	elif event is InputEventKey and event.pressed and event.keycode == KEY_F:
		fit()


## Centres and zooms the camera on the grey box, below the controls.
func fit() -> void:
	var view: Vector2 = get_viewport_rect().size
	var top: float = _panel.get_combined_minimum_size().y  # laid out or not
	if not _bounds.has_area():
		_camera.position = Vector2.ZERO
		_camera.zoom = Vector2.ONE
	else:
		var room := Vector2(view.x, view.y - top) * 0.9
		var zoom: float = clampf(minf(room.x / _bounds.size.x, room.y / _bounds.size.y), 0.02, 8.0)
		_camera.zoom = Vector2(zoom, zoom)
		# The box centres in the space under the panel, not in the whole window.
		_camera.position = _bounds.get_center() - Vector2(0, top / 2.0) / zoom
	queue_redraw()


## What frames 0, 1/8, 2/8 ... of the animation cover, in the player's space.
func _measure() -> Rect2:
	var bounds := Rect2()
	var first: bool = true
	var count: int = _player.frame_count()
	for sample in FIT_SAMPLES:
		for quad in _player.quads(count * sample / FIT_SAMPLES):
			for point in quad["points"]:
				if first:
					bounds = Rect2(point, Vector2.ZERO)
					first = false
				else:
					bounds = bounds.expand(point)
	return bounds


func _select_file(index: int, wanted_animation: String = "") -> void:
	_animations.clear()
	if _paths.is_empty():
		return
	_files.select(index)
	var data: SsbpData = SsbpData.load_file(_paths[index])
	if data.error != "":
		push_warning(data.error)
		return
	var names: PackedStringArray = []
	for pack_name in data.packs:
		for animation_name in data.packs[pack_name].animations:
			names.append("%s/%s" % [pack_name, animation_name])
	names.sort()
	for name in names:
		_animations.add_item(name)
	var start: int = names.find(wanted_animation)
	_select_animation(maxi(start, 0))


func _select_animation(index: int) -> void:
	if _animations.item_count == 0:
		return
	_animations.select(index)
	_player.open(_paths[_files.selected], _animations.get_item_text(index))
	_slider.max_value = maxi(_player.frame_count() - 1, 0)
	_player.set_frame(0)
	_bounds = _measure()
	fit()


func _toggle_play() -> void:
	_player.playing = not _player.playing
	_play.text = "Pause" if _player.playing else "Play"


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	layer.add_child(_panel)
	var rows := VBoxContainer.new()
	_panel.add_child(rows)
	var top := HBoxContainer.new()
	rows.add_child(top)
	_files = OptionButton.new()
	_files.fit_to_longest_item = false
	_files.clip_text = true
	_files.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_files.item_selected.connect(func(index: int) -> void: _select_file(index))
	top.add_child(_files)
	_animations = OptionButton.new()
	_animations.fit_to_longest_item = false
	_animations.clip_text = true
	_animations.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_animations.item_selected.connect(_select_animation)
	top.add_child(_animations)
	var bottom := HBoxContainer.new()
	rows.add_child(bottom)
	_play = Button.new()
	_play.text = "Pause"
	_play.pressed.connect(_toggle_play)
	bottom.add_child(_play)
	var fit_button := Button.new()
	fit_button.text = "Fit"
	fit_button.pressed.connect(fit)
	bottom.add_child(fit_button)
	_slider = HSlider.new()
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slider.step = 1
	_slider.value_changed.connect(func(value: float) -> void: _player.set_frame(int(value)))
	bottom.add_child(_slider)
	_frame_label = Label.new()
	_frame_label.custom_minimum_size = Vector2(130, 0)
	bottom.add_child(_frame_label)
