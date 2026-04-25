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
