extends Control

const TILE_SOURCE_ID: int = 0
const TILE_ATLAS_COORD: Vector2i = Vector2i(0, 0)
const TILE_SIZE: int = 100
const CLICK_DRAG_THRESHOLD: float = 8.0

@onready var back_button: TextureButton = $VBoxContainer/UnitNamebgChara2/BackButton
@onready var title_label: Label = $VBoxContainer/UnitNamebgChara2/Title
@onready var tile_map_layer: TileMapLayer = $TileMapLayer
@onready var info_label: Label = $VBoxContainer/InfoLabel
@onready var sp_label: Label = $label_cp

var _summon_id: String = ""
var _summon_name: String = ""
var _is_panning: bool = false
var _pan_start: Vector2 = Vector2.ZERO
var _tmap_start: Vector2 = Vector2.ZERO

# Esper training state
var _unlocked_board_nodes: Array[String] = []
var _unlocked_skills: Array[String] = []
var _board_nodes_data: Dictionary = {}  # Cache board node data for state queries
var _node_press_id: String = ""  # Track which node was pressed
var _node_press_pos: Vector2 = Vector2.ZERO  # Track press position

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
	#source.create_tile(TILE_ATLAS_COORD)
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

	# ESPER TRAINING: Fetch esper progression state
	var progression: Dictionary = EsperService.get_esper_progression(_summon_id)
	var rank: int = maxi(1, int(progression.get("current_rank", progression.get("rank", 1))))

	var board_nodes: Array = GameDatabase.get_esper_board(_summon_id.to_int(), rank)
	if board_nodes.is_empty():
		_show_empty("No board data found for summon #%s rank %d." % [_summon_id, rank])
		return

	var unlocked_nodes_raw: Variant = progression.get("unlocked_board_nodes", [])
	_unlocked_board_nodes.clear()
	if unlocked_nodes_raw is Array:
		for node_id in unlocked_nodes_raw:
			_unlocked_board_nodes.append(str(node_id))
	var unlocked_skills_raw: Variant = progression.get("unlocked_skills", [])
	_unlocked_skills.clear()
	if unlocked_skills_raw is Array:
		for skill_id in unlocked_skills_raw:
			_unlocked_skills.append(str(skill_id))
	_board_nodes_data.clear()

	var cells: Array[Dictionary] = []
	var node_lookup: Dictionary = {}
	var sum_local := Vector2.ZERO
	
	for node_value in board_nodes:
		var node_id: String = str(node_value.get("pieceId", ""))
		if node_id == "": continue
		
		var node_data: Dictionary = node_value
		_board_nodes_data[node_id] = node_data  # Cache for state queries
		
		var pos_str: String = str(node_data.get("position", ""))
		if pos_str == "": continue
		var pos_parts = pos_str.split(":")
		if pos_parts.size() < 2: continue
		
		# 1. Grab the raw Axial coordinate from the datamine
		var raw_axial_coord := Vector2i(int(pos_parts[0]), int(pos_parts[1]))
		
		# 2. CONVERT to Godot's internal Offset coordinate immediately!
		var godot_offset_coord := _axial_to_offset(raw_axial_coord)
		
		# 3. Store the CONVERTED coordinate
		cells.append({"coord": godot_offset_coord, "node_id": node_id, "data": node_data})
		node_lookup[node_id] = {"coord": godot_offset_coord, "data": node_data}
		
		# Calculate the centroid using the converted coordinate
		sum_local += tile_map_layer.map_to_local(godot_offset_coord)

	if cells.is_empty():
		_show_empty("Board nodes are missing valid positions.")
		return

	# ESPER TRAINING: Pre-calculate learnable nodes based on unlocked parents
	# A node is learnable if its ID is in the unlockPiece string of any UNLOCKED node, or the START node.
	var learnable_nodes: Dictionary = {}
	for cell in cells:
		var node_id: String = cell["node_id"]
		var node_data: Dictionary = cell["data"]
		var piece_type: int = int(node_data.get("pieceType", -1))
		
		if piece_type == 0 or node_id in _unlocked_board_nodes:
			var unlock_piece: String = str(node_data.get("unlockPiece", ""))
			if unlock_piece != "":
				for child_id in unlock_piece.split(","):
					var c_id = child_id.strip_edges()
					if c_id != "":
						learnable_nodes[c_id] = true
						
	# Cache learnable status
	for cell in cells:
		var node_id: String = cell["node_id"]
		var piece_type: int = int(cell["data"].get("pieceType", -1))
		if piece_type == 0:
			cell["data"]["_computed_state"] = "start"
		elif node_id in _unlocked_board_nodes:
			cell["data"]["_computed_state"] = "learned"
		elif learnable_nodes.has(node_id):
			cell["data"]["_computed_state"] = "learnable"
		else:
			cell["data"]["_computed_state"] = "unreachable"

	# ESPER TRAINING: Draw connectors with state-based coloring
	# Iterate over all nodes, drawing lines to their children
	for cell in cells:
		var node_data: Dictionary = cell["data"]
		var parent_coord: Vector2i = cell["coord"]
		var parent_pos: Vector2 = tile_map_layer.map_to_local(parent_coord)
		
		var unlock_piece: String = str(node_data.get("unlockPiece", ""))
		if unlock_piece == "": continue
		
		for child_id in unlock_piece.split(","):
			var c_id = child_id.strip_edges()
			if c_id == "": continue
			
			var child_lookup = node_lookup.get(c_id, null)
			if child_lookup == null: continue
			
			var child_coord: Vector2i = child_lookup["coord"]
			var child_pos: Vector2 = tile_map_layer.map_to_local(child_coord)
			
			var child_data: Dictionary = child_lookup["data"]
			var child_state: String = str(child_data.get("_computed_state", "unreachable"))

			var connector_color: Color
			if child_state == "unreachable":
				connector_color = Color(0.5, 0.5, 0.5, 0.3)  # Dimmed grey for unreachable
			elif child_state == "learnable":
				connector_color = Color(0.4, 0.7, 1.0, 0.6)  # Brighter blue for learnable
			else:  # learned or start
				connector_color = Color(0.0, 1.0, 0.0, 0.5)  # Green for learned/start
			
			var connector := Line2D.new()
			connector.default_color = connector_color
			connector.width = 6.0
			connector.z_index = -1
			connector.add_point(parent_pos)
			connector.add_point(child_pos)
			tile_map_layer.add_child(connector)

	# ESPER TRAINING: Render nodes with colors and click handlers
	for cell in cells:
		var coord: Vector2i = cell["coord"]
		var node_id: String = cell["node_id"]
		var node_data: Dictionary = cell["data"]
		
		# This places your new transparent Hex Outline sprite!
		tile_map_layer.set_cell(coord, TILE_SOURCE_ID, TILE_ATLAS_COORD)
		
		var pixel_center: Vector2 = tile_map_layer.map_to_local(coord)
		
		# ESPER TRAINING: Create clickable control node with color background
		var node_control := Control.new()
		node_control.size = Vector2(TILE_SIZE, TILE_SIZE)
		node_control.position = pixel_center - (node_control.size * 0.5)
		node_control.mouse_filter = Control.MOUSE_FILTER_PASS
		node_control.set_meta("node_id", node_id)
		
		var state: String = str(node_data.get("_computed_state", "unreachable"))
		node_control.set_meta("node_state", state)

		# Color state is represented by node text color.
		var text_color: Color = _get_node_color(state)
		
		# Create label for reward text
		var lbl := Label.new()
		lbl.text = _format_reward(node_data)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", text_color)
		lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		lbl.add_theme_constant_override("outline_size", 3)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Allow input to pass through
		node_control.add_child(lbl)
		lbl.size = node_control.size
		lbl.position = Vector2.ZERO
		
		# ESPER TRAINING: Add click handler for learnable and start nodes
		if state in ["learnable", "start"]:
			node_control.gui_input.connect(func(event: InputEvent) -> void:
				if event is InputEventMouseButton:
					var mb := event as InputEventMouseButton
					if mb.button_index == MOUSE_BUTTON_LEFT:
						if mb.pressed:
							_node_press_id = node_id
							_node_press_pos = mb.position
						else:
							# On release, check if this was a click (not a drag)
							if _node_press_id == node_id and mb.position.distance_to(_node_press_pos) < CLICK_DRAG_THRESHOLD:
								_on_node_clicked(node_id)
							_node_press_id = ""
			)
			node_control.mouse_entered.connect(func() -> void:
				# Slightly brighten text on hover for clickable nodes.
				lbl.add_theme_color_override("font_color", text_color.lerp(Color.WHITE, 0.25))
			)
			node_control.mouse_exited.connect(func() -> void:
				# Reset text color on exit.
				lbl.add_theme_color_override("font_color", text_color)
			)
		
		tile_map_layer.add_child(node_control)
	
	# Wait one frame so layout sizes (header height) are resolved before centering.
	await get_tree().process_frame
	var header_h: float = $VBoxContainer/HeaderRow.size.y + 10.0
	var info_h: float = info_label.size.y + 10.0
	var centroid: Vector2 = sum_local / float(cells.size())
	tile_map_layer.position = Vector2(size.x * 0.5, header_h + (size.y - header_h - info_h) * 0.5) - centroid

	var board_title_name: String = _summon_name if _summon_name != "" else "Summon %s" % _summon_id
	title_label.text = "%s Board" % board_title_name
	info_label.text = "Nodes: %d  •  Drag to pan  •  Click to learn skills" % cells.size()
	sp_label.text = str(int(progression.get("current_sp", 0)))


