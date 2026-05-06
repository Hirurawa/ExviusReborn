extends Control

const TILE_SOURCE_ID: int = 0
const TILE_ATLAS_COORD: Vector2i = Vector2i(0, 0)
const TILE_SIZE: int = 100

@onready var back_button: Button = $VBoxContainer/HeaderRow/BackButton
@onready var title_label: Label = $VBoxContainer/HeaderRow/TitleLabel
@onready var tile_map_layer: TileMapLayer = $TileMapLayer
@onready var info_label: Label = $VBoxContainer/InfoLabel

var _summon_id: String = ""
var _summon_name: String = ""
var _is_panning: bool = false
var _pan_start: Vector2 = Vector2.ZERO
var _tmap_start: Vector2 = Vector2.ZERO

func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	_setup_tileset()
	if _summon_id != "":
		_render_board()
	else:
		_show_empty("No summon board selected.")

func _setup_tileset() -> void:
	#var img := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	#img.fill(Color(0.2, 0.45, 0.8, 0.9))
	#var tex := ImageTexture.create_from_image(img)
	var source := TileSetAtlasSource.new()
	#source.texture = tex
	source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	source.create_tile(TILE_ATLAS_COORD)
	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_HEXAGON
	#ts.tile_layout = TileSet.TILE_LAYOUT_STACKED
	ts.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	#ts.add_source(source, TILE_SOURCE_ID)
	tile_map_layer.tile_set = ts

func init_scene(params: Dictionary) -> void:
	_summon_id = str(params.get("summon_id", "")).strip_edges()
	_summon_name = str(params.get("summon_name", "")).strip_edges()
	if is_node_ready():
		_render_board()

func _on_back_pressed() -> void:
	UIManager.pop()

func _render_board() -> void:
	tile_map_layer.clear()
	for child in tile_map_layer.get_children():
		child.queue_free()

	if _summon_id == "":
		_show_empty("No summon board selected.")
		return

	var boards: Dictionary = DataManager.game_data_summons_boards
	var board_value: Variant = boards.get(_summon_id, {})
	if not (board_value is Dictionary):
		_show_empty("No board data found for summon #%s." % _summon_id)
		return

	var board_nodes: Dictionary = board_value
	if board_nodes.is_empty():
		_show_empty("No board data found for summon #%s." % _summon_id)
		return

	var cells: Array[Dictionary] = []
	var sum_local := Vector2.ZERO
	
	for node_id_variant in board_nodes.keys():
		var node_id: String = str(node_id_variant)
		var node_value: Variant = board_nodes.get(node_id_variant, {})
		if not (node_value is Dictionary): continue
		
		var node_data: Dictionary = node_value
		var pos_value: Variant = node_data.get("position", [])
		if not (pos_value is Array) or pos_value.size() < 2: continue
		
		# 1. Grab the raw Axial coordinate from the datamine
		var raw_axial_coord := Vector2i(int(pos_value[0]), int(pos_value[1]))
		
		# 2. CONVERT to Godot's internal Offset coordinate immediately!
		var godot_offset_coord := _axial_to_offset(raw_axial_coord)
		
		# 3. Store the CONVERTED coordinate
		cells.append({"coord": godot_offset_coord, "node_id": node_id, "data": node_data})
		
		# Calculate the centroid using the converted coordinate
		sum_local += tile_map_layer.map_to_local(godot_offset_coord)

	if cells.is_empty():
		_show_empty("Board nodes are missing valid positions.")
		return

	for cell in cells:
		var coord: Vector2i = cell["coord"]
		
		# This places your new transparent Hex Outline sprite!
		tile_map_layer.set_cell(coord, TILE_SOURCE_ID, TILE_ATLAS_COORD)
		
		var pixel_center: Vector2 = tile_map_layer.map_to_local(coord)
		var lbl := Label.new()
		lbl.text = _format_reward(cell["data"])
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		
		# Optional: Add a subtle drop shadow/outline to the text so it's readable 
		# even if it overlaps the hex borders slightly
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", Color.WHITE)
		lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		lbl.add_theme_constant_override("outline_size", 3)
		
		# Add to tree FIRST to prevent Godot from overriding sizes
		tile_map_layer.add_child(lbl)
		
		# Set dimensions SECOND
		lbl.size = Vector2(TILE_SIZE, TILE_SIZE)
		lbl.position = pixel_center - (lbl.size * 0.5)

	# Wait one frame so layout sizes (header height) are resolved before centering.
	await get_tree().process_frame
	var header_h: float = $VBoxContainer/HeaderRow.size.y + 10.0
	var info_h: float = info_label.size.y + 10.0
	var centroid: Vector2 = sum_local / float(cells.size())
	tile_map_layer.position = Vector2(size.x * 0.5, header_h + (size.y - header_h - info_h) * 0.5) - centroid

	var board_title_name: String = _summon_name if _summon_name != "" else "Summon %s" % _summon_id
	title_label.text = "%s Board" % board_title_name
	info_label.text = "Nodes: %d  •  Drag to pan" % cells.size()

func _format_reward(node_data: Dictionary) -> String:
	var reward_value: Variant = node_data.get("reward", null)
	if reward_value == null:
		return "START"
	if reward_value is Array:
		var reward_arr: Array = reward_value
		if reward_arr.size() >= 2:
			return "%s\n+%s" % [str(reward_arr[0]), str(reward_arr[1])]
		if reward_arr.size() == 1:
			return str(reward_arr[0])
	return "?"

func _show_empty(message: String) -> void:
	title_label.text = "Summon Board"
	info_label.text = message
	tile_map_layer.clear()
	for child in tile_map_layer.get_children():
		child.queue_free()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_is_panning = mb.pressed
			if _is_panning:
				_pan_start = mb.position
				_tmap_start = tile_map_layer.position
	elif event is InputEventMouseMotion and _is_panning:
		var motion := event as InputEventMouseMotion
		tile_map_layer.position = _tmap_start + motion.position - _pan_start

func _axial_to_offset(axial: Vector2i) -> Vector2i:
	var raw_x := int(axial[0])
	var raw_y := int(axial[1])
	# THE SHEAR CONVERSION: Translate Left-Shear Axial to Godot Odd-R Offset
	# We use posmod to safely handle negative Y rows without breaking the math
	var col = raw_x - (raw_y + posmod(raw_y, 2)) / 2
	var row = raw_y 
	return Vector2i(col, row)
