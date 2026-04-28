extends Control

@onready var unit: Sprite2D = $Pedestal/Unit
@onready var pedestal: Sprite2D = $Pedestal

# Adjust this value to your liking (e.g., 10 pixels up from the bottom)
const OFFSET_FROM_BOTTOM: float = 25.0
const UNIT_TEXTURE_SCALE: float = 1.7

func setup(char_tex: Texture2D, ped_tex: Texture2D) -> void:
	if not is_node_ready():
		await ready
	if char_tex == null or ped_tex == null:
		return

	_apply_unit_textures(char_tex, ped_tex)
	scale = Vector2.ONE
	position = Vector2.ZERO

func setup_in_cell(char_tex: Texture2D, ped_tex: Texture2D, cell_width: float, cell_height: float, side_padding: float, bottom_margin: float) -> void:
	if not is_node_ready():
		await ready
	if char_tex == null or ped_tex == null:
		return

	_apply_unit_textures(char_tex, ped_tex)

	# Keep pedestal pinned at native pixel size. Only the character scales to fit.
	pedestal.scale = Vector2.ONE
	scale = Vector2.ONE

	var pedestal_half_height: float = ped_tex.get_size().y * 0.5
	position = Vector2(
		cell_width * 0.5,
		cell_height - bottom_margin - pedestal_half_height
	)

	#var available_w: float = maxf(1.0, cell_width - (side_padding * 2.0))
	#var max_scale_by_width: float = available_w / maxf(1.0, char_tex.get_size().x)
	#var max_scale_by_height: float = maxf(0.05, (cell_height - bottom_margin - OFFSET_FROM_BOTTOM) / maxf(1.0, char_tex.get_size().y))
	#var temp = minf(max_scale_by_width, max_scale_by_height)
	#var final_unit_scale: float = maxf(0.05, minf(UNIT_TEXTURE_SCALE, temp))
	unit.scale = Vector2.ONE# * final_unit_scale

func _apply_unit_textures(char_tex: Texture2D, ped_tex: Texture2D) -> void:

	pedestal.texture = ped_tex
	unit.texture = char_tex
	unit.scale = Vector2.ONE * UNIT_TEXTURE_SCALE
	
	# 1. Find the bottom-middle of the pedestal relative to its center
	var pedestal_bottom_y = ped_tex.get_size().y / 2.0
	
	# 2. Position the unit's feet (its origin) 
	# relative to that bottom point
	unit.position.x = 0 # Stay centered horizontally
	unit.position.y = pedestal_bottom_y - OFFSET_FROM_BOTTOM

	# 3. Handle unit offset (to keep origin at feet)
	# This ensures even tall/short sprites stand on the same line
	unit.offset.y = -char_tex.get_size().y / 2.0