func _format_reward(node_data: Dictionary) -> String:
	var piece_type: int = int(node_data.get("pieceType", -1))
	var piece_param: int = int(node_data.get("pieceParam", 0))
	var sp_cost: int = int(node_data.get("costSp", 0))
	
	if piece_type == 0:
		return "START"
		
	var reward_type: String = ""
	if piece_type == 10: reward_type = "HP"
	elif piece_type == 11: reward_type = "MP"
	elif piece_type == 12: reward_type = "ATK"
	elif piece_type == 13: reward_type = "DEF"
	elif piece_type == 14: reward_type = "MAG"
	elif piece_type == 15: reward_type = "SPR"
	elif piece_type == 20: reward_type = "MAGIC"
	elif piece_type == 21: reward_type = "ABILITY"
	elif piece_type == 100: reward_type = "Fire Resist"
	elif piece_type == 101: reward_type = "Ice Resist"
	elif piece_type == 102: reward_type = "Lightning Resist"
	elif piece_type == 103: reward_type = "Water Resist"
	elif piece_type == 104: reward_type = "Wind Resist"
	elif piece_type == 105: reward_type = "Earth Resist"
	elif piece_type == 106: reward_type = "Light Resist"
	elif piece_type == 107: reward_type = "Dark Resist"
	else: reward_type = "UNKNOWN"

	if reward_type == "ABILITY":
		# Check active abilities first
		var skill_data: Dictionary = GameDatabase.get_ability(str(piece_param))
		if not skill_data.is_empty():
			var skill_name: String = str(skill_data.get("name", str(piece_param)))
			if sp_cost > 0:
				return "%s
%d SP" % [skill_name, sp_cost]
			return skill_name
		# Then check passive abilities
		skill_data = GameDatabase.get_passive(str(piece_param))
		if not skill_data.is_empty():
			var skill_name: String = str(skill_data.get("name", str(piece_param)))
			if sp_cost > 0:
				return "%s
%d SP" % [skill_name, sp_cost]
			return skill_name
			
	elif reward_type == "MAGIC":
		var skill_data: Dictionary = GameDatabase.get_magic(str(piece_param))
		if not skill_data.is_empty():
			var skill_name: String = str(skill_data.get("name", str(piece_param)))
			if sp_cost > 0:
				return "%s
%d SP" % [skill_name, sp_cost]
			return skill_name
	
	# Fall back to stat rewards format (ATK +5 on line 1, SP cost on line 2)
	if sp_cost > 0:
		if "Resist" in reward_type:
			return "%s %d%%
%d SP" % [reward_type, piece_param, sp_cost]
		return "%s +%d
%d SP" % [reward_type, piece_param, sp_cost]
	
	if "Resist" in reward_type:
		return "%s %d%%" % [reward_type, piece_param]
	return "%s +%d" % [reward_type, piece_param]

func _get_node_state(node_id: String) -> String:
	# Now rely on computed state
	var node_data: Dictionary = _board_nodes_data.get(node_id, {})
	return str(node_data.get("_computed_state", "unreachable"))

func _get_node_color(state: String) -> Color:
	match state:
		"learned":
			return Color.GREEN
		"learnable":
			return Color(0.0, 0.5, 1.0)  # Blue
		"start":
			return Color.GREEN  # START nodes appear as learned (always available)
		"unreachable":
			return Color(0.5, 0.5, 0.5)  # Grey
	return Color.WHITE

func _get_node_reward_skill_id(node_data: Dictionary) -> String:
	var piece_type: int = int(node_data.get("pieceType", -1))
	var piece_param: int = int(node_data.get("pieceParam", 0))
	if piece_type in [20, 21]:
		return str(piece_param)
	return ""

func _on_node_clicked(node_id: String) -> void:
	"""Handle clicking on a board node to learn a skill"""
	# Prevent stale drag state if a click triggers an immediate board rerender.
	_is_panning = false

	var state: String = _get_node_state(node_id)
	
	if state == "unreachable":
		return
	
	if state == "learned":
		return
	
	var node_data: Dictionary = _board_nodes_data.get(node_id, {})
	var reward_skill_id: String = _get_node_reward_skill_id(node_data)

	# Unlock the node via DataManager (handles persistence)
	var sp_cost: int = 0
	sp_cost = int(node_data.get("costSp", 0))

	var result: Dictionary = EsperService.unlock_esper_board_node(_summon_id, node_id, sp_cost, reward_skill_id)

	if not bool(result.get("success", false)):
		return

	# Refresh board visuals (await the async render)
	await _render_board()

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
